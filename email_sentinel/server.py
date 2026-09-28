"""REST API server for Email Sentinel (consumed by the Android app and Hermes)."""

from __future__ import annotations

import ipaddress
import secrets
import threading
from typing import Any, Dict, List, Optional

import uvicorn
from fastapi import APIRouter, Depends, FastAPI, HTTPException, Query, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from rich.console import Console

from email_sentinel import __version__
from email_sentinel.config import RUNTIME_EDITABLE, Settings, apply_overrides, get_settings
from email_sentinel.db import Database, ScanInProgressError, utc_now_iso
from email_sentinel.email_client import EmailClient
from email_sentinel.engine import SentinelEngine
from email_sentinel.models import EmailCategory
from email_sentinel.schemas import (
    ActionResult,
    AlertsResponse,
    Briefing,
    BriefingCreate,
    DoneRequest,
    EmailItem,
    EmailPage,
    Health,
    ProjectSummary,
    ProjectUpdate,
    ReclassifyRequest,
    RuntimeSettings,
    RuntimeSettingsPatch,
    ScanRequest,
    ScanRun,
    Stats,
    SystemStatus,
    UnsubscribeLog,
)

console = Console()


def _to_runtime(settings: Settings) -> RuntimeSettings:
    return RuntimeSettings(**{key.lower(): getattr(settings, key) for key in RUNTIME_EDITABLE})


def _mask_mailbox(user: str) -> str:
    if "@" not in user:
        return "not configured" if not user else user[:2] + "***"
    name, domain = user.split("@", 1)
    return f"{name[:2]}***@{domain}"


def create_app(settings: Optional[Settings] = None) -> FastAPI:
    base = settings or get_settings()
    db = Database(base.DB_PATH)
    bearer = HTTPBearer(auto_error=False)

    def effective() -> Settings:
        return apply_overrides(base, db.get_setting_overrides())

    def require_token(creds: Optional[HTTPAuthorizationCredentials] = Depends(bearer)) -> None:
        if not base.API_TOKEN:
            return  # loopback-only dev mode; run_server refuses to expose a token-less API
        if creds is None or not secrets.compare_digest(creds.credentials.encode(), base.API_TOKEN.encode()):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or missing bearer token",
                headers={"WWW-Authenticate": "Bearer"},
            )

    def get_email_or_404(email_id: int) -> Dict[str, Any]:
        email = db.get_email(email_id)
        if email is None:
            raise HTTPException(status_code=404, detail="Email not found")
        return email

    app = FastAPI(
        title="Email Sentinel API",
        description="Triage feed, project updates, briefings and controls for the Email Sentinel app.",
        version=__version__,
    )

    @app.get("/", include_in_schema=False)
    def root() -> Dict[str, str]:
        return {"name": "Email Sentinel API", "version": __version__, "docs": "/docs"}

    @app.get("/api/health", response_model=Health, tags=["system"])
    def health() -> Health:
        return Health(version=__version__)

    api = APIRouter(prefix="/api", dependencies=[Depends(require_token)])

    # ---------------------------------------------------------------- system
    @api.get("/status", response_model=SystemStatus, tags=["system"])
    def get_status() -> SystemStatus:
        cfg = effective()
        briefings = db.list_briefings(limit=1)
        return SystemStatus(
            version=__version__,
            server_time=utc_now_iso(),
            mailbox=_mask_mailbox(cfg.IMAP_USER),
            llm_provider=cfg.LLM_PROVIDER,
            llm_model=cfg.LLM_MODEL,
            scan_running=db.is_scan_running(),
            last_scan=db.get_last_scan(),
            latest_briefing_id=briefings[0]["id"] if briefings else None,
            settings=_to_runtime(cfg),
        )

    @api.get("/stats", response_model=Stats, tags=["system"])
    def get_stats() -> Dict[str, Any]:
        return db.get_stats()

    @api.get("/settings", response_model=RuntimeSettings, tags=["system"])
    def get_runtime_settings() -> RuntimeSettings:
        return _to_runtime(effective())

    @api.patch("/settings", response_model=RuntimeSettings, tags=["system"])
    def patch_runtime_settings(patch: RuntimeSettingsPatch) -> RuntimeSettings:
        values = {k.upper(): v for k, v in patch.model_dump(exclude_none=True).items()}
        for key in ("PROTECTED_DOMAINS", "PROJECT_KEYWORDS"):
            if key in values:
                values[key] = sorted({s.strip().lower() for s in values[key] if s.strip()})
        if values:
            db.set_setting_overrides(values)
        return _to_runtime(effective())

    # ---------------------------------------------------------------- emails
    @api.get("/emails", response_model=EmailPage, tags=["emails"])
    def list_emails(
        category: Optional[List[EmailCategory]] = Query(None),
        include_done: bool = False,
        include_trashed: bool = True,
        project: Optional[str] = None,
        limit: int = Query(50, ge=1, le=200),
        before_id: Optional[int] = Query(None, ge=1),
    ) -> EmailPage:
        items = db.list_emails(
            limit=limit,
            before_id=before_id,
            categories=[c.value for c in category or []],
            include_done=include_done,
            include_trashed=include_trashed,
            project=project,
        )
        next_cursor = items[-1]["id"] if len(items) == limit else None
        return EmailPage(items=[EmailItem(**i) for i in items], next_cursor=next_cursor)

    @api.get("/emails/{email_id}", response_model=EmailItem, tags=["emails"])
    def get_email(email_id: int) -> Dict[str, Any]:
        return get_email_or_404(email_id)

    @api.post("/emails/{email_id}/done", response_model=ActionResult, tags=["emails"])
    def mark_done(email_id: int, req: DoneRequest = DoneRequest()) -> ActionResult:
        get_email_or_404(email_id)
        db.update_email_status(email_id, is_done=req.done)
        return ActionResult(ok=True, message="Updated", email=EmailItem(**get_email_or_404(email_id)))

    @api.post("/emails/{email_id}/reclassify", response_model=ActionResult, tags=["emails"])
    def reclassify(email_id: int, req: ReclassifyRequest) -> ActionResult:
        updated = db.reclassify_email(email_id, req.category)
        if updated is None:
            raise HTTPException(status_code=404, detail="Email not found")
        return ActionResult(ok=True, message=f"Reclassified as {req.category.value}", email=EmailItem(**updated))

    @api.post("/emails/{email_id}/protect-sender", response_model=ActionResult, tags=["emails"])
    def protect_sender(email_id: int) -> ActionResult:
        email = get_email_or_404(email_id)
        sender = (email.get("sender_email") or "").strip().lower()
        if not sender:
            raise HTTPException(status_code=422, detail="Email has no sender address")
        protected = list(effective().PROTECTED_DOMAINS)
        if sender not in (p.lower() for p in protected):
            db.set_setting_overrides({"PROTECTED_DOMAINS": sorted({*protected, sender})})
        return ActionResult(
            ok=True, message=f"{sender} will never be unsubscribed or trashed", email=EmailItem(**email)
        )

    @api.post("/emails/{email_id}/restore", response_model=ActionResult, tags=["emails"])
    def restore_email(email_id: int) -> ActionResult:
        email = get_email_or_404(email_id)
        if not email["is_trashed"]:
            raise HTTPException(status_code=409, detail="Email is not in Trash")
        client = EmailClient(effective())
        try:
            client.connect()
            restored = client.restore_from_trash(email["message_id"])
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"Mailbox error: {e}") from e
        finally:
            client.close()
        if not restored:
            raise HTTPException(status_code=404, detail="Message not found in Trash (it may have been purged)")
        db.update_email_status(email_id, is_trashed=False)
        return ActionResult(ok=True, message="Restored to inbox", email=EmailItem(**get_email_or_404(email_id)))

    @api.get("/alerts", response_model=AlertsResponse, tags=["emails"])
    def get_alerts(
        after_id: int = Query(-1, description="Cursor from the previous poll; -1 = just return the current cursor."),
        limit: int = Query(50, ge=1, le=200),
    ) -> AlertsResponse:
        latest = db.latest_email_id()
        if after_id < 0:
            return AlertsResponse(items=[], cursor=latest)
        cfg = effective()
        items = db.get_alerts(
            after_id=after_id,
            min_urgency=cfg.MIN_URGENCY_TO_NOTIFY,
            notify_projects=cfg.NOTIFY_ON_PROJECT_UPDATES,
            notify_urgent=cfg.NOTIFY_ON_URGENT,
            limit=limit,
        )
        cursor = items[-1]["id"] if len(items) == limit else max(latest, after_id)
        return AlertsResponse(items=[EmailItem(**i) for i in items], cursor=cursor)

    # -------------------------------------------------------------- projects
    @api.get("/projects", response_model=List[ProjectSummary], tags=["projects"])
    def list_projects() -> List[Dict[str, Any]]:
        return db.get_project_summaries()

    @api.get("/project-updates", response_model=List[ProjectUpdate], tags=["projects"])
    def list_project_updates(
        project: Optional[str] = None, limit: int = Query(50, ge=1, le=200)
    ) -> List[Dict[str, Any]]:
        return db.get_recent_project_updates(limit=limit, project_name=project)

    @api.get("/unsubscribes", response_model=List[UnsubscribeLog], tags=["projects"])
    def list_unsubscribes(limit: int = Query(50, ge=1, le=200)) -> List[Dict[str, Any]]:
        return db.get_unsubscribe_history(limit=limit)

    # ----------------------------------------------------------------- scans
    @api.post(
        "/scan",
        response_model=ScanRun,
        status_code=status.HTTP_202_ACCEPTED,
        tags=["scans"],
        responses={200: {"model": ScanRun}, 409: {"description": "A scan is already running"}},
    )
    def trigger_scan(req: ScanRequest, response: Response) -> Dict[str, Any]:
        engine = SentinelEngine(effective())
        try:
            scan_id = db.start_scan("api", base.SCAN_LEASE_MINUTES)
        except ScanInProgressError as e:
            raise HTTPException(status_code=409, detail=str(e)) from e

        def run() -> None:
            try:
                engine.run_scan(limit=req.limit, unread_only=req.unread_only, scan_id=scan_id)
            except Exception as e:  # recorded on the scan row by run_scan
                console.print(f"[red]API scan {scan_id} failed: {e}[/red]")

        if req.wait:
            run()
            response.status_code = status.HTTP_200_OK
        else:
            threading.Thread(target=run, name=f"scan-{scan_id}", daemon=True).start()
        scan = db.get_scan(scan_id)
        assert scan is not None
        return scan

    @api.get("/scans", response_model=List[ScanRun], tags=["scans"])
    def list_scans(limit: int = Query(20, ge=1, le=100)) -> List[Dict[str, Any]]:
        return db.list_scans(limit=limit)

    @api.get("/scans/{scan_id}", response_model=ScanRun, tags=["scans"])
    def get_scan(scan_id: int) -> Dict[str, Any]:
        scan = db.get_scan(scan_id)
        if scan is None:
            raise HTTPException(status_code=404, detail="Scan not found")
        return scan

    # ------------------------------------------------------------- briefings
    @api.get("/briefings", response_model=List[Briefing], tags=["briefings"])
    def list_briefings(limit: int = Query(20, ge=1, le=100)) -> List[Dict[str, Any]]:
        return db.list_briefings(limit=limit)

    @api.get("/briefings/latest", response_model=Briefing, tags=["briefings"])
    def latest_briefing() -> Dict[str, Any]:
        briefings = db.list_briefings(limit=1)
        if not briefings:
            raise HTTPException(status_code=404, detail="No briefing yet")
        return briefings[0]

    @api.post("/briefings", response_model=Briefing, status_code=status.HTTP_201_CREATED, tags=["briefings"])
    def create_briefing(req: BriefingCreate) -> Dict[str, Any]:
        return db.save_briefing(req.period, req.title, req.summary, req.body_markdown, req.source)

    @api.get("/briefing-context", tags=["briefings"])
    def briefing_context(hours: int = Query(12, ge=1, le=168)) -> Dict[str, Any]:
        """Pre-aggregated data Hermes uses to write a briefing."""
        return db.get_briefing_context(hours=hours)

    app.include_router(api)
    return app


def _is_loopback(host: str) -> bool:
    if host == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def run_server(host: Optional[str] = None, port: Optional[int] = None) -> None:
    """Start the API server. Refuses to listen beyond loopback without SENTINEL_API_TOKEN."""
    settings = get_settings()
    host = host or settings.API_HOST
    port = port or settings.API_PORT
    if not _is_loopback(host) and len(settings.API_TOKEN) < 24:
        raise SystemExit(
            "Refusing to bind to a non-loopback address without SENTINEL_API_TOKEN (min 24 chars). "
            'Generate one with: python -c "import secrets; print(secrets.token_urlsafe(32))"'
        )
    uvicorn.run(create_app(settings), host=host, port=port)
