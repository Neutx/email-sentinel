"""Data models for Email Sentinel."""

from __future__ import annotations

from datetime import UTC, datetime
from enum import Enum
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class EmailCategory(str, Enum):
    MARKETING_PROMO = "marketing_promo"
    PROJECT_UPDATE = "project_update"
    URGENT_ACTIONABLE = "urgent_actionable"
    TRANSACTIONAL = "transactional"
    GENERAL_FYI = "general_fyi"
    SPAM = "spam"


class UnsubscribeMethod(str, Enum):
    RFC8058_POST = "rfc8058_post"
    MAILTO = "mailto"
    URL_GET = "url_get"
    FAILED = "failed"
    SKIPPED = "skipped"


class NotificationChannel(str, Enum):
    DESKTOP = "desktop"
    WHATSAPP = "whatsapp"
    TELEGRAM = "telegram"
    DISCORD = "discord"
    SLACK = "slack"
    WEBHOOK = "webhook"
    CONSOLE = "console"


class EmailMessage(BaseModel):
    id: str  # IMAP UID or Gmail ID
    message_id: str = ""  # RFC 822 Message-ID
    subject: str = ""
    sender: str = ""
    sender_name: str = ""
    sender_email: str = ""
    to: List[str] = Field(default_factory=list)
    cc: List[str] = Field(default_factory=list)
    date: datetime = Field(default_factory=lambda: datetime.now(UTC))
    body_plain: str = ""
    body_html: str = ""
    list_unsubscribe: Optional[str] = None
    list_unsubscribe_post: Optional[str] = None
    headers: Dict[str, str] = Field(default_factory=dict)

    @property
    def domain(self) -> str:
        if "@" in self.sender_email:
            return self.sender_email.split("@")[-1].lower().strip()
        return ""


class ClassificationResult(BaseModel):
    category: EmailCategory
    urgency: int = Field(default=1, ge=1, le=5)  # 1 (lowest) to 5 (critical/urgent)
    summary: str = ""
    project_name: Optional[str] = None
    action_required: bool = False
    action_description: Optional[str] = None
    confidence: float = Field(default=1.0, ge=0.0, le=1.0)
    reasoning: str = ""


class UnsubscribeResult(BaseModel):
    success: bool
    method: UnsubscribeMethod
    target: str = ""
    http_status: Optional[int] = None
    message: str = ""
    details: Dict[str, Any] = Field(default_factory=dict)


class NotificationPayload(BaseModel):
    title: str
    body: str
    category: EmailCategory
    urgency: int = 1
    project_name: Optional[str] = None
    sender: str = ""
    subject: str = ""
    received_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    action_description: Optional[str] = None


class ProcessedEmailResult(BaseModel):
    email: EmailMessage
    classification: ClassificationResult
    unsubscribed: Optional[UnsubscribeResult] = None
    deleted_or_trashed: bool = False
    notification_sent: bool = False
    channels_notified: List[NotificationChannel] = Field(default_factory=list)
    error: Optional[str] = None
