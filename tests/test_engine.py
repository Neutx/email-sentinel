"""Tests for SentinelEngine orchestration."""

import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch

from email_sentinel.config import Settings
from email_sentinel.engine import SentinelEngine
from email_sentinel.models import EmailCategory, EmailMessage


def test_engine_process_marketing_email():
    with tempfile.TemporaryDirectory() as tmpdir:
        settings = Settings(
            DB_PATH=str(Path(tmpdir) / "sentinel.db"),
            AUTO_UNSUBSCRIBE=True,
            AUTO_DELETE_MARKETING=True,
            LLM_PROVIDER="rules_only",
        )
        engine = SentinelEngine(settings)

        email = EmailMessage(
            id="101",
            message_id="<promo-101@discount.com>",
            subject="Exclusive Sale: 70% Off Today Only!",
            sender="Discounts <promo@discount.com>",
            sender_email="promo@discount.com",
            list_unsubscribe="<https://discount.com/unsub?id=101>",
            list_unsubscribe_post="List-Unsubscribe=One-Click",
            body_plain="Click to buy now.",
        )

        mock_client = MagicMock()
        mock_client.move_to_trash.return_value = True

        mock_resp = MagicMock(status_code=200)
        with patch("httpx.Client.post", return_value=mock_resp):
            res = engine.process_email(email, client=mock_client)

            assert res.classification.category == EmailCategory.MARKETING_PROMO
            assert res.unsubscribed is not None
            assert res.unsubscribed.success is True
            assert res.deleted_or_trashed is True
            mock_client.move_to_trash.assert_called_once_with("101")


def test_engine_process_project_update():
    with tempfile.TemporaryDirectory() as tmpdir:
        settings = Settings(
            DB_PATH=str(Path(tmpdir) / "sentinel.db"),
            LLM_PROVIDER="rules_only",
            WHATSAPP_ENABLED=True,
            WHATSAPP_PROVIDER="callmebot",
            CALLMEBOT_PHONE="1234567890",
            CALLMEBOT_API_KEY="key",
        )
        engine = SentinelEngine(settings)

        email = EmailMessage(
            id="102",
            message_id="<pr-merge-102@github.com>",
            subject="[Murphy-Labs/core] Pull request #88 merged",
            sender="GitHub Notifications <notifications@github.com>",
            sender_email="notifications@github.com",
            body_plain="PR #88 has been merged into main branch.",
        )

        mock_client = MagicMock()
        mock_resp = MagicMock(status_code=200, text="success")
        with patch("httpx.Client.get", return_value=mock_resp):
            res = engine.process_email(email, client=mock_client)

            assert res.classification.category == EmailCategory.PROJECT_UPDATE
            assert res.notification_sent is True
            assert "Murphy-Labs/core" in (res.classification.project_name or "")
            mock_client.mark_as_read.assert_called_once_with("102")


def test_engine_skips_already_processed():
    with tempfile.TemporaryDirectory() as tmpdir:
        settings = Settings(
            DB_PATH=str(Path(tmpdir) / "sentinel.db"),
            LLM_PROVIDER="rules_only",
        )
        engine = SentinelEngine(settings)

        email = EmailMessage(
            id="103",
            message_id="<dup-103@example.com>",
            subject="Invoice for month",
            sender="billing@saas.com",
            sender_email="billing@saas.com",
            body_plain="Here is your monthly invoice.",
        )

        # First run
        res1 = engine.process_email(email)
        assert res1.error is None

        # Second run with same message_id
        res2 = engine.process_email(email)
        assert res2.error == "Already processed"
