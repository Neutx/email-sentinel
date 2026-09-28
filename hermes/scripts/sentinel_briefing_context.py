"""Hermes cron pre-script for the briefing agent job.

Its stdout is injected into the agent prompt: the period to write and the
aggregated inbox context as JSON (no email bodies, no secrets).
"""

from __future__ import annotations

import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sentinel_common import run_cli  # noqa: E402


def main() -> int:
    hour = datetime.now().hour
    period, hours = ("morning", 14) if hour < 12 else ("evening", 10)
    proc = run_cli("briefing", "context", "--hours", str(hours), timeout=120)
    if proc.returncode != 0:
        print(f"CONTEXT_ERROR: {(proc.stderr or proc.stdout)[-400:]}")
        return 1
    print(f"PERIOD: {period}")
    print(f"LOCAL_TIME: {datetime.now().strftime('%A %d %B %Y, %H:%M')}")
    print("CONTEXT_JSON:")
    print(proc.stdout.strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
