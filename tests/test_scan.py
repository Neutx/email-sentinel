"""End-to-end scan behaviour against a fake IMAP server."""

import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from email_sentinel.config import Settings
from email_sentinel.db import Database, ScanInProgressError
from email_sentinel.engine import SentinelEngine
from tests.fakes import FakeIMAP, make_raw


def _settings(tmpdir: str, **overrides) -> Settings:
    base = dict(
        DB_PATH=str(Path(tmpdir) / "sentinel.db"),
        IMAP_USER="me@example.com",
        IMAP_PASSWORD="pw",
        LLM_PROVIDER="rules_only",
        DESKTOP_NOTIFY_ENABLED=False,
    )
    base.update(overrides)
    return Settings(**base)


def _mailbox() -> FakeIMAP:
    return FakeIMAP(
        {
            "INBOX": [
                make_raw(
                    "<promo1@shop.com>",
                    "Flash sale: 70% off everything",
                    "Shop <deals@shop.com>",
                    list_unsubscribe="<https://shop.com/unsub>",
                    list_unsubscribe_post="List-Unsubscribe=One-Click",
                ),
                make_raw(
                    "<pr@github.com>",
                    "[Murphy-Labs/core] Pull request #88 merged",
                    "GitHub <notifications@github.com>",
                ),
                make_raw(
                    "<promo2@shop.com>",
                    "Weekly newsletter: exclusive deals",
                    "Shop <news@shop.com>",
                    list_unsubscribe="<https://shop.com/unsub2>",
                    list_unsubscribe_post="List-Unsubscribe=One-Click",
                ),
                make_raw("<fyi@team.com>", "Lunch on Friday", "Sam <sam@team.com>"),
            ]
        }
    )


def _run(settings: Settings, fake: FakeIMAP):
    with (
        patch("imaplib.IMAP4_SSL", return_value=fake),
        patch("httpx.Client.post", return_value=MagicMock(status_code=200)),
    ):
        return SentinelEngine(settings).run_scan(limit=20, trigger="test")


def test_scan_trashes_marketing_and_marks_project_read():
    with tempfile.TemporaryDirectory() as tmp:
        fake = _mailbox()
        report = _run(_settings(tmp), fake)

        assert len(report.results) == 4
        inbox = {m.raw.split(b"Message-ID: ")[1].split(b"\n")[0].strip(): m for m in fake.folders["INBOX"]}
        assert set(inbox) == {b"<pr@github.com>", b"<fyi@team.com>"}
        assert "\\Seen" in inbox[b"<pr@github.com>"].flags
        assert "\\Seen" not in inbox[b"<fyi@team.com>"].flags  # FYI stays unread for the human
        assert len(fake.folders["[Gmail]/Trash"]) == 2

        db = Database(str(Path(tmp) / "sentinel.db"))
        scan = db.get_last_scan()
        assert scan["status"] == "succeeded"
        assert scan["summary"]["trashed"] == 2
        assert db.get_stats()["trashed_count"] == 2


def test_second_scan_skips_processed_without_reclassifying():
    with tempfile.TemporaryDirectory() as tmp:
        settings = _settings(tmp)
        fake = _mailbox()
        _run(settings, fake)
        with patch("email_sentinel.classifier.EmailClassifier.classify") as classify:
            report = _run(settings, fake)
        assert report.results == []
        assert report.skipped == 1  # only the unread FYI is still UNSEEN
        classify.assert_not_called()


def test_dry_run_changes_nothing_then_live_run_reprocesses():
    with tempfile.TemporaryDirectory() as tmp:
        fake = _mailbox()
        _run(_settings(tmp, DRY_RUN=True), fake)
        assert len(fake.folders["INBOX"]) == 4
        assert all(not m.flags for m in fake.folders["INBOX"])
        db = Database(str(Path(tmp) / "sentinel.db"))
        assert db.get_stats()["trashed_count"] == 0

        report = _run(_settings(tmp), fake)
        assert len(report.results) == 4
        assert len(fake.folders["[Gmail]/Trash"]) == 2
        assert db.get_stats()["trashed_count"] == 2


def test_scan_lease_blocks_concurrent_scans_and_records_failures():
    with tempfile.TemporaryDirectory() as tmp:
        settings = _settings(tmp)
        db = Database(settings.DB_PATH)
        held = db.start_scan("other")
        with pytest.raises(ScanInProgressError):
            SentinelEngine(settings).run_scan()
        db.finish_scan(held, processed=0, skipped=0)

        with patch("imaplib.IMAP4_SSL", side_effect=OSError("network down")), pytest.raises(OSError):
            SentinelEngine(settings).run_scan()
        last = db.get_last_scan()
        assert last["status"] == "failed"
        assert "network down" in last["error"]
        assert not db.is_scan_running()


def test_stale_lease_is_abandoned():
    with tempfile.TemporaryDirectory() as tmp:
        db = Database(str(Path(tmp) / "sentinel.db"))
        stale = db.start_scan("crashed")
        with db._get_connection() as conn:
            conn.execute("UPDATE scan_runs SET started_at = '2000-01-01T00:00:00Z' WHERE id = ?", (stale,))
        fresh = db.start_scan("new", lease_minutes=15)
        assert db.get_scan(stale)["status"] == "abandoned"
        assert db.get_scan(fresh)["status"] == "running"
