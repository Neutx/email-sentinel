"""Tests for Email Classifier."""

from email_sentinel.classifier import EmailClassifier
from email_sentinel.config import Settings
from email_sentinel.models import EmailCategory, EmailMessage


def test_classify_marketing_promo_with_header():
    settings = Settings(LLM_PROVIDER="rules_only")
    classifier = EmailClassifier(settings)

    email = EmailMessage(
        id="1",
        subject="Special Black Friday Deals - 50% Off Everything!",
        sender="deals@retailer.com",
        sender_email="deals@retailer.com",
        list_unsubscribe="<https://retailer.com/unsub?id=999>, <mailto:unsub@retailer.com>",
        body_plain="Check out our new catalog and discounts today.",
    )
    result = classifier.classify(email)
    assert result.category == EmailCategory.MARKETING_PROMO
    assert result.urgency == 1


def test_classify_github_project_update():
    settings = Settings(LLM_PROVIDER="rules_only")
    classifier = EmailClassifier(settings)

    email = EmailMessage(
        id="2",
        subject="[Murphy-Labs/email-sentinel] Pull request #12 merged (main)",
        sender="GitHub <notifications@github.com>",
        sender_email="notifications@github.com",
        body_plain="Pull request #12 merged by author.",
    )
    result = classifier.classify(email)
    assert result.category == EmailCategory.PROJECT_UPDATE
    assert "Murphy-Labs/email-sentinel" in (result.project_name or "")
    assert result.urgency >= 3


def test_classify_urgent_action_required():
    settings = Settings(LLM_PROVIDER="rules_only")
    classifier = EmailClassifier(settings)

    email = EmailMessage(
        id="3",
        subject="URGENT: Security alert - Suspicious login attempt detected",
        sender="security@authprovider.com",
        sender_email="security@authprovider.com",
        body_plain="We detected a suspicious login attempt from an unknown IP address.",
    )
    result = classifier.classify(email)
    assert result.category == EmailCategory.URGENT_ACTIONABLE
    assert result.urgency == 5
    assert result.action_required is True


def test_classify_transactional_receipt():
    settings = Settings(LLM_PROVIDER="rules_only")
    classifier = EmailClassifier(settings)

    email = EmailMessage(
        id="4",
        subject="Your order confirmation and receipt #984210",
        sender="orders@store.com",
        sender_email="orders@store.com",
        body_plain="Thank you for your order. Here is your receipt.",
    )
    result = classifier.classify(email)
    assert result.category == EmailCategory.TRANSACTIONAL
    assert result.action_required is False


def test_protected_domain_not_marked_marketing():
    settings = Settings(
        LLM_PROVIDER="rules_only",
        PROTECTED_DOMAINS=["github.com", "bank.com"],
    )
    classifier = EmailClassifier(settings)

    email = EmailMessage(
        id="5",
        subject="Weekly digest and updates",
        sender="GitHub <newsletter@github.com>",
        sender_email="newsletter@github.com",
        list_unsubscribe="<https://github.com/unsub>",
        body_plain="Updates for developers on GitHub.",
    )
    result = classifier.classify(email)
    # GitHub is a protected domain and contains dev keywords
    assert result.category == EmailCategory.PROJECT_UPDATE
