"""Multi-channel notification dispatcher supporting WhatsApp, Telegram, Discord, Slack, and Webhooks."""

from __future__ import annotations

import html
import urllib.parse
from typing import Dict, List, Optional

import httpx
from rich.console import Console

from email_sentinel.config import Settings
from email_sentinel.models import (
    EmailCategory,
    NotificationChannel,
    NotificationPayload,
)

console = Console()


class Notifier:
    def __init__(self, settings: Settings):
        self.settings = settings

    def should_notify(self, payload: NotificationPayload) -> bool:
        """Check if notification should be dispatched based on settings."""
        if payload.category == EmailCategory.PROJECT_UPDATE and self.settings.NOTIFY_ON_PROJECT_UPDATES:
            return True
        if payload.category == EmailCategory.URGENT_ACTIONABLE and self.settings.NOTIFY_ON_URGENT:
            return True
        if payload.urgency >= self.settings.MIN_URGENCY_TO_NOTIFY:
            return True
        return False

    def dispatch(self, payload: NotificationPayload) -> List[Dict[str, str]]:
        """Dispatch notification to all configured channels."""
        if not self.should_notify(payload):
            return []

        results: List[Dict[str, str]] = []

        # 0. Local Desktop Notification (Zero external service)
        if self.settings.DESKTOP_NOTIFY_ENABLED:
            res = self._send_desktop_notification(payload)
            results.append(res)

        # 1. WhatsApp
        if self.settings.WHATSAPP_ENABLED:
            res = self._send_whatsapp(payload)
            results.append(res)

        # 2. Telegram
        if self.settings.TELEGRAM_ENABLED:
            res = self._send_telegram(payload)
            results.append(res)

        # 3. Discord
        if self.settings.DISCORD_WEBHOOK_URL:
            res = self._send_discord(payload)
            results.append(res)

        # 4. Slack
        if self.settings.SLACK_WEBHOOK_URL:
            res = self._send_slack(payload)
            results.append(res)

        # 5. Generic Webhook
        if self.settings.GENERIC_WEBHOOK_URL:
            res = self._send_generic_webhook(payload)
            results.append(res)

        # 6. Always print to console
        self._print_console(payload)

        return results

    def _format_text_message(self, payload: NotificationPayload) -> str:
        urgency_emojis = {1: "ℹ️", 2: "📌", 3: "⚡", 4: "⚠️", 5: "🚨"}
        emoji = urgency_emojis.get(payload.urgency, "📌")

        lines = [
            f"{emoji} *[{payload.title.upper()}]*",
            f"👤 *From:* {payload.sender}",
            f"📧 *Subject:* {payload.subject}",
        ]
        if payload.project_name:
            lines.append(f"📁 *Project:* {payload.project_name}")

        lines.append(f"\n📝 *Summary:*\n{payload.body}")

        if payload.action_description:
            lines.append(f"\n⚡ *Action Required:*\n{payload.action_description}")

        lines.append(f"\n🕒 *Time:* {payload.received_at.strftime('%Y-%m-%d %H:%M:%S UTC')}")
        return "\n".join(lines)

    def _format_html_message(self, payload: NotificationPayload) -> str:
        urgency_emojis = {1: "ℹ️", 2: "📌", 3: "⚡", 4: "⚠️", 5: "🚨"}
        emoji = urgency_emojis.get(payload.urgency, "📌")

        title = html.escape(payload.title.upper())
        sender = html.escape(payload.sender)
        subject = html.escape(payload.subject)
        body = html.escape(payload.body)

        lines = [
            f"{emoji} <b>[{title}]</b>",
            f"👤 <b>From:</b> {sender}",
            f"📧 <b>Subject:</b> {subject}",
        ]
        if payload.project_name:
            lines.append(f"📁 <b>Project:</b> {html.escape(payload.project_name)}")

        lines.append(f"\n📝 <b>Summary:</b>\n{body}")

        if payload.action_description:
            lines.append(f"\n⚡ <b>Action Required:</b>\n{html.escape(payload.action_description)}")

        lines.append(f"\n🕒 <i>{payload.received_at.strftime('%Y-%m-%d %H:%M:%S UTC')}</i>")
        return "\n".join(lines)

    def _send_desktop_notification(self, payload: NotificationPayload) -> Dict[str, str]:
        import platform
        import subprocess

        system = platform.system()
        safe_title = payload.title.replace('"', "'")
        safe_summary = (payload.body[:150] + ("..." if len(payload.body) > 150 else "")).replace('"', "'")

        try:
            if system == "Windows":
                ps_script = (
                    f"Add-Type -AssemblyName System.Windows.Forms; "
                    f"$notify = New-Object System.Windows.Forms.NotifyIcon; "
                    f"$notify.Icon = [System.Drawing.SystemIcons]::Information; "
                    f"$notify.Visible = $True; "
                    f"$notify.ShowBalloonTip(4000, '{safe_title}', '{safe_summary}', [System.Windows.Forms.ToolTipIcon]::Info)"
                )
                subprocess.run(
                    ["powershell.exe", "-NoProfile", "-Command", ps_script],
                    capture_output=True,
                    timeout=5,
                )
                return {"channel": NotificationChannel.DESKTOP.value, "status": "sent"}
            elif system == "Darwin":
                script = f'display notification "{safe_summary}" with title "{safe_title}"'
                subprocess.run(["osascript", "-e", script], capture_output=True, timeout=5)
                return {"channel": NotificationChannel.DESKTOP.value, "status": "sent"}
            elif system == "Linux":
                subprocess.run(["notify-send", safe_title, safe_summary], capture_output=True, timeout=5)
                return {"channel": NotificationChannel.DESKTOP.value, "status": "sent"}
        except Exception as e:
            return {"channel": NotificationChannel.DESKTOP.value, "status": "failed", "error": str(e)}

        return {"channel": NotificationChannel.DESKTOP.value, "status": "skipped"}

    def _send_whatsapp(self, payload: NotificationPayload) -> Dict[str, str]:
        text = self._format_text_message(payload)
        provider = self.settings.WHATSAPP_PROVIDER.lower()

        if provider == "callmebot":
            if not self.settings.CALLMEBOT_PHONE or not self.settings.CALLMEBOT_API_KEY:
                return {
                    "channel": NotificationChannel.WHATSAPP.value,
                    "status": "failed",
                    "error": "CallMeBot requires CALLMEBOT_PHONE and CALLMEBOT_API_KEY",
                }
            try:
                encoded = urllib.parse.quote(text)
                url = (
                    f"https://api.callmebot.com/whatsapp.php?"
                    f"phone={self.settings.CALLMEBOT_PHONE}&"
                    f"text={encoded}&"
                    f"apikey={self.settings.CALLMEBOT_API_KEY}"
                )
                with httpx.Client(timeout=15.0) as client:
                    resp = client.get(url)
                    if resp.status_code == 200 and "success" in resp.text.lower():
                        return {"channel": NotificationChannel.WHATSAPP.value, "status": "sent"}
                    elif resp.status_code == 200:
                        return {"channel": NotificationChannel.WHATSAPP.value, "status": "sent"}
                    return {
                        "channel": NotificationChannel.WHATSAPP.value,
                        "status": "failed",
                        "error": f"CallMeBot HTTP {resp.status_code}: {resp.text}",
                    }
            except Exception as e:
                return {"channel": NotificationChannel.WHATSAPP.value, "status": "failed", "error": str(e)}

        elif provider == "twilio":
            if (
                not self.settings.TWILIO_ACCOUNT_SID
                or not self.settings.TWILIO_AUTH_TOKEN
                or not self.settings.TWILIO_WHATSAPP_TO
            ):
                return {
                    "channel": NotificationChannel.WHATSAPP.value,
                    "status": "failed",
                    "error": "Twilio requires TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, and TWILIO_WHATSAPP_TO",
                }
            try:
                url = f"https://api.twilio.com/2010-04-01/Accounts/{self.settings.TWILIO_ACCOUNT_SID}/Messages.json"
                auth = (self.settings.TWILIO_ACCOUNT_SID, self.settings.TWILIO_AUTH_TOKEN)
                data = {
                    "From": self.settings.TWILIO_WHATSAPP_FROM,
                    "To": self.settings.TWILIO_WHATSAPP_TO,
                    "Body": text,
                }
                with httpx.Client(timeout=15.0) as client:
                    resp = client.post(url, auth=auth, data=data)
                    if resp.status_code in (200, 201):
                        return {"channel": NotificationChannel.WHATSAPP.value, "status": "sent"}
                    return {
                        "channel": NotificationChannel.WHATSAPP.value,
                        "status": "failed",
                        "error": f"Twilio HTTP {resp.status_code}: {resp.text}",
                    }
            except Exception as e:
                return {"channel": NotificationChannel.WHATSAPP.value, "status": "failed", "error": str(e)}

        elif provider == "webhook" and self.settings.WHATSAPP_WEBHOOK_URL:
            try:
                with httpx.Client(timeout=15.0) as client:
                    resp = client.post(
                        self.settings.WHATSAPP_WEBHOOK_URL,
                        json={"message": text, "payload": payload.model_dump(mode="json")},
                    )
                    if resp.status_code in (200, 201, 204):
                        return {"channel": NotificationChannel.WHATSAPP.value, "status": "sent"}
                    return {
                        "channel": NotificationChannel.WHATSAPP.value,
                        "status": "failed",
                        "error": f"WhatsApp Webhook HTTP {resp.status_code}",
                    }
            except Exception as e:
                return {"channel": NotificationChannel.WHATSAPP.value, "status": "failed", "error": str(e)}

        return {
            "channel": NotificationChannel.WHATSAPP.value,
            "status": "failed",
            "error": "No valid WhatsApp configuration provided",
        }

    def _send_telegram(self, payload: NotificationPayload) -> Dict[str, str]:
        if not self.settings.TELEGRAM_BOT_TOKEN or not self.settings.TELEGRAM_CHAT_ID:
            return {
                "channel": NotificationChannel.TELEGRAM.value,
                "status": "failed",
                "error": "Telegram requires TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID",
            }
        try:
            url = f"https://api.telegram.org/bot{self.settings.TELEGRAM_BOT_TOKEN}/sendMessage"
            html_msg = self._format_html_message(payload)
            data = {
                "chat_id": self.settings.TELEGRAM_CHAT_ID,
                "text": html_msg,
                "parse_mode": "HTML",
                "disable_web_page_preview": True,
            }
            with httpx.Client(timeout=15.0) as client:
                resp = client.post(url, json=data)
                if resp.status_code == 200 and resp.json().get("ok"):
                    return {"channel": NotificationChannel.TELEGRAM.value, "status": "sent"}
                return {
                    "channel": NotificationChannel.TELEGRAM.value,
                    "status": "failed",
                    "error": f"Telegram API error: {resp.text}",
                }
        except Exception as e:
            return {"channel": NotificationChannel.TELEGRAM.value, "status": "failed", "error": str(e)}

    def _send_discord(self, payload: NotificationPayload) -> Dict[str, str]:
        try:
            color = 0x3498DB
            if payload.category == EmailCategory.URGENT_ACTIONABLE:
                color = 0xE74C3C
            elif payload.category == EmailCategory.PROJECT_UPDATE:
                color = 0x2ECC71

            embed = {
                "title": f"[{payload.title}] {payload.subject}",
                "description": payload.body,
                "color": color,
                "fields": [
                    {"name": "From", "value": payload.sender, "inline": True},
                    {"name": "Urgency", "value": f"{payload.urgency}/5", "inline": True},
                ],
                "footer": {"text": f"Email Sentinel • {payload.received_at.strftime('%Y-%m-%d %H:%M UTC')}"},
            }
            if payload.project_name:
                embed["fields"].append({"name": "Project", "value": payload.project_name, "inline": True})
            if payload.action_description:
                embed["fields"].append(
                    {"name": "Action Required", "value": payload.action_description, "inline": False}
                )

            with httpx.Client(timeout=15.0) as client:
                resp = client.post(self.settings.DISCORD_WEBHOOK_URL, json={"embeds": [embed]})
                if resp.status_code in (200, 204):
                    return {"channel": NotificationChannel.DISCORD.value, "status": "sent"}
                return {
                    "channel": NotificationChannel.DISCORD.value,
                    "status": "failed",
                    "error": f"Discord HTTP {resp.status_code}",
                }
        except Exception as e:
            return {"channel": NotificationChannel.DISCORD.value, "status": "failed", "error": str(e)}

    def _send_slack(self, payload: NotificationPayload) -> Dict[str, str]:
        try:
            text = self._format_text_message(payload)
            with httpx.Client(timeout=15.0) as client:
                resp = client.post(self.settings.SLACK_WEBHOOK_URL, json={"text": text})
                if resp.status_code == 200:
                    return {"channel": NotificationChannel.SLACK.value, "status": "sent"}
                return {
                    "channel": NotificationChannel.SLACK.value,
                    "status": "failed",
                    "error": f"Slack HTTP {resp.status_code}",
                }
        except Exception as e:
            return {"channel": NotificationChannel.SLACK.value, "status": "failed", "error": str(e)}

    def _send_generic_webhook(self, payload: NotificationPayload) -> Dict[str, str]:
        try:
            with httpx.Client(timeout=15.0) as client:
                resp = client.post(
                    self.settings.GENERIC_WEBHOOK_URL,
                    json=payload.model_dump(mode="json"),
                )
                if resp.status_code in (200, 201, 204):
                    return {"channel": NotificationChannel.WEBHOOK.value, "status": "sent"}
                return {
                    "channel": NotificationChannel.WEBHOOK.value,
                    "status": "failed",
                    "error": f"Generic webhook HTTP {resp.status_code}",
                }
        except Exception as e:
            return {"channel": NotificationChannel.WEBHOOK.value, "status": "failed", "error": str(e)}

    def _print_console(self, payload: NotificationPayload) -> None:
        color = "yellow"
        if payload.category == EmailCategory.URGENT_ACTIONABLE:
            color = "bold red"
        elif payload.category == EmailCategory.PROJECT_UPDATE:
            color = "bold green"

        console.print(f"[{color}]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/{color}]")
        console.print(f"[{color}]🔔 NOTIFICATION: {payload.title}[/{color}]")
        console.print(f"[bold]From:[/bold] {payload.sender}")
        console.print(f"[bold]Subject:[/bold] {payload.subject}")
        if payload.project_name:
            console.print(f"[bold]Project:[/bold] {payload.project_name}")
        console.print(f"[bold]Summary:[/bold] {payload.body}")
        if payload.action_description:
            console.print(f"[bold red]Action Required:[/bold red] {payload.action_description}")
        console.print(f"[{color}]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/{color}]")
