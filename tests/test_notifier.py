"""Tests for Notifier dispatch."""

from unittest.mock import MagicMock, patch

from email_sentinel.config import Settings
from email_sentinel.models import EmailCategory, NotificationPayload
from email_sentinel.notifier import Notifier


def test_whatsapp_callmebot_dispatch():
    settings = Settings(
        WHATSAPP_ENABLED=True,
        WHATSAPP_PROVIDER="callmebot",
        CALLMEBOT_PHONE="1234567890",
        CALLMEBOT_API_KEY="testkey123",
    )
    notifier = Notifier(settings)

    payload = NotificationPayload(
        title="Project Update: Murphy Labs",
        body="Deployment v2.0 succeeded",
        category=EmailCategory.PROJECT_UPDATE,
        urgency=3,
        project_name="Murphy Labs",
        sender="ci@murphylabs.com",
        subject="[Murphy Labs] Build #100 Passed",
    )

    mock_resp = MagicMock(status_code=200, text="Message queued (success)")
    with patch("httpx.Client.get", return_value=mock_resp) as mock_get:
        results = notifier.dispatch(payload)
        assert len(results) >= 1
        whatsapp_res = next(r for r in results if r["channel"] == "whatsapp")
        assert whatsapp_res["status"] == "sent"
        mock_get.assert_called_once()
        assert "callmebot.com" in mock_get.call_args[0][0]


def test_telegram_dispatch():
    settings = Settings(
        TELEGRAM_ENABLED=True,
        TELEGRAM_BOT_TOKEN="123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11",
        TELEGRAM_CHAT_ID="987654321",
    )
    notifier = Notifier(settings)

    payload = NotificationPayload(
        title="Urgent Security Alert",
        body="Action required immediately",
        category=EmailCategory.URGENT_ACTIONABLE,
        urgency=5,
        sender="security@service.com",
        subject="Password reset requested",
    )

    mock_resp = MagicMock(status_code=200)
    mock_resp.json.return_value = {"ok": True}
    with patch("httpx.Client.post", return_value=mock_resp) as mock_post:
        results = notifier.dispatch(payload)
        telegram_res = next(r for r in results if r["channel"] == "telegram")
        assert telegram_res["status"] == "sent"
        mock_post.assert_called_once()


def test_should_notify_filtering():
    settings = Settings(
        NOTIFY_ON_PROJECT_UPDATES=True,
        NOTIFY_ON_URGENT=True,
        MIN_URGENCY_TO_NOTIFY=3,
    )
    notifier = Notifier(settings)

    # Low urgency marketing should not notify
    low_payload = NotificationPayload(
        title="Marketing promo",
        body="50% off",
        category=EmailCategory.MARKETING_PROMO,
        urgency=1,
        sender="sales@shop.com",
        subject="Sale",
    )
    assert notifier.should_notify(low_payload) is False

    # Project update should notify
    project_payload = NotificationPayload(
        title="Project update",
        body="PR merged",
        category=EmailCategory.PROJECT_UPDATE,
        urgency=2,
        sender="dev@team.com",
        subject="PR #5",
    )
    assert notifier.should_notify(project_payload) is True


def test_desktop_notification_does_not_interpolate_email_text():
    """Regression: a crafted subject must not be able to inject PowerShell."""
    settings = Settings(DESKTOP_NOTIFY_ENABLED=True)
    notifier = Notifier(settings)
    evil = "x'; Remove-Item -Recurse C:/ ; '"
    payload = NotificationPayload(
        title=evil,
        body=evil,
        category=EmailCategory.URGENT_ACTIONABLE,
        urgency=5,
    )
    with patch("platform.system", return_value="Windows"), patch("subprocess.run") as run:
        result = notifier._send_desktop_notification(payload)
    assert result["status"] == "sent"
    args, kwargs = run.call_args
    script = args[0][-1]
    assert "Remove-Item" not in script
    assert kwargs["env"]["SENTINEL_NOTIFY_TITLE"] == evil
