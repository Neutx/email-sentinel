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


def test_project_names_are_normalized_onto_known_names():
    from email_sentinel.classifier import normalize_project_name

    known = ["Neutx/murphy-labs-website", "h-tool", "acme/web"]
    assert normalize_project_name("H Tool", known) == "h-tool"
    assert normalize_project_name("murphy-labs-website", known) == "Neutx/murphy-labs-website"
    assert normalize_project_name("neutx/web", known) == "neutx/web"  # different owner stays distinct
    assert normalize_project_name("Untitled", known) is None
    assert normalize_project_name("  New Thing ", known) == "New Thing"


def test_llm_prompt_lists_known_projects(monkeypatch):
    import json as _json
    from unittest.mock import MagicMock

    settings = Settings(LLM_PROVIDER="gemini", LLM_API_KEY="k", LLM_MODEL="m")
    captured = {}

    def fake_post(self, url, headers=None, json=None):
        captured["prompt"] = json["messages"][1]["content"]
        body = {"category": "project_update", "urgency": 3, "summary": "s", "project_name": "H Tool"}
        return MagicMock(status_code=200, json=lambda: {"choices": [{"message": {"content": _json.dumps(body)}}]})

    monkeypatch.setattr("httpx.Client.post", fake_post)
    email = EmailMessage(id="1", message_id="<x>", subject="Deploy", sender_email="ci@x.com")
    result = EmailClassifier(settings).classify(email, known_projects=["h-tool"])
    assert "h-tool" in captured["prompt"]
    assert result.project_name == "h-tool"
