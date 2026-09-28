"""Core orchestrator engine for Email Sentinel."""

from __future__ import annotations

import concurrent.futures
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from rich.console import Console

from email_sentinel.classifier import EmailClassifier
from email_sentinel.config import Settings
from email_sentinel.db import Database, ScanInProgressError
from email_sentinel.email_client import EmailClient
from email_sentinel.models import (
    ClassificationResult,
    EmailCategory,
    EmailMessage,
    NotificationChannel,
    NotificationPayload,
    ProcessedEmailResult,
    UnsubscribeResult,
)
from email_sentinel.notifier import Notifier
from email_sentinel.unsubscriber import EmailUnsubscriber

console = Console()

# How many of the newest matching UIDs a scan inspects (Message-ID headers only)
# when looking for not-yet-processed mail.
SCAN_LOOKBACK = 500


@dataclass
class ScanReport:
    scan_id: int
    results: List[ProcessedEmailResult] = field(default_factory=list)
    skipped: int = 0
    failed: int = 0
    dry_run: bool = False

    def summary(self) -> Dict[str, Any]:
        categories: Dict[str, int] = {}
        for r in self.results:
            key = r.classification.category.value
            categories[key] = categories.get(key, 0) + 1
        return {
            "dry_run": self.dry_run,
            "processed": len(self.results),
            "skipped_already_processed": self.skipped,
            "failed": self.failed,
            "categories": categories,
            "unsubscribed": sum(1 for r in self.results if r.unsubscribed and r.unsubscribed.success),
            "trashed": sum(1 for r in self.results if r.deleted_or_trashed),
            "notified": sum(1 for r in self.results if r.notification_sent),
        }


class SentinelEngine:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.db = Database(settings.DB_PATH)
        self.classifier = EmailClassifier(settings)
        self.unsubscriber = EmailUnsubscriber(settings)
        self.notifier = Notifier(settings)

    def process_email(self, email: EmailMessage, client: Optional[EmailClient] = None) -> ProcessedEmailResult:
        """Process a single email through classification, unsubscription, storage, and notification."""
        dry_run = self.settings.DRY_RUN

        # 1. Deduplication check (never re-classify: that would spend LLM calls on every scan)
        if email.message_id and self.db.is_email_processed(email.message_id, include_dry_run=dry_run):
            console.print(f"[dim]Email {email.subject} ({email.message_id}) already processed. Skipping.[/dim]")
            classification = self.db.get_classification(email.message_id) or ClassificationResult(
                category=EmailCategory.GENERAL_FYI
            )
            return ProcessedEmailResult(email=email, classification=classification, error="Already processed")

        # 2. Classification
        classification = self.classifier.classify(email, self.db.get_known_project_names())
        console.print(
            f"[cyan]Classified '[bold]{email.subject}[/bold]' as "
            f"[magenta]{classification.category.value}[/magenta] (Urgency: {classification.urgency}/5)[/cyan]"
        )

        # 3. Save to database
        email_id = self.db.save_email(email, classification, dry_run=dry_run)

        unsub_result: Optional[UnsubscribeResult] = None
        trashed = False
        channels_notified: List[NotificationChannel] = []

        # 4. Action Dispatch
        if classification.category in (EmailCategory.MARKETING_PROMO, EmailCategory.SPAM):
            if self.settings.AUTO_UNSUBSCRIBE:
                console.print(f"[yellow]Attempting auto-unsubscribe for {email.sender_email}...[/yellow]")
                unsub_result = self.unsubscriber.unsubscribe(email)
                self.db.record_unsubscribe(email_id, email.sender_email, unsub_result)
                if unsub_result.success:
                    console.print(f"[green]✓ {unsub_result.message}[/green]")
                else:
                    console.print(f"[yellow]⚠ {unsub_result.message}[/yellow]")

            if self.settings.AUTO_DELETE_MARKETING and client is not None:
                console.print("[red]Moving marketing email to Trash...[/red]")
                trashed = client.move_to_trash(email.id)
                if trashed and not dry_run:
                    self.db.update_email_status(email_id, is_trashed=True)
        else:
            if classification.category == EmailCategory.PROJECT_UPDATE:
                self.db.record_project_update(email_id, classification, email)
                console.print(f"[green]Stored project update for '{classification.project_name or 'General'}'[/green]")

            channels_notified = self._notify(email_id, email, classification)

            if (
                classification.category in (EmailCategory.PROJECT_UPDATE, EmailCategory.URGENT_ACTIONABLE)
                and client
                and self.settings.AUTO_MARK_READ_PROCESSED
            ):
                client.mark_as_read(email.id)

        return ProcessedEmailResult(
            email=email,
            classification=classification,
            unsubscribed=unsub_result,
            deleted_or_trashed=trashed,
            notification_sent=bool(channels_notified),
            channels_notified=channels_notified,
        )

    def _notify(
        self, email_id: int, email: EmailMessage, classification: ClassificationResult
    ) -> List[NotificationChannel]:
        if classification.category == EmailCategory.PROJECT_UPDATE:
            title = f"Project Update: {classification.project_name or 'General'}"
        elif classification.category == EmailCategory.URGENT_ACTIONABLE:
            title = "URGENT EMAIL ATTENTION REQUIRED"
        else:
            title = classification.category.value.replace("_", " ").title()

        payload = NotificationPayload(
            title=title,
            body=classification.summary,
            category=classification.category,
            urgency=classification.urgency,
            project_name=classification.project_name,
            sender=email.sender,
            subject=email.subject,
            received_at=email.date,
            action_description=classification.action_description,
        )

        sent: List[NotificationChannel] = []
        for res in self.notifier.dispatch(payload):
            ch = NotificationChannel(res["channel"])
            self.db.record_notification(
                email_id=email_id,
                channel=ch,
                title=payload.title,
                body=payload.body,
                status=res["status"],
                error_message=res.get("error"),
            )
            if res["status"] == "sent":
                sent.append(ch)
        return sent

    def run_scan(
        self,
        limit: int = 20,
        unread_only: bool = True,
        trigger: str = "cli",
        scan_id: Optional[int] = None,
    ) -> ScanReport:
        """Process up to `limit` of the newest not-yet-processed emails.

        Pass `scan_id` if the caller already acquired the lease via Database.start_scan.
        Raises ScanInProgressError if another scan (CLI, API or Hermes) holds the lease.
        """
        if scan_id is None:
            scan_id = self.db.start_scan(trigger, self.settings.SCAN_LEASE_MINUTES)
        report = ScanReport(scan_id=scan_id, dry_run=self.settings.DRY_RUN)
        error: Optional[str] = None
        try:
            client = EmailClient(self.settings)
            try:
                client.connect()
                uids = client.search_uids(unread_only=unread_only)[-SCAN_LOOKBACK:]
                message_ids = client.fetch_message_ids(uids)
                pending = [
                    uid
                    for uid in uids
                    if not self.db.is_email_processed(message_ids.get(uid, ""), include_dry_run=self.settings.DRY_RUN)
                ]
                report.skipped = len(uids) - len(pending)
                pending = pending[-limit:] if limit > 0 else pending

                console.print(f"[bold green]{len(pending)} new email(s) to process.[/bold green]")
                for em in client.fetch_emails(pending):
                    try:
                        report.results.append(self.process_email(em, client=client))
                    except Exception as e:  # one bad email must not abort the scan
                        report.failed += 1
                        console.print(f"[red]Failed to process '{em.subject}': {e}[/red]")
            finally:
                client.close()
        except Exception as e:
            error = f"{type(e).__name__}: {e}"
            raise
        finally:
            self.db.finish_scan(
                report.scan_id,
                processed=len(report.results),
                skipped=report.skipped,
                summary=report.summary(),
                error=error,
            )
        return report

    def run_audit(self, batch_size: int = 50, max_emails: Optional[int] = None) -> Dict[str, Any]:
        """Audit and process all unread emails in high-speed batches."""
        scan_id = self.db.start_scan("audit", self.settings.SCAN_LEASE_MINUTES * 8)
        stats = {"total": 0, "marketing": 0, "projects": 0, "urgent": 0, "other": 0}
        error: Optional[str] = None
        client = EmailClient(self.settings)
        try:
            client.connect()
            uids = client.search_uids(unread_only=True)
            if not uids:
                console.print("[yellow]No unread emails found in inbox.[/yellow]")
                return stats
            if max_emails:
                uids = uids[-max_emails:]

            total_count = len(uids)
            console.print(f"[bold cyan]Found {total_count} unread emails to audit and triage.[/bold cyan]")
            dry_run = self.settings.DRY_RUN

            for i in range(0, total_count, batch_size):
                chunk_uids = uids[i : i + batch_size]
                batch_num = (i // batch_size) + 1
                total_batches = (total_count + batch_size - 1) // batch_size
                console.print(
                    f"\n[bold blue]━━━ Processing Batch {batch_num}/{total_batches} "
                    f"({len(chunk_uids)} emails) ━━━[/bold blue]"
                )

                trash: List[tuple[str, int]] = []
                seen_uids: List[str] = []
                unsub_tasks: List[tuple[int, EmailMessage]] = []
                message_ids = client.fetch_message_ids(chunk_uids)

                for uid in chunk_uids:
                    try:
                        if self.db.is_email_processed(message_ids.get(uid, ""), include_dry_run=dry_run):
                            continue
                        em = client.fetch_email_by_uid(uid)
                        if not em:
                            continue

                        classification = self.classifier.classify(em, self.db.get_known_project_names())
                        email_id = self.db.save_email(em, classification, dry_run=dry_run)
                        stats["total"] += 1

                        if classification.category in (EmailCategory.MARKETING_PROMO, EmailCategory.SPAM):
                            stats["marketing"] += 1
                            if self.settings.AUTO_UNSUBSCRIBE:
                                unsub_tasks.append((email_id, em))
                            if self.settings.AUTO_DELETE_MARKETING:
                                trash.append((uid, email_id))
                        elif classification.category == EmailCategory.PROJECT_UPDATE:
                            stats["projects"] += 1
                            self.db.record_project_update(email_id, classification, em)
                            seen_uids.append(uid)
                        elif classification.category == EmailCategory.URGENT_ACTIONABLE:
                            stats["urgent"] += 1
                            seen_uids.append(uid)
                        else:
                            stats["other"] += 1
                    except Exception as e:
                        console.print(f"[red]Error processing UID {uid}: {e}[/red]")

                if unsub_tasks:
                    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
                        future_to_unsub = {
                            executor.submit(self.unsubscriber.unsubscribe, em): (email_id, em)
                            for email_id, em in unsub_tasks
                        }
                        for future in concurrent.futures.as_completed(future_to_unsub):
                            email_id, em = future_to_unsub[future]
                            try:
                                self.db.record_unsubscribe(email_id, em.sender_email, future.result())
                            except Exception as e:
                                console.print(f"[red]Unsubscribe failed for {em.sender_email}: {e}[/red]")

                # UIDs are stable across expunge, so the order of these batch ops is safe.
                if seen_uids and self.settings.AUTO_MARK_READ_PROCESSED:
                    client.mark_batch_as_read(seen_uids)
                if trash and client.move_batch_to_trash([uid for uid, _ in trash]):
                    if not dry_run:
                        for _, email_id in trash:
                            self.db.update_email_status(email_id, is_trashed=True)
                    console.print(f"[green]✓ Moved {len(trash)} marketing email(s) to Trash[/green]")

                console.print(
                    f"[dim]Progress: {min(i + batch_size, total_count)}/{total_count} | "
                    f"Marketing trashed: {stats['marketing']} | "
                    f"Projects saved: {stats['projects']}[/dim]"
                )

            return stats
        except Exception as e:
            error = f"{type(e).__name__}: {e}"
            raise
        finally:
            client.close()
            self.db.finish_scan(scan_id, processed=stats["total"], skipped=0, summary=stats, error=error)

    def run_watcher(self) -> None:
        """Scan continuously every POLL_INTERVAL_SECONDS (use Hermes cron instead in production)."""
        console.print("[bold green]Starting Email Sentinel Continuous Watcher...[/bold green]")
        while True:
            try:
                self.run_scan(limit=self.settings.FETCH_BATCH_SIZE, trigger="watch")
            except ScanInProgressError as e:
                console.print(f"[dim]{e}; waiting for next cycle.[/dim]")
            except Exception as e:
                console.print(f"[red]Scan failed: {e}[/red]")
            time.sleep(self.settings.POLL_INTERVAL_SECONDS)
