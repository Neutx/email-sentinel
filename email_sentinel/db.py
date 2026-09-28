"""SQLite database layer for Email Sentinel."""

from __future__ import annotations

import contextlib
import json
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Generator, List, Optional

from email_sentinel.models import (
    ClassificationResult,
    EmailCategory,
    EmailMessage,
    NotificationChannel,
    UnsubscribeResult,
)


class Database:
    def __init__(self, db_path: str):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    @contextlib.contextmanager
    def _get_connection(self) -> Generator[sqlite3.Connection, None, None]:
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        try:
            conn.execute("PRAGMA journal_mode=WAL;")
            conn.execute("PRAGMA foreign_keys=ON;")
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    def _init_db(self) -> None:
        with self._get_connection() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS emails (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uid TEXT,
                    message_id TEXT UNIQUE,
                    sender TEXT,
                    sender_email TEXT,
                    subject TEXT,
                    received_at TEXT,
                    category TEXT,
                    urgency INTEGER,
                    summary TEXT,
                    project_name TEXT,
                    action_required INTEGER,
                    action_description TEXT,
                    is_trashed INTEGER DEFAULT 0,
                    is_unsubscribed INTEGER DEFAULT 0,
                    raw_headers_json TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP
                );

                CREATE INDEX IF NOT EXISTS idx_emails_message_id ON emails(message_id);
                CREATE INDEX IF NOT EXISTS idx_emails_category ON emails(category);
                CREATE INDEX IF NOT EXISTS idx_emails_project ON emails(project_name);

                CREATE TABLE IF NOT EXISTS unsub_logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email_id INTEGER,
                    sender_email TEXT,
                    domain TEXT,
                    method TEXT,
                    target TEXT,
                    http_status INTEGER,
                    success INTEGER,
                    error_message TEXT,
                    details_json TEXT,
                    attempted_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (email_id) REFERENCES emails(id) ON DELETE SET NULL
                );

                CREATE TABLE IF NOT EXISTS project_updates (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email_id INTEGER,
                    project_name TEXT,
                    sender TEXT,
                    subject TEXT,
                    summary TEXT,
                    urgency INTEGER,
                    action_required INTEGER,
                    action_description TEXT,
                    received_at TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (email_id) REFERENCES emails(id) ON DELETE SET NULL
                );

                CREATE INDEX IF NOT EXISTS idx_project_updates_name ON project_updates(project_name);

                CREATE TABLE IF NOT EXISTS notifications (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email_id INTEGER,
                    channel TEXT,
                    title TEXT,
                    body TEXT,
                    status TEXT,
                    sent_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    error_message TEXT,
                    FOREIGN KEY (email_id) REFERENCES emails(id) ON DELETE SET NULL
                );
                """
            )

    def is_email_processed(self, message_id: str) -> bool:
        if not message_id:
            return False
        with self._get_connection() as conn:
            cur = conn.execute("SELECT 1 FROM emails WHERE message_id = ?", (message_id,))
            return cur.fetchone() is not None

    def save_email(self, email: EmailMessage, classification: ClassificationResult) -> int:
        with self._get_connection() as conn:
            cur = conn.execute(
                """
                INSERT OR REPLACE INTO emails (
                    uid, message_id, sender, sender_email, subject,
                    received_at, category, urgency, summary, project_name,
                    action_required, action_description, raw_headers_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    email.id,
                    email.message_id,
                    email.sender,
                    email.sender_email,
                    email.subject,
                    email.date.isoformat(),
                    classification.category.value,
                    classification.urgency,
                    classification.summary,
                    classification.project_name,
                    1 if classification.action_required else 0,
                    classification.action_description,
                    json.dumps(email.headers),
                ),
            )
            email_id = cur.lastrowid
            assert email_id is not None
            return email_id

    def update_email_status(
        self,
        email_id: int,
        is_trashed: Optional[bool] = None,
        is_unsubscribed: Optional[bool] = None,
    ) -> None:
        updates = []
        params = []
        if is_trashed is not None:
            updates.append("is_trashed = ?")
            params.append(1 if is_trashed else 0)
        if is_unsubscribed is not None:
            updates.append("is_unsubscribed = ?")
            params.append(1 if is_unsubscribed else 0)

        if not updates:
            return

        params.append(email_id)
        query = f"UPDATE emails SET {', '.join(updates)} WHERE id = ?"
        with self._get_connection() as conn:
            conn.execute(query, tuple(params))

    def record_unsubscribe(
        self,
        email_id: Optional[int],
        sender_email: str,
        result: UnsubscribeResult,
    ) -> int:
        domain = sender_email.split("@")[-1].lower() if "@" in sender_email else ""
        with self._get_connection() as conn:
            cur = conn.execute(
                """
                INSERT INTO unsub_logs (
                    email_id, sender_email, domain, method, target,
                    http_status, success, error_message, details_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    email_id,
                    sender_email,
                    domain,
                    result.method.value,
                    result.target,
                    result.http_status,
                    1 if result.success else 0,
                    result.message if not result.success else None,
                    json.dumps(result.details),
                ),
            )
            if email_id and result.success:
                conn.execute("UPDATE emails SET is_unsubscribed = 1 WHERE id = ?", (email_id,))
            return cur.lastrowid or 0

    def record_project_update(
        self,
        email_id: int,
        classification: ClassificationResult,
        email: EmailMessage,
    ) -> int:
        with self._get_connection() as conn:
            cur = conn.execute(
                """
                INSERT INTO project_updates (
                    email_id, project_name, sender, subject, summary,
                    urgency, action_required, action_description, received_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    email_id,
                    classification.project_name or "General",
                    email.sender,
                    email.subject,
                    classification.summary,
                    classification.urgency,
                    1 if classification.action_required else 0,
                    classification.action_description,
                    email.date.isoformat(),
                ),
            )
            return cur.lastrowid or 0

    def record_notification(
        self,
        email_id: Optional[int],
        channel: NotificationChannel,
        title: str,
        body: str,
        status: str,
        error_message: Optional[str] = None,
    ) -> int:
        with self._get_connection() as conn:
            cur = conn.execute(
                """
                INSERT INTO notifications (
                    email_id, channel, title, body, status, error_message
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    email_id,
                    channel.value,
                    title,
                    body,
                    status,
                    error_message,
                ),
            )
            return cur.lastrowid or 0

    def get_recent_project_updates(
        self, limit: int = 50, project_name: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        with self._get_connection() as conn:
            if project_name:
                cur = conn.execute(
                    """
                    SELECT * FROM project_updates
                    WHERE project_name LIKE ?
                    ORDER BY received_at DESC LIMIT ?
                    """,
                    (f"%{project_name}%", limit),
                )
            else:
                cur = conn.execute(
                    """
                    SELECT * FROM project_updates
                    ORDER BY received_at DESC LIMIT ?
                    """,
                    (limit,),
                )
            return [dict(row) for row in cur.fetchall()]

    def get_unsubscribe_history(self, limit: int = 50) -> List[Dict[str, Any]]:
        with self._get_connection() as conn:
            cur = conn.execute(
                """
                SELECT * FROM unsub_logs
                ORDER BY attempted_at DESC LIMIT ?
                """,
                (limit,),
            )
            return [dict(row) for row in cur.fetchall()]

    def get_stats(self) -> Dict[str, Any]:
        with self._get_connection() as conn:
            total_emails = conn.execute("SELECT COUNT(*) FROM emails").fetchone()[0]
            unsubscribed = conn.execute("SELECT COUNT(*) FROM unsub_logs WHERE success = 1").fetchone()[0]
            trashed = conn.execute("SELECT COUNT(*) FROM emails WHERE is_trashed = 1").fetchone()[0]
            project_updates = conn.execute("SELECT COUNT(*) FROM project_updates").fetchone()[0]
            notifications_sent = conn.execute(
                "SELECT COUNT(*) FROM notifications WHERE status = 'sent'"
            ).fetchone()[0]

            categories_raw = conn.execute(
                "SELECT category, COUNT(*) as cnt FROM emails GROUP BY category"
            ).fetchall()
            categories = {row["category"]: row["cnt"] for row in categories_raw}

            return {
                "total_emails_processed": total_emails,
                "unsubscribed_count": unsubscribed,
                "trashed_count": trashed,
                "project_updates_count": project_updates,
                "notifications_sent_count": notifications_sent,
                "categories": categories,
            }
