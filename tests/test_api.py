"""REST API contract tests."""

import tempfile
from pathlib import Path
from typing import Iterator
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from email_sentinel.config import Settings
from email_sentinel.db import Database
from email_sentinel.models import ClassificationResult, EmailCategory, EmailMessage
from email_sentinel.server import create_app
from tests.fakes import FakeIMAP, make_raw

TOKEN = "test-token-0123456789abcdef"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


@pytest.fixture
def env() -> Iterator[tuple[TestClient, Database, Settings]]:
    with tempfile.TemporaryDirectory() as tmp:
        settings = Settings(
            DB_PATH=str(Path(tmp) / "sentinel.db"),
            API_TOKEN=TOKEN,
            IMAP_USER="someone@example.com",
            IMAP_PASSWORD="pw",
            LLM_PROVIDER="rules_only",
            DESKTOP_NOTIFY_ENABLED=False,
        )
        client = TestClient(create_app(settings))
        yield client, Database(settings.DB_PATH), settings


def _seed(
    db: Database, n: int, category: EmailCategory = EmailCategory.GENERAL_FYI, urgency: int = 1, **kw
) -> list[int]:
    ids = []
    for i in range(n):
        email = EmailMessage(
            id=str(i),
            message_id=f"<{category.value}-{urgency}-{i}-{kw.get('tag', '')}@x.com>",
            subject=f"{category.value} {i}",
            sender=f"Sender <s{i}@{kw.get('domain', 'x.com')}>",
            sender_email=f"s{i}@{kw.get('domain', 'x.com')}",
        )
        cls = ClassificationResult(
            category=category,
            urgency=urgency,
            summary="summary",
            project_name=kw.get("project"),
            action_required=kw.get("action", False),
        )
        email_id = db.save_email(email, cls)
        if category == EmailCategory.PROJECT_UPDATE:
            db.record_project_update(email_id, cls, email)
        ids.append(email_id)
    return ids


def test_health_is_public_but_api_requires_token(env):
    client, _, _ = env
    assert client.get("/api/health").json()["status"] == "ok"
    assert client.get("/api/stats").status_code == 401
    assert client.get("/api/stats", headers={"Authorization": "Bearer wrong"}).status_code == 401
    assert client.get("/api/stats", headers=AUTH).status_code == 200


def test_email_pagination_and_filters(env):
    client, db, _ = env
    _seed(db, 5)
    _seed(db, 2, EmailCategory.URGENT_ACTIONABLE, urgency=5)

    page = client.get("/api/emails", params={"limit": 4}, headers=AUTH).json()
    assert len(page["items"]) == 4
    assert page["next_cursor"] == page["items"][-1]["id"]
    rest = client.get("/api/emails", params={"limit": 4, "before_id": page["next_cursor"]}, headers=AUTH).json()
    assert len(rest["items"]) == 3 and rest["next_cursor"] is None

    urgent = client.get("/api/emails", params={"category": "urgent_actionable"}, headers=AUTH).json()
    assert {i["category"] for i in urgent["items"]} == {"urgent_actionable"}
    assert isinstance(urgent["items"][0]["is_done"], bool)


def test_done_hides_email_from_default_feed(env):
    client, db, _ = env
    (email_id,) = _seed(db, 1, EmailCategory.URGENT_ACTIONABLE, urgency=5)
    res = client.post(f"/api/emails/{email_id}/done", json={"done": True}, headers=AUTH).json()
    assert res["ok"] and res["email"]["is_done"] is True
    assert client.get("/api/emails", headers=AUTH).json()["items"] == []
    assert len(client.get("/api/emails", params={"include_done": True}, headers=AUTH).json()["items"]) == 1
    assert client.post("/api/emails/9999/done", headers=AUTH).status_code == 404


def test_reclassify_syncs_project_board(env):
    client, db, _ = env
    (email_id,) = _seed(db, 1, project="Apollo")
    res = client.post(f"/api/emails/{email_id}/reclassify", json={"category": "project_update"}, headers=AUTH)
    assert res.json()["email"]["reclassified"] is True
    projects = client.get("/api/projects", headers=AUTH).json()
    assert projects[0]["name"] == "Apollo" and projects[0]["update_count"] == 1

    client.post(f"/api/emails/{email_id}/reclassify", json={"category": "general_fyi"}, headers=AUTH)
    assert client.get("/api/projects", headers=AUTH).json() == []
    bad = client.post(f"/api/emails/{email_id}/reclassify", json={"category": "nope"}, headers=AUTH)
    assert bad.status_code == 422


def test_protect_sender_updates_runtime_settings(env):
    client, db, _ = env
    (email_id,) = _seed(db, 1, EmailCategory.MARKETING_PROMO, domain="Vendor.io")
    client.post(f"/api/emails/{email_id}/protect-sender", headers=AUTH)
    settings = client.get("/api/settings", headers=AUTH).json()
    assert "s0@vendor.io" in settings["protected_domains"]
    assert "github.com" in settings["protected_domains"]


def test_settings_patch_persists_and_validates(env):
    client, _, _ = env
    res = client.patch(
        "/api/settings",
        json={"dry_run": True, "min_urgency_to_notify": 4, "project_keywords": [" Apollo ", "apollo", ""]},
        headers=AUTH,
    ).json()
    assert res["dry_run"] is True and res["min_urgency_to_notify"] == 4
    assert res["project_keywords"] == ["apollo"]
    assert client.get("/api/status", headers=AUTH).json()["settings"]["dry_run"] is True
    assert client.patch("/api/settings", json={"min_urgency_to_notify": 9}, headers=AUTH).status_code == 422


def test_alert_cursor_semantics(env):
    client, db, _ = env
    _seed(db, 2, EmailCategory.URGENT_ACTIONABLE, urgency=5, tag="old")
    first = client.get("/api/alerts", headers=AUTH).json()
    assert first["items"] == [] and first["cursor"] == 2  # first poll: no backlog flood

    _seed(db, 1, EmailCategory.MARKETING_PROMO, urgency=5)
    _seed(db, 1, EmailCategory.PROJECT_UPDATE, urgency=3, project="Apollo")
    _seed(db, 1, EmailCategory.GENERAL_FYI, urgency=1)
    polled = client.get("/api/alerts", params={"after_id": first["cursor"]}, headers=AUTH).json()
    assert [i["category"] for i in polled["items"]] == ["project_update"]
    assert polled["cursor"] == 5
    again = client.get("/api/alerts", params={"after_id": polled["cursor"]}, headers=AUTH).json()
    assert again["items"] == [] and again["cursor"] == 5


def test_briefings_roundtrip_and_context(env):
    client, db, _ = env
    assert client.get("/api/briefings/latest", headers=AUTH).status_code == 404
    _seed(db, 1, EmailCategory.URGENT_ACTIONABLE, urgency=5)
    ctx = client.get("/api/briefing-context", params={"hours": 24}, headers=AUTH).json()
    assert len(ctx["open_action_items"]) == 1

    body = {"period": "morning", "title": "Morning brief", "summary": "1 urgent item.", "body_markdown": "## Urgent"}
    created = client.post("/api/briefings", json=body, headers=AUTH)
    assert created.status_code == 201
    latest = client.get("/api/briefings/latest", headers=AUTH).json()
    assert latest["id"] == created.json()["id"] and latest["created_at"].endswith("Z")
    assert client.get("/api/status", headers=AUTH).json()["latest_briefing_id"] == latest["id"]
    assert client.post("/api/briefings", json={**body, "title": ""}, headers=AUTH).status_code == 422


def test_scan_endpoint_wait_and_conflict(env):
    client, db, _ = env
    fake = FakeIMAP({"INBOX": [make_raw("<a@x.com>", "Lunch", "Sam <sam@team.com>")]})
    with patch("imaplib.IMAP4_SSL", return_value=fake):
        res = client.post("/api/scan", json={"wait": True}, headers=AUTH)
    assert res.status_code == 200
    assert res.json()["status"] == "succeeded" and res.json()["processed_count"] == 1

    held = db.start_scan("other")
    assert client.post("/api/scan", json={}, headers=AUTH).status_code == 409
    db.finish_scan(held, processed=0, skipped=0)
    assert client.get("/api/scans", headers=AUTH).json()[0]["id"] == held


def test_restore_requires_trashed_email(env):
    client, db, _ = env
    (email_id,) = _seed(db, 1, EmailCategory.MARKETING_PROMO)
    assert client.post(f"/api/emails/{email_id}/restore", headers=AUTH).status_code == 409

    db.update_email_status(email_id, is_trashed=True)
    fake = FakeIMAP({"INBOX": [], "[Gmail]/Trash": [make_raw("<marketing_promo-1-0-@x.com>", "promo", "s0@x.com")]})
    with patch("imaplib.IMAP4_SSL", return_value=fake):
        res = client.post(f"/api/emails/{email_id}/restore", headers=AUTH)
    assert res.status_code == 200 and res.json()["email"]["is_trashed"] is False
    assert len(fake.folders["INBOX"]) == 1


def test_server_refuses_public_bind_without_token():
    from email_sentinel import server

    with patch.object(server, "get_settings", return_value=Settings(API_TOKEN="")), pytest.raises(SystemExit):
        server.run_server(host="100.64.0.1", port=8765)
    with (
        patch.object(server, "get_settings", return_value=Settings(API_TOKEN="")),
        patch.object(server.uvicorn, "run", MagicMock()) as run,
    ):
        server.run_server(host="127.0.0.1", port=8765)
        run.assert_called_once()
