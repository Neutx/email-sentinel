"""Local Web App and REST API Server for Email Sentinel."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import BackgroundTasks, FastAPI, Query
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
import uvicorn

from email_sentinel.config import Settings, get_settings
from email_sentinel.db import Database
from email_sentinel.engine import SentinelEngine
from email_sentinel.models import (
    EmailCategory,
    NotificationPayload,
)
from email_sentinel.notifier import Notifier

app = FastAPI(
    title="Email Sentinel Dashboard",
    description="Autonomous Local AI Email Watcher & Project Updates Dashboard",
    version="0.1.0",
)

settings = get_settings()
db = Database(settings.DB_PATH)
notifier = Notifier(settings)


class TestAlertRequest(BaseModel):
    title: str = "Murphy Labs Project Alert"
    body: str = "Test alert from local Email Sentinel app."
    project: str = "Murphy Labs"
    urgency: int = 3


class ScanRequest(BaseModel):
    limit: int = 20
    unread_only: bool = True
    dry_run: bool = False


@app.get("/api/stats")
def get_stats() -> Dict[str, Any]:
    return db.get_stats()


@app.get("/api/projects")
def get_project_updates(
    limit: int = Query(50, ge=1, le=200),
    project: Optional[str] = None,
) -> List[Dict[str, Any]]:
    return db.get_recent_project_updates(limit=limit, project_name=project)


@app.get("/api/unsub-history")
def get_unsub_history(limit: int = Query(50, ge=1, le=200)) -> List[Dict[str, Any]]:
    return db.get_unsubscribe_history(limit=limit)


@app.get("/api/emails")
def get_recent_emails(limit: int = Query(50, ge=1, le=200)) -> List[Dict[str, Any]]:
    with db._get_connection() as conn:
        cur = conn.execute(
            """
            SELECT id, uid, message_id, sender, sender_email, subject,
                   received_at, category, urgency, summary, project_name,
                   action_required, action_description, is_trashed, is_unsubscribed, created_at
            FROM emails
            ORDER BY created_at DESC LIMIT ?
            """,
            (limit,),
        )
        return [dict(row) for row in cur.fetchall()]


@app.post("/api/scan")
def trigger_scan(req: ScanRequest) -> Dict[str, Any]:
    cfg = get_settings()
    if req.dry_run:
        cfg.DRY_RUN = True
    engine = SentinelEngine(cfg)
    results = engine.run_scan(limit=req.limit, unread_only=req.unread_only)
    return {
        "processed_count": len(results),
        "results": [
            {
                "subject": r.email.subject,
                "sender": r.email.sender_email,
                "category": r.classification.category.value,
                "urgency": r.classification.urgency,
                "unsubscribed": bool(r.unsubscribed and r.unsubscribed.success),
                "trashed": r.deleted_or_trashed,
                "notified": r.notification_sent,
            }
            for r in results
        ],
    }


@app.post("/api/test-alert")
def trigger_test_alert(req: TestAlertRequest) -> Dict[str, Any]:
    payload = NotificationPayload(
        title=req.title,
        body=req.body,
        category=EmailCategory.PROJECT_UPDATE,
        urgency=req.urgency,
        project_name=req.project,
        sender="local-app@murphylabs.internal",
        subject=f"[{req.project}] Test Alert",
        action_description="Verification from local dashboard.",
    )
    res = notifier.dispatch(payload)
    return {"status": "dispatched", "channels": res}


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    html_content = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Email Sentinel • Murphy Labs</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;600&display=swap');
    body { font-family: 'Inter', sans-serif; }
    code, pre { font-family: 'JetBrains Mono', monospace; }
  </style>
</head>
<body class="bg-slate-950 text-slate-100 min-h-screen">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    
    <!-- Top Header -->
    <header class="flex flex-col sm:flex-row sm:items-center justify-between border-b border-slate-800 pb-6 gap-4">
      <div>
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-xl bg-gradient-to-tr from-indigo-500 to-emerald-400 flex items-center justify-center font-bold text-xl shadow-lg shadow-indigo-500/20">
            🛡️
          </div>
          <div>
            <h1 class="text-2xl font-bold tracking-tight text-white flex items-center gap-2">
              Email Sentinel
              <span class="text-xs font-mono uppercase bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-2 py-0.5 rounded-full">Local Engine</span>
            </h1>
            <p class="text-sm text-slate-400">Autonomous Inbox Watcher, Auto-Unsubscriber & Project Notifier</p>
          </div>
        </div>
      </div>
      <div class="flex items-center gap-3">
        <button onclick="triggerScan()" class="bg-indigo-600 hover:bg-indigo-500 text-white font-medium px-4 py-2 rounded-lg text-sm shadow-md transition flex items-center gap-2">
          <span>⚡</span> Run Scan Now
        </button>
        <button onclick="triggerTestAlert()" class="bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 font-medium px-4 py-2 rounded-lg text-sm transition flex items-center gap-2">
          <span>🔔</span> Test Alert
        </button>
      </div>
    </header>

    <!-- Metrics Grid -->
    <section class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5 my-8" id="metrics-grid">
      <div class="bg-slate-900 border border-slate-800 p-5 rounded-2xl shadow-sm">
        <span class="text-xs font-semibold uppercase tracking-wider text-slate-400">Total Emails Triaged</span>
        <div class="text-3xl font-bold text-white mt-2" id="metric-total">0</div>
        <div class="text-xs text-slate-500 mt-1">Processed through local rules & LLM</div>
      </div>
      <div class="bg-slate-900 border border-slate-800 p-5 rounded-2xl shadow-sm">
        <span class="text-xs font-semibold uppercase tracking-wider text-red-400">Marketing Unsubscribed</span>
        <div class="text-3xl font-bold text-red-400 mt-2" id="metric-unsub">0</div>
        <div class="text-xs text-slate-500 mt-1">RFC 8058 & HTML link one-clicks</div>
      </div>
      <div class="bg-slate-900 border border-slate-800 p-5 rounded-2xl shadow-sm">
        <span class="text-xs font-semibold uppercase tracking-wider text-emerald-400">Project Updates</span>
        <div class="text-3xl font-bold text-emerald-400 mt-2" id="metric-projects">0</div>
        <div class="text-xs text-slate-500 mt-1">Captured in local knowledge base</div>
      </div>
      <div class="bg-slate-900 border border-slate-800 p-5 rounded-2xl shadow-sm">
        <span class="text-xs font-semibold uppercase tracking-wider text-indigo-400">Notifications Sent</span>
        <div class="text-3xl font-bold text-indigo-400 mt-2" id="metric-notifications">0</div>
        <div class="text-xs text-slate-500 mt-1">Desktop & Mobile instant alerts</div>
      </div>
    </section>

    <!-- Tabs Navigation -->
    <div class="flex border-b border-slate-800 gap-6 mb-6">
      <button onclick="switchTab('projects')" id="tab-btn-projects" class="pb-3 text-sm font-semibold border-b-2 border-indigo-500 text-indigo-400 transition">
        📁 Project Updates & Milestones
      </button>
      <button onclick="switchTab('emails')" id="tab-btn-emails" class="pb-3 text-sm font-semibold border-b-2 border-transparent text-slate-400 hover:text-slate-200 transition">
        📥 Live Inbox Feed
      </button>
      <button onclick="switchTab('unsub')" id="tab-btn-unsub" class="pb-3 text-sm font-semibold border-b-2 border-transparent text-slate-400 hover:text-slate-200 transition">
        🚫 Unsubscribe & Trash Audit
      </button>
    </div>

    <!-- Tab 1: Project Updates -->
    <div id="tab-projects" class="space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold text-white">Extracted Project Updates</h2>
        <input type="text" id="project-filter" oninput="loadProjects()" placeholder="Filter by project name..." class="bg-slate-900 border border-slate-700 text-slate-200 px-3 py-1.5 rounded-lg text-sm w-64 focus:outline-none focus:border-indigo-500">
      </div>
      <div id="projects-list" class="space-y-3">
        <div class="p-8 text-center text-slate-500 bg-slate-900/50 border border-slate-800/80 rounded-2xl">
          No project updates recorded yet. Run a scan to ingest emails.
        </div>
      </div>
    </div>

    <!-- Tab 2: Live Inbox Feed -->
    <div id="tab-emails" class="hidden space-y-4">
      <div class="overflow-x-auto bg-slate-900 border border-slate-800 rounded-2xl">
        <table class="w-full text-left text-sm">
          <thead class="bg-slate-950/60 text-slate-400 text-xs uppercase tracking-wider border-b border-slate-800">
            <tr>
              <th class="p-4">Subject</th>
              <th class="p-4">Sender</th>
              <th class="p-4">Category</th>
              <th class="p-4 text-center">Urgency</th>
              <th class="p-4 text-center">Unsub</th>
              <th class="p-4 text-center">Trash</th>
              <th class="p-4 text-right">Received</th>
            </tr>
          </thead>
          <tbody id="emails-tbody" class="divide-y divide-slate-800/60">
            <tr><td colspan="7" class="p-6 text-center text-slate-500">No emails loaded.</td></tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Tab 3: Unsubscribe Audit -->
    <div id="tab-unsub" class="hidden space-y-4">
      <div class="overflow-x-auto bg-slate-900 border border-slate-800 rounded-2xl">
        <table class="w-full text-left text-sm">
          <thead class="bg-slate-950/60 text-slate-400 text-xs uppercase tracking-wider border-b border-slate-800">
            <tr>
              <th class="p-4">Sender / Domain</th>
              <th class="p-4">Method</th>
              <th class="p-4 text-center">Status</th>
              <th class="p-4">Target URL / Mailto</th>
              <th class="p-4 text-right">Attempted At</th>
            </tr>
          </thead>
          <tbody id="unsub-tbody" class="divide-y divide-slate-800/60">
            <tr><td colspan="5" class="p-6 text-center text-slate-500">No unsubscribe records yet.</td></tr>
          </tbody>
        </table>
      </div>
    </div>

  </div>

  <script>
    async function loadStats() {
      try {
        const res = await fetch('/api/stats');
        const data = await res.json();
        document.getElementById('metric-total').innerText = data.total_emails_processed || 0;
        document.getElementById('metric-unsub').innerText = data.unsubscribed_count || 0;
        document.getElementById('metric-projects').innerText = data.project_updates_count || 0;
        document.getElementById('metric-notifications').innerText = data.notifications_sent_count || 0;
      } catch (e) {
        console.error("Failed to load stats", e);
      }
    }

    async function loadProjects() {
      const q = document.getElementById('project-filter').value;
      const res = await fetch('/api/projects' + (q ? '?project=' + encodeURIComponent(q) : ''));
      const list = await res.json();
      const container = document.getElementById('projects-list');

      if (!list || list.length === 0) {
        container.innerHTML = '<div class="p-8 text-center text-slate-500 bg-slate-900/50 border border-slate-800/80 rounded-2xl">No project updates found.</div>';
        return;
      }

      container.innerHTML = list.map(item => `
        <div class="bg-slate-900 border border-slate-800 p-5 rounded-2xl hover:border-slate-700 transition">
          <div class="flex items-start justify-between gap-4">
            <div>
              <div class="flex items-center gap-2 mb-1">
                <span class="bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 text-xs font-semibold px-2.5 py-0.5 rounded-md">
                  ${item.project_name || 'General'}
                </span>
                <span class="text-xs text-slate-500 font-mono">${item.received_at ? item.received_at.replace('T', ' ').slice(0, 16) : ''}</span>
              </div>
              <h3 class="text-base font-semibold text-white">${item.subject || ''}</h3>
              <p class="text-sm text-slate-400 mt-2 leading-relaxed">${item.summary || ''}</p>
              ${item.action_description ? `
                <div class="mt-3 bg-amber-500/10 border border-amber-500/20 text-amber-300 text-xs p-2.5 rounded-lg flex items-center gap-2">
                  <span>⚡</span> <strong>Action Required:</strong> ${item.action_description}
                </div>
              ` : ''}
            </div>
            <span class="bg-slate-800 text-slate-300 text-xs px-2 py-1 rounded-md font-mono shrink-0">
              Urgency ${item.urgency}/5
            </span>
          </div>
        </div>
      `).join('');
    }

    async function loadEmails() {
      const res = await fetch('/api/emails');
      const list = await res.json();
      const tbody = document.getElementById('emails-tbody');
      if (!list || list.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="p-6 text-center text-slate-500">No emails loaded.</td></tr>';
        return;
      }
      tbody.innerHTML = list.map(e => `
        <tr class="hover:bg-slate-800/30 transition">
          <td class="p-4 font-medium text-white max-w-xs truncate">${e.subject || '(No Subject)'}</td>
          <td class="p-4 text-slate-400 font-mono text-xs max-w-xs truncate">${e.sender_email || ''}</td>
          <td class="p-4"><span class="px-2 py-0.5 rounded-full text-xs font-medium bg-slate-800 text-slate-300">${e.category}</span></td>
          <td class="p-4 text-center font-mono text-xs">${e.urgency}/5</td>
          <td class="p-4 text-center">${e.is_unsubscribed ? '<span class="text-emerald-400">✓</span>' : '-'}</td>
          <td class="p-4 text-center">${e.is_trashed ? '<span class="text-red-400">✓</span>' : '-'}</td>
          <td class="p-4 text-right text-slate-500 text-xs font-mono">${e.received_at ? e.received_at.slice(0, 10) : ''}</td>
        </tr>
      `).join('');
    }

    async function loadUnsubHistory() {
      const res = await fetch('/api/unsub-history');
      const list = await res.json();
      const tbody = document.getElementById('unsub-tbody');
      if (!list || list.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" class="p-6 text-center text-slate-500">No unsubscribe records.</td></tr>';
        return;
      }
      tbody.innerHTML = list.map(h => `
        <tr class="hover:bg-slate-800/30 transition">
          <td class="p-4 font-medium text-white">${h.sender_email || h.domain || ''}</td>
          <td class="p-4 font-mono text-xs text-indigo-400">${h.method || ''}</td>
          <td class="p-4 text-center">${h.success ? '<span class="text-xs bg-emerald-500/10 text-emerald-400 border border-emerald-500/30 px-2 py-0.5 rounded-full">SUCCESS</span>' : '<span class="text-xs bg-red-500/10 text-red-400 border border-red-500/30 px-2 py-0.5 rounded-full">FAILED</span>'}</td>
          <td class="p-4 font-mono text-xs text-slate-400 max-w-sm truncate">${h.target || ''}</td>
          <td class="p-4 text-right text-slate-500 text-xs font-mono">${h.attempted_at ? h.attempted_at.replace('T', ' ').slice(0, 16) : ''}</td>
        </tr>
      `).join('');
    }

    function switchTab(tab) {
      document.getElementById('tab-projects').classList.add('hidden');
      document.getElementById('tab-emails').classList.add('hidden');
      document.getElementById('tab-unsub').classList.add('hidden');

      document.getElementById('tab-btn-projects').className = 'pb-3 text-sm font-semibold border-b-2 border-transparent text-slate-400 hover:text-slate-200 transition';
      document.getElementById('tab-btn-emails').className = 'pb-3 text-sm font-semibold border-b-2 border-transparent text-slate-400 hover:text-slate-200 transition';
      document.getElementById('tab-btn-unsub').className = 'pb-3 text-sm font-semibold border-b-2 border-transparent text-slate-400 hover:text-slate-200 transition';

      if (tab === 'projects') {
        document.getElementById('tab-projects').classList.remove('hidden');
        document.getElementById('tab-btn-projects').className = 'pb-3 text-sm font-semibold border-b-2 border-indigo-500 text-indigo-400 transition';
        loadProjects();
      } else if (tab === 'emails') {
        document.getElementById('tab-emails').classList.remove('hidden');
        document.getElementById('tab-btn-emails').className = 'pb-3 text-sm font-semibold border-b-2 border-indigo-500 text-indigo-400 transition';
        loadEmails();
      } else if (tab === 'unsub') {
        document.getElementById('tab-unsub').classList.remove('hidden');
        document.getElementById('tab-btn-unsub').className = 'pb-3 text-sm font-semibold border-b-2 border-indigo-500 text-indigo-400 transition';
        loadUnsubHistory();
      }
    }

    async function triggerScan() {
      const btn = event.target;
      btn.disabled = true;
      btn.innerText = 'Scanning...';
      try {
        const res = await fetch('/api/scan', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({limit: 20}) });
        const data = await res.json();
        alert(`Scan Complete! Triaged ${data.processed_count} emails.`);
        loadStats();
        loadProjects();
        loadEmails();
      } catch (e) {
        alert('Scan failed: ' + e);
      } finally {
        btn.disabled = false;
        btn.innerHTML = '<span>⚡</span> Run Scan Now';
      }
    }

    async function triggerTestAlert() {
      try {
        await fetch('/api/test-alert', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({}) });
        alert('Dispatched test alert to desktop & channels!');
        loadStats();
      } catch (e) {
        alert('Test alert failed: ' + e);
      }
    }

    // Initial load
    loadStats();
    loadProjects();
  </script>
</body>
</html>
"""
    return html_content


def run_server(host: str = "127.0.0.1", port: int = 8765) -> None:
    """Start local web dashboard server."""
    uvicorn.run(app, host=host, port=port)
