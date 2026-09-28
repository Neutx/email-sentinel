"""Core orchestrator engine for Email Sentinel."""

from __future__ import annotations

from typing import Any, Dict, List, Optional
from rich.console import Console

from email_sentinel.classifier import EmailClassifier
from email_sentinel.config import Settings
from email_sentinel.db import Database
from email_sentinel.email_client import EmailClient
from email_sentinel.models import (
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


class SentinelEngine:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.db = Database(settings.DB_PATH)
        self.classifier = EmailClassifier(settings)
        self.unsubscriber = EmailUnsubscriber(settings)
        self.notifier = Notifier(settings)

    def process_email(
        self, email: EmailMessage, client: Optional[EmailClient] = None
    ) -> ProcessedEmailResult:
        """Process a single email through classification, unsubscription, storage, and notification."""
        # 1. Deduplication check
        if email.message_id and self.db.is_email_processed(email.message_id):
            console.print(f"[dim]Email {email.subject} ({email.message_id}) already processed. Skipping.[/dim]")
            classification = self.classifier.classify(email)
            return ProcessedEmailResult(
                email=email,
                classification=classification,
                error="Already processed",
            )

        # 2. Classification
        classification = self.classifier.classify(email)
        console.print(
            f"[cyan]Classified '[bold]{email.subject}[/bold]' as "
            f"[magenta]{classification.category.value}[/magenta] (Urgency: {classification.urgency}/5)[/cyan]"
        )

        # 3. Save to database
        email_id = self.db.save_email(email, classification)

        unsub_result: Optional[UnsubscribeResult] = None
        trashed = False
        notification_sent = False
        channels_notified: List[NotificationChannel] = []

        # 4. Action Dispatch
        if classification.category in (EmailCategory.MARKETING_PROMO, EmailCategory.SPAM):
            # Automated Unsubscribe
            if self.settings.AUTO_UNSUBSCRIBE:
                console.print(f"[yellow]Attempting auto-unsubscribe for {email.sender_email}...[/yellow]")
                unsub_result = self.unsubscriber.unsubscribe(email)
                self.db.record_unsubscribe(email_id, email.sender_email, unsub_result)
                if unsub_result.success:
                    console.print(f"[green]✓ {unsub_result.message}[/green]")
                else:
                    console.print(f"[yellow]⚠ {unsub_result.message}[/yellow]")

            # Move to Trash / Delete
            if self.settings.AUTO_DELETE_MARKETING and client is not None:
                console.print(f"[red]Moving marketing email to Trash...[/red]")
                trashed = client.move_to_trash(email.id)
                self.db.update_email_status(email_id, is_trashed=trashed)

        elif classification.category == EmailCategory.PROJECT_UPDATE:
            # Record Project Update in DB
            self.db.record_project_update(email_id, classification, email)
            console.print(f"[green]Stored project update for '{classification.project_name or 'General'}'[/green]")

            # Prepare Notification
            payload = NotificationPayload(
                title=f"Project Update: {classification.project_name or 'General'}",
                body=classification.summary,
                category=classification.category,
                urgency=classification.urgency,
                project_name=classification.project_name,
                sender=email.sender,
                subject=email.subject,
                received_at=email.date,
                action_description=classification.action_description,
            )
            dispatched = self.notifier.dispatch(payload)
            for res in dispatched:
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
                    notification_sent = True
                    channels_notified.append(ch)

            if client and self.settings.AUTO_MARK_READ_PROCESSED:
                client.mark_as_read(email.id)

        elif classification.category == EmailCategory.URGENT_ACTIONABLE:
            # Critical Alert Notification
            payload = NotificationPayload(
                title="URGENT EMAIL ATTENTION REQUIRED",
                body=classification.summary,
                category=classification.category,
                urgency=classification.urgency,
                project_name=classification.project_name,
                sender=email.sender,
                subject=email.subject,
                received_at=email.date,
                action_description=classification.action_description,
            )
            dispatched = self.notifier.dispatch(payload)
            for res in dispatched:
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
                    notification_sent = True
                    channels_notified.append(ch)

            if client and self.settings.AUTO_MARK_READ_PROCESSED:
                client.mark_as_read(email.id)

        else:
            # TRANSACTIONAL or GENERAL_FYI
            payload = NotificationPayload(
                title=f"{classification.category.value.replace('_', ' ').title()}",
                body=classification.summary,
                category=classification.category,
                urgency=classification.urgency,
                project_name=classification.project_name,
                sender=email.sender,
                subject=email.subject,
                received_at=email.date,
                action_description=classification.action_description,
            )
            if self.notifier.should_notify(payload):
                dispatched = self.notifier.dispatch(payload)
                for res in dispatched:
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
                        notification_sent = True
                        channels_notified.append(ch)

        return ProcessedEmailResult(
            email=email,
            classification=classification,
            unsubscribed=unsub_result,
            deleted_or_trashed=trashed,
            notification_sent=notification_sent,
            channels_notified=channels_notified,
        )

    def run_scan(self, limit: int = 20, unread_only: bool = True) -> List[ProcessedEmailResult]:
        """Run a single scan over inbox."""
        client = EmailClient(self.settings)
        try:
            client.connect()
            if unread_only:
                emails = client.fetch_unseen_emails(limit=limit)
            else:
                emails = client.fetch_recent_emails(limit=limit)

            console.print(f"[bold green]Fetched {len(emails)} emails to process.[/bold green]")
            results: List[ProcessedEmailResult] = []
            for em in emails:
                res = self.process_email(em, client=client)
                results.append(res)
            return results
        finally:
            client.close()

    def run_audit(
        self, batch_size: int = 50, max_emails: Optional[int] = None
    ) -> Dict[str, Any]:
        """Audit and process all unread emails in high-speed batches."""
        client = EmailClient(self.settings)
        client.connect()
        try:
            raw_client = client._ensure_connected()
            status, data = raw_client.search(None, "UNSEEN")
            if status != "OK" or not data or not data[0]:
                console.print("[yellow]No unread emails found in inbox.[/yellow]")
                return {"total": 0, "marketing": 0, "projects": 0, "urgent": 0, "other": 0}

            uids = [u.decode("utf-8") for u in data[0].split()]
            if max_emails:
                uids = uids[-max_emails:]

            total_count = len(uids)
            console.print(f"[bold cyan]Found {total_count} unread emails to audit and triage.[/bold cyan]")

            stats = {"total": 0, "marketing": 0, "projects": 0, "urgent": 0, "other": 0}

            import concurrent.futures

            for i in range(0, total_count, batch_size):
                chunk_uids = uids[i : i + batch_size]
                batch_num = (i // batch_size) + 1
                total_batches = (total_count + batch_size - 1) // batch_size
                console.print(f"\n[bold blue]━━━ Processing Batch {batch_num}/{total_batches} ({len(chunk_uids)} emails) ━━━[/bold blue]")

                trash_uids: List[str] = []
                seen_uids: List[str] = []
                unsub_tasks = []

                for uid in chunk_uids:
                    try:
                        em = client.fetch_email_by_uid(uid)
                        if not em:
                            continue

                        # Deduplication check
                        if em.message_id and self.db.is_email_processed(em.message_id):
                            continue

                        classification = self.classifier.classify(em)
                        email_id = self.db.save_email(em, classification)
                        stats["total"] += 1

                        if classification.category in (EmailCategory.MARKETING_PROMO, EmailCategory.SPAM):
                            stats["marketing"] += 1
                            if self.settings.AUTO_UNSUBSCRIBE:
                                unsub_tasks.append((email_id, em))
                            if self.settings.AUTO_DELETE_MARKETING:
                                trash_uids.append(uid)
                                self.db.update_email_status(email_id, is_trashed=True)

                        elif classification.category == EmailCategory.PROJECT_UPDATE:
                            stats["projects"] += 1
                            self.db.record_project_update(email_id, classification, em)
                            seen_uids.append(uid)

                        elif classification.category == EmailCategory.URGENT_ACTIONABLE:
                            stats["urgent"] += 1
                            seen_uids.append(uid)
                        else:
                            stats["other"] += 1
                            seen_uids.append(uid)

                    except Exception as e:
                        console.print(f"[red]Error processing UID {uid}: {e}[/red]")

                # Execute unsubscribe tasks in parallel across worker threads
                if unsub_tasks:
                    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
                        future_to_unsub = {
                            executor.submit(self.unsubscriber.unsubscribe, em): (email_id, em)
                            for email_id, em in unsub_tasks
                        }
                        for future in concurrent.futures.as_completed(future_to_unsub):
                            email_id, em = future_to_unsub[future]
                            try:
                                unsub_res = future.result()
                                self.db.record_unsubscribe(email_id, em.sender_email, unsub_res)
                            except Exception:
                                pass

                # Execute batch operations
                if trash_uids:
                    client.move_batch_to_trash(trash_uids)
                    console.print(f"[green]✓ Moved {len(trash_uids)} marketing email(s) to Trash[/green]")
                if seen_uids:
                    client.mark_batch_as_read(seen_uids)

                console.print(
                    f"[dim]Progress: {min(i + batch_size, total_count)}/{total_count} | "
                    f"Marketing trashed: {stats['marketing']} | "
                    f"Projects saved: {stats['projects']}[/dim]"
                )

            return stats
        finally:
            client.close()

    def run_watcher(self) -> None:
        """Run real-time continuous email watcher."""
        console.print("[bold green]Starting Email Sentinel Continuous Watcher...[/bold green]")
        client = EmailClient(self.settings)
        try:
            for new_batch in client.idle_watch():
                console.print(f"[bold cyan]Received batch of {len(new_batch)} new email(s).[/bold cyan]")
                for em in new_batch:
                    self.process_email(em, client=client)
        finally:
            client.close()
