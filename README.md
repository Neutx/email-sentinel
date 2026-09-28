# 🛡️ Email Sentinel

**Autonomous AI Email Watcher, Unsubscriber & Project Updates Notifier**

Email Sentinel monitors your inbox in real time, automatically classifies incoming emails with AI and rules, unsubscribes from and deletes marketing/promo clutter, captures important project updates into a local SQLite database, and alerts you instantly via **WhatsApp**, **Telegram**, **Discord**, or **Slack**.

---

## ⚡ Key Features

- 🧠 **Dual-Layer Intelligence**: High-speed header heuristics combined with LLM triage (OpenRouter, OpenAI, Gemini, Claude, or local Ollama).
- 🚫 **Automated Unsubscribe Pipeline**:
  - **RFC 8058 One-Click POST**: Fast server-to-server POST unsubscriptions.
  - **RFC 2369 Mailto**: Automated unsubscribe email handler.
  - **HTML Link Extractor & Crawler**: Discovers and visits hidden `opt-out` / `unsubscribe` links.
- 🗑️ **Auto-Trash & Delete**: Moves marketing spam directly to Trash to keep your inbox at zero.
- 📁 **Project Updates Knowledge Base**: Automatically extracts updates from GitHub, Jira, Linear, CI/CD, clients, and teammates, and indexes them in SQLite (`sentinel.db`).
- 🔔 **Multi-Channel Instant Notifications**:
  - **WhatsApp**: Free 1-click integration via CallMeBot, Twilio WhatsApp, or custom webhooks.
  - **Telegram**: Rich HTML alerts via Telegram Bot API.
  - **Discord / Slack**: Webhook embeds.
- 🛡️ **Zero-Loss Safety Guardrails**: Domain allowlists and dry-run mode prevent accidentally unsubscribing from critical accounts (banking, GitHub, internal services).

---

## 🏗️ Architecture

```
Incoming Email (IMAP IDLE / Poll / Gmail)
                    │
                    ▼
          ┌───────────────────┐
          │  Safety Allowlist │──[ Protected Domain? ]──► Keep Safe in Inbox
          └───────────────────┘
                    │
                    ▼
          ┌───────────────────┐
          │ Layered Triage &  │
          │  Classification   │
          └───────────────────┘
            /       |       \
           /        |        \
          ▼         ▼         ▼
  [Marketing/Promo] [Project Update] [Urgent / Actionable]
         │                 │                 │
         ├─► Auto-Unsub    ├─► Store in DB   ├─► High-Priority Alert
         │   (RFC8058/URL) ├─► WhatsApp/TG   ├─► WhatsApp / Telegram
         └─► Move to Trash └─► Mark as Read  └─► Mark as Read
```

---

## 🚀 Quick Start

### 1. Installation

Using `uv` (recommended) or standard `pip`:

```bash
cd "D:/Murphy Labs/email-sentinel"
uv sync
```

### 2. Configure Credentials

Initialize your `.env` configuration file:

```bash
uv run email-sentinel config-init
```

Edit `.env` to configure your mailbox and alert channels:

```env
# Mailbox Credentials (e.g., Gmail with App Password)
SENTINEL_IMAP_HOST=imap.gmail.com
SENTINEL_IMAP_PORT=993
SENTINEL_IMAP_USER=your_email@gmail.com
SENTINEL_IMAP_PASSWORD=your_16_char_app_password

# Automated Actions
SENTINEL_AUTO_UNSUBSCRIBE=true
SENTINEL_AUTO_DELETE_MARKETING=true
SENTINEL_DRY_RUN=false

# WhatsApp Alerts (CallMeBot: Free & 1-minute setup)
SENTINEL_WHATSAPP_ENABLED=true
SENTINEL_WHATSAPP_PROVIDER=callmebot
SENTINEL_CALLMEBOT_PHONE=919876543210
SENTINEL_CALLMEBOT_API_KEY=123456

# Or Telegram Alerts
SENTINEL_TELEGRAM_ENABLED=false
SENTINEL_TELEGRAM_BOT_TOKEN=your_bot_token
SENTINEL_TELEGRAM_CHAT_ID=your_chat_id
```

> **How to get a Gmail App Password:**
> 1. Go to Google Account Settings → **Security** → **2-Step Verification**.
> 2. Scroll to the bottom and click **App passwords**.
> 3. Create a password named `Email Sentinel` and paste the 16-character string into `SENTINEL_IMAP_PASSWORD`.

> **How to get free WhatsApp alerts via CallMeBot:**
> 1. Add `+34 644 10 55 84` to your WhatsApp contacts (name it "CallMeBot").
> 2. Send the message: `I allow callmebot to send me messages` to the bot on WhatsApp.
> 3. The bot will reply with your API key. Put your phone number (country code without `+`) and API key in `.env`.

---

## 🛠️ CLI Usage

### Test Notifications
Verify WhatsApp / Telegram / Discord connectivity:
```bash
uv run email-sentinel test-notify --title "Deployment Complete" --body "Murphy Labs v1.0.0 is live" --project "Murphy Labs"
```

### Run a One-Shot Inbox Scan
Triage the last 20 unread emails:
```bash
uv run email-sentinel scan --limit 20
```

Run in dry-run mode (simulate without moving or unsubscribing):
```bash
uv run email-sentinel scan --limit 10 --dry-run
```

### Run the Continuous Real-Time Watcher Daemon
Monitors your inbox with IMAP IDLE for instant reaction to incoming mail:
```bash
uv run email-sentinel watch
```

### Query Project Updates
View all updates captured from your emails:
```bash
uv run email-sentinel projects
uv run email-sentinel projects --name "Murphy Labs"
```

### Audit Unsubscribe History
See exactly which senders were unsubscribed and their HTTP response status:
```bash
uv run email-sentinel unsub-history
```

### View Sentinel Stats & Triage Counts
```bash
uv run email-sentinel stats
```

---

## 🧪 Testing

Run the full test suite with:

```bash
uv run pytest -v
```
