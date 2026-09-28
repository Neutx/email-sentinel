"""Command-line interface for Email Sentinel."""

from __future__ import annotations

import contextlib
import io
import json
import sys
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

from email_sentinel.config import Settings, get_settings
from email_sentinel.db import Database, ScanInProgressError
from email_sentinel.engine import SentinelEngine
from email_sentinel.models import (
    EmailCategory,
    NotificationPayload,
)
from email_sentinel.notifier import Notifier
from email_sentinel.runtime import load_effective_settings

app = typer.Typer(
    name="email-sentinel",
    help="Autonomous AI-powered Email Watcher, Unsubscriber & Project Updates Notifier.",
    add_completion=False,
)
console = Console()


@app.command()
def scan(
    limit: int = typer.Option(20, "--limit", "-n", help="Max emails to scan"),
    all_emails: bool = typer.Option(False, "--all", "-a", help="Scan both read and unread emails"),
    dry_run: bool = typer.Option(False, "--dry-run", help="Simulate actions without deleting/unsubscribing"),
    as_json: bool = typer.Option(False, "--json", help="Print only a one-line JSON summary (for Hermes cron)"),
    trigger: str = typer.Option("cli", "--trigger", help="Label recorded on the scan run"),
) -> None:
    """Scan inbox, classify emails, unsubscribe/trash marketing, and store/alert on project updates."""
    settings = load_effective_settings()
    if dry_run:
        settings.DRY_RUN = True

    if as_json:
        _scan_json(settings, limit=limit, unread_only=not all_emails, trigger=trigger)
        return

    if not settings.IMAP_USER or not settings.IMAP_PASSWORD:
        console.print(
            "[bold red]Error: IMAP credentials not configured.[/bold red]\n"
            "Run [bold cyan]email-sentinel config-init[/bold cyan] to generate your .env file."
        )
        raise typer.Exit(1) from None

    console.print(
        Panel.fit(
            f"[bold cyan]Email Sentinel Inbox Scan[/bold cyan]\n"
            f"Mailbox: [yellow]{settings.IMAP_USER}[/yellow] ({settings.IMAP_HOST})\n"
            f"Mode: {'[yellow]DRY-RUN[/yellow]' if settings.DRY_RUN else '[green]LIVE[/green]'}\n"
            f"LLM: [magenta]{settings.LLM_PROVIDER}[/magenta] ({settings.LLM_MODEL})",
            title="Sentinel Status",
        )
    )

    engine = SentinelEngine(settings)
    try:
        report = engine.run_scan(limit=limit, unread_only=not all_emails, trigger=trigger)
    except ScanInProgressError as e:
        console.print(f"[yellow]{e}. Try again shortly.[/yellow]")
        raise typer.Exit(0) from None
    results = report.results

    table = Table(title="Scan Results", show_lines=True)
    table.add_column("Subject", style="cyan", overflow="ellipsis", max_width=30)
    table.add_column("Sender", style="dim", max_width=25)
    table.add_column("Category", style="magenta")
    table.add_column("Urgency", justify="center")
    table.add_column("Unsubscribed", justify="center")
    table.add_column("Trashed", justify="center")
    table.add_column("Notified", justify="center")

    for r in results:
        table.add_row(
            r.email.subject or "(No Subject)",
            r.email.sender_email,
            r.classification.category.value,
            f"{r.classification.urgency}/5",
            "[green]✓[/green]"
            if r.unsubscribed and r.unsubscribed.success
            else ("[yellow]⚠[/yellow]" if r.unsubscribed else "-"),
            "[green]✓[/green]" if r.deleted_or_trashed else "-",
            "[green]✓[/green]" if r.notification_sent else "-",
        )

    console.print(table)


def _scan_json(settings: Settings, limit: int, unread_only: bool, trigger: str) -> None:
    """Run a scan with all console chatter suppressed; emit one JSON line on stdout."""
    out: dict
    exit_code = 0
    with contextlib.redirect_stdout(io.StringIO()):
        try:
            report = SentinelEngine(settings).run_scan(limit=limit, unread_only=unread_only, trigger=trigger)
            urgent = [
                {
                    "subject": r.email.subject,
                    "sender": r.email.sender_email,
                    "urgency": r.classification.urgency,
                    "summary": r.classification.summary,
                }
                for r in report.results
                if r.classification.category == EmailCategory.URGENT_ACTIONABLE
            ]
            out = {"status": "ok", "scan_id": report.scan_id, **report.summary(), "urgent": urgent}
        except ScanInProgressError as e:
            out = {"status": "busy", "detail": str(e)}
        except Exception as e:
            out = {"status": "error", "detail": f"{type(e).__name__}: {e}"}
            exit_code = 1
    sys.stdout.write(json.dumps(out) + "\n")
    raise typer.Exit(exit_code)


@app.command()
def watch(
    dry_run: bool = typer.Option(False, "--dry-run", help="Simulate actions without deleting/unsubscribing"),
) -> None:
    """Scan continuously in the foreground (production uses the Hermes cron job instead)."""
    settings = load_effective_settings()
    if dry_run:
        settings.DRY_RUN = True

    if not settings.IMAP_USER or not settings.IMAP_PASSWORD:
        console.print(
            "[bold red]Error: IMAP credentials not configured.[/bold red]\n"
            "Run [bold cyan]email-sentinel config-init[/bold cyan] to generate your .env file."
        )
        raise typer.Exit(1) from None

    console.print(
        Panel.fit(
            f"[bold green]Starting Real-Time Email Sentinel Watcher...[/bold green]\n"
            f"Watching: [yellow]{settings.IMAP_USER}[/yellow]\n"
            f"Auto-Unsubscribe: {'[green]ON[/green]' if settings.AUTO_UNSUBSCRIBE else '[red]OFF[/red]'}\n"
            f"Auto-Trash Marketing: {'[green]ON[/green]' if settings.AUTO_DELETE_MARKETING else '[red]OFF[/red]'}\n"
            f"WhatsApp Alerts: {'[green]ON[/green]' if settings.WHATSAPP_ENABLED else '[dim]OFF[/dim]'}\n"
            f"Telegram Alerts: {'[green]ON[/green]' if settings.TELEGRAM_ENABLED else '[dim]OFF[/dim]'}",
            title="Sentinel Daemon Active",
        )
    )

    engine = SentinelEngine(settings)
    try:
        engine.run_watcher()
    except KeyboardInterrupt:
        console.print("\n[yellow]Watcher stopped by user.[/yellow]")


@app.command()
def projects(
    limit: int = typer.Option(20, "--limit", "-n", help="Max updates to display"),
    name: Optional[str] = typer.Option(None, "--name", "-p", help="Filter by project name"),
) -> None:
    """View stored project updates extracted from emails."""
    settings = get_settings()
    db = Database(settings.DB_PATH)
    updates = db.get_recent_project_updates(limit=limit, project_name=name)

    if not updates:
        console.print("[yellow]No project updates found in database.[/yellow]")
        return

    table = Table(title=f"Project Updates ({len(updates)})", show_lines=True)
    table.add_column("Date", style="dim", max_width=16)
    table.add_column("Project", style="bold green", max_width=20)
    table.add_column("Subject", style="cyan", max_width=30)
    table.add_column("Summary", style="white", max_width=45)
    table.add_column("Action Needed", style="yellow", max_width=25)

    for u in updates:
        date_str = u["received_at"][:16].replace("T", " ") if u.get("received_at") else ""
        table.add_row(
            date_str,
            u.get("project_name") or "General",
            u.get("subject") or "",
            u.get("summary") or "",
            u.get("action_description") or ("[dim]None[/dim]"),
        )

    console.print(table)


@app.command()
def unsub_history(
    limit: int = typer.Option(20, "--limit", "-n", help="Max records to display"),
) -> None:
    """View history of unsubscribed senders and outcomes."""
    settings = get_settings()
    db = Database(settings.DB_PATH)
    history = db.get_unsubscribe_history(limit=limit)

    if not history:
        console.print("[yellow]No unsubscribe history found.[/yellow]")
        return

    table = Table(title=f"Unsubscribe Audit History ({len(history)})", show_lines=True)
    table.add_column("Date", style="dim", max_width=16)
    table.add_column("Sender / Domain", style="cyan", max_width=30)
    table.add_column("Method", style="magenta")
    table.add_column("Status", justify="center")
    table.add_column("Details", style="dim", max_width=40)

    for h in history:
        date_str = h["attempted_at"][:16].replace("T", " ") if h.get("attempted_at") else ""
        status_str = "[green]SUCCESS[/green]" if h.get("success") else "[red]FAILED[/red]"
        table.add_row(
            date_str,
            h.get("sender_email") or h.get("domain") or "",
            h.get("method") or "",
            status_str,
            h.get("error_message") or f"HTTP {h.get('http_status') or 200}",
        )

    console.print(table)


@app.command()
def test_notify(
    title: str = typer.Option("Test Project Alert", "--title", "-t", help="Alert title"),
    body: str = typer.Option("This is a test notification from Email Sentinel.", "--body", "-b", help="Alert body"),
    urgency: int = typer.Option(3, "--urgency", "-u", help="Urgency level 1-5"),
    project: str = typer.Option("Murphy Labs", "--project", "-p", help="Project name"),
) -> None:
    """Test notification dispatch to WhatsApp, Telegram, Discord, Slack, etc."""
    settings = get_settings()
    notifier = Notifier(settings)

    payload = NotificationPayload(
        title=title,
        body=body,
        category=EmailCategory.PROJECT_UPDATE,
        urgency=urgency,
        project_name=project,
        sender="sentinel-test@murphylabs.internal",
        subject=f"[{project}] Automated Pipeline Test Alert",
        action_description="No action needed. Verification test.",
    )

    console.print("[cyan]Dispatching test notifications...[/cyan]")
    results = notifier.dispatch(payload)

    if not results:
        console.print("[yellow]No external notification channels enabled in settings (console only).[/yellow]")
        return

    for res in results:
        if res["status"] == "sent":
            console.print(f"[green]✓ Channel '{res['channel']}': Sent successfully.[/green]")
        else:
            console.print(f"[red]✗ Channel '{res['channel']}': Failed - {res.get('error')}[/red]")


@app.command()
def stats() -> None:
    """Display system statistics and triage metrics."""
    settings = get_settings()
    db = Database(settings.DB_PATH)
    data = db.get_stats()

    table = Table(title="Email Sentinel Metrics", show_header=False)
    table.add_column("Metric", style="bold cyan")
    table.add_column("Value", style="bold green", justify="right")

    table.add_row("Total Emails Processed", str(data["total_emails_processed"]))
    table.add_row("Marketing Senders Unsubscribed", str(data["unsubscribed_count"]))
    table.add_row("Emails Moved to Trash", str(data["trashed_count"]))
    table.add_row("Project Updates Captured", str(data["project_updates_count"]))
    table.add_row("Notifications Dispatched", str(data["notifications_sent_count"]))

    console.print(table)

    if data.get("categories"):
        cat_table = Table(title="Category Breakdown", show_lines=True)
        cat_table.add_column("Category", style="magenta")
        cat_table.add_column("Count", justify="right", style="green")
        for cat, cnt in data["categories"].items():
            cat_table.add_row(cat, str(cnt))
        console.print(cat_table)


@app.command()
def config_init(
    path: str = typer.Option(".env", "--path", "-p", help="Output path for .env template"),
) -> None:
    """Generate a starter .env configuration template."""
    env_content = """# =========================================================
# Email Sentinel Configuration
# =========================================================

# --- IMAP Mailbox Settings (e.g. Gmail with App Password) ---
SENTINEL_IMAP_HOST=imap.gmail.com
SENTINEL_IMAP_PORT=993
SENTINEL_IMAP_USER=your_email@gmail.com
SENTINEL_IMAP_PASSWORD=your_16_char_app_password
SENTINEL_IMAP_FOLDER=INBOX
SENTINEL_IMAP_TRASH_FOLDER=[Gmail]/Trash

# --- Automated Actions ---
SENTINEL_AUTO_UNSUBSCRIBE=true
SENTINEL_AUTO_DELETE_MARKETING=true
SENTINEL_DRY_RUN=false

# --- REST API (Android app + Hermes) ---
# Bind to your Tailscale IP to reach it from the phone; a token (>= 24 chars) is then mandatory.
SENTINEL_API_HOST=127.0.0.1
SENTINEL_API_PORT=8765
SENTINEL_API_TOKEN=

# --- LLM Classification (OpenRouter, OpenAI, Gemini, or rules_only) ---
# Options: 'rules_only', 'openrouter', 'openai', 'gemini', 'ollama'
SENTINEL_LLM_PROVIDER=gemini
SENTINEL_LLM_API_KEY=
SENTINEL_LLM_MODEL=gemini-3.7-flash
# SENTINEL_LLM_BASE_URL=https://openrouter.ai/api/v1

# --- WhatsApp Notifications ---
SENTINEL_WHATSAPP_ENABLED=false
# Options: 'callmebot', 'twilio', 'webhook'
SENTINEL_WHATSAPP_PROVIDER=callmebot
# For CallMeBot (Free WhatsApp bot: send text to +34 644 10 55 84 to get apikey)
SENTINEL_CALLMEBOT_PHONE=
SENTINEL_CALLMEBOT_API_KEY=
# For Twilio:
# SENTINEL_TWILIO_ACCOUNT_SID=
# SENTINEL_TWILIO_AUTH_TOKEN=
# SENTINEL_TWILIO_WHATSAPP_FROM=whatsapp:+14155238886
# SENTINEL_TWILIO_WHATSAPP_TO=whatsapp:+1234567890

# --- Telegram Notifications ---
SENTINEL_TELEGRAM_ENABLED=false
SENTINEL_TELEGRAM_BOT_TOKEN=
SENTINEL_TELEGRAM_CHAT_ID=

# --- Discord / Slack / Webhooks ---
SENTINEL_DISCORD_WEBHOOK_URL=
SENTINEL_SLACK_WEBHOOK_URL=
SENTINEL_GENERIC_WEBHOOK_URL=

# --- Allowlist & Project Tracking ---
SENTINEL_PROTECTED_DOMAINS=["github.com", "accounts.google.com", "paypal.com", "stripe.com", "bank"]
SENTINEL_PROJECT_KEYWORDS=["murphy", "deploy", "release", "pull request", "issue", "linear", "jira"]
"""
    p = Path(path)
    if p.exists():
        console.print(f"[yellow]File {path} already exists. Skipping overwrite.[/yellow]")
    else:
        p.write_text(env_content, encoding="utf-8")
        console.print(f"[green]Created {path} template successfully![/green]")


@app.command()
def audit(
    batch_size: int = typer.Option(50, "--batch-size", "-b", help="Batch size for processing"),
    max_emails: Optional[int] = typer.Option(None, "--max", "-m", help="Max unread emails to audit"),
    dry_run: bool = typer.Option(False, "--dry-run", help="Simulate without trashing/unsubscribing"),
) -> None:
    """Perform a full high-speed audit & cleanup of ALL unread inbox emails."""
    settings = load_effective_settings()
    if dry_run:
        settings.DRY_RUN = True

    if not settings.IMAP_USER or not settings.IMAP_PASSWORD:
        console.print("[bold red]Error: IMAP credentials not configured.[/bold red]")
        raise typer.Exit(1) from None

    console.print(
        Panel.fit(
            f"[bold cyan]Full Unread Inbox Audit & Automated Cleanup[/bold cyan]\n"
            f"Mailbox: [yellow]{settings.IMAP_USER}[/yellow]\n"
            f"Mode: {'[yellow]DRY-RUN[/yellow]' if settings.DRY_RUN else '[green]LIVE CLEANUP[/green]'}\n"
            f"Auto-Unsubscribe: {'[green]ON[/green]' if settings.AUTO_UNSUBSCRIBE else '[red]OFF[/red]'} | "
            f"Auto-Trash: {'[green]ON[/green]' if settings.AUTO_DELETE_MARKETING else '[red]OFF[/red]'}",
            title="Audit Engine",
        )
    )

    engine = SentinelEngine(settings)
    try:
        stats = engine.run_audit(batch_size=batch_size, max_emails=max_emails)
    except ScanInProgressError as e:
        console.print(f"[yellow]{e}. Try again shortly.[/yellow]")
        raise typer.Exit(1) from None

    console.print("\n[bold green]━━━ Audit Complete ━━━[/bold green]")
    table = Table(title="Audit Summary", show_header=False)
    table.add_column("Category", style="bold cyan")
    table.add_column("Count", style="bold green", justify="right")
    table.add_row("Total Processed", str(stats.get("total", 0)))
    table.add_row("Marketing Unsubscribed & Trashed", str(stats.get("marketing", 0)))
    table.add_row("Project Updates Captured", str(stats.get("projects", 0)))
    table.add_row("Urgent Items", str(stats.get("urgent", 0)))
    table.add_row("Transactional / Saved", str(stats.get("other", 0)))
    console.print(table)


@app.command()
def serve(
    host: Optional[str] = typer.Option(None, "--host", "-h", help="Bind host (default SENTINEL_API_HOST)"),
    port: Optional[int] = typer.Option(None, "--port", "-p", help="Bind port (default SENTINEL_API_PORT)"),
) -> None:
    """Run the REST API used by the Android app and Hermes."""
    from email_sentinel.server import run_server

    settings = get_settings()
    auth = "[green]bearer token[/green]" if settings.API_TOKEN else "[yellow]none (loopback only)[/yellow]"
    console.print(
        Panel.fit(
            f"[bold green]Email Sentinel API[/bold green]\n"
            f"Listening: [bold cyan]http://{host or settings.API_HOST}:{port or settings.API_PORT}[/bold cyan]\n"
            f"Auth: {auth}\n"
            f"Database: [yellow]{settings.DB_PATH}[/yellow]",
            title="Email Sentinel",
        )
    )
    run_server(host=host, port=port)


briefing_app = typer.Typer(help="Read briefing context and store briefings (used by the Hermes briefing job).")
app.add_typer(briefing_app, name="briefing")


@briefing_app.command("context")
def briefing_context(
    hours: int = typer.Option(12, "--hours", help="Look-back window in hours"),
) -> None:
    """Print the aggregated inbox context for a briefing as JSON."""
    db = Database(get_settings().DB_PATH)
    sys.stdout.write(json.dumps(db.get_briefing_context(hours=hours), indent=2, default=str) + "\n")


@briefing_app.command("save")
def briefing_save(
    file: Path = typer.Option(..., "--file", "-f", exists=True, readable=True, help="JSON file to store"),
) -> None:
    """Store a briefing. JSON keys: period (morning|evening|adhoc), title, summary, body_markdown."""
    from pydantic import ValidationError

    from email_sentinel.schemas import BriefingCreate

    try:
        req = BriefingCreate.model_validate_json(file.read_text(encoding="utf-8"))
    except ValidationError as e:
        console.print(f"[red]Invalid briefing JSON:[/red]\n{e}")
        raise typer.Exit(1) from None
    saved = Database(get_settings().DB_PATH).save_briefing(
        req.period, req.title, req.summary, req.body_markdown, req.source
    )
    sys.stdout.write(json.dumps({"status": "saved", "id": saved["id"]}) + "\n")


def main() -> None:
    app()


if __name__ == "__main__":
    main()
