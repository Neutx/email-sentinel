---
name: sentinel-app-builder
description: Build Sentinel Flutter app phases via PRs with CI gates.
version: 0.1.0
author: Neutx (Murphy Labs)
license: MIT
platforms: [windows]
metadata:
  hermes:
    tags: [Flutter, Android, Sentinel, CI, GitHub]
    related_skills: [ui-ux-pro-max, liquid-glass-claude-skill, sentinel-ops, test-driven-development, github]
---

# Building the Sentinel app

You implement the Android app in `D:\Murphy Labs\email-sentinel\app` one plan phase at a
time. Quality bar: production. The owner installs every merged build on their phone.

## Before writing code (every session)

1. `cd "D:\Murphy Labs\email-sentinel"; git switch main; git pull --ff-only`
2. Read, in full: `AGENTS.md`, `docs/plans/2026-09-28-sentinel-mobile-plan.md` (your phase),
   `docs/design/DESIGN_BRIEF.md`, `docs/api/API.md`. Skim `docs/PRD.md`.
3. Read the existing foundation you build on: `app/lib/core/**`, `app/lib/data/**`,
   `app/lib/app/**`, `app/lib/widgets/tab_scaffold.dart`, `app/test/helpers/**`.
   Copy their patterns (imports, Riverpod style, tokens) exactly.
4. Design skills: consult `ui-ux-pro-max` for UX rules (touch targets, states, motion,
   accessibility) and `liquid-glass-claude-skill` for material decisions. The design brief
   already encodes their output — when in doubt, the brief wins. Do not add glass anywhere new.

## Tooling (Windows host)

```powershell
$env:Path = "D:\dev-sdks\flutter-3.47.5\flutter\bin;" + $env:Path
cd "D:\Murphy Labs\email-sentinel\app"
flutter pub get
flutter test test/path/to/one_test.dart      # fast loop
dart format lib test
flutter analyze --fatal-infos
flutter test
```

- Terminal commands time out after ~180 s: run single test files while iterating, the full suite before committing. Never run `flutter build apk` (CI does it).
- Use `dart format` rather than hand-formatting.

## Loop per task (TDD)

1. Create the test file exactly as given in the plan. Run it → confirm it fails for the right reason.
2. Implement the minimum that satisfies the plan's interface + behaviour text.
3. Run the test → pass. Run `flutter analyze --fatal-infos` → clean.
4. Commit: `git add -A; git diff --cached --stat; git commit -m "<plan's commit message>"`.

If a plan test is itself wrong (e.g. a typo against the real API or fixtures), fix the test
minimally and explain why in the PR body. Never delete assertions or skip tests to go green.

## Finish the phase

1. Bump `version:` in `app/pubspec.yaml` as the plan says.
2. Full verification (format, analyze, test) — capture the output.
3. `git push -u origin HEAD`
4. `gh pr create --base main --title "<plan PR title>" --body-file <tmpfile>` with:
   summary, checklist of the phase's tasks, verification output, notes on any deviations.
5. `gh pr checks --watch`. If red: `gh run view --log-failed`, fix, push, repeat until green.
6. **Stop** after CI is green and report the PR URL. Do **not** merge unless the owner (or the
   architect session that launched you) explicitly says to merge. Merging to `main` ships an APK.

## Hard rules

- Never commit secrets (`.env`, `key.properties`, `*.jks`, tokens).
- Never edit `.github/workflows/**`, `docs/api/openapi.json`, `app/test/fixtures/**`,
  or backend code (`email_sentinel/**`) during app phases.
- No new packages except those the plan names.
- No AI attribution in commits/PRs (no `Co-Authored-By`, no "Generated with").
- No hover-to-raise / press-to-lift effects. Ripple only.
