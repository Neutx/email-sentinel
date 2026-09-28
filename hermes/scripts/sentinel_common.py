"""Shared helpers for the Hermes cron scripts (stdlib only: Hermes runs these with its own Python)."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import urllib.request
from pathlib import Path

# The installer (hermes/install.ps1) rewrites this line with the real repo path.
REPO = Path(os.environ.get("SENTINEL_REPO", r"D:\Murphy Labs\email-sentinel"))
LOG_DIR = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "email-sentinel" / "logs"


def uv() -> str:
    found = shutil.which("uv")
    if found:
        return found
    hermes_uv = Path(os.environ.get("LOCALAPPDATA", "")) / "hermes" / "bin" / "uv.exe"
    if hermes_uv.exists():
        return str(hermes_uv)
    raise FileNotFoundError("uv not found on PATH")


def env_value(key: str, default: str = "") -> str:
    """Read one SENTINEL_* value from the repo's .env without printing secrets."""
    env_file = REPO / ".env"
    if env_file.exists():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            if line.startswith(f"{key}="):
                return line.split("=", 1)[1].strip().strip('"')
    return default


def api_base() -> str:
    return f"http://{env_value('SENTINEL_API_HOST', '127.0.0.1')}:{env_value('SENTINEL_API_PORT', '8765')}"


def api_healthy(timeout: float = 5.0) -> bool:
    try:
        with urllib.request.urlopen(f"{api_base()}/api/health", timeout=timeout) as resp:
            return resp.status == 200 and json.loads(resp.read()).get("status") == "ok"
    except Exception:
        return False


def run_cli(*args: str, timeout: int = 900) -> subprocess.CompletedProcess[str]:
    """Run `email-sentinel <args>` inside the repo's uv environment."""
    return subprocess.run(
        [uv(), "run", "--project", str(REPO), "--quiet", "email-sentinel", *args],
        cwd=REPO,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )


def last_json_line(text: str) -> dict:
    for line in reversed(text.strip().splitlines()):
        line = line.strip()
        if line.startswith("{"):
            return json.loads(line)
    raise ValueError("no JSON line in output")
