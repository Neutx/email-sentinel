"""Keep tests hermetic: never read the developer's .env or SENTINEL_* environment."""

import os

import pytest


@pytest.fixture(autouse=True)
def _isolate_settings(tmp_path, monkeypatch):
    for key in list(os.environ):
        if key.startswith("SENTINEL_"):
            monkeypatch.delenv(key, raising=False)
    monkeypatch.chdir(tmp_path)  # Settings reads ".env" relative to the working directory
