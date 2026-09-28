"""Generate JSON fixtures for the Flutter app tests from the real API (app/test/fixtures/).

The app's model tests parse these files, so any backend contract change that breaks
the app shows up as a failing Flutter test. Re-run after changing the API:

    uv run python scripts/export_app_fixtures.py
"""

from __future__ import annotations

import json
import tempfile
from datetime import UTC, datetime
from pathlib import Path

from fastapi.testclient import TestClient

from email_sentinel.config import Settings
from email_sentinel.db import Database
from email_sentinel.models import (
    ClassificationResult,
    EmailCategory,
    EmailMessage,
    UnsubscribeMethod,
    UnsubscribeResult,
)
from email_sentinel.server import create_app

OUT = Path(__file__).resolve().parent.parent / "app" / "test" / "fixtures"
TOKEN = "fixture-token-0123456789abcdef"
SAMPLES = [
    (
        EmailCategory.URGENT_ACTIONABLE,
        5,
        "Invoice overdue: contract renewal needs signature",
        "legal@client.io",
        None,
        True,
    ),
    (
        EmailCategory.PROJECT_UPDATE,
        3,
        "[Murphy-Labs/core] Pull request #88 merged",
        "notifications@github.com",
        "Murphy-Labs/core",
        False,
    ),
    (
        EmailCategory.PROJECT_UPDATE,
        4,
        "[Murphy-Labs/core] CI failed on main",
        "notifications@github.com",
        "Murphy-Labs/core",
        True,
    ),
    (EmailCategory.TRANSACTIONAL, 2, "Your receipt from Vercel", "billing@vercel.com", None, False),
    (EmailCategory.GENERAL_FYI, 1, "Team lunch on Friday", "sam@murphylabs.com", None, False),
    (EmailCategory.MARKETING_PROMO, 1, "Flash sale: 70% off", "deals@shop.com", None, False),
]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        settings = Settings(
            _env_file=None,  # never leak the developer's .env into committed fixtures
            DB_PATH=str(Path(tmp) / "fixtures.db"),
            API_TOKEN=TOKEN,
            IMAP_USER="owner@example.com",
            LLM_PROVIDER="gemini",
            LLM_MODEL="gemini-3.7-flash",
        )
        db = Database(settings.DB_PATH)
        for i, (category, urgency, subject, sender, project, action) in enumerate(SAMPLES, start=1):
            email = EmailMessage(
                id=str(i),
                message_id=f"<fixture-{i}@example.com>",
                subject=subject,
                sender=f"{sender.split('@')[0].title()} <{sender}>",
                sender_email=sender,
                date=datetime(2026, 9, 28, 8, i, tzinfo=UTC),
            )
            cls = ClassificationResult(
                category=category,
                urgency=urgency,
                summary=f"Summary of: {subject}",
                project_name=project,
                action_required=action,
                action_description="Review and respond" if action else None,
            )
            email_id = db.save_email(email, cls)
            if category == EmailCategory.PROJECT_UPDATE:
                db.record_project_update(email_id, cls, email)
            if category == EmailCategory.MARKETING_PROMO:
                db.update_email_status(email_id, is_trashed=True)
                db.record_unsubscribe(
                    email_id,
                    sender,
                    UnsubscribeResult(
                        success=True,
                        method=UnsubscribeMethod.RFC8058_POST,
                        target="https://shop.com/unsub",
                        http_status=200,
                        message="Unsubscribed",
                    ),
                )
        scan_id = db.start_scan("hermes-cron")
        db.finish_scan(
            scan_id, processed=6, skipped=2, summary={"processed": 6, "trashed": 1, "categories": {"project_update": 2}}
        )
        db.save_briefing(
            "morning",
            "Morning briefing",
            "1 urgent item and 2 project updates.",
            "## Needs you\n- **Contract renewal** needs a signature today.\n\n## Projects\n- Murphy-Labs/core: PR #88 merged, CI failing on main.",
        )

        client = TestClient(create_app(settings))
        auth = {"Authorization": f"Bearer {TOKEN}"}
        fixtures = {
            "health": client.get("/api/health"),
            "status": client.get("/api/status", headers=auth),
            "stats": client.get("/api/stats", headers=auth),
            "email_page": client.get("/api/emails", params={"limit": 4}, headers=auth),
            "email_item": client.get("/api/emails/1", headers=auth),
            "alerts": client.get("/api/alerts", params={"after_id": 0}, headers=auth),
            "projects": client.get("/api/projects", headers=auth),
            "project_updates": client.get("/api/project-updates", headers=auth),
            "unsubscribes": client.get("/api/unsubscribes", headers=auth),
            "scans": client.get("/api/scans", headers=auth),
            "settings": client.get("/api/settings", headers=auth),
            "briefing": client.get("/api/briefings/latest", headers=auth),
            "briefings": client.get("/api/briefings", headers=auth),
            "action_result": client.post("/api/emails/1/done", json={"done": True}, headers=auth),
            "error_404": client.get("/api/emails/999", headers=auth),
            "error_422": client.patch("/api/settings", json={"min_urgency_to_notify": 9}, headers=auth),
        }
        for name, response in fixtures.items():
            (OUT / f"{name}.json").write_text(json.dumps(response.json(), indent=2) + "\n", encoding="utf-8")
        print(f"wrote {len(fixtures)} fixtures to {OUT}")


if __name__ == "__main__":
    main()
