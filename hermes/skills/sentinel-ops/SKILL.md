---
name: sentinel-ops
description: Operate and troubleshoot the Email Sentinel backend.
version: 0.1.0
author: Neutx (Murphy Labs)
license: MIT
platforms: [windows]
metadata:
  hermes:
    tags: [Email, Sentinel, Operations, Runbook]
    related_skills: [sentinel-briefing, sentinel-app-builder]
---

# Operating Email Sentinel

Email Sentinel is the owner's autonomous email triage backend. You (Hermes) keep it
running. Full runbook: `D:\Murphy Labs\email-sentinel\docs\ops\RUNBOOK.md`.

## Facts

| Thing | Value |
|---|---|
| Repo | `D:\Murphy Labs\email-sentinel` (GitHub `Neutx/email-sentinel`, private) |
| Config | `D:\Murphy Labs\email-sentinel\.env` (secrets — never print values, never commit) |
| Database | `%USERPROFILE%\.email_sentinel\sentinel.db` (SQLite) |
| API | `http://100.125.243.21:8765` (Tailscale only) — health: `GET /api/health` |
| API logs | `%LOCALAPPDATA%\email-sentinel\logs\api.log` |
| CLI | `uv run --project "D:\Murphy Labs\email-sentinel" email-sentinel <command>` |
| Cron jobs | `sentinel-watchdog` (5 min), `sentinel-scan` (5 min), `sentinel-briefing` (08:00, 18:00) |

## Common requests

- **"Is Sentinel working?"** → `hermes cron list`, then `curl http://100.125.243.21:8765/api/health`, then `uv run --project "D:\Murphy Labs\email-sentinel" email-sentinel stats`. Report: API up/down, last scan time/status (`GET /api/status` with the bearer token read from `.env` — do not print the token), counts.
- **"Scan now"** → `uv run --project "D:\Murphy Labs\email-sentinel" email-sentinel scan --json --trigger hermes-chat`. A `busy` status means another scan is running; wait a minute.
- **"Restart the API"** → find the listener: `Get-NetTCPConnection -LocalPort 8765 -State Listen` → `Stop-Process -Id <OwningProcess>`; then `hermes cron run sentinel-watchdog` (it restarts the server).
- **"Dry run on/off"**, "stop trashing", "stop unsubscribing" → prefer telling the owner to use the app's Control tab. If asked to do it yourself: `PATCH /api/settings` with `{"dry_run": true}` (bearer token from `.env`).
- **"What's the API token?"** → the owner may ask for it to set up the phone. Read `SENTINEL_API_TOKEN` from `.env` and give it to them only in a direct conversation with the owner, never in logs, commits, cron output or group chats.
- **Rotate the token** → generate `python -c "import secrets; print(secrets.token_urlsafe(32))"`, replace `SENTINEL_API_TOKEN` in `.env`, restart the API, tell the owner to reconnect the app.
- **Classifier mistakes** → the owner reclassifies in the app; persistent sender issues → add the sender to protected domains via the app (Control → Protected senders).

## Troubleshooting

| Symptom | Check / fix |
|---|---|
| App says "Can't reach Sentinel" | Tailscale up on PC and phone (`tailscale status`)? API healthy? Watchdog job active (`hermes cron list`)? |
| Watchdog keeps failing | Read the tail of `api.log`. Typical: Tailscale IP not up yet after boot (wait), port 8765 in use (stop the other process), `.env` token < 24 chars. |
| Scans fail with IMAP auth errors | Gmail app password revoked → owner must create a new one and update `SENTINEL_IMAP_PASSWORD` in `.env`. |
| Classification all "rules" | Gemini key/quota problem: look for "LLM API returned HTTP" in scan logs; `SENTINEL_LLM_*` in `.env`. |
| Briefing missing | `hermes cron runs sentinel-briefing`; re-run with `hermes cron run sentinel-briefing`. |

Never delete the database, never run `email-sentinel audit` (bulk cleanup of all unread mail) unless the owner explicitly asks, and never disable the protected-domains allowlist.
