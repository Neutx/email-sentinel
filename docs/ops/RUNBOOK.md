# Runbook — operating Email Sentinel with Hermes

## Topology

```
Windows PC (desktop-h4gp2e6, Tailscale 100.125.243.21)
├─ Task Scheduler: "EmailSentinel API"      → uv run email-sentinel serve  (port 8765, Tailscale IP only)
│    starts at logon · restarts on failure · logs %LOCALAPPDATA%\email-sentinel\logs\api.log
├─ Hermes Agent (profile devta, Gemini 3.7 flash)
│    cron sentinel-watchdog  every 5m   no-agent  → /api/health, `schtasks /Run` if down
│    cron sentinel-scan      every 5m   no-agent  → email-sentinel scan --json (Gemini classifies inside)
│    cron sentinel-briefing  08:00,18:00 agent    → briefing context → write → briefing save
├─ SQLite  %USERPROFILE%\.email_sentinel\sentinel.db
└─ Gmail over IMAP (app password in .env)

Android phone (Tailscale) ── http://desktop-h4gp2e6.tail87425d.ts.net:8765 ──► API (Bearer token)
   WorkManager every ~15 min → /api/alerts → local notifications
```

## Install / update (idempotent)

```powershell
cd "D:\Murphy Labs\email-sentinel"
uv sync
powershell -ExecutionPolicy Bypass -File hermes\install.ps1            # task + scripts + skills + cron jobs
# design skills for the app builder (one-time; pass the folder holding ui-ux-pro-max and liquid-glass):
powershell -ExecutionPolicy Bypass -File hermes\install.ps1 -SkipCron -DesignSkillsSource <dir>
```

The installer targets the active Hermes profile (`%LOCALAPPDATA%\hermes\active_profile`, currently `devta`). Re-running it updates scripts/skills and skips cron jobs that already exist.

## Configuration (`.env`, never committed)

| Key | Purpose |
|---|---|
| `SENTINEL_IMAP_*` | Gmail account + 16-char app password |
| `SENTINEL_API_HOST=100.125.243.21`, `SENTINEL_API_PORT=8765` | Bind to Tailscale only |
| `SENTINEL_API_TOKEN` | ≥ 24 chars; the phone's bearer token. Server refuses non-loopback binds without it |
| `SENTINEL_LLM_PROVIDER=gemini`, `SENTINEL_LLM_MODEL=gemini-3.7-flash`, `SENTINEL_LLM_API_KEY` | Classification (same Gemini key Hermes uses) |
| `SENTINEL_AUTO_UNSUBSCRIBE`, `SENTINEL_AUTO_DELETE_MARKETING`, `SENTINEL_DRY_RUN` | Defaults; the app overrides them at runtime (stored in the DB) |
| `SENTINEL_PROTECTED_DOMAINS`, `SENTINEL_PROJECT_KEYWORDS` | Defaults; editable in the app |

After editing `.env`: restart the API (below). Scans pick up changes on the next run.

## Everyday operations

| Task | Command |
|---|---|
| Health | `curl http://100.125.243.21:8765/api/health` |
| Job status | `hermes cron list` · `hermes cron runs <job-id>` · `hermes cron doctor` |
| Scan now | `uv run email-sentinel scan --json --trigger manual` (or the app's Scan now) |
| Briefing now | `hermes cron run <sentinel-briefing id>` |
| Restart API | `schtasks /End /TN "EmailSentinel API"; schtasks /Run /TN "EmailSentinel API"` |
| API logs | `Get-Content "$env:LOCALAPPDATA\email-sentinel\logs\api.log" -Tail 50` |
| Pause everything | `hermes pause` (cron) + `schtasks /End /TN "EmailSentinel API"`; resume with `hermes resume` |
| Stop destructive actions but keep triage | App → Control → Dry run on |
| Rotate API token | new token in `.env` → restart API → reconnect the app |
| Get the token for the phone | read `SENTINEL_API_TOKEN` in `.env` (or ask Hermes in a private chat) |

## Failure modes

| Symptom | Cause / fix |
|---|---|
| Phone: "Can't reach Sentinel" | Tailscale off on phone or PC; PC asleep (set *Sleep: never* on AC power); API down → watchdog restarts within 5 min. |
| API won't start (`api.log`) | Tailscale not up yet after boot (task restarts every minute) · port 8765 taken · token < 24 chars. |
| Scans `status: error` with IMAP auth | App password revoked → create a new one in Google Account → Security → App passwords → update `.env`. |
| Everything classified by rules, not Gemini | `LLM API returned HTTP …` in output → key/quota; check `SENTINEL_LLM_*`. |
| Duplicate/missed alerts on the phone | Cursor stored on the phone; toggling Background alerts off/on re-initialises it without backfilling. |
| Scan stuck "running" | Lease expires after 15 min automatically (`abandoned`); the next scan proceeds. |
| Wrong email trashed | App → Inbox → Show done/All → open it → Restore from Trash; then Protect sender. Gmail keeps Trash for 30 days. |

## Releases

- PR → `App CI` builds a release-signed `sentinel-pr-N-arm64` APK artifact (installs over the production app).
- Merge to `main` touching `app/` → `Release APK` publishes `v<version>-build.<run>` with universal + arm64 APKs and `SHA256SUMS.txt`.
- Signing keystore: `%USERPROFILE%\.sentinel-signing\sentinel-release.jks` + `key.properties` (back both up offline; losing them means users must uninstall to update). CI copies live in repo secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
