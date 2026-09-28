# PRD — Sentinel (Email Sentinel mobile app)

**Owner:** Neutx (Murphy Labs) · **Status:** Approved 2026-09-28 · **Platform:** Android (Flutter) · **Backend:** Email Sentinel API on the owner's Windows PC, operated by Hermes

## 1. Problem

The owner's work inbox mixes project signals (GitHub, CI, clients, Jira/Linear) with marketing noise. The Python backend already classifies mail, unsubscribes from marketing, trashes clutter and extracts project updates — but the only UI was a generic, AI-generated web page on localhost. There is no way to see what matters, correct the AI, or control automation from the phone.

## 2. Goal

A calm, fast Android app that answers three questions in under 10 seconds:

1. **What needs me right now?** (urgent / actionable mail)
2. **What moved on my projects?** (project updates, per project)
3. **Is the sentinel working, and what did it do?** (scans, unsubscribes, trash, settings)

## 3. Users & context

Single user (the owner), technical, uses the app during work hours and on the go. The phone reaches the backend only over Tailscale. The backend runs 24/7 on a Windows PC; Hermes (Gemini) schedules scans, keeps the API alive, and writes briefings.

## 4. Scope (v1)

### 4.1 Connect (first run)
- Enter server URL (pre-filled `http://desktop-h4gp2e6.tail87425d.ts.net:8765`) and API token (paste; obscured with reveal toggle).
- "Test connection" checks `/api/health` then `/api/status`; clear, specific errors (unreachable → mention Tailscale; 401 → token).
- On success: store in secure storage, ask for notification permission, go to Briefing.

### 4.2 Briefing (home tab)
- Latest Hermes briefing rendered from Markdown with title, period (Morning/Evening) and relative time.
- "Needs you": up to 5 open urgent/actionable emails with one-tap Done.
- Stat strip: open actions, project updates, unsubscribed, trashed.
- Last-scan status chip (e.g. "Scanned 3 min ago · 4 new").
- Briefing history screen.
- Empty state when no briefing exists yet (explains schedule 08:00 / 18:00).

### 4.3 Inbox (triage feed)
- Chronological feed grouped by day; filter chips per category (+ "All"); toggle to show done items.
- Each item: category (icon + label + color), sender, subject, AI summary, urgency (1–5), project chip, status badges (Trashed, Unsubscribed, Dry run).
- Swipe right → Done (with Undo snackbar). Swipe left → Reclassify sheet. Both also available as visible buttons in the detail sheet.
- Detail sheet: summary, required action, sender, time, and actions: Done/Undone, Reclassify, Protect sender, Restore from Trash (only when trashed).
- Infinite scroll, pull-to-refresh, skeleton loading.

### 4.4 Projects
- Project list: name, update count, last activity, open actions, highest urgency.
- Project timeline: updates newest-first, action items highlighted, tap opens the email detail.

### 4.5 Control
- System status: API version, mailbox (masked), model, scan running, last scan result.
- "Scan now" with live progress (poll scan run) and result summary; handles 409 gracefully.
- Automation toggles: Dry run (warning styling), Auto-unsubscribe, Auto-trash marketing, Mark processed as read.
- Notifications: urgent on/off, project updates on/off, minimum urgency (1–5), background alerts on/off.
- Lists: protected senders/domains editor, project keywords editor.
- Unsubscribe history (method, target, HTTP status, success).
- Appearance: System / Light / Dark; Reduce transparency.
- Connection: edit URL/token, disconnect. About: app version/build.

### 4.6 Background alerts
- WorkManager periodic task (~15 min, network required) polls `/api/alerts` with a persisted cursor and shows local notifications: urgent (high-importance channel) and project updates (default channel); ≥4 items collapse into one summary notification.
- Notifies when a new briefing is available.
- Tapping a notification deep-links to the email detail or the briefing.
- First activation initialises the cursor without notifying about history.

## 5. Out of scope (v1)

Reading full email bodies, replying/composing, multiple accounts, iOS, FCM push, editing the classifier prompt, multi-user auth. (YAGNI — revisit after v1 is in daily use.)

## 6. Non-functional requirements

| Area | Requirement |
|---|---|
| Performance | Cold start < 2 s on a mid-range phone; feed scroll at 60 fps; first data < 1 s on Tailscale. |
| Offline | Any network failure shows an offline banner with Retry; never a blank screen or raw exception text. |
| Security | Token only in `flutter_secure_storage`; cleartext HTTP only to `*.ts.net` / the tailnet IP; no analytics or third-party network calls. |
| Accessibility | Touch targets ≥ 48 dp; contrast AA in both themes; every icon-only button has a semantic label; text scaling to 200% without overflow; reduced-motion and reduce-transparency respected. |
| Quality | `flutter analyze --fatal-infos` clean; tests for models, repository, poller and key widgets; CI green before merge. |
| Delivery | Every merge to `main` publishes a signed APK (universal + arm64) to GitHub Releases; updates install over the previous version. |

## 7. Success criteria

- The owner uses the app daily instead of opening Gmail for triage.
- < 5 % of feed items need reclassification after two weeks.
- Zero missed urgent emails (alert within ~15 min of arrival while Tailscale is connected).

## 8. Operations (Hermes)

| Job | Schedule | Type | Purpose |
|---|---|---|---|
| `sentinel-watchdog` | every 5 min | script, no LLM | Restart the API if `/api/health` fails. |
| `sentinel-scan` | every 5 min | script, no LLM | `email-sentinel scan --json` (classification uses Gemini inside the backend). |
| `sentinel-briefing` | 08:00 and 18:00 | agent (Gemini) | Read `briefing context`, write and save a Markdown briefing. |

Details: [`docs/ops/RUNBOOK.md`](ops/RUNBOOK.md).
