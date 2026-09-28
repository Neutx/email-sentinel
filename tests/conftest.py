"""Keep tests hermetic: never read the developer's .env or SENTINEL_* environment."""

import os
import subprocess

import pytest


@pytest.fixture(autouse=True)
def _isolate_settings(tmp_path, monkeypatch):
    for key in list(os.environ):
        if key.startswith("SENTINEL_"):
            monkeypatch.delenv(key, raising=False)
    monkeypatch.chdir(tmp_path)  # Settings reads ".env" relative to the working directory


@pytest.fixture(autouse=True)
def _no_real_desktop_notifications(monkeypatch):
    """Tests may enable DESKTOP_NOTIFY_ENABLED; never let a test pop a real OS balloon."""
    real_run = subprocess.run

    def fake_run(args, *a, **kw):
        if isinstance(args, (list, tuple)) and args and args[0] in ("powershell.exe", "osascript", "notify-send"):
            return subprocess.CompletedProcess(args, 0, b"", b"")
        return real_run(args, *a, **kw)

    monkeypatch.setattr(subprocess, "run", fake_run)
