"""Email classification and triage engine."""

from __future__ import annotations

import json
import re
from typing import Iterable, Optional, Sequence

import httpx
from rich.console import Console

from email_sentinel.config import Settings
from email_sentinel.models import ClassificationResult, EmailCategory, EmailMessage

console = Console()

_PLACEHOLDER_PROJECTS = {"", "untitled", "general", "none", "null", "n/a", "na", "unknown", "project", "misc"}


def _alnum(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", text.lower())


def _same_project(a: str, b: str) -> bool:
    """'h-tool' == 'H Tool'; 'murphy-labs-website' == 'Neutx/murphy-labs-website'.

    Owner prefixes are only ignored when one side has none, so 'acme/web' and
    'neutx/web' stay distinct.
    """
    if _alnum(a) == _alnum(b):
        return True
    if ("/" in a) != ("/" in b):
        return _alnum(a.split("/")[-1]) == _alnum(b.split("/")[-1])
    return False


def normalize_project_name(name: Optional[str], known: Iterable[str] = ()) -> Optional[str]:
    """Map a classifier-supplied project name onto an existing canonical name.

    LLMs spell the same project differently between emails ("h-tool", "H Tool");
    reuse the first (most recent) known name that matches, and drop placeholders.
    """
    if name is None or name.strip().lower() in _PLACEHOLDER_PROJECTS or not _alnum(name):
        return None
    for existing in known:
        if _same_project(name, existing):
            return existing
    return name.strip()


class EmailClassifier:
    def __init__(self, settings: Settings):
        self.settings = settings

    def classify(self, email: EmailMessage, known_projects: Sequence[str] = ()) -> ClassificationResult:
        """Classify an email using LLM if configured, otherwise rule-based heuristics.

        `known_projects` (most recent first) lets the LLM reuse existing project names.
        """
        result = self._classify(email, known_projects)
        result.project_name = normalize_project_name(result.project_name, known_projects)
        return result

    def _classify(self, email: EmailMessage, known_projects: Sequence[str]) -> ClassificationResult:
        # 1. Try LLM classification if provider configured and key exists
        if self.settings.LLM_PROVIDER != "rules_only" and (
            self.settings.LLM_API_KEY or self.settings.LLM_PROVIDER == "ollama"
        ):
            try:
                llm_result = self._classify_with_llm(email, known_projects)
                if llm_result:
                    # Enforce domain protection on LLM output
                    if self._is_protected(email) and llm_result.category in (
                        EmailCategory.MARKETING_PROMO,
                        EmailCategory.SPAM,
                    ):
                        llm_result.category = EmailCategory.GENERAL_FYI
                        llm_result.reasoning += " (Overridden: Protected domain)"
                    return llm_result
            except Exception as e:
                console.print(f"[yellow]LLM classification failed ({type(e).__name__}: {e}); using rules.[/yellow]")

        # 2. Fallback to high-precision rule-based heuristics
        return self._classify_with_rules(email)

    def _is_protected(self, email: EmailMessage) -> bool:
        sender_lower = email.sender_email.lower()
        domain_lower = email.domain
        for protected in self.settings.PROTECTED_DOMAINS:
            p_lower = protected.lower().strip()
            if p_lower and (p_lower in sender_lower or p_lower in domain_lower):
                return True
        return False

    def _classify_with_rules(self, email: EmailMessage) -> ClassificationResult:
        """High-precision heuristic and regex-based classification."""
        subject = email.subject.lower()
        sender_email = email.sender_email.lower()
        domain = email.domain
        body = (email.body_plain or email.body_html or "").lower()
        has_list_unsub = bool(email.list_unsubscribe)

        # 1. Urgent / Critical Security Alerts & Action Required
        urgent_keywords = [
            "security alert",
            "suspicious login",
            "account compromised",
            "account suspended",
            "payment failed",
            "unauthorized access",
            "server down",
            "critical alert",
            "incident response",
            "signature requested",
            "action required",
            "urgent action",
        ]
        if any(k in subject for k in urgent_keywords):
            return ClassificationResult(
                category=EmailCategory.URGENT_ACTIONABLE,
                urgency=5,
                summary=f"Urgent notification regarding: {email.subject}",
                action_required=True,
                action_description=f"Review urgent email from {email.sender}: {email.subject}",
                confidence=0.98,
                reasoning="Matched critical security / urgent action pattern in subject",
            )

        # 2. Authentic Developer & Project Updates (GitHub, GitLab, Linear, Jira, Sentry, CI/CD)
        dev_platforms = [
            "github.com",
            "gitlab.com",
            "linear.app",
            "atlassian.net",
            "jira",
            "sentry.io",
            "circleci.com",
            "vercel.com",
            "render.com",
            "aws.amazon.com",
        ]
        is_dev_platform = any(dp in sender_email or dp in domain for dp in dev_platforms)

        # Check explicit project keywords in subject or sender (not loose body)
        matched_project = None
        for kw in self.settings.PROJECT_KEYWORDS:
            kw_clean = kw.lower().strip()
            if kw_clean and (kw_clean in subject or (len(kw_clean) >= 5 and kw_clean in sender_email)):
                matched_project = kw.capitalize()
                break

        if is_dev_platform or matched_project:
            project_name = matched_project or (
                "GitHub" if "github" in sender_email or "github" in subject else "Project Update"
            )
            repo_match = re.search(r"\[([a-zA-Z0-9_\-\./]+)\]", email.subject)
            if repo_match:
                project_name = repo_match.group(1)

            urgency = 3
            action_required = False
            action_desc = None
            if any(f in subject for f in ["failed", "broken", "incident", "outage", "error"]):
                urgency = 4
                action_required = True
                action_desc = "Inspect build / CI or service failure"
            elif any(r in subject for r in ["review requested", "requested your review", "assigned to you"]):
                urgency = 3
                action_required = True
                action_desc = "Code review or ticket action requested"

            return ClassificationResult(
                category=EmailCategory.PROJECT_UPDATE,
                urgency=urgency,
                summary=f"Project update for {project_name}: {email.subject}",
                project_name=project_name,
                action_required=action_required,
                action_description=action_desc,
                confidence=0.92,
                reasoning="Identified development platform update",
            )

        # 3. Transactional Messages (OTPs, Receipts, Invoices, Orders, Shipping)
        transactional_keywords = [
            "receipt",
            "invoice",
            "order confirmation",
            "your order",
            "tracking number",
            "package delivered",
            "verification code",
            "your code is",
            "password reset",
            "billing statement",
            "payment receipt",
        ]
        if any(tk in subject for tk in transactional_keywords) or any(
            tk in body[:250] for tk in ["verification code", "your one-time password", "otp"]
        ):
            return ClassificationResult(
                category=EmailCategory.TRANSACTIONAL,
                urgency=2,
                summary=f"Transactional message: {email.subject}",
                action_required=False,
                confidence=0.9,
                reasoning="Matched transactional receipt/billing pattern",
            )

        # 4. Marketing / Newsletters / Commercial Digests / Promo Emails
        marketing_senders = [
            "marketing",
            "newsletter",
            "promo",
            "campaign",
            "deals",
            "offers",
            "news@",
            "digest@",
            "sales@",
            "promotions@",
            "updates@",
            "info@",
            "mail.",
            "em.",
            "notice.alibaba.com",
            "email.groww.in",
            "nipponindia.email",
        ]
        is_promo_sender = any(ms in sender_email or ms in domain for ms in marketing_senders)

        marketing_keywords = [
            "discount",
            "sale",
            "special offer",
            "% off",
            "save big",
            "deals of the day",
            "digest",
            "newsletter",
            "weekly round-up",
            "fund!",
            "invest",
            "portfolio",
            "webinar",
            "samples available",
            "trending topics",
            "black friday",
            "cyber monday",
            "free trial",
            "pricing update",
        ]
        is_promo_subject = any(mk in subject for mk in marketing_keywords)

        # If it has List-Unsubscribe or is a known marketing sender / promo subject
        if not self._is_protected(email) and (
            has_list_unsub or is_promo_sender or (is_promo_subject and is_promo_sender)
        ):
            return ClassificationResult(
                category=EmailCategory.MARKETING_PROMO,
                urgency=1,
                summary=f"Promotional/Marketing email: {email.subject}",
                action_required=False,
                confidence=0.95,
                reasoning=f"Detected commercial sender/digest/promo pattern (List-Unsubscribe: {has_list_unsub})",
            )

        # 5. Protected Domain Safeguard
        if self._is_protected(email):
            return ClassificationResult(
                category=EmailCategory.GENERAL_FYI,
                urgency=2,
                summary=f"Email from protected sender {email.sender}: {email.subject}",
                action_required=False,
                confidence=0.85,
                reasoning="Protected domain notification",
            )

        # 6. Default to General FYI
        return ClassificationResult(
            category=EmailCategory.GENERAL_FYI,
            urgency=2,
            summary=f"Email from {email.sender}: {email.subject}",
            action_required=False,
            confidence=0.7,
            reasoning="Standard incoming correspondence",
        )

    def _classify_with_llm(
        self, email: EmailMessage, known_projects: Sequence[str] = ()
    ) -> Optional[ClassificationResult]:
        """Classify using an LLM (OpenAI-compatible / OpenRouter / Gemini / Ollama)."""
        known_list = ", ".join(list(known_projects)[:40]) or "(none yet)"
        prompt = f"""You are an expert AI email triage assistant.
Analyze this email and classify it accurately into one of the following categories:
- marketing_promo: Newsletters, promotional offers, marketing campaigns, commercial digests, sales pitches, bulk emails.
- project_update: Updates regarding software development, GitHub/GitLab, pull requests, CI/CD builds, Jira/Linear/Notion tickets, deployments, or client project milestones.
- urgent_actionable: Critical messages requiring immediate human attention, direct personal emails with urgent questions, payment failures, security alerts, contracts to sign.
- transactional: Order confirmations, receipts, invoices, tracking codes, 2FA/OTPs, account verifications.
- general_fyi: Informational emails, team discussions, non-urgent general updates.
- spam: Phishing, blatant junk, unsolicited malicious offers.

Email Details:
Sender: {email.sender} <{email.sender_email}>
Subject: {email.subject}
Date: {email.date.isoformat()}
Has List-Unsubscribe Header: {bool(email.list_unsubscribe)}
Body Excerpt:
{(email.body_plain or email.body_html)[:1500]}

Known project names (if this email is about one of them, set project_name to that exact spelling;
use null when the email is not about a specific project or repository):
{known_list}

Respond ONLY with a JSON object matching this schema:
{{
  "category": "marketing_promo" | "project_update" | "urgent_actionable" | "transactional" | "general_fyi" | "spam",
  "urgency": 1 to 5 (1=lowest, 5=critical),
  "summary": "1-2 concise sentences summarizing the content",
  "project_name": "Name of the project/repository if applicable, otherwise null",
  "action_required": true/false,
  "action_description": "Description of action required by the user, or null",
  "confidence": 0.0 to 1.0,
  "reasoning": "Brief reason for this classification"
}}
"""
        base_url = self.settings.LLM_BASE_URL
        if not base_url:
            if self.settings.LLM_PROVIDER == "openrouter":
                base_url = "https://openrouter.ai/api/v1"
            elif self.settings.LLM_PROVIDER == "ollama":
                base_url = "http://localhost:11434/v1"
            elif self.settings.LLM_PROVIDER == "gemini":
                base_url = "https://generativelanguage.googleapis.com/v1beta/openai"
            else:
                base_url = "https://api.openai.com/v1"

        headers = {
            "Authorization": f"Bearer {self.settings.LLM_API_KEY}",
            "Content-Type": "application/json",
        }
        if self.settings.LLM_PROVIDER == "openrouter":
            headers["HTTP-Referer"] = "https://github.com/MurphyLabs/email-sentinel"
            headers["X-Title"] = "Email Sentinel"

        payload = {
            "model": self.settings.LLM_MODEL,
            "messages": [
                {
                    "role": "system",
                    "content": "You are a precise email classifier that always outputs valid JSON.",
                },
                {"role": "user", "content": prompt},
            ],
            "temperature": self.settings.LLM_TEMPERATURE,
            "response_format": {"type": "json_object"},
        }
        if self.settings.LLM_REASONING_EFFORT and self.settings.LLM_PROVIDER != "ollama":
            payload["reasoning_effort"] = self.settings.LLM_REASONING_EFFORT

        with httpx.Client(timeout=30.0) as client:
            response = client.post(f"{base_url}/chat/completions", headers=headers, json=payload)
            if response.status_code != 200:
                console.print(f"[yellow]LLM API returned HTTP {response.status_code}: {response.text[:200]}[/yellow]")
                return None

            data = response.json()
            content = data["choices"][0]["message"]["content"].strip()
            if content.startswith("```"):
                content = re.sub(r"^```(?:json)?\s*|\s*```$", "", content)
            parsed = json.loads(content)

            return ClassificationResult(
                category=EmailCategory(parsed["category"]),
                urgency=int(parsed.get("urgency", 1)),
                summary=parsed.get("summary", ""),
                project_name=parsed.get("project_name"),
                action_required=bool(parsed.get("action_required", False)),
                action_description=parsed.get("action_description"),
                confidence=float(parsed.get("confidence", 1.0)),
                reasoning=parsed.get("reasoning", "LLM classified"),
            )
