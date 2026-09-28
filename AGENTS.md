# AGENTS.md — Email Sentinel

Rules for any coding agent (Hermes, Claude, Codex…) working in this repository.
Read this file fully before changing anything.

## What this repo is

| Path | What | Stack |
|------|------|-------|
| `email_sentinel/` | Backend: IMAP triage engine, classifier, unsubscriber, REST API | Python 3.11, FastAPI, SQLite, uv |
| `tests/` | Backend tests (fake IMAP server in `tests/fakes.py`) | pytest |
| `app/` | Android app "Sentinel" | Flutter 3.47.5 / Dart 3.13, Riverpod 3, go_router, dio |
| `docs/api/openapi.json` | **The API contract.** Generated — never hand-edit | OpenAPI 3.1 |
| `docs/api/API.md` | How the app must use the API (auth, cursors, errors) | |
| `docs/PRD.md` | Product requirements | |
| `docs/design/DESIGN_BRIEF.md` | Visual system: tokens, glass tiers, screens, motion | |
| `docs/plans/2026-09-28-sentinel-mobile-plan.md` | Phased build plan with acceptance criteria | |
| `docs/ops/RUNBOOK.md` | How Hermes operates the backend in production | |
| `.github/workflows/` | CI (backend, app) and APK release pipeline | GitHub Actions |

## Toolchain on the host machine (Windows)

- Flutter: `D:\dev-sdks\flutter-3.47.5\flutter\bin\flutter.bat` (do **not** use the older Flutter on PATH at `C:\flutter_windows_3.22.2-stable`).
- Java for Gradle: `C:\Program Files\Android\Android Studio\jbr`; Android SDK: `%LOCALAPPDATA%\Android\Sdk`.
- Python tooling: `uv` (`uv run pytest`, `uv run ruff check`).
- GitHub: `gh` is authenticated as `Neutx`. Repo: `Neutx/email-sentinel` (private).
- Commands in agent terminals time out after ~180 s. Do **not** run `flutter build apk` locally; CI builds APKs.

## Golden rules

1. **Never commit secrets.** `.env`, `*.jks`, `key.properties`, tokens, passwords, API keys. Check `git diff --cached` before every commit.
2. **Never push to `main` directly.** Branch → PR → CI green → merge (squash). Merging to `main` publishes an APK release.
3. **The API contract is fixed for app work.** The app consumes `docs/api/openapi.json` exactly. If the app truly needs a backend change, make it in a separate backend PR (update code + tests + `uv run python scripts/export_openapi.py`).
4. **Follow the plan.** Implement the phase you were asked to, in order, meeting every acceptance criterion. Do not add features that are not in the PRD.
5. **Follow the design brief.** Use tokens from `app/lib/core/theme/`, never raw hex/size literals in feature code. Glass is for the navigation layer only.
6. **No hover-to-raise effects, ever.** No translate/elevation "lift" on hover or press. Press feedback = Material state layer (ripple) only.
7. **Verify before claiming done.** Run the verification commands below and paste real output in the PR description.
8. **Commits and PRs are authored by the repo owner's account only.** Do not add `Co-Authored-By` trailers, "Generated with …" lines, or any AI attribution to commits, PR titles or PR bodies.

## Verification commands

Backend (from repo root):

```powershell
uv run ruff check email_sentinel tests scripts
uv run ruff format --check email_sentinel tests scripts
uv run pytest -q
uv run python scripts/export_openapi.py --check
```

App (from `app/`):

```powershell
$env:Path = "D:\dev-sdks\flutter-3.47.5\flutter\bin;" + $env:Path
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
```

## Branch / PR workflow

```powershell
git switch main; git pull --ff-only
git switch -c feat/app-phase-<n>-<slug>
# ... implement, verify ...
git add -A; git diff --cached --stat   # confirm no secrets / build outputs
git commit -m "<imperative summary>"
git push -u origin HEAD
gh pr create --base main --title "<Phase n: summary>" --body-file <file>
gh pr checks --watch                   # CI must be green
```

PR body must contain: what changed, which acceptance criteria are met (checklist), verification output, screenshots or widget-test evidence for UI.

If CI fails: `gh run view --log-failed`, fix, push again. Never disable a check, skip a test, or lower lint rules to get green.

## Definition of done (every PR)

- [ ] All verification commands pass locally and in CI.
- [ ] New logic has tests (models parse fixtures, repository calls correct endpoints, widgets render states).
- [ ] Loading, empty, error and offline states handled for every screen touched.
- [ ] Works in light and dark theme; text scales to 200% without overflow errors.
- [ ] No TODOs, commented-out code, debug prints, or unused files.
