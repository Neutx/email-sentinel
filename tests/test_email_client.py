"""EmailClient must use UIDs and never mark mail as read just by scanning it."""

from email_sentinel.config import Settings
from email_sentinel.email_client import EmailClient
from tests.fakes import FakeIMAP, make_raw


def _client(fake: FakeIMAP, **overrides) -> EmailClient:
    settings = Settings(IMAP_USER="me@example.com", IMAP_PASSWORD="pw", **overrides)
    client = EmailClient(settings)
    client.client = fake
    return client


def _inbox(n: int = 3) -> FakeIMAP:
    return FakeIMAP({"INBOX": [make_raw(f"<m{i}@x.com>", f"Subject {i}", f"s{i}@x.com") for i in range(1, n + 1)]})


def test_fetch_does_not_mark_seen():
    fake = _inbox()
    client = _client(fake)
    uids = client.search_uids(unread_only=True)
    assert uids == ["1", "2", "3"]
    emails = client.fetch_emails(uids)
    assert [e.message_id for e in emails] == ["<m1@x.com>", "<m2@x.com>", "<m3@x.com>"]
    assert all("\\Seen" not in m.flags for m in fake.folders["INBOX"])


def test_fetch_message_ids_maps_uid_to_header():
    client = _client(_inbox())
    assert client.fetch_message_ids(["1", "3"]) == {"1": "<m1@x.com>", "3": "<m3@x.com>"}


def test_trash_then_mark_read_targets_correct_messages():
    """Regression: sequence numbers shift after EXPUNGE; UIDs must not."""
    fake = _inbox(4)
    client = _client(fake)
    assert client.move_to_trash("1")
    assert client.mark_as_read("3")
    inbox = {m.uid: m for m in fake.folders["INBOX"]}
    assert set(inbox) == {2, 3, 4}
    assert "\\Seen" in inbox[3].flags
    assert "\\Seen" not in inbox[2].flags and "\\Seen" not in inbox[4].flags
    assert len(fake.folders["[Gmail]/Trash"]) == 1


def test_trash_falls_back_to_copy_when_move_unsupported():
    fake = _inbox(2)
    fake.capabilities = ("IMAP4REV1",)
    client = _client(fake)
    assert client.move_batch_to_trash(["2"])
    assert [m.uid for m in fake.folders["INBOX"]] == [1]
    assert len(fake.folders["[Gmail]/Trash"]) == 1


def test_restore_from_trash_moves_back_and_reselects_inbox():
    fake = _inbox(2)
    client = _client(fake)
    client.move_to_trash("2")
    assert client.restore_from_trash("<m2@x.com>")
    assert fake.selected == "INBOX"
    assert fake.folders["[Gmail]/Trash"] == []
    assert any(b"<m2@x.com>" in m.raw for m in fake.folders["INBOX"])


def test_dry_run_never_touches_mailbox():
    fake = _inbox(2)
    client = _client(fake, DRY_RUN=True)
    assert client.move_to_trash("1")
    assert client.mark_as_read("2")
    assert [m.uid for m in fake.folders["INBOX"]] == [1, 2]
    assert all(not m.flags for m in fake.folders["INBOX"])


def test_missing_message_id_gets_deterministic_fallback():
    raw = make_raw("", "No id", "a@x.com").replace(b"Message-ID: \n", b"")
    fake = FakeIMAP({"INBOX": [raw]})
    client = _client(fake)
    first = client.fetch_email_by_uid("1")
    second = client.fetch_email_by_uid("1")
    assert first is not None and second is not None
    assert first.message_id == second.message_id == "<no-message-id.INBOX.1@email-sentinel>"
