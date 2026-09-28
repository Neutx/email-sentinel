"""Effective settings = .env values layered with runtime overrides stored in the database."""

from __future__ import annotations

from typing import Optional

from email_sentinel.config import Settings, apply_overrides, get_settings
from email_sentinel.db import Database


def load_effective_settings(base: Optional[Settings] = None, db: Optional[Database] = None) -> Settings:
    base = base or get_settings()
    db = db or Database(base.DB_PATH)
    return apply_overrides(base, db.get_setting_overrides())
