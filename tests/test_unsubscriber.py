"""Tests for Email Unsubscriber."""

from unittest.mock import MagicMock, patch
import httpx

from email_sentinel.config import Settings
from email_sentinel.models import EmailMessage, UnsubscribeMethod
from email_sentinel.unsubscriber import EmailUnsubscriber


def test_rfc8058_one_click_post():
    settings = Settings(DRY_RUN=False)
    unsub = EmailUnsubscriber(settings)

    email = EmailMessage(
        id="1",
        subject="Promo newsletter",
        sender="Marketing <promo@brand.com>",
        sender_email="promo@brand.com",
        list_unsubscribe="<https://brand.com/api/unsub?user=123>",
        list_unsubscribe_post="List-Unsubscribe=One-Click",
    )

    mock_resp = MagicMock(status_code=200)
    with patch("httpx.Client.post", return_value=mock_resp) as mock_post:
        result = unsub.unsubscribe(email)
        assert result.success is True
        assert result.method == UnsubscribeMethod.RFC8058_POST
        mock_post.assert_called_once()
        args, kwargs = mock_post.call_args
        assert args[0] == "https://brand.com/api/unsub?user=123"
        assert kwargs["data"] == {"List-Unsubscribe": "One-Click"}


def test_html_body_link_extraction_and_get():
    settings = Settings(DRY_RUN=False)
    unsub = EmailUnsubscriber(settings)

    html_content = """
    <html>
      <body>
        <p>Thanks for subscribing!</p>
        <a href="https://service.com/manage-subscription/optout?id=456">Click here to unsubscribe</a>
      </body>
    </html>
    """

    email = EmailMessage(
        id="2",
        subject="Newsletter",
        sender="news@service.com",
        sender_email="news@service.com",
        body_html=html_content,
    )

    mock_resp = MagicMock(status_code=200, text="You have successfully unsubscribed.")
    with patch("httpx.Client.get", return_value=mock_resp) as mock_get:
        result = unsub.unsubscribe(email)
        assert result.success is True
        assert result.method == UnsubscribeMethod.URL_GET
        mock_get.assert_called_once()
        assert "optout" in mock_get.call_args[0][0]


def test_protected_domain_skipped():
    settings = Settings(
        DRY_RUN=False,
        PROTECTED_DOMAINS=["trusted.com"],
    )
    unsub = EmailUnsubscriber(settings)

    email = EmailMessage(
        id="3",
        subject="Update",
        sender="admin@trusted.com",
        sender_email="admin@trusted.com",
        list_unsubscribe="<https://trusted.com/unsub>",
    )

    result = unsub.unsubscribe(email)
    assert result.success is False
    assert result.method == UnsubscribeMethod.SKIPPED


def test_dry_run_mode():
    settings = Settings(DRY_RUN=True)
    unsub = EmailUnsubscriber(settings)

    email = EmailMessage(
        id="4",
        subject="Sale",
        sender="sales@randomstore.com",
        sender_email="sales@randomstore.com",
        list_unsubscribe="<https://randomstore.com/unsub>",
    )

    result = unsub.unsubscribe(email)
    assert result.success is True
    assert "[DRY-RUN]" in result.message
