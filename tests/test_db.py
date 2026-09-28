"""Tests for Database storage layer."""

import tempfile
from pathlib import Path

from email_sentinel.db import Database
from email_sentinel.models import (
    ClassificationResult,
    EmailCategory,
    EmailMessage,
    NotificationChannel,
    UnsubscribeMethod,
    UnsubscribeResult,
)


def test_database_lifecycle():
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = str(Path(tmpdir) / "test_sentinel.db")
        db = Database(db_path)

        # 1. Save email
        email = EmailMessage(
            id="1",
            message_id="<msg-001@example.com>",
            subject="[Murphy Labs] Sprint 14 Complete",
            sender="Team <team@murphylabs.com>",
            sender_email="team@murphylabs.com",
            body_plain="All tasks done.",
        )
        classification = ClassificationResult(
            category=EmailCategory.PROJECT_UPDATE,
            urgency=3,
            summary="Sprint 14 completed with 12 tickets closed.",
            project_name="Murphy Labs",
            action_required=False,
        )

        assert db.is_email_processed(email.message_id) is False
        email_id = db.save_email(email, classification)
        assert email_id > 0
        assert db.is_email_processed(email.message_id) is True

        # 2. Record Project Update
        update_id = db.record_project_update(email_id, classification, email)
        assert update_id > 0

        updates = db.get_recent_project_updates(project_name="Murphy")
        assert len(updates) == 1
        assert updates[0]["project_name"] == "Murphy Labs"

        # 3. Record Notification
        notif_id = db.record_notification(
            email_id=email_id,
            channel=NotificationChannel.WHATSAPP,
            title="Project Update: Murphy Labs",
            body=classification.summary,
            status="sent",
        )
        assert notif_id > 0

        # 4. Record Unsubscribe
        unsub_res = UnsubscribeResult(
            success=True,
            method=UnsubscribeMethod.RFC8058_POST,
            target="https://example.com/unsub",
            http_status=200,
            message="Unsubscribed",
        )
        unsub_log_id = db.record_unsubscribe(email_id, "promo@spam.com", unsub_res)
        assert unsub_log_id > 0

        history = db.get_unsubscribe_history()
        assert len(history) == 1
        assert history[0]["sender_email"] == "promo@spam.com"

        # 5. Stats
        stats = db.get_stats()
        assert stats["total_emails_processed"] == 1
        assert stats["unsubscribed_count"] == 1
        assert stats["project_updates_count"] == 1
        assert stats["notifications_sent_count"] == 1
