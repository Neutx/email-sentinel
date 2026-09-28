"""Write the API contract to docs/api/openapi.json (CI fails if it is stale)."""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

from email_sentinel.config import Settings
from email_sentinel.server import create_app

OUT = Path(__file__).resolve().parent.parent / "docs" / "api" / "openapi.json"


def render() -> str:
    with tempfile.TemporaryDirectory() as tmp:
        app = create_app(Settings(_env_file=None, DB_PATH=str(Path(tmp) / "schema.db"), API_TOKEN="x" * 32))
        spec = app.openapi()
    return json.dumps(spec, indent=2, sort_keys=True) + "\n"


if __name__ == "__main__":
    content = render()
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != content:
            sys.exit("docs/api/openapi.json is stale: run `uv run python scripts/export_openapi.py`")
        print("openapi.json is up to date")
    else:
        OUT.write_text(content, encoding="utf-8", newline="\n")
        print(f"wrote {OUT}")
