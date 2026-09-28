"""CLI commands used by the Hermes jobs."""

import json
from pathlib import Path

from typer.testing import CliRunner

from email_sentinel.cli import _repair_mojibake, app
from email_sentinel.db import Database

runner = CliRunner()


def test_repair_mojibake_fixes_double_encoded_punctuation():
    assert _repair_mojibake("Needs you \u00e2\u20ac\u201d now") == "Needs you \u2014 now"
    assert _repair_mojibake("plain \u2014 text") == "plain \u2014 text"


def test_briefing_save_and_context_roundtrip(tmp_path, monkeypatch):
    db_path = tmp_path / "s.db"
    monkeypatch.setenv("SENTINEL_DB_PATH", str(db_path))
    brief = tmp_path / "b.json"
    payload = {
        "period": "morning",
        "title": "Morning briefing",
        "summary": "All quiet.",
        "body_markdown": "## Needs you\nNothing.",
    }
    brief.write_text("\ufeff" + json.dumps(payload), encoding="utf-8")  # BOM like PowerShell writes

    saved = runner.invoke(app, ["briefing", "save", "--file", str(brief)])
    assert saved.exit_code == 0, saved.output
    assert json.loads(saved.output.strip().splitlines()[-1])["status"] == "saved"
    assert Database(str(db_path)).list_briefings()[0]["title"] == "Morning briefing"

    ctx = runner.invoke(app, ["briefing", "context", "--hours", "6"])
    assert ctx.exit_code == 0
    assert json.loads(ctx.output)["window_hours"] == 6


def test_briefing_save_rejects_invalid_json(tmp_path, monkeypatch):
    monkeypatch.setenv("SENTINEL_DB_PATH", str(Path(tmp_path) / "s.db"))
    bad = tmp_path / "bad.json"
    bad.write_text(json.dumps({"period": "morning", "title": ""}), encoding="utf-8")
    result = runner.invoke(app, ["briefing", "save", "--file", str(bad)])
    assert result.exit_code == 1
