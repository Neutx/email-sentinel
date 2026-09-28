"""Hermes cron (no-agent, every 5 min): scan the inbox.

Runs `email-sentinel scan --json`. Silent on routine scans; prints only when
urgent mail arrived or the scan failed, so Hermes only delivers real events.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sentinel_common import last_json_line, run_cli  # noqa: E402

SCAN_LIMIT = "25"


def main() -> int:
    proc = run_cli("scan", "--json", "--trigger", "hermes-cron", "--limit", SCAN_LIMIT)
    try:
        result = last_json_line(proc.stdout)
    except ValueError:
        print(f"Sentinel scan crashed (exit {proc.returncode}): {(proc.stderr or proc.stdout)[-400:]}")
        return 1

    status = result.get("status")
    if status == "busy":
        return 0  # another scan (app or previous tick) holds the lease
    if status != "ok":
        print(f"Sentinel scan failed: {result.get('detail', 'unknown error')}")
        return 1

    urgent = result.get("urgent") or []
    if urgent:
        lines = [f"{len(urgent)} urgent email(s) just arrived:"]
        for item in urgent[:5]:
            lines.append(f"- [{item.get('urgency')}/5] {item.get('subject')} ({item.get('sender')})")
        print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
