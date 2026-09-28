"""Configuration management for Email Sentinel."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        env_prefix="SENTINEL_",
    )

    # General / Runtime
    DRY_RUN: bool = Field(default=False, description="Simulate actions without deleting/unsubscribing")
    POLL_INTERVAL_SECONDS: int = Field(default=300, description="Seconds between scans for the `watch` daemon")
    DB_PATH: str = Field(
        default=str(Path.home() / ".email_sentinel" / "sentinel.db"),
        description="Path to SQLite database",
    )

    # REST API (consumed by the Android app and Hermes)
    API_HOST: str = Field(default="127.0.0.1", description="Bind address for `email-sentinel serve`")
    API_PORT: int = Field(default=8765, description="Bind port for `email-sentinel serve`")
    API_TOKEN: str = Field(
        default="",
        description="Bearer token required on /api/* (mandatory when API_HOST is not loopback)",
    )
    SCAN_LEASE_MINUTES: int = Field(
        default=15, description="A running scan older than this is considered crashed and may be replaced"
    )

    # Mailbox (IMAP)
    IMAP_HOST: str = Field(default="imap.gmail.com", description="IMAP server hostname")
    IMAP_PORT: int = Field(default=993, description="IMAP server port (SSL)")
    IMAP_USER: str = Field(default="", description="Email address/username")
    IMAP_PASSWORD: str = Field(default="", description="Email password or App Password")
    IMAP_FOLDER: str = Field(default="INBOX", description="Folder to watch")
    IMAP_TRASH_FOLDER: str = Field(default="[Gmail]/Trash", description="Trash folder for deleted mail")
    FETCH_BATCH_SIZE: int = Field(default=20, description="Number of emails to fetch per batch")

    # Automated Actions
    AUTO_UNSUBSCRIBE: bool = Field(default=True, description="Automatically unsubscribe from marketing emails")
    AUTO_DELETE_MARKETING: bool = Field(default=True, description="Move marketing/spam emails to Trash")
    AUTO_MARK_READ_PROCESSED: bool = Field(default=True, description="Mark processed emails as read")

    # LLM / Classification
    LLM_PROVIDER: str = Field(
        default="rules_only",
        description="LLM provider: 'openai', 'gemini', 'openrouter', 'ollama', or 'rules_only'",
    )
    LLM_API_KEY: str = Field(default="", description="API key for LLM provider")
    LLM_BASE_URL: Optional[str] = Field(default=None, description="Custom LLM API base URL")
    LLM_MODEL: str = Field(default="gpt-4o-mini", description="Model name for classification")
    LLM_TEMPERATURE: float = Field(default=0.1, description="Sampling temperature for classification")
    LLM_REASONING_EFFORT: str = Field(
        default="low",
        description="reasoning_effort for thinking models (low keeps Gemini flash ~3s/email); empty to omit",
    )

    # Allowlist and Project Detection
    PROTECTED_DOMAINS: List[str] = Field(
        default_factory=lambda: [
            "github.com",
            "accounts.google.com",
            "paypal.com",
            "stripe.com",
            "apple.com",
            "bank",
        ],
        description="Domains that should never be unsubscribed or auto-deleted",
    )
    PROJECT_KEYWORDS: List[str] = Field(
        default_factory=lambda: [
            "murphy",
            "deploy",
            "release",
            "pull request",
            "issue",
            "ticket",
            "build",
            "outage",
            "incident",
        ],
        description="Keywords used to identify project updates",
    )

    # Notification settings
    DESKTOP_NOTIFY_ENABLED: bool = Field(default=True, description="Enable local native desktop notifications")
    NOTIFY_ON_PROJECT_UPDATES: bool = Field(default=True, description="Send notification for project updates")
    NOTIFY_ON_URGENT: bool = Field(default=True, description="Send notification for urgent/actionable emails")
    MIN_URGENCY_TO_NOTIFY: int = Field(default=2, description="Minimum urgency level (1-5) to trigger an alert")

    # WhatsApp Integration
    WHATSAPP_ENABLED: bool = Field(default=False, description="Enable WhatsApp alerts")
    WHATSAPP_PROVIDER: str = Field(
        default="callmebot",
        description="WhatsApp provider: 'callmebot', 'twilio', 'webhook'",
    )
    # CallMeBot WhatsApp (easiest free setup: phone + apikey)
    CALLMEBOT_PHONE: str = Field(default="", description="Phone number with country code (no + or spaces)")
    CALLMEBOT_API_KEY: str = Field(default="", description="CallMeBot API key")
    # Twilio WhatsApp
    TWILIO_ACCOUNT_SID: str = Field(default="", description="Twilio Account SID")
    TWILIO_AUTH_TOKEN: str = Field(default="", description="Twilio Auth Token")
    TWILIO_WHATSAPP_FROM: str = Field(default="whatsapp:+14155238886", description="Twilio WhatsApp sender")
    TWILIO_WHATSAPP_TO: str = Field(default="", description="Recipient WhatsApp number (whatsapp:+1234567890)")
    # Custom Webhook for WhatsApp / bridge
    WHATSAPP_WEBHOOK_URL: str = Field(default="", description="Custom WhatsApp webhook / bridge URL")

    # Telegram Integration
    TELEGRAM_ENABLED: bool = Field(default=False, description="Enable Telegram alerts")
    TELEGRAM_BOT_TOKEN: str = Field(default="", description="Telegram Bot Token")
    TELEGRAM_CHAT_ID: str = Field(default="", description="Telegram Chat ID")

    # Discord / Slack / Generic Webhooks
    DISCORD_WEBHOOK_URL: str = Field(default="", description="Discord Webhook URL")
    SLACK_WEBHOOK_URL: str = Field(default="", description="Slack Webhook URL")
    GENERIC_WEBHOOK_URL: str = Field(default="", description="Generic Webhook URL")


# Settings the Android app may change at runtime. Values live in the database
# (settings_overrides table) and are layered over the .env values.
RUNTIME_EDITABLE: Dict[str, type] = {
    "DRY_RUN": bool,
    "AUTO_UNSUBSCRIBE": bool,
    "AUTO_DELETE_MARKETING": bool,
    "AUTO_MARK_READ_PROCESSED": bool,
    "NOTIFY_ON_PROJECT_UPDATES": bool,
    "NOTIFY_ON_URGENT": bool,
    "MIN_URGENCY_TO_NOTIFY": int,
    "PROTECTED_DOMAINS": list,
    "PROJECT_KEYWORDS": list,
}


def get_settings() -> Settings:
    return Settings()


def apply_overrides(settings: Settings, overrides: Mapping[str, Any]) -> Settings:
    """Return a copy of `settings` with runtime-editable overrides applied."""
    updates = {k: v for k, v in overrides.items() if k in RUNTIME_EDITABLE}
    if not updates:
        return settings
    return settings.model_copy(update=updates)
