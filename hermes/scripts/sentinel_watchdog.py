"""Hermes cron (no-agent, every 5 min): keep the Sentinel API alive.

Silent when healthy. Prints one line only when it had to (re)start the server,
so Hermes delivers output only for real events.

On Windows the server is owned by the "EmailSentinel API" scheduled task
(hermes/windows/register-api-task.ps1) so it outlives this short-lived script;
a directly spawned child would die with Hermes' job object.
"""

from __future__ import annotations

import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sentinel_common import LOG_DIR, REPO, api_base, api_healthy, uv  # noqa: E402

DETACHED_PROCESS = 0x00000008
CREATE_NEW_PROCESS_GROUP = 0x00000200
CREATE_BREAKAWAY_FROM_JOB = 0x01000000  # survive Hermes' job object when allowed
TASK_NAME = "EmailSentinel API"


def start_via_task() -> bool:
    if sys.platform != "win32":
        return False
    proc = subprocess.run(["schtasks", "/Run", "/TN", TASK_NAME], capture_output=True, text=True)
    return proc.returncode == 0


def start_server() -> str:
    if start_via_task():
        return f"scheduled task '{TASK_NAME}'"
    return f"pid {spawn_server()}"


def spawn_server() -> int:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log = open(LOG_DIR / "api.log", "a", encoding="utf-8")  # noqa: SIM115 - handed to the child
    log.write(f"\n=== starting API {datetime.now().isoformat(timespec='seconds')} ===\n")
    log.flush()
    cmd = [uv(), "run", "--project", str(REPO), "email-sentinel", "serve"]
    kwargs: dict = dict(cwd=REPO, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, close_fds=True)
    if sys.platform == "win32":
        flags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
        try:
            return subprocess.Popen(cmd, creationflags=flags | CREATE_BREAKAWAY_FROM_JOB, **kwargs).pid
        except OSError:
            return subprocess.Popen(cmd, creationflags=flags, **kwargs).pid
    return subprocess.Popen(cmd, start_new_session=True, **kwargs).pid


def main() -> int:
    if api_healthy():
        return 0
    how = start_server()
    for _ in range(45):
        time.sleep(1)
        if api_healthy(timeout=2):
            print(f"Sentinel API was down and has been restarted via {how} at {api_base()}.")
            return 0
    print(
        f"Sentinel API is down and failed to start within 45 s ({api_base()}). "
        f"Check {LOG_DIR / 'api.log'} and that Tailscale is connected."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
