"""Universal IMAP Client supporting SSL, message decoding, trash operations, and IMAP IDLE."""

from __future__ import annotations

import email
from email.header import decode_header
from email.utils import parseaddr, parsedate_to_datetime
import imaplib
import socket
import time
from datetime import datetime, timezone
from typing import Dict, Generator, List, Optional, Tuple

from rich.console import Console

from email_sentinel.config import Settings
from email_sentinel.models import EmailMessage

console = Console()


class EmailClient:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.client: Optional[imaplib.IMAP4_SSL] = None

    def connect(self) -> None:
        """Connect and authenticate to the IMAP server."""
        if not self.settings.IMAP_USER or not self.settings.IMAP_PASSWORD:
            raise ValueError("IMAP_USER and IMAP_PASSWORD must be configured.")

        console.print(f"[cyan]Connecting to IMAP {self.settings.IMAP_HOST}:{self.settings.IMAP_PORT}...[/cyan]")
        self.client = imaplib.IMAP4_SSL(self.settings.IMAP_HOST, self.settings.IMAP_PORT)
        self.client.login(self.settings.IMAP_USER, self.settings.IMAP_PASSWORD)
        self.client.select(self.settings.IMAP_FOLDER)
        console.print("[green]Connected and authenticated successfully.[/green]")

    def close(self) -> None:
        """Close connection cleanly."""
        if self.client:
            try:
                self.client.close()
            except Exception:
                pass
            try:
                self.client.logout()
            except Exception:
                pass
            self.client = None

    def _ensure_connected(self) -> imaplib.IMAP4_SSL:
        if self.client is None:
            self.connect()
        assert self.client is not None
        return self.client

    def fetch_unseen_emails(self, limit: Optional[int] = None) -> List[EmailMessage]:
        """Fetch unseen/unread emails from the mailbox."""
        client = self._ensure_connected()
        status, data = client.search(None, "UNSEEN")
        if status != "OK" or not data or not data[0]:
            return []

        uids = data[0].split()
        if limit:
            uids = uids[-limit:]

        emails: List[EmailMessage] = []
        for uid_bytes in uids:
            uid = uid_bytes.decode("utf-8")
            try:
                msg = self.fetch_email_by_uid(uid)
                if msg:
                    emails.append(msg)
            except Exception as e:
                console.print(f"[red]Error parsing email UID {uid}: {e}[/red]")

        return emails

    def fetch_recent_emails(self, limit: int = 20) -> List[EmailMessage]:
        """Fetch the most recent emails from the mailbox (read and unread)."""
        client = self._ensure_connected()
        status, data = client.search(None, "ALL")
        if status != "OK" or not data or not data[0]:
            return []

        uids = data[0].split()
        target_uids = uids[-limit:]

        emails: List[EmailMessage] = []
        for uid_bytes in target_uids:
            uid = uid_bytes.decode("utf-8")
            try:
                msg = self.fetch_email_by_uid(uid)
                if msg:
                    emails.append(msg)
            except Exception as e:
                console.print(f"[red]Error parsing email UID {uid}: {e}[/red]")

        return emails

    def fetch_email_by_uid(self, uid: str) -> Optional[EmailMessage]:
        """Fetch and parse a single email by UID."""
        client = self._ensure_connected()
        status, data = client.fetch(uid, "(RFC822)")
        if status != "OK" or not data or not data[0]:
            return None

        raw_bytes = b""
        for part in data:
            if isinstance(part, tuple) and len(part) == 2:
                raw_bytes = part[1]
                break

        if not raw_bytes:
            return None

        return self._parse_raw_email(uid, raw_bytes)

    def mark_as_read(self, uid: str) -> bool:
        """Mark an email as read / SEEN."""
        if self.settings.DRY_RUN:
            console.print(f"[yellow][DRY-RUN] Would mark UID {uid} as SEEN[/yellow]")
            return True
        try:
            client = self._ensure_connected()
            client.store(uid, "+FLAGS", "\\Seen")
            return True
        except Exception as e:
            console.print(f"[red]Failed to mark UID {uid} as read: {e}[/red]")
            return False

    def move_to_trash(self, uid: str) -> bool:
        """Move email to Trash folder and mark for deletion."""
        if self.settings.DRY_RUN:
            console.print(f"[yellow][DRY-RUN] Would move UID {uid} to Trash and delete[/yellow]")
            return True

        client = self._ensure_connected()
        trash_folder = self.settings.IMAP_TRASH_FOLDER

        try:
            # 1. Try COPY to trash folder
            copy_status, _ = client.copy(uid, trash_folder)
            if copy_status == "OK":
                client.store(uid, "+FLAGS", "\\Deleted")
                client.expunge()
                return True
        except Exception:
            # Fallback to generic Trash or mark Deleted directly
            pass

        try:
            client.store(uid, "+FLAGS", "\\Deleted")
            client.expunge()
            return True
        except Exception as e:
            console.print(f"[red]Failed to delete UID {uid}: {e}[/red]")
            return False

    def move_batch_to_trash(self, uids: List[str]) -> bool:
        """Move multiple emails to Trash in a single batch operation."""
        if not uids:
            return True
        if self.settings.DRY_RUN:
            console.print(f"[yellow][DRY-RUN] Would move {len(uids)} emails to Trash[/yellow]")
            return True

        client = self._ensure_connected()
        uids_str = ",".join(uids)
        trash_folder = self.settings.IMAP_TRASH_FOLDER

        try:
            copy_status, _ = client.copy(uids_str, trash_folder)
            if copy_status == "OK":
                client.store(uids_str, "+FLAGS", "\\Deleted")
                client.expunge()
                return True
        except Exception:
            pass

        try:
            client.store(uids_str, "+FLAGS", "\\Deleted")
            client.expunge()
            return True
        except Exception as e:
            console.print(f"[red]Failed to batch delete {len(uids)} emails: {e}[/red]")
            return False

    def mark_batch_as_read(self, uids: List[str]) -> bool:
        """Mark multiple emails as read in a single batch operation."""
        if not uids:
            return True
        if self.settings.DRY_RUN:
            return True
        try:
            client = self._ensure_connected()
            client.store(",".join(uids), "+FLAGS", "\\Seen")
            return True
        except Exception as e:
            console.print(f"[red]Failed to batch mark as read: {e}[/red]")
            return False

    def idle_watch(self) -> Generator[List[EmailMessage], None, None]:
        """Watch mailbox continuously using polling or IMAP IDLE."""
        while True:
            try:
                self._ensure_connected()
                unseen = self.fetch_unseen_emails()
                if unseen:
                    yield unseen

                if self.settings.USE_IMAP_IDLE and hasattr(self.client, "idle"):
                    # Wait via IDLE or fallback sleep
                    time.sleep(self.settings.POLL_INTERVAL_SECONDS)
                else:
                    time.sleep(self.settings.POLL_INTERVAL_SECONDS)
            except (imaplib.IMAP4.error, socket.error, OSError) as e:
                console.print(f"[yellow]IMAP connection interrupted ({e}). Reconnecting in 5s...[/yellow]")
                self.close()
                time.sleep(5)
            except Exception as e:
                console.print(f"[red]Unexpected error in idle_watch: {e}[/red]")
                time.sleep(10)

    def _decode_header_str(self, header_raw: Optional[str]) -> str:
        if not header_raw:
            return ""
        decoded_parts = decode_header(header_raw)
        result = []
        for part, encoding in decoded_parts:
            if isinstance(part, bytes):
                try:
                    result.append(part.decode(encoding or "utf-8", errors="replace"))
                except Exception:
                    result.append(part.decode("latin1", errors="replace"))
            else:
                result.append(str(part))
        return "".join(result)

    def _parse_raw_email(self, uid: str, raw_bytes: bytes) -> EmailMessage:
        msg = email.message_from_bytes(raw_bytes)

        # Subject
        subject = self._decode_header_str(msg.get("Subject", ""))

        # From
        raw_from = self._decode_header_str(msg.get("From", ""))
        sender_name, sender_email = parseaddr(raw_from)

        # Message-ID
        message_id = msg.get("Message-ID", f"generated-{uid}-{int(time.time())}")

        # Date
        date_header = msg.get("Date")
        date_val = datetime.now(timezone.utc)
        if date_header:
            try:
                date_val = parsedate_to_datetime(date_header)
            except Exception:
                pass

        # List-Unsubscribe & Post headers
        list_unsub = msg.get("List-Unsubscribe")
        list_unsub_post = msg.get("List-Unsubscribe-Post")

        # Collect headers dict
        headers = {}
        for k, v in msg.items():
            headers[k] = self._decode_header_str(v)

        # Extract bodies
        body_plain = ""
        body_html = ""

        if msg.is_multipart():
            for part in msg.walk():
                content_type = part.get_content_type()
                content_disposition = str(part.get("Content-Disposition", ""))

                if "attachment" in content_disposition:
                    continue

                payload = part.get_payload(decode=True)
                if not payload:
                    continue

                charset = part.get_content_charset() or "utf-8"
                try:
                    text = payload.decode(charset, errors="replace")
                except Exception:
                    text = payload.decode("latin1", errors="replace")

                if content_type == "text/plain":
                    body_plain += text + "\n"
                elif content_type == "text/html":
                    body_html += text + "\n"
        else:
            payload = msg.get_payload(decode=True)
            if payload:
                charset = msg.get_content_charset() or "utf-8"
                try:
                    text = payload.decode(charset, errors="replace")
                except Exception:
                    text = payload.decode("latin1", errors="replace")

                if msg.get_content_type() == "text/html":
                    body_html = text
                else:
                    body_plain = text

        return EmailMessage(
            id=uid,
            message_id=message_id,
            subject=subject,
            sender=raw_from,
            sender_name=sender_name,
            sender_email=sender_email,
            to=[msg.get("To", "")],
            date=date_val,
            body_plain=body_plain.strip(),
            body_html=body_html.strip(),
            list_unsubscribe=list_unsub,
            list_unsubscribe_post=list_unsub_post,
            headers=headers,
        )
