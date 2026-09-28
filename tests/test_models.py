"""Tests for Email Sentinel data models."""

from email_sentinel.models import (
    ClassificationResult,
    EmailCategory,
    EmailMessage,
    NotificationPayload,
    UnsubscribeMethod,
    UnsubscribeResult,
)


def test_email_message_domain_extraction():
    msg = EmailMessage(
        id="101",
        subject="Special Deal 50% Off",
        sender="Promotions <promo@shop.deals.com>",
        sender_email="promo@shop.deals.com",
    )
    assert msg.domain == "shop.deals.com"


def test_classification_result_defaults():
    res = ClassificationResult(
        category=EmailCategory.PROJECT_UPDATE,
        urgency=4,
        summary="PR merged into main",
        project_name="Murphy Labs",
        action_required=False,
    )
    assert res.category == EmailCategory.PROJECT_UPDATE
    assert res.urgency == 4
    assert res.project_name == "Murphy Labs"
    assert res.confidence == 1.0


def test_unsubscribe_result_creation():
    unsub = UnsubscribeResult(
        success=True,
        method=UnsubscribeMethod.RFC8058_POST,
        target="https://example.com/unsub",
        http_status=200,
        message="One-click unsubscribe successful",
    )
    assert unsub.success is True
    assert unsub.method == UnsubscribeMethod.RFC8058_POST
    assert unsub.http_status == 200


def test_notification_payload_creation():
    payload = NotificationPayload(
        title="CI Build Failed",
        body="Tests failed on commit abc1234",
        category=EmailCategory.PROJECT_UPDATE,
        urgency=4,
        project_name="Email Sentinel",
        sender="notifications@github.com",
        subject="[Murphy-Labs/email-sentinel] Build #42 Failed",
        action_description="Check CI failure logs",
    )
    assert payload.category == EmailCategory.PROJECT_UPDATE
    assert payload.urgency == 4
    assert payload.project_name == "Email Sentinel"
