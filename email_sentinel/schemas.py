"""REST API request/response schemas (the contract the Android app is built against)."""

from __future__ import annotations

from typing import Dict, List, Literal, Optional

from pydantic import BaseModel, Field

from email_sentinel.models import EmailCategory


class Health(BaseModel):
    status: Literal["ok"] = "ok"
    version: str


class EmailItem(BaseModel):
    id: int
    message_id: Optional[str] = None
    sender: str = ""
    sender_email: str = ""
    subject: str = ""
    received_at: Optional[str] = None
    category: EmailCategory
    urgency: int = 1
    summary: str = ""
    project_name: Optional[str] = None
    action_required: bool = False
    action_description: Optional[str] = None
    is_trashed: bool = False
    is_unsubscribed: bool = False
    is_done: bool = False
    reclassified: bool = False
    dry_run: bool = False
    created_at: Optional[str] = None


class EmailPage(BaseModel):
    items: List[EmailItem]
    next_cursor: Optional[int] = Field(
        None, description="Pass as `before_id` to fetch the next (older) page; null when exhausted."
    )


class AlertsResponse(BaseModel):
    items: List[EmailItem]
    cursor: int = Field(description="Highest email id seen; pass back as `after_id` on the next poll.")


class ReclassifyRequest(BaseModel):
    category: EmailCategory


class DoneRequest(BaseModel):
    done: bool = True


class ActionResult(BaseModel):
    ok: bool
    message: str = ""
    email: Optional[EmailItem] = None


class ProjectSummary(BaseModel):
    name: str
    update_count: int
    last_update_at: Optional[str] = None
    open_actions: int = 0
    max_urgency: int = 1


class ProjectUpdate(BaseModel):
    id: int
    email_id: Optional[int] = None
    project_name: str
    sender: Optional[str] = None
    subject: Optional[str] = None
    summary: Optional[str] = None
    urgency: int = 1
    action_required: bool = False
    action_description: Optional[str] = None
    received_at: Optional[str] = None
    is_done: bool = False
    created_at: Optional[str] = None


class UnsubscribeLog(BaseModel):
    id: int
    email_id: Optional[int] = None
    sender_email: str = ""
    domain: str = ""
    method: str
    target: Optional[str] = None
    http_status: Optional[int] = None
    success: bool
    error_message: Optional[str] = None
    attempted_at: Optional[str] = None


class Stats(BaseModel):
    total_emails_processed: int
    unsubscribed_count: int
    trashed_count: int
    project_updates_count: int
    notifications_sent_count: int
    open_actions_count: int
    categories: Dict[str, int]


class ScanRequest(BaseModel):
    limit: int = Field(20, ge=1, le=200)
    unread_only: bool = True
    wait: bool = Field(False, description="Block until the scan finishes (otherwise returns 202 immediately).")


class ScanRun(BaseModel):
    id: int
    trigger: str
    status: Literal["running", "succeeded", "failed", "abandoned"]
    started_at: str
    finished_at: Optional[str] = None
    processed_count: int = 0
    skipped_count: int = 0
    summary: Dict[str, object] = Field(default_factory=dict)
    error: Optional[str] = None


class RuntimeSettings(BaseModel):
    dry_run: bool
    auto_unsubscribe: bool
    auto_delete_marketing: bool
    auto_mark_read_processed: bool
    notify_on_project_updates: bool
    notify_on_urgent: bool
    min_urgency_to_notify: int = Field(ge=1, le=5)
    protected_domains: List[str]
    project_keywords: List[str]


class RuntimeSettingsPatch(BaseModel):
    dry_run: Optional[bool] = None
    auto_unsubscribe: Optional[bool] = None
    auto_delete_marketing: Optional[bool] = None
    auto_mark_read_processed: Optional[bool] = None
    notify_on_project_updates: Optional[bool] = None
    notify_on_urgent: Optional[bool] = None
    min_urgency_to_notify: Optional[int] = Field(None, ge=1, le=5)
    protected_domains: Optional[List[str]] = None
    project_keywords: Optional[List[str]] = None


class SystemStatus(BaseModel):
    version: str
    server_time: str
    mailbox: str
    llm_provider: str
    llm_model: str
    scan_running: bool
    last_scan: Optional[ScanRun] = None
    latest_briefing_id: Optional[int] = None
    settings: RuntimeSettings


class BriefingCreate(BaseModel):
    period: Literal["morning", "evening", "adhoc"] = "adhoc"
    title: str = Field(min_length=1, max_length=200)
    summary: str = Field(
        min_length=1, max_length=500, description="One or two sentences; used as the notification text."
    )
    body_markdown: str = Field(min_length=1, max_length=20000)
    source: str = Field("hermes", max_length=50)


class Briefing(BaseModel):
    id: int
    period: str
    title: str
    summary: str
    body_markdown: str
    source: str
    created_at: str
