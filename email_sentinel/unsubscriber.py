"""Automated email unsubscribe pipeline implementing RFC 8058, RFC 2369, and HTML link extraction."""

from __future__ import annotations

import re
import smtplib
from email.message import EmailMessage as PyEmailMessage
from typing import List, Optional
from urllib.parse import parse_qs, unquote, urlparse

from bs4 import BeautifulSoup
import httpx

from email_sentinel.config import Settings
from email_sentinel.models import EmailMessage, UnsubscribeMethod, UnsubscribeResult


class EmailUnsubscriber:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/125.0.0.0 Safari/537.36"
            ),
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        }

    def unsubscribe(self, email: EmailMessage) -> UnsubscribeResult:
        """Execute automated unsubscription using RFC 8058 POST, Mailto, or HTTP link crawler."""
        # 1. Safety check
        if self._is_protected(email):
            return UnsubscribeResult(
                success=False,
                method=UnsubscribeMethod.SKIPPED,
                target=email.sender_email,
                message="Skipped: Sender domain is protected by allowlist policy.",
            )

        if self.settings.DRY_RUN:
            return UnsubscribeResult(
                success=True,
                method=UnsubscribeMethod.RFC8058_POST if email.list_unsubscribe_post else UnsubscribeMethod.URL_GET,
                target=email.list_unsubscribe or "dry-run-target",
                message="[DRY-RUN] Would have unsubscribed from sender.",
            )

        # 2. Check for RFC 8058 One-Click Unsubscribe (POST)
        post_url = self._extract_http_url(email.list_unsubscribe)
        is_rfc8058 = email.list_unsubscribe_post and "List-Unsubscribe=One-Click" in email.list_unsubscribe_post

        if post_url and is_rfc8058:
            result = self._execute_rfc8058_post(post_url)
            if result.success:
                return result

        # 3. Check for standard HTTP List-Unsubscribe URL (GET)
        if post_url:
            result = self._execute_url_get(post_url, method_name=UnsubscribeMethod.URL_GET)
            if result.success:
                return result

        # 4. Check for RFC 2369 Mailto Unsubscribe
        mailto_target = self._extract_mailto(email.list_unsubscribe)
        if mailto_target:
            result = self._execute_mailto(mailto_target, email)
            if result.success:
                return result

        # 5. Fallback: Parse HTML body for unsubscribe links
        body_links = self._extract_body_links(email.body_html, email.body_plain)
        for link in body_links:
            result = self._execute_url_get(link, method_name=UnsubscribeMethod.URL_GET)
            if result.success:
                return result

        return UnsubscribeResult(
            success=False,
            method=UnsubscribeMethod.FAILED,
            target=email.sender_email,
            message="No valid unsubscribe mechanism found or all attempts failed.",
        )

    def _is_protected(self, email: EmailMessage) -> bool:
        sender_lower = email.sender_email.lower()
        domain_lower = email.domain
        for protected in self.settings.PROTECTED_DOMAINS:
            p_lower = protected.lower().strip()
            if p_lower in sender_lower or p_lower in domain_lower:
                return True
        return False

    def _extract_http_url(self, list_unsub_header: Optional[str]) -> Optional[str]:
        if not list_unsub_header:
            return None
        # Headers usually look like <https://...>, <mailto:...>
        matches = re.findall(r"<(https?://[^>]+)>", list_unsub_header)
        if matches:
            return matches[0]
        # Direct URL match
        direct = re.search(r"(https?://[^\s,]+)", list_unsub_header)
        return direct.group(1) if direct else None

    def _extract_mailto(self, list_unsub_header: Optional[str]) -> Optional[str]:
        if not list_unsub_header:
            return None
        matches = re.findall(r"<(mailto:[^>]+)>", list_unsub_header, re.IGNORECASE)
        if matches:
            return matches[0]
        direct = re.search(r"(mailto:[^\s,]+)", list_unsub_header, re.IGNORECASE)
        return direct.group(1) if direct else None

    def _execute_rfc8058_post(self, url: str) -> UnsubscribeResult:
        try:
            with httpx.Client(timeout=4.0, follow_redirects=True, headers=self.headers) as client:
                resp = client.post(
                    url,
                    data={"List-Unsubscribe": "One-Click"},
                    headers={"Content-Type": "application/x-www-form-urlencoded"},
                )
                if resp.status_code in (200, 201, 202, 204, 301, 302, 303, 307):
                    return UnsubscribeResult(
                        success=True,
                        method=UnsubscribeMethod.RFC8058_POST,
                        target=url,
                        http_status=resp.status_code,
                        message=f"Successfully unsubscribed via RFC 8058 POST (HTTP {resp.status_code})",
                    )
                return UnsubscribeResult(
                    success=False,
                    method=UnsubscribeMethod.RFC8058_POST,
                    target=url,
                    http_status=resp.status_code,
                    message=f"RFC 8058 POST returned non-success status {resp.status_code}",
                )
        except Exception as e:
            return UnsubscribeResult(
                success=False,
                method=UnsubscribeMethod.RFC8058_POST,
                target=url,
                message=f"Error executing RFC 8058 POST: {str(e)}",
            )

    def _execute_url_get(
        self, url: str, method_name: UnsubscribeMethod = UnsubscribeMethod.URL_GET
    ) -> UnsubscribeResult:
        try:
            with httpx.Client(timeout=4.0, follow_redirects=True, headers=self.headers) as client:
                resp = client.get(url)
                if resp.status_code in (200, 201, 202, 204, 301, 302, 303, 307):
                    # Check if the page contains a confirmation form to submit
                    page_text = resp.text.lower()
                    if "unsubscribe" in page_text or "opted out" in page_text or "preferences" in page_text:
                        # Attempt to auto-submit form if there's a simple form
                        soup = BeautifulSoup(resp.text, "html.parser")
                        form = soup.find("form")
                        if form and form.get("action"):
                            action = form.get("action")
                            form_url = action if action.startswith("http") else str(resp.url.join(action))
                            form_method = (form.get("method") or "POST").upper()
                            try:
                                if form_method == "POST":
                                    client.post(form_url, data={"confirm": "true", "action": "unsubscribe"})
                                else:
                                    client.get(form_url)
                            except Exception:
                                pass

                        return UnsubscribeResult(
                            success=True,
                            method=method_name,
                            target=url,
                            http_status=resp.status_code,
                            message=f"Successfully visited unsubscribe URL (HTTP {resp.status_code})",
                        )
                return UnsubscribeResult(
                    success=False,
                    method=method_name,
                    target=url,
                    http_status=resp.status_code,
                    message=f"Unsubscribe URL returned status {resp.status_code}",
                )
        except Exception as e:
            return UnsubscribeResult(
                success=False,
                method=method_name,
                target=url,
                message=f"Error visiting unsubscribe URL: {str(e)}",
            )

    def _execute_mailto(self, mailto_target: str, original_email: EmailMessage) -> UnsubscribeResult:
        """Send an automated mailto unsubscribe email."""
        try:
            parsed = urlparse(mailto_target)
            recipient = parsed.path
            query_params = parse_qs(parsed.query)
            subject = query_params.get("subject", ["Unsubscribe"])[0]
            body = query_params.get("body", ["Please unsubscribe me from this mailing list."])[0]

            if not self.settings.IMAP_USER or not self.settings.IMAP_PASSWORD:
                return UnsubscribeResult(
                    success=False,
                    method=UnsubscribeMethod.MAILTO,
                    target=mailto_target,
                    message="Mailto unsubscribe requires SMTP credentials (IMAP_USER and IMAP_PASSWORD)",
                )

            # Send via SMTP
            msg = PyEmailMessage()
            msg["From"] = self.settings.IMAP_USER
            msg["To"] = recipient
            msg["Subject"] = subject
            msg.set_content(body)

            smtp_host = self.settings.IMAP_HOST.replace("imap.", "smtp.")
            with smtplib.SMTP_SSL(smtp_host, 465, timeout=10) as smtp:
                smtp.login(self.settings.IMAP_USER, self.settings.IMAP_PASSWORD)
                smtp.send_message(msg)

            return UnsubscribeResult(
                success=True,
                method=UnsubscribeMethod.MAILTO,
                target=recipient,
                message=f"Sent unsubscribe email to {recipient} with subject '{subject}'",
            )
        except Exception as e:
            return UnsubscribeResult(
                success=False,
                method=UnsubscribeMethod.MAILTO,
                target=mailto_target,
                message=f"Failed to send mailto unsubscribe: {str(e)}",
            )

    def _extract_body_links(self, html_body: str, plain_body: str) -> List[str]:
        links: List[str] = []
        if html_body:
            soup = BeautifulSoup(html_body, "html.parser")
            for a in soup.find_all("a", href=True):
                href = a["href"].strip()
                text = a.get_text().strip().lower()

                if not href.startswith("http"):
                    continue

                href_lower = href.lower()
                is_unsub_link = any(
                    kw in href_lower
                    for kw in [
                        "unsubscribe",
                        "optout",
                        "opt-out",
                        "mailpreferences",
                        "email-preferences",
                        "manage-subscription",
                        "remove",
                    ]
                ) or any(
                    kw in text
                    for kw in [
                        "unsubscribe",
                        "opt out",
                        "stop receiving",
                        "manage preferences",
                        "click here to unsubscribe",
                        "subscription preferences",
                    ]
                )

                if is_unsub_link and href not in links:
                    links.append(href)

        if not links and plain_body:
            url_matches = re.findall(
                r"https?://[^\s<>\"']+(?:unsubscribe|optout|opt-out|preference)[^\s<>\"']*",
                plain_body,
                re.IGNORECASE,
            )
            for m in url_matches:
                if m not in links:
                    links.append(m)

        return links
