"""IMAP client: UID-safe fetching, flagging, trash and restore operations."""

from __future__ import annotations

import email
import imaplib
import re
from datetime import UTC, datetime
from email.header import decode_header
from email.utils import parseaddr, parsedate_to_datetime
from typing import Dict, List, Optional

from rich.console import Console

from email_sentinel.config import Settings
from email_sentinel.models import EmailMessage

console = Console()

_UID_RE = re.compile(r"UID (\d+)")


def _fallback_message_id(folder: str, uid: str) -> str:
    """Deterministic ID for messages without a Message-ID header, so dedup still works."""
    return f"<no-message-id.{folder}.{uid}@email-sentinel>"


def _quote_mailbox(name: str) -> str:
    if name.startswith('"'):
        return name
    return '"' + name.replace("\\", "\\\\").replace('"', '\\"') + '"'


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
        self.client.select(_quote_mailbox(self.settings.IMAP_FOLDER))
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

    # ------------------------------------------------------------------
    # All mailbox operations use IMAP UIDs (never sequence numbers), so that
    # expunging one message can't shift the identity of another mid-scan.
    # Fetches use BODY.PEEK so scanning never flips the Seen flag.
    # ------------------------------------------------------------------

    def search_uids(self, unread_only: bool = True) -> List[str]:
        """Return UIDs in the watched folder, oldest first."""
        client = self._ensure_connected()
        status, data = client.uid("SEARCH", None, "UNSEEN" if unread_only else "ALL")
        if status != "OK" or not data or not data[0]:
            return []
        return [u.decode("utf-8") for u in data[0].split()]

    def fetch_message_ids(self, uids: List[str]) -> Dict[str, str]:
        """Cheaply fetch the Message-ID header for many UIDs in one round trip."""
        if not uids:
            return {}
        client = self._ensure_connected()
        status, data = client.uid("FETCH", ",".join(uids), "(UID BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)])")
        result: Dict[str, str] = {}
        if status != "OK" or not data:
            return result
        for part in data:
            if not (isinstance(part, tuple) and len(part) == 2):
                continue
            meta = part[0].decode("utf-8", errors="replace")
            m = _UID_RE.search(meta)
            if not m:
                continue
            uid = m.group(1)
            header_msg = email.message_from_bytes(part[1])
            result[uid] = (header_msg.get("Message-ID") or "").strip() or _fallback_message_id(
                self.settings.IMAP_FOLDER, uid
            )
        return result

    def fetch_emails(self, uids: List[str]) -> List[EmailMessage]:
        emails: List[EmailMessage] = []
        for uid in uids:
            try:
                msg = self.fetch_email_by_uid(uid)
                if msg:
                    emails.append(msg)
            except Exception as e:
                console.print(f"[red]Error parsing email UID {uid}: {e}[/red]")
        return emails

    def fetch_email_by_uid(self, uid: str) -> Optional[EmailMessage]:
        """Fetch and parse a single email by UID without marking it as read."""
        client = self._ensure_connected()
        status, data = client.uid("FETCH", uid, "(BODY.PEEK[])")
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
        return self.mark_batch_as_read([uid])

    def mark_batch_as_read(self, uids: List[str]) -> bool:
        """Mark multiple emails as read in a single UID STORE."""
        if not uids:
            return True
        if self.settings.DRY_RUN:
            console.print(f"[yellow][DRY-RUN] Would mark {len(uids)} email(s) as SEEN[/yellow]")
            return True
        try:
            client = self._ensure_connected()
            status, _ = client.uid("STORE", ",".join(uids), "+FLAGS", r"(\Seen)")
            return status == "OK"
        except Exception as e:
            console.print(f"[red]Failed to mark {len(uids)} email(s) as read: {e}[/red]")
            return False

    def move_to_trash(self, uid: str) -> bool:
        """Move one email to the Trash folder."""
        return self.move_batch_to_trash([uid])

    def move_batch_to_trash(self, uids: List[str]) -> bool:
        """Move emails to Trash (UID MOVE when supported, else COPY + delete)."""
        if not uids:
            return True
        if self.settings.DRY_RUN:
            console.print(f"[yellow][DRY-RUN] Would move {len(uids)} email(s) to Trash[/yellow]")
            return True
        try:
            return self._uid_move(",".join(uids), self.settings.IMAP_TRASH_FOLDER)
        except Exception as e:
            console.print(f"[red]Failed to move {len(uids)} email(s) to Trash: {e}[/red]")
            return False

    def restore_from_trash(self, message_id: str) -> bool:
        """Move a trashed email (found by Message-ID) back into the watched folder."""
        if self.settings.DRY_RUN:
            console.print(f"[yellow][DRY-RUN] Would restore {message_id} from Trash[/yellow]")
            return True
        client = self._ensure_connected()
        safe_id = message_id.replace('"', "").replace("\\", "")
        try:
            client.select(_quote_mailbox(self.settings.IMAP_TRASH_FOLDER))
            status, data = client.uid("SEARCH", None, "HEADER", "Message-ID", f'"{safe_id}"')
            if status != "OK" or not data or not data[0]:
                return False
            uids = [u.decode("utf-8") for u in data[0].split()]
            return self._uid_move(",".join(uids), self.settings.IMAP_FOLDER)
        finally:
            client.select(_quote_mailbox(self.settings.IMAP_FOLDER))

    def _uid_move(self, uid_set: str, destination: str) -> bool:
        client = self._ensure_connected()
        target = _quote_mailbox(destination)
        if "MOVE" in getattr(client, "capabilities", ()):
            status, _ = client.uid("MOVE", uid_set, target)
            return status == "OK"
        status, _ = client.uid("COPY", uid_set, target)
        if status != "OK":
            return False
        client.uid("STORE", uid_set, "+FLAGS", r"(\Deleted)")
        client.expunge()
        return True

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
        message_id = (msg.get("Message-ID") or "").strip() or _fallback_message_id(self.settings.IMAP_FOLDER, uid)

        # Date
        date_header = msg.get("Date")
        date_val = datetime.now(UTC)
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
