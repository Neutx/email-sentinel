---
name: sentinel-briefing
description: Write and save the Sentinel morning/evening inbox briefing.
version: 0.2.0
author: Neutx (Murphy Labs)
license: MIT
platforms: [windows]
metadata:
  hermes:
    tags: [Email, Briefing, Sentinel, Cron]
    related_skills: [sentinel-ops]
---

# Sentinel briefing

Runs inside the `sentinel-briefing` cron job (08:00 and 18:00). The pre-script
`sentinel_briefing_context.py` has already injected three blocks into your prompt:

- `PERIOD:` `morning` or `evening`
- `LOCAL_TIME:` the owner's local time
- `CONTEXT_JSON:` aggregated inbox data from `email-sentinel briefing context`
  (`open_action_items`, `project_activity`, `category_counts`, `unsubscribed_count`,
  `trashed_count`, `last_scan`, `window_hours`)

If the prompt contains `CONTEXT_ERROR:` instead, do not invent a briefing: reply with
one line describing the error and stop.

## Write the briefing

Produce JSON with exactly these keys:

```json
{
  "period": "morning",
  "title": "Morning briefing",
  "summary": "2 urgent items; CI failing on Murphy-Labs/core; 14 promos cleaned up.",
  "body_markdown": "## Needs you\n..."
}
```

Rules:

1. **Only facts from CONTEXT_JSON.** Never invent senders, projects, numbers or deadlines. If a section has no data, write one short sentence saying so (e.g. "Nothing needs you right now.").
2. `title`: "Morning briefing" or "Evening briefing".
3. `summary`: ≤ 160 characters, one sentence, the most important point first. It becomes the phone notification text.
4. `body_markdown` sections, in this order, using `##` headings:
   - `## Needs you` — items from `open_action_items`, highest urgency first, as `- **<subject>** - <what to do> (<sender>, urgency N/5)`. Use `action_description` when present, else the summary. **Group near-duplicates** into one bullet (e.g. five Google security alerts become `- **5 Google security alerts** for <accounts> - review recent sign-ins`). Show at most **10** bullets; if more remain, end with `- ...and N more in the Sentinel app.`
   - `## Projects` — one bullet per project in `project_activity`: `- **<project>**: <1–2 line synthesis of its updates>`; call out failures/incidents first.
   - `## Inbox hygiene` — one line: processed counts by category, unsubscribed and trashed counts in the window.
   - `## System` — only if `last_scan.status` is not `succeeded` or `last_scan` is older than 30 minutes: say so plainly.
5. Plain, direct language. No greetings, no emoji, no filler. Keep the whole body under ~300 words.

## Save it

1. Write the JSON to a temp file, e.g. `%TEMP%\sentinel-briefing.json`, as **ASCII-only** text: escape every non-ASCII character as a JSON `\u` escape (for example serialize with Python `json.dumps(obj, ensure_ascii=True)`), or avoid non-ASCII punctuation entirely (write `-` instead of an em dash). Windows shells otherwise corrupt the encoding.
2. Run exactly:

   ```powershell
   uv run --project "D:\Murphy Labs\email-sentinel" --quiet email-sentinel briefing save --file "$env:TEMP\sentinel-briefing.json"
   ```

3. Expect `{"status": "saved", "id": N}`. On a validation error, fix the JSON (field lengths: title ≤ 200, summary ≤ 500, body ≤ 20000) and retry once.
4. Delete the temp file.
5. Reply with one line: `Saved <period> briefing #N: <summary>`.

Do not call any other command, do not modify files in the repository, and do not send the briefing anywhere else — the Android app picks it up from the API.
