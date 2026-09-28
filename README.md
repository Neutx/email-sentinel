# Email Sentinel

Autonomous email triage for Murphy Labs: a Python backend that classifies incoming Gmail with Gemini, unsubscribes from and trashes marketing, captures project updates, and serves a token-protected API to **Sentinel**, the Android app. Hermes Agent operates it 24/7 (scans, watchdog, daily briefings).

| Part | Where | Docs |
|---|---|---|
| Backend (FastAPI, SQLite, IMAP) | `email_sentinel/` | this file, [`docs/api/API.md`](docs/api/API.md) |
| Android app (Flutter) | `app/` | [`docs/PRD.md`](docs/PRD.md), [`docs/design/DESIGN_BRIEF.md`](docs/design/DESIGN_BRIEF.md) |
| Hermes integration (cron scripts, skills, installer) | `hermes/` | [`docs/ops/RUNBOOK.md`](docs/ops/RUNBOOK.md) |
| Build plan for agents | `docs/plans/` | [`AGENTS.md`](AGENTS.md) |

## How it works

```
Gmail ──IMAP (UIDs, BODY.PEEK)──► scan (every 5 min, Hermes cron)
                                   ├─ protected-domain allowlist
                                   ├─ Gemini 3.7 flash classification (rules fallback)
                                   ├─ marketing/spam → RFC 8058 unsubscribe → Trash
                                   ├─ project update → project board + alert
                                   └─ urgent → alert
SQLite ◄──────────────────────────┘
   ▲
FastAPI /api/* (Tailscale IP, Bearer token) ◄── Sentinel app (feed, actions, briefings, controls)
   ▲
Hermes briefing job (08:00/18:00) writes Markdown briefings
```

## Install the app

1. Install **Tailscale** on the phone and sign in to the same tailnet as the PC.
2. Download the latest APK from [Releases](https://github.com/Neutx/email-sentinel/releases) (`…-arm64-v8a.apk` for modern phones, or `…-universal.apk`).
3. Open the app → enter the server URL (pre-filled) and the API token (`SENTINEL_API_TOKEN` in the PC's `.env`) → **Test & connect**.

Every merge to `main` publishes a new signed build that installs over the previous one.

## Backend quick start (developer)

```powershell
uv sync
uv run email-sentinel config-init        # creates .env from the template, then edit it
uv run email-sentinel scan --dry-run -n 5
uv run email-sentinel serve              # API on SENTINEL_API_HOST:SENTINEL_API_PORT
powershell -ExecutionPolicy Bypass -File hermes\install.ps1   # production: task + Hermes jobs
```

CLI: `scan [--json] [--dry-run] [--all]`, `serve`, `watch`, `audit`, `projects`, `unsub-history`, `stats`, `test-notify`, `briefing context|save`, `config-init`.

## Safety

- Dry-run mode (app → Control) simulates every destructive action; dry-run results are re-processed for real once it's switched off.
- Protected senders/domains are never unsubscribed or trashed (editable in the app).
- Trashed mail can be restored from the app; Gmail keeps Trash for 30 days.
- The API listens only on the Tailscale interface and requires a bearer token.

## Development

```powershell
uv run ruff check email_sentinel tests scripts; uv run pytest -q
uv run python scripts/export_openapi.py        # after any API change (CI checks drift)
uv run python scripts/export_app_fixtures.py   # refresh app test fixtures from the real API
cd app; flutter analyze --fatal-infos; flutter test
```
