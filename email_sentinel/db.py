"""SQLite database layer for Email Sentinel."""

from __future__ import annotations

import contextlib
import json
import sqlite3
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Dict, Generator, Iterable, List, Optional

from email_sentinel.models import (
    ClassificationResult,
    EmailCategory,
    EmailMessage,
    NotificationChannel,
    UnsubscribeResult,
)

EMAIL_COLUMNS = """
    id, uid, message_id, sender, sender_email, subject, received_at, category,
    urgency, summary, project_name, action_required, action_description,
    is_trashed, is_unsubscribed, is_done, reclassified, dry_run, created_at
"""

_BOOL_COLUMNS = ("action_required", "is_trashed", "is_unsubscribed", "is_done", "reclassified", "dry_run", "success")
_SQLITE_TS_COLUMNS = ("created_at", "attempted_at", "sent_at")


class ScanInProgressError(RuntimeError):
    """Raised when another scan holds the lease."""


def utc_now_iso() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def _normalize_row(row: sqlite3.Row) -> Dict[str, Any]:
    """Convert a row into API-friendly JSON types (bools, ISO-8601 UTC timestamps)."""
    d = dict(row)
    for key in _BOOL_COLUMNS:
        if key in d and d[key] is not None:
            d[key] = bool(d[key])
    for key in _SQLITE_TS_COLUMNS:
        # SQLite CURRENT_TIMESTAMP is "YYYY-MM-DD HH:MM:SS" in UTC.
        val = d.get(key)
        if isinstance(val, str) and len(val) == 19 and val[10] == " ":
            d[key] = val.replace(" ", "T") + "Z"
    return d


class Database:
    def __init__(self, db_path: str):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    @contextlib.contextmanager
    def _get_connection(self) -> Generator[sqlite3.Connection, None, None]:
        conn = sqlite3.connect(str(self.db_path), timeout=30)
        conn.row_factory = sqlite3.Row
        try:
            conn.execute("PRAGMA journal_mode=WAL;")
            conn.execute("PRAGMA foreign_keys=ON;")
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    def _init_db(self) -> None:
        with self._get_connection() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS emails (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uid TEXT,
                    message_id TEXT UNIQUE,
                    sender TEXT,
                    sender_email TEXT,
                    subject TEXT,
                    received_at TEXT,
                    category TEXT,
                    urgency INTEGER,
                    summary TEXT,
                    project_name TEXT,
                    action_required INTEGER,
                    action_description TEXT,
                    is_trashed INTEGER DEFAULT 0,
                    is_unsubscribed INTEGER DEFAULT 0,
                    raw_headers_json TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP
                );

                CREATE INDEX IF NOT EXISTS idx_emails_message_id ON emails(message_id);
                CREATE INDEX IF NOT EXISTS idx_emails_category ON emails(category);
                CREATE INDEX IF NOT EXISTS idx_emails_project ON emails(project_name);

                CREATE TABLE IF NOT EXISTS unsub_logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email_id INTEGER,
                    sender_email TEXT,
                    domain TEXT,
                    method TEXT,
                    target TEXT,
                    http_status INTEGER,
                    success INTEGER,
                    error_message TEXT,
                    details_json TEXT,
                    attempted_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (email_id) REFERENCES emails(id) ON DELETE SET NULL
                );

                CREATE TABLE IF NOT EXISTS project_updates (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email_id INTEGER,
                    project_name TEXT,
                    sender TEXT,
                    subject TEXT,
                    summary TEXT,
                    urgency INTEGER,
                    action_required INTEGER,
                    action_description TEXT,
                    received_at TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (email_id) REFERENCES emails(id) ON DELETE SET NULL
                );

                CREATE INDEX IF NOT EXISTS idx_project_updates_name ON project_updates(project_name);

                CREATE TABLE IF NOT EXISTS notifications (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email_id INTEGER,
                    channel TEXT,
                    title TEXT,
                    body TEXT,
                    status TEXT,
                    sent_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    error_message TEXT,
                    FOREIGN KEY (email_id) REFERENCES emails(id) ON DELETE SET NULL
                );

                CREATE TABLE IF NOT EXISTS settings_overrides (
                    key TEXT PRIMARY KEY,
                    value_json TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS briefings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    period TEXT NOT NULL,
                    title TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    body_markdown TEXT NOT NULL,
                    source TEXT NOT NULL DEFAULT 'hermes',
                    created_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS scan_runs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    trigger TEXT NOT NULL,
                    status TEXT NOT NULL,
                    started_at TEXT NOT NULL,
                    finished_at TEXT,
                    processed_count INTEGER DEFAULT 0,
                    skipped_count INTEGER DEFAULT 0,
                    summary_json TEXT,
                    error TEXT
                );

                CREATE INDEX IF NOT EXISTS idx_scan_runs_status ON scan_runs(status);
                """
            )
            self._add_missing_columns(
                conn,
                "emails",
                {
                    "is_done": "INTEGER DEFAULT 0",
                    "reclassified": "INTEGER DEFAULT 0",
                    "dry_run": "INTEGER DEFAULT 0",
                },
            )

    @staticmethod
    def _add_missing_columns(conn: sqlite3.Connection, table: str, columns: Dict[str, str]) -> None:
        existing = {row["name"] for row in conn.execute(f"PRAGMA table_info({table})")}
        for name, ddl in columns.items():
            if name not in existing:
                conn.execute(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}")

    # ------------------------------------------------------------------
    # Emails
    # ------------------------------------------------------------------

    def is_email_processed(self, message_id: str, include_dry_run: bool = True) -> bool:
        """True if already stored. Dry-run rows count only when include_dry_run is set,
        so switching from dry-run to live re-processes (and really acts on) those emails."""
        if not message_id:
            return False
        query = "SELECT 1 FROM emails WHERE message_id = ?"
        if not include_dry_run:
            query += " AND dry_run = 0"
        with self._get_connection() as conn:
            return conn.execute(query, (message_id,)).fetchone() is not None

    def get_classification(self, message_id: str) -> Optional[ClassificationResult]:
        with self._get_connection() as conn:
            row = conn.execute(
                """SELECT category, urgency, summary, project_name, action_required, action_description
                   FROM emails WHERE message_id = ?""",
                (message_id,),
            ).fetchone()
        if row is None:
            return None
        return ClassificationResult(
            category=EmailCategory(row["category"]),
            urgency=row["urgency"] or 1,
            summary=row["summary"] or "",
            project_name=row["project_name"],
            action_required=bool(row["action_required"]),
            action_description=row["action_description"],
            reasoning="Loaded from database",
        )

    def save_email(self, email: EmailMessage, classification: ClassificationResult, dry_run: bool = False) -> int:
        with self._get_connection() as conn:
            cur = conn.execute(
                """
                INSERT OR REPLACE INTO emails (
                    uid, message_id, sender, sender_email, subject,
                    received_at, category, urgency, summary, project_name,
                    action_required, action_description, raw_headers_json, dry_run
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    email.id,
                    email.message_id,
                    email.sender,
                    email.sender_email,
                    email.subject,
                    email.date.isoformat(),
                    classification.category.value,
                    classification.urgency,
                    classification.summary,
                    classification.project_name,
                    1 if classification.action_required else 0,
                    classification.action_description,
                    json.dumps(email.headers),
                    1 if dry_run else 0,
                ),
            )
            email_id = cur.lastrowid
            assert email_id is not None
            return email_id

    def update_email_status(
        self,
        email_id: int,
        is_trashed: Optional[bool] = None,
        is_unsubscribed: Optional[bool] = None,
        is_done: Optional[bool] = None,
    ) -> None:
        updates = []
        params: List[Any] = []
        for column, value in (
            ("is_trashed", is_trashed),
            ("is_unsubscribed", is_unsubscribed),
            ("is_done", is_done),
        ):
            if value is not None:
                updates.append(f"{column} = ?")
                params.append(1 if value else 0)

        if not updates:
            return

        params.append(email_id)
        query = f"UPDATE emails SET {', '.join(updates)} WHERE id = ?"
        with self._get_connection() as conn:
            conn.execute(query, tuple(params))

    def get_email(self, email_id: int) -> Optional[Dict[str, Any]]:
        with self._get_connection() as conn:
            row = conn.execute(f"SELECT {EMAIL_COLUMNS} FROM emails WHERE id = ?", (email_id,)).fetchone()
        return _normalize_row(row) if row else None

    def list_emails(
        self,
        limit: int = 50,
        before_id: Optional[int] = None,
        categories: Optional[Iterable[str]] = None,
        include_done: bool = False,
        include_trashed: bool = True,
        project: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        where: List[str] = []
        params: List[Any] = []
        if before_id is not None:
            where.append("id < ?")
            params.append(before_id)
        cats = list(categories or [])
        if cats:
            where.append(f"category IN ({', '.join('?' for _ in cats)})")
            params.extend(cats)
        if not include_done:
            where.append("is_done = 0")
        if not include_trashed:
            where.append("is_trashed = 0")
        if project:
            where.append("project_name = ?")
            params.append(project)
        clause = f"WHERE {' AND '.join(where)}" if where else ""
        params.append(limit)
        with self._get_connection() as conn:
            rows = conn.execute(
                f"SELECT {EMAIL_COLUMNS} FROM emails {clause} ORDER BY id DESC LIMIT ?",
                tuple(params),
            ).fetchall()
        return [_normalize_row(r) for r in rows]

    def reclassify_email(self, email_id: int, category: EmailCategory) -> Optional[Dict[str, Any]]:
        """Apply a user correction; keeps the project board in sync with the new category."""
        with self._get_connection() as conn:
            row = conn.execute(f"SELECT {EMAIL_COLUMNS} FROM emails WHERE id = ?", (email_id,)).fetchone()
            if row is None:
                return None
            conn.execute(
                "UPDATE emails SET category = ?, reclassified = 1 WHERE id = ?",
                (category.value, email_id),
            )
            has_update = conn.execute("SELECT 1 FROM project_updates WHERE email_id = ?", (email_id,)).fetchone()
            if category == EmailCategory.PROJECT_UPDATE and not has_update:
                conn.execute(
                    """
                    INSERT INTO project_updates (
                        email_id, project_name, sender, subject, summary,
                        urgency, action_required, action_description, received_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        email_id,
                        row["project_name"] or "General",
                        row["sender"],
                        row["subject"],
                        row["summary"],
                        row["urgency"],
                        row["action_required"],
                        row["action_description"],
                        row["received_at"],
                    ),
                )
            elif category != EmailCategory.PROJECT_UPDATE and has_update:
                conn.execute("DELETE FROM project_updates WHERE email_id = ?", (email_id,))
        return self.get_email(email_id)

    def get_alerts(
        self,
        after_id: int,
        min_urgency: int,
        notify_projects: bool,
        notify_urgent: bool,
        limit: int = 50,
    ) -> List[Dict[str, Any]]:
        """Emails newer than `after_id` that deserve a phone notification."""
        with self._get_connection() as conn:
            rows = conn.execute(
                f"""
                SELECT {EMAIL_COLUMNS} FROM emails
                WHERE id > ?
                  AND is_done = 0
                  AND category NOT IN ('marketing_promo', 'spam')
                  AND (
                        (category = 'project_update' AND ?)
                     OR (category = 'urgent_actionable' AND ?)
                     OR urgency >= ?
                  )
                ORDER BY id ASC LIMIT ?
                """,
                (after_id, 1 if notify_projects else 0, 1 if notify_urgent else 0, min_urgency, limit),
            ).fetchall()
        return [_normalize_row(r) for r in rows]

    def latest_email_id(self) -> int:
        with self._get_connection() as conn:
            return conn.execute("SELECT COALESCE(MAX(id), 0) FROM emails").fetchone()[0]

    # ------------------------------------------------------------------
    # Unsubscribes, project updates, notifications
    # ------------------------------------------------------------------

    def record_unsubscribe(
        self,
        email_id: Optional[int],
        sender_email: str,
        result: UnsubscribeResult,
    ) -> int:
        domain = sender_email.split("@")[-1].lower() if "@" in sender_email else ""
        simulated = bool(result.details.get("dry_run"))
        with self._get_connection() as conn:
            cur = conn.execute(
                """
                INSERT INTO unsub_logs (
                    email_id, sender_email, domain, method, target,
                    http_status, success, error_message, details_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    email_id,
                    sender_email,
                    domain,
                    result.method.value,
                    result.target,
                    result.http_status,
                    1 if result.success else 0,
                    result.message if not result.success else None,
                    json.dumps(result.details),
                ),
            )
            if email_id and result.success and not simulated:
                conn.execute("UPDATE emails SET is_unsubscribed = 1 WHERE id = ?", (email_id,))
            return cur.lastrowid or 0

    def record_project_update(
        self,
        email_id: int,
        classification: ClassificationResult,
        email: EmailMessage,
    ) -> int:
        with self._get_connection() as conn:
            cur = conn.execute(
                """
                INSERT INTO project_updates (
                    email_id, project_name, sender, subject, summary,
                    urgency, action_required, action_description, received_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    email_id,
                    classification.project_name or "General",
                    email.sender,
                    email.subject,
                    classification.summary,
                    classification.urgency,
                    1 if classification.action_required else 0,
                    classification.action_description,
                    email.date.isoformat(),
                ),
            )
            return cur.lastrowid or 0

    def record_notification(
        self,
        email_id: Optional[int],
        channel: NotificationChannel,
        title: str,
        body: str,
        status: str,
        error_message: Optional[str] = None,
    ) -> int:
        with self._get_connection() as conn:
            cur = conn.execute(
                """
                INSERT INTO notifications (
                    email_id, channel, title, body, status, error_message
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    email_id,
                    channel.value,
                    title,
                    body,
                    status,
                    error_message,
                ),
            )
            return cur.lastrowid or 0

    def get_recent_project_updates(self, limit: int = 50, project_name: Optional[str] = None) -> List[Dict[str, Any]]:
        with self._get_connection() as conn:
            if project_name:
                cur = conn.execute(
                    """
                    SELECT p.*, COALESCE(e.is_done, 0) AS is_done FROM project_updates p
                    LEFT JOIN emails e ON e.id = p.email_id
                    WHERE p.project_name LIKE ?
                    ORDER BY p.id DESC LIMIT ?
                    """,
                    (f"%{project_name}%", limit),
                )
            else:
                cur = conn.execute(
                    """
                    SELECT p.*, COALESCE(e.is_done, 0) AS is_done FROM project_updates p
                    LEFT JOIN emails e ON e.id = p.email_id
                    ORDER BY p.id DESC LIMIT ?
                    """,
                    (limit,),
                )
            return [_normalize_row(row) for row in cur.fetchall()]

    def get_project_summaries(self) -> List[Dict[str, Any]]:
        with self._get_connection() as conn:
            rows = conn.execute(
                """
                SELECT p.project_name AS name,
                       COUNT(*) AS update_count,
                       MAX(p.created_at) AS last_update_at,
                       SUM(CASE WHEN p.action_required = 1 AND COALESCE(e.is_done, 0) = 0
                                THEN 1 ELSE 0 END) AS open_actions,
                       MAX(p.urgency) AS max_urgency
                FROM project_updates p
                LEFT JOIN emails e ON e.id = p.email_id
                GROUP BY p.project_name
                ORDER BY MAX(p.id) DESC
                """
            ).fetchall()
        result = []
        for r in rows:
            d = dict(r)
            ts = d.get("last_update_at")
            if isinstance(ts, str) and len(ts) == 19 and ts[10] == " ":
                d["last_update_at"] = ts.replace(" ", "T") + "Z"
            result.append(d)
        return result

    def get_unsubscribe_history(self, limit: int = 50) -> List[Dict[str, Any]]:
        with self._get_connection() as conn:
            cur = conn.execute(
                """
                SELECT * FROM unsub_logs
                ORDER BY id DESC LIMIT ?
                """,
                (limit,),
            )
            return [_normalize_row(row) for row in cur.fetchall()]

    def get_stats(self) -> Dict[str, Any]:
        with self._get_connection() as conn:
            total_emails = conn.execute("SELECT COUNT(*) FROM emails").fetchone()[0]
            unsubscribed = conn.execute("SELECT COUNT(*) FROM unsub_logs WHERE success = 1").fetchone()[0]
            trashed = conn.execute("SELECT COUNT(*) FROM emails WHERE is_trashed = 1").fetchone()[0]
            project_updates = conn.execute("SELECT COUNT(*) FROM project_updates").fetchone()[0]
            notifications_sent = conn.execute("SELECT COUNT(*) FROM notifications WHERE status = 'sent'").fetchone()[0]
            open_actions = conn.execute(
                """SELECT COUNT(*) FROM emails WHERE is_done = 0 AND
                   (category = 'urgent_actionable' OR action_required = 1)"""
            ).fetchone()[0]

            categories_raw = conn.execute("SELECT category, COUNT(*) as cnt FROM emails GROUP BY category").fetchall()
            categories = {row["category"]: row["cnt"] for row in categories_raw}

            return {
                "total_emails_processed": total_emails,
                "unsubscribed_count": unsubscribed,
                "trashed_count": trashed,
                "project_updates_count": project_updates,
                "notifications_sent_count": notifications_sent,
                "open_actions_count": open_actions,
                "categories": categories,
            }

    # ------------------------------------------------------------------
    # Runtime settings overrides
    # ------------------------------------------------------------------

    def get_setting_overrides(self) -> Dict[str, Any]:
        with self._get_connection() as conn:
            rows = conn.execute("SELECT key, value_json FROM settings_overrides").fetchall()
        return {r["key"]: json.loads(r["value_json"]) for r in rows}

    def set_setting_overrides(self, values: Dict[str, Any]) -> None:
        now = utc_now_iso()
        with self._get_connection() as conn:
            conn.executemany(
                """INSERT INTO settings_overrides (key, value_json, updated_at) VALUES (?, ?, ?)
                   ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json,
                                                  updated_at = excluded.updated_at""",
                [(k, json.dumps(v), now) for k, v in values.items()],
            )

    # ------------------------------------------------------------------
    # Briefings (written by Hermes)
    # ------------------------------------------------------------------

    def save_briefing(
        self, period: str, title: str, summary: str, body_markdown: str, source: str = "hermes"
    ) -> Dict[str, Any]:
        with self._get_connection() as conn:
            cur = conn.execute(
                """INSERT INTO briefings (period, title, summary, body_markdown, source, created_at)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (period, title, summary, body_markdown, source, utc_now_iso()),
            )
            briefing_id = cur.lastrowid
        briefing = self.get_briefing(briefing_id or 0)
        assert briefing is not None
        return briefing

    def get_briefing(self, briefing_id: int) -> Optional[Dict[str, Any]]:
        with self._get_connection() as conn:
            row = conn.execute("SELECT * FROM briefings WHERE id = ?", (briefing_id,)).fetchone()
        return dict(row) if row else None

    def list_briefings(self, limit: int = 20) -> List[Dict[str, Any]]:
        with self._get_connection() as conn:
            rows = conn.execute("SELECT * FROM briefings ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
        return [dict(r) for r in rows]

    def get_briefing_context(self, hours: int = 12) -> Dict[str, Any]:
        """Everything Hermes needs to write a briefing, pre-aggregated."""
        since = (datetime.now(UTC) - timedelta(hours=hours)).strftime("%Y-%m-%d %H:%M:%S")
        with self._get_connection() as conn:
            open_urgent = conn.execute(
                f"""SELECT {EMAIL_COLUMNS} FROM emails
                    WHERE is_done = 0 AND (category = 'urgent_actionable' OR action_required = 1)
                    ORDER BY urgency DESC, id DESC LIMIT 25"""
            ).fetchall()
            project_rows = conn.execute(
                """SELECT project_name, subject, summary, urgency, action_required, action_description
                   FROM project_updates WHERE created_at >= ? ORDER BY id DESC LIMIT 100""",
                (since,),
            ).fetchall()
            counts = conn.execute(
                """SELECT category, COUNT(*) AS cnt FROM emails WHERE created_at >= ?
                   GROUP BY category""",
                (since,),
            ).fetchall()
            unsubscribed = conn.execute(
                "SELECT COUNT(*) FROM unsub_logs WHERE success = 1 AND attempted_at >= ?", (since,)
            ).fetchone()[0]
            trashed = conn.execute(
                "SELECT COUNT(*) FROM emails WHERE is_trashed = 1 AND created_at >= ?", (since,)
            ).fetchone()[0]

        projects: Dict[str, List[Dict[str, Any]]] = {}
        for r in project_rows:
            projects.setdefault(r["project_name"] or "General", []).append(
                {k: r[k] for k in ("subject", "summary", "urgency", "action_description")}
                | {"action_required": bool(r["action_required"])}
            )

        return {
            "window_hours": hours,
            "generated_at": utc_now_iso(),
            "open_action_items": [
                {
                    k: v
                    for k, v in _normalize_row(r).items()
                    if k
                    in (
                        "id",
                        "sender",
                        "subject",
                        "summary",
                        "urgency",
                        "category",
                        "action_description",
                        "received_at",
                    )
                }
                for r in open_urgent
            ],
            "project_activity": projects,
            "category_counts": {r["category"]: r["cnt"] for r in counts},
            "unsubscribed_count": unsubscribed,
            "trashed_count": trashed,
            "last_scan": self.get_last_scan(),
        }

    # ------------------------------------------------------------------
    # Scan runs — a DB-backed lease so the CLI (Hermes cron) and the API
    # never scan the mailbox concurrently.
    # ------------------------------------------------------------------

    def start_scan(self, trigger: str, lease_minutes: int = 15) -> int:
        stale_before = (datetime.now(UTC) - timedelta(minutes=lease_minutes)).strftime("%Y-%m-%dT%H:%M:%SZ")
        conn = sqlite3.connect(str(self.db_path), timeout=30, isolation_level=None)
        try:
            conn.execute("BEGIN IMMEDIATE")
            conn.execute(
                """UPDATE scan_runs SET status = 'abandoned', finished_at = ?,
                          error = 'Lease expired (process died or hung)'
                   WHERE status = 'running' AND started_at < ?""",
                (utc_now_iso(), stale_before),
            )
            running = conn.execute("SELECT id FROM scan_runs WHERE status = 'running'").fetchone()
            if running:
                conn.execute("ROLLBACK")
                raise ScanInProgressError(f"Scan {running[0]} is already running")
            cur = conn.execute(
                "INSERT INTO scan_runs (trigger, status, started_at) VALUES (?, 'running', ?)",
                (trigger, utc_now_iso()),
            )
            conn.execute("COMMIT")
            return cur.lastrowid or 0
        finally:
            conn.close()

    def finish_scan(
        self,
        scan_id: int,
        processed: int,
        skipped: int,
        summary: Optional[Dict[str, Any]] = None,
        error: Optional[str] = None,
    ) -> None:
        with self._get_connection() as conn:
            conn.execute(
                """UPDATE scan_runs SET status = ?, finished_at = ?, processed_count = ?,
                          skipped_count = ?, summary_json = ?, error = ?
                   WHERE id = ?""",
                (
                    "failed" if error else "succeeded",
                    utc_now_iso(),
                    processed,
                    skipped,
                    json.dumps(summary or {}),
                    error,
                    scan_id,
                ),
            )

    def get_scan(self, scan_id: int) -> Optional[Dict[str, Any]]:
        with self._get_connection() as conn:
            row = conn.execute("SELECT * FROM scan_runs WHERE id = ?", (scan_id,)).fetchone()
        return self._scan_row(row) if row else None

    def list_scans(self, limit: int = 20) -> List[Dict[str, Any]]:
        with self._get_connection() as conn:
            rows = conn.execute("SELECT * FROM scan_runs ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
        return [self._scan_row(r) for r in rows]

    def get_last_scan(self) -> Optional[Dict[str, Any]]:
        scans = self.list_scans(limit=1)
        return scans[0] if scans else None

    def is_scan_running(self) -> bool:
        with self._get_connection() as conn:
            return conn.execute("SELECT 1 FROM scan_runs WHERE status = 'running'").fetchone() is not None

    @staticmethod
    def _scan_row(row: sqlite3.Row) -> Dict[str, Any]:
        d = dict(row)
        d["summary"] = json.loads(d.pop("summary_json") or "{}")
        return d
