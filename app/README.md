# Sentinel Android App

Sentinel is the Android client for the Email Sentinel AI triage platform at Murphy Labs. It provides a real-time, privacy-first interface for triaging emails, reviewing morning/evening briefings, tracking project updates, and controlling autonomous email automations.

## Installation

1. Download the latest release APK from [GitHub Releases](https://github.com/Neutx/email-sentinel/releases).
2. Install the APK on your Android device (Android 8.0 / API 26+ required).

## Connection Setup

1. **Tailscale Connection**: Ensure the Tailscale app is active and connected on your Android device.
2. **Server URL**: Enter your Sentinel backend host URL:
   - MagicDNS: `http://desktop-h4gp2e6.tail87425d.ts.net:8765`
   - Direct Tailscale IP: `http://100.125.243.21:8765`
3. **API Token**:
   - The token is defined as `SENTINEL_API_TOKEN` in the backend `.env` file on your server.
   - Paste the token into the connection screen and tap **Test & connect**.
   - Credentials are stored securely on-device using `flutter_secure_storage`.

## Features

- **Executive Briefings**: AI-generated morning and evening executive summaries with expand/collapse markdown reader and archive history.
- **Triage Feed (Inbox)**: Feed with category chips, urgency indicators (1–5), optimistic swipe-to-complete with 5s Undo, and category reclassification.
- **Project Timelines**: Real-time project activity feeds and update cards.
- **Control Center**:
  - Live system status and on-demand mailbox scanning with progress indicators.
  - Automation toggles: Dry-run simulation mode, Auto-unsubscribe, Auto-trash marketing, Mark processed as read.
  - List editors: Protected senders and project keywords.
  - Audit logs: Unsubscribe history and scan history.
  - Appearance: System/Light/Dark themes, Reduce transparency toggle.
- **Background Alerts & Deep Links**: Periodic background polling via Android WorkManager (~15 min cadence) alerting on high-urgency emails and fresh briefings, with instant deep-linking into email details and briefings.
