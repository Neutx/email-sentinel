"""In-memory IMAP server double that honours UID semantics (UIDs stay stable across EXPUNGE)."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from email.message import EmailMessage as MimeMessage
from typing import Dict, List, Optional, Tuple


def make_raw(
    message_id: str,
    subject: str,
    sender: str,
    body: str = "Hello",
    list_unsubscribe: Optional[str] = None,
    list_unsubscribe_post: Optional[str] = None,
) -> bytes:
    msg = MimeMessage()
    msg["Message-ID"] = message_id
    msg["Subject"] = subject
    msg["From"] = sender
    msg["To"] = "me@example.com"
    msg["Date"] = "Mon, 28 Sep 2026 09:00:00 +0000"
    if list_unsubscribe:
        msg["List-Unsubscribe"] = list_unsubscribe
    if list_unsubscribe_post:
        msg["List-Unsubscribe-Post"] = list_unsubscribe_post
    msg.set_content(body)
    return msg.as_bytes()


@dataclass
class FakeMessage:
    uid: int
    raw: bytes
    flags: set = field(default_factory=set)


class FakeIMAP:
    """Supports the subset of imaplib.IMAP4_SSL used by EmailClient."""

    def __init__(self, folders: Dict[str, List[bytes]], capabilities: Tuple[str, ...] = ("IMAP4REV1", "MOVE")):
        self.capabilities = capabilities
        self.folders: Dict[str, List[FakeMessage]] = {}
        self.next_uid = 1
        for name, raws in folders.items():
            self.folders[name] = []
            for raw in raws:
                self.append(name, raw)
        self.selected = "INBOX"
        self.commands: List[tuple] = []

    # -- helpers -------------------------------------------------------
    def append(self, folder: str, raw: bytes, flags: Optional[set] = None) -> int:
        uid = self.next_uid
        self.next_uid += 1
        self.folders.setdefault(folder, []).append(FakeMessage(uid, raw, set(flags or ())))
        return uid

    def _box(self) -> List[FakeMessage]:
        return self.folders[self.selected]

    def _by_uids(self, uid_set: str) -> List[FakeMessage]:
        wanted = {int(u) for u in uid_set.split(",")}
        return [m for m in self._box() if m.uid in wanted]

    @staticmethod
    def _unquote(name: str) -> str:
        return name[1:-1] if name.startswith('"') and name.endswith('"') else name

    # -- imaplib surface -----------------------------------------------
    def login(self, user: str, password: str):
        return "OK", [b"logged in"]

    def select(self, mailbox: str = "INBOX"):
        self.selected = self._unquote(mailbox)
        self.folders.setdefault(self.selected, [])
        return "OK", [str(len(self._box())).encode()]

    def close(self):
        return "OK", []

    def logout(self):
        return "BYE", []

    def expunge(self):
        self.folders[self.selected] = [m for m in self._box() if "\\Deleted" not in m.flags]
        return "OK", []

    def uid(self, command: str, *args):
        self.commands.append((command, *args))
        command = command.upper()
        if command == "SEARCH":
            criteria = [a for a in args if a is not None]
            box = self._box()
            if criteria[0] == "UNSEEN":
                hits = [m for m in box if "\\Seen" not in m.flags]
            elif criteria[0] == "ALL":
                hits = list(box)
            elif criteria[0] == "HEADER":
                needle = criteria[2].strip('"')
                hits = [m for m in box if needle.encode() in m.raw]
            else:
                raise AssertionError(f"unsupported search {criteria}")
            return "OK", [" ".join(str(m.uid) for m in hits).encode()]
        if command == "FETCH":
            uid_set, spec = args
            data: list = []
            for seq, m in enumerate(self._by_uids(uid_set), start=1):
                if "HEADER.FIELDS" in spec:
                    mid = re.search(rb"Message-ID: ([^\r\n]+)", m.raw)
                    payload = b"Message-ID: " + (mid.group(1) if mid else b"") + b"\r\n\r\n"
                    data.append(
                        (f"{seq} (UID {m.uid} BODY[HEADER.FIELDS (MESSAGE-ID)] {{{len(payload)}}}".encode(), payload)
                    )
                else:
                    assert "PEEK" in spec, "full fetches must use BODY.PEEK so the Seen flag is untouched"
                    data.append((f"{seq} (UID {m.uid} BODY[] {{{len(m.raw)}}}".encode(), m.raw))
                data.append(b")")
            return "OK", data or [None]
        if command == "STORE":
            uid_set, op, flags = args
            for m in self._by_uids(uid_set):
                for flag in flags.strip("()").split():
                    (m.flags.add if op.startswith("+") else m.flags.discard)(flag)
            return "OK", []
        if command in ("MOVE", "COPY"):
            uid_set, dest = args
            dest = self._unquote(dest)
            moved = self._by_uids(uid_set)
            for m in moved:
                self.append(dest, m.raw, m.flags - {"\\Deleted"})
            if command == "MOVE":
                ids = {m.uid for m in moved}
                self.folders[self.selected] = [m for m in self._box() if m.uid not in ids]
            return "OK", []
        raise AssertionError(f"unsupported UID command {command}")

    # Sequence-number commands must never be used.
    def search(self, *args):
        raise AssertionError("sequence-number SEARCH used; use UID SEARCH")

    def fetch(self, *args):
        raise AssertionError("sequence-number FETCH used; use UID FETCH")

    def store(self, *args):
        raise AssertionError("sequence-number STORE used; use UID STORE")

    def copy(self, *args):
        raise AssertionError("sequence-number COPY used; use UID COPY")
