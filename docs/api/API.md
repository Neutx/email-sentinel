# Sentinel API — client guide

The machine-readable contract is [`openapi.json`](openapi.json) (generated from the FastAPI app; CI fails if it drifts).
This guide explains the semantics a client needs that a schema cannot express.

## Connection

| | |
|---|---|
| Base URL (production) | `http://desktop-h4gp2e6.tail87425d.ts.net:8765` (MagicDNS) or `http://100.125.243.21:8765` |
| Transport | Tailscale (WireGuard-encrypted). The phone must have the Tailscale app connected. |
| Auth | `Authorization: Bearer <SENTINEL_API_TOKEN>` on every `/api/*` route except `/api/health`. |
| Content type | JSON in and out. Timestamps are ISO-8601 UTC strings ending in `Z` (email `received_at` keeps the sender's offset). |

The user pastes the base URL and token once on the Connect screen; store both with `flutter_secure_storage`.

## Error model

| Status | Meaning | Client behaviour |
|---|---|---|
| 401 | Missing/wrong token | Route to Connect screen with "Token rejected" message. |
| 404 | Resource gone (email, scan, no briefing yet) | Show empty/not-found state, not an error toast. |
| 409 | Conflict: scan already running, or restore on a non-trashed email | Show the `detail` string as an info snackbar. |
| 422 | Validation error (FastAPI `detail` list) | Show first `detail[].msg`. |
| 502 | Mailbox (IMAP) error during restore | Show `detail`, offer Retry. |
| Network error / timeout | Server unreachable (Tailscale off, PC asleep) | Show offline banner: "Can't reach Sentinel. Is Tailscale connected?" + Retry. |

Error bodies are `{"detail": "<string>"}` except 422 (`{"detail": [{"msg": "...", ...}]}`).
Use timeouts: connect 8 s, receive 20 s (60 s for `POST /api/scan` with `wait=true`, which the app should not use).

## Endpoints by screen

### Connect
- `GET /api/health` → `{status, version}` — reachability check (no auth).
- `GET /api/status` → validates the token and returns mailbox, model, last scan, settings.

### Briefing (home)
- `GET /api/briefings/latest` → latest briefing (`404` = none yet). Render `body_markdown`.
- `GET /api/briefings?limit=20` → history.
- `GET /api/emails?category=urgent_actionable&limit=5` → "Needs you" list (not-done items only by default).
- `GET /api/stats` → counters (`open_actions_count`, `project_updates_count`, `unsubscribed_count`, `trashed_count`).

### Inbox (triage feed)
- `GET /api/emails` — params: `category` (repeatable), `include_done` (default false), `include_trashed` (default true), `project`, `limit` (1–200, default 50), `before_id`.
  - **Pagination:** newest first. Response `next_cursor` → pass as `before_id` for the next page; `null` = end.
- `GET /api/emails/{id}` — single email.
- `POST /api/emails/{id}/done` body `{"done": true|false}` — hide/unhide from the feed (use `false` for Undo).
- `POST /api/emails/{id}/reclassify` body `{"category": "<EmailCategory>"}` — user correction; keeps the project board in sync.
- `POST /api/emails/{id}/protect-sender` — adds the sender to the protected list (never unsubscribed/trashed again).
- `POST /api/emails/{id}/restore` — moves a trashed email back to the inbox (`409` if not trashed).

`EmailCategory` values: `urgent_actionable`, `project_update`, `transactional`, `general_fyi`, `marketing_promo`, `spam`.
`urgency` is 1 (lowest) – 5 (critical). `dry_run: true` means the email was processed in simulation mode (nothing was actually trashed/unsubscribed).

### Projects
- `GET /api/projects` → `[ProjectSummary]` ordered by most recent activity.
- `GET /api/project-updates?project=<name>&limit=50` → timeline for one project (newest first).

### Control
- `GET /api/status` → `SystemStatus` (includes `settings`, `last_scan`, `scan_running`).
- `GET /api/settings`, `PATCH /api/settings` (partial `RuntimeSettingsPatch`; returns full `RuntimeSettings`). Lists are normalised (trimmed, lower-cased, de-duplicated, sorted).
- `POST /api/scan` body `{"limit": 20}` → `202` with a `ScanRun` in `running` state; poll `GET /api/scans/{id}` every 2 s until `status != running`. `409` = a scan is already running (Hermes runs one every 5 minutes).
- `GET /api/scans?limit=20` → recent scan history.
- `GET /api/unsubscribes?limit=50` → unsubscribe audit log.

### Background alerts (WorkManager, every ~15 min)
- `GET /api/alerts?after_id=<cursor>` → `{items, cursor}`.
  - **First run:** call with `after_id=-1`; it returns no items and the current cursor. Store it. This prevents a flood of historical notifications.
  - Each poll: notify for every item, then persist the returned `cursor`.
  - Which emails count as alerts is decided server-side from the runtime settings (`notify_on_urgent`, `notify_on_project_updates`, `min_urgency_to_notify`); marketing/spam and done items are never alerts.
- `GET /api/briefings/latest` → if `id` > last seen briefing id, notify "Your briefing is ready".

### Hermes-only
- `GET /api/briefing-context?hours=12` and `POST /api/briefings` are used by the Hermes briefing job. The app never writes briefings.
