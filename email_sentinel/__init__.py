"""Email Sentinel - Autonomous AI Email Watcher, Unsubscriber & Project Updates Notifier."""

from email_sentinel.classifier import EmailClassifier
from email_sentinel.config import Settings, get_settings
from email_sentinel.db import Database
from email_sentinel.email_client import EmailClient
from email_sentinel.engine import SentinelEngine
from email_sentinel.models import (
    ClassificationResult,
    EmailCategory,
    EmailMessage,
    NotificationChannel,
    NotificationPayload,
    ProcessedEmailResult,
    UnsubscribeMethod,
    UnsubscribeResult,
)
from email_sentinel.notifier import Notifier
from email_sentinel.unsubscriber import EmailUnsubscriber

__version__ = "0.1.0"
__all__ = [
    "EmailClassifier",
    "EmailUnsubscriber",
    "Notifier",
    "EmailClient",
    "SentinelEngine",
    "Database",
    "Settings",
    "get_settings",
    "EmailMessage",
    "EmailCategory",
    "ClassificationResult",
    "UnsubscribeMethod",
    "UnsubscribeResult",
    "NotificationPayload",
    "NotificationChannel",
    "ProcessedEmailResult",
]
