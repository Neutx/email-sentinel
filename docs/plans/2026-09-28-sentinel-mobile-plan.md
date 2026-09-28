# Sentinel App Implementation Plan (Phases 2–5)

> **For agentic workers (Hermes):** Execute ONE phase per session and per PR, in order. Load skills `sentinel-app-builder`, `ui-ux-pro-max`, `liquid-glass`. Steps use checkbox (`- [ ]`) syntax. Follow TDD: write the test from this plan first, watch it fail, implement, watch it pass, commit.

**Goal:** Build the Sentinel Android app features (Inbox, Briefing, Projects, Control, background alerts) on top of the verified Phase 1 foundation already in `app/`.

**Architecture:** Flutter + Riverpod 3 (Notifier/AsyncNotifier/FutureProvider, no codegen) + go_router `StatefulShellRoute` + Dio. Screens read data through `SentinelRepository` (via `repositoryProvider`) only. Visuals come exclusively from `core/theme` tokens and the design brief.

**Tech stack (pinned in `app/pubspec.yaml`):** Flutter 3.47.5 / Dart 3.13, flutter_riverpod 3.4, go_router 18, dio 5.11, flutter_secure_storage 11, shared_preferences 2.5, workmanager 0.10, flutter_local_notifications 22.3, flutter_markdown_plus 1.0, url_launcher 6.3, intl 0.20, mocktail 1.0 (dev).

## Global Constraints

- Read first: `AGENTS.md`, `docs/PRD.md`, `docs/design/DESIGN_BRIEF.md`, `docs/api/API.md`.
- Flutter binary: `D:\dev-sdks\flutter-3.47.5\flutter\bin\flutter.bat`. Never run `flutter build apk` locally (terminal timeout); CI builds APKs.
- Verification (from `app/`), all must pass before every commit: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze --fatal-infos`, `flutter test`.
- No new dependencies except `package_info_plus` in Phase 4. No codegen (no freezed/json_serializable/riverpod_generator).
- No raw colors, font sizes, radii, durations or paddings in feature code: use `context.colors`, `context.sentinelColors`, `context.text`, `Space`, `Radii`, `Motion`, `NavMetrics`.
- Glass (`GlassSurface`) only in the nav pill and `TabScaffold` app bar (already done). Never in tiles, cards, sheets.
- Never hover/press "lift" effects. Press feedback = ink ripple.
- Every async screen state handles loading (skeleton), empty (`EmptyState`), error (`ErrorState`, offline copy mentions Tailscale) and data.
- Every icon-only button has `tooltip` (gives a semantics label). Touch targets ≥ 48 dp.
- Every modal (`showModalBottomSheet`, `showDialog`) passes `useRootNavigator: true` so it renders above the floating nav pill, and scrollable sheet content pads its bottom by `MediaQuery.viewPaddingOf(context).bottom` (emulator review of Phase 2).
- Every user-triggered API call (buttons, swipes, toggles, pull-to-refresh, Undo) goes through `guardAction(context, () => ...)` from `lib/core/utils/guard.dart` (added in Phase 2 review) so failures show `ApiException.userMessage` instead of throwing. Gesture callbacks (e.g. `Dismissible.confirmDismiss`) must only report success when the call succeeded. Add a widget test for the failure path of each new action.
- Tests use the existing helpers: `test/helpers/fake_api.dart` (`FakeAdapter`, `FakeResponse`, `fixture`, `fixtureMap`, `testConfig`) and `test/helpers/pump_app.dart` (`testOverrides`, `pumpScreen`, `MemoryConnectionStore`). Fixtures in `test/fixtures/*.json` are generated from the real backend — do not hand-edit; add new canned bodies inline in tests.
- Do not modify Phase 1 files except where a task explicitly says so.
- Commit messages: imperative, no AI attribution, no `Co-Authored-By`.
- Version bump per phase in `app/pubspec.yaml`: Phase 2 → `0.2.0+1`, Phase 3 → `0.3.0+1`, Phase 4 → `0.4.0+1`, Phase 5 → `1.0.0+1` (CI overrides the build number).

## Foundation you build on (already in `app/`, do not rewrite)

| File | Provides |
|---|---|
| `lib/core/theme/tokens.dart` | `Space.s1…s12`, `Space.gutter(ctx)`, `Radii.control/card/sheet/nav/chip`, `Motion.fast/base/slow/stagger/enter/exit`, `Motion.of(ctx, d)`, `NavMetrics.contentBottomPadding(ctx)` |
| `lib/core/theme/sentinel_colors.dart` | `SentinelColors` (`card, caution, success, urgent, project, transactional, fyi, marketing, spam, glass*`), extension `context.sentinelColors / context.colors / context.text` |
| `lib/core/theme/app_theme.dart`, `glass.dart` | `AppTheme.light()/dark()`, `GlassSurface` |
| `lib/core/network/api_exception.dart` | `ApiException(kind, detail)`, `ApiErrorKind { offline, unauthorized, notFound, conflict, validation, server, unknown }`, `.userMessage` |
| `lib/core/providers.dart` | `connectionProvider` (`ConnectionController.connect/disconnect`), `repositoryProvider`, `apiClientFactoryProvider`, `connectionStoreProvider` |
| `lib/core/preferences/app_preferences.dart` | `sharedPreferencesProvider`, `appPreferencesProvider` (`setThemeMode/setReduceTransparency/setBackgroundAlerts`), `reduceTransparencyProvider` |
| `lib/data/models.dart` | `EmailCategory` (`wire`, `label`, `fromWire`), `EmailItem` (`senderName`, `timestamp`, `copyWith`), `EmailPage`, `AlertsResponse`, `ActionResult`, `ProjectSummary`, `ProjectUpdate`, `UnsubscribeLog`, `Stats`, `ScanRun`/`ScanStatus`, `RuntimeSettings`, `RuntimeSettingsPatch`, `SystemStatus`, `Briefing` |
| `lib/data/sentinel_repository.dart` | `health, status, stats, emails({categories, includeDone, includeTrashed, project, limit, beforeId}), email, setDone(id, done:), reclassify, protectSender, restore, alerts(afterId:), projects, projectUpdates(name), unsubscribes, startScan, scan, scans, settings, updateSettings, latestBriefing (null on 404), briefings` |
| `lib/app/router.dart`, `routes.dart`, `app_shell.dart` | `routerProvider`, `Routes.*`, `inboxBadgeProvider`, `StatefulShellRoute` with 4 branches |
| `lib/widgets/tab_scaffold.dart` | `TabScaffold(title, slivers, actions, onRefresh)` — every tab screen uses it |

---

# Phase 2 — Shared widgets + Inbox triage feed

Branch `feat/app-phase-2-inbox`. PR title `Phase 2: Inbox triage feed`.

## File map

| Create | Responsibility |
|---|---|
| `lib/core/utils/clock.dart` | `clockProvider` (injectable "now") |
| `lib/core/utils/time_format.dart` | `relativeTime`, `dayBucket` |
| `lib/widgets/category_style.dart` | category → color/icon/label |
| `lib/widgets/category_chip.dart` | `CategoryChip` |
| `lib/widgets/urgency_pips.dart` | `UrgencyPips` |
| `lib/widgets/empty_state.dart`, `error_state.dart`, `skeleton.dart`, `status_banner.dart`, `section_header.dart` | shared states |
| `lib/features/control/scan_controller.dart` | start + poll a scan (used by Inbox now, Control later) |
| `lib/features/inbox/inbox_controller.dart` | filter, paging, optimistic actions |
| `lib/features/inbox/email_tile.dart` | `EmailTile` |
| `lib/features/inbox/swipeable_email_tile.dart` | swipe actions |
| `lib/features/inbox/reclassify_sheet.dart` | `showReclassifySheet` |
| `lib/features/inbox/email_detail_sheet.dart` | `EmailDetailView`, `showEmailDetailSheet`, `EmailDetailScreen` |
| Modify `lib/features/inbox/inbox_screen.dart` | real screen |
| Modify `lib/app/app_shell.dart` | badge = open urgent count |
| Modify `lib/app/routes.dart`, `router.dart` | `/inbox/email/:id` |

### Task 2.1: Clock + time formatting

**Files:** Create `lib/core/utils/clock.dart`, `lib/core/utils/time_format.dart`; Test `test/core/time_format_test.dart`

**Interfaces — Produces:**
- `final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);`
- `String relativeTime(DateTime t, DateTime now)` → `'now'` (<1 min), `'5 min ago'`, `'3 h ago'` (same day, <24 h), `'Yesterday'`, `'Mon 28 Sep'` (older, same year), `'28 Sep 2025'` (other year).
- `String dayBucket(DateTime t, DateTime now)` → `'Today'`, `'Yesterday'`, else `'Mon 28 Sep'` (other year: `'28 Sep 2025'`).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/utils/time_format.dart';

void main() {
  final now = DateTime(2026, 9, 28, 12);
  test('relativeTime', () {
    expect(relativeTime(now.subtract(const Duration(seconds: 20)), now), 'now');
    expect(relativeTime(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
    expect(relativeTime(now.subtract(const Duration(hours: 3)), now), '3 h ago');
    expect(relativeTime(DateTime(2026, 9, 27, 23), now), 'Yesterday');
    expect(relativeTime(DateTime(2026, 9, 21, 9), now), 'Mon 21 Sep');
    expect(relativeTime(DateTime(2025, 9, 28, 9), now), '28 Sep 2025');
  });
  test('dayBucket', () {
    expect(dayBucket(DateTime(2026, 9, 28, 1), now), 'Today');
    expect(dayBucket(DateTime(2026, 9, 27, 23), now), 'Yesterday');
    expect(dayBucket(DateTime(2026, 9, 21), now), 'Mon 21 Sep');
  });
}
```

- [ ] **Step 2:** Run `flutter test test/core/time_format_test.dart` → FAIL (file missing).
- [ ] **Step 3: Implement**

```dart
// lib/core/utils/clock.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable clock so widget tests can pin "now".
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
```

```dart
// lib/core/utils/time_format.dart
import 'package:intl/intl.dart';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _date(DateTime t, DateTime now) => t.year == now.year
    ? DateFormat('EEE d MMM').format(t)
    : DateFormat('d MMM y').format(t);

String relativeTime(DateTime t, DateTime now) {
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return 'now';
  if (_sameDay(t, now) && diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (_sameDay(t, now)) return '${diff.inHours} h ago';
  if (_sameDay(t, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return _date(t, now);
}

String dayBucket(DateTime t, DateTime now) {
  if (_sameDay(t, now)) return 'Today';
  if (_sameDay(t, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return _date(t, now);
}
```

- [ ] **Step 4:** Run the test → PASS. **Step 5:** Commit `Add clock provider and relative time formatting`.

### Task 2.2: Category style, CategoryChip, UrgencyPips

**Files:** Create `lib/widgets/category_style.dart`, `category_chip.dart`, `urgency_pips.dart`; Test `test/widgets/category_widgets_test.dart`

**Interfaces — Produces:**
- `class CategoryStyle { final Color color; final IconData icon; final String label; static CategoryStyle of(BuildContext context, EmailCategory c); }` — colors from `context.sentinelColors` (`urgent, project, transactional, fyi, marketing, spam`), icons exactly as DESIGN_BRIEF §3.2, label = `c.label`.
- `CategoryChip({required EmailCategory category})` — pill (height ≥ 28, `Radii.chip`), background `color.withValues(alpha: 0.12)`, icon 16 + `labelMedium` text in `color`.
- `UrgencyPips({required int urgency})` — 5 bars 4×12 dp, gap 2, radius 2; filled count = urgency; filled color: 1–2 `colors.onSurfaceVariant`, 3 `colors.primary`, 4 `sentinelColors.caution`, 5 `colors.error`; unfilled `colors.outlineVariant`; wrapped in `Semantics(label: 'Urgency $urgency of 5')` with `ExcludeSemantics` children.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/data/models.dart';
import 'package:sentinel/widgets/category_chip.dart';
import 'package:sentinel/widgets/urgency_pips.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets('chip shows icon and label for every category', (tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: Wrap(children: [
          for (final c in EmailCategory.values) CategoryChip(category: c),
        ]),
      ),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );
    for (final c in EmailCategory.values) {
      expect(find.text(c.label), findsOneWidget);
    }
    expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
  });

  testWidgets('urgency pips expose a semantic label', (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(body: UrgencyPips(urgency: 4)),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );
    expect(find.bySemanticsLabel('Urgency 4 of 5'), findsOneWidget);
  });
}
```

- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement per the interface above. **Step 4:** PASS. **Step 5:** Commit `Add category chip and urgency pips`.

### Task 2.3: Shared state widgets

**Files:** Create `lib/widgets/empty_state.dart`, `error_state.dart`, `skeleton.dart`, `status_banner.dart`, `section_header.dart`; Test `test/widgets/state_widgets_test.dart`

**Interfaces — Produces:**
- `EmptyState({required IconData icon, required String title, required String body, Widget? action})` — DESIGN_BRIEF §8.
- `ErrorState({required Object error, required VoidCallback onRetry})` — message = `error is ApiException ? error.userMessage : 'Something went wrong. Please try again.'`; shows `FilledButton` "Retry"; when `error.kind == ApiErrorKind.unauthorized` shows `FilledButton` "Reconnect" that calls `ref.read(connectionProvider.notifier).disconnect()` instead of Retry (so it must be a `ConsumerWidget`). Offline icon `Icons.cloud_off_rounded`, others `Icons.error_outline_rounded`.
- `SkeletonBox({double? width, required double height, double radius = Radii.control})` with 1.2 s opacity pulse 0.5↔1.0 (static when `MediaQuery.disableAnimationsOf`), and `EmailTileSkeleton()` mirroring `EmailTile` rows.
- `StatusBanner.offline({required VoidCallback onRetry})`, `StatusBanner.dryRun()`, `StatusBanner.scanRunning()` — full-width strip, tinted background (`error`/`caution`/`primary` at 12 % alpha), icon + one line of `labelLarge`; scanRunning adds a `LinearProgressIndicator`. Copy: offline "Offline — can't reach Sentinel", dryRun "Dry run — nothing is really trashed or unsubscribed", scanRunning "Scanning inbox…".
- `SectionHeader({required String title, String? actionLabel, VoidCallback? onAction})` — `titleLarge`, padding top `Space.s6` bottom `Space.s2`, horizontal gutter.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/network/api_exception.dart';
import 'package:sentinel/widgets/empty_state.dart';
import 'package:sentinel/widgets/error_state.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  testWidgets('offline error mentions Tailscale and retries', (tester) async {
    var retried = 0;
    await pumpScreen(
      tester,
      Scaffold(
        body: ErrorState(
          error: const ApiException(ApiErrorKind.offline, ''),
          onRetry: () => retried++,
        ),
      ),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );
    expect(find.textContaining('Tailscale'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('unauthorized error offers Reconnect', (tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: ErrorState(
          error: const ApiException(ApiErrorKind.unauthorized, ''),
          onRetry: () {},
        ),
      ),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('empty state renders title and body', (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(
        body: EmptyState(
          icon: Icons.inbox_rounded,
          title: 'All clear',
          body: 'Nothing to triage.',
        ),
      ),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );
    expect(find.text('All clear'), findsOneWidget);
    expect(find.text('Nothing to triage.'), findsOneWidget);
  });
}
```

- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `Add shared empty, error, skeleton and banner widgets`.

### Task 2.4: Scan controller

**Files:** Create `lib/features/control/scan_controller.dart`; Test `test/features/scan_controller_test.dart`

**Interfaces — Produces:**
```dart
class ScanState {
  const ScanState({this.run, this.error, this.busy = false});
  final ScanRun? run;       // latest known run (running or finished)
  final Object? error;      // ApiException from start/poll
  final bool busy;          // true while starting or polling
}
class ScanController extends Notifier<ScanState> {
  /// Poll interval; tests override via [pollInterval].
  static Duration pollInterval = const Duration(seconds: 2);
  Future<void> start({int limit = 20});   // POST /api/scan then poll GET /api/scans/{id} until !isRunning
}
final scanControllerProvider = NotifierProvider<ScanController, ScanState>(ScanController.new);
```
Behaviour: `start` sets `busy`; on `ApiErrorKind.conflict` sets `error` (UI shows "A scan is already running") and stops; while polling uses `Future.delayed(pollInterval)`; stops after the run finishes or after 3 minutes; checks `ref.mounted` after every await. When finished it invalidates `inboxControllerProvider` is NOT done here (avoid cycles) — the Inbox listens to `scanControllerProvider` instead (Task 2.8).

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/network/api_exception.dart';
import 'package:sentinel/data/models.dart';
import 'package:sentinel/features/control/scan_controller.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

Json _run(String status) => {
      'id': 7,
      'trigger': 'api',
      'status': status,
      'started_at': '2026-09-28T08:00:00Z',
      'finished_at': status == 'running' ? null : '2026-09-28T08:00:09Z',
      'processed_count': status == 'running' ? 0 : 3,
      'skipped_count': 0,
      'summary': <String, Object?>{},
      'error': null,
    };

void main() {
  setUp(() => ScanController.pollInterval = Duration.zero);

  test('starts a scan and polls until it finishes', () async {
    final adapter = FakeAdapter({
      'POST /api/scan': FakeResponse(_run('running'), status: 202),
      'GET /api/scans/7': FakeResponse(_run('succeeded')),
    });
    final container = ProviderContainer.test(
      overrides: await testOverrides(adapter: adapter),
    );
    await container.read(scanControllerProvider.notifier).start();
    final state = container.read(scanControllerProvider);
    expect(state.busy, isFalse);
    expect(state.run!.status, ScanStatus.succeeded);
    expect(state.run!.processedCount, 3);
  });

  test('a running scan (409) is reported, not thrown', () async {
    final adapter = FakeAdapter({
      'POST /api/scan': const FakeResponse(
        {'detail': 'Scan 3 is already running'},
        status: 409,
      ),
    });
    final container = ProviderContainer.test(
      overrides: await testOverrides(adapter: adapter),
    );
    await container.read(scanControllerProvider.notifier).start();
    final state = container.read(scanControllerProvider);
    expect(state.busy, isFalse);
    expect((state.error! as ApiException).kind, ApiErrorKind.conflict);
  });
}
```

- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `Add scan controller with polling`.

### Task 2.5: Inbox controller

**Files:** Create `lib/features/inbox/inbox_controller.dart`; Test `test/features/inbox/inbox_controller_test.dart`

**Interfaces — Produces:**
```dart
class InboxFilter {
  const InboxFilter({this.category, this.showDone = false});
  final EmailCategory? category; // null = All
  final bool showDone;
}
class InboxState {
  const InboxState({required this.items, required this.nextCursor, this.loadingMore = false});
  final List<EmailItem> items;
  final int? nextCursor;
  final bool loadingMore;
  bool get hasMore => nextCursor != null;
}
final inboxFilterProvider = NotifierProvider<InboxFilterController, InboxFilter>(InboxFilterController.new);
// InboxFilterController: setCategory(EmailCategory?), setShowDone(bool)
final inboxControllerProvider = AsyncNotifierProvider<InboxController, InboxState>(InboxController.new);
class InboxController extends AsyncNotifier<InboxState> {
  static const pageSize = 30;
  Future<InboxState> build();                 // watches inboxFilterProvider; first page
  Future<void> refresh();                     // reload first page, keep current data visible
  Future<void> loadMore();                    // before_id = nextCursor; no-op if !hasMore or loadingMore
  Future<void> setDone(EmailItem email, bool done);   // optimistic; reverts + rethrows ApiException
  Future<void> reclassify(EmailItem email, EmailCategory category); // optimistic; reverts + rethrows
  void replace(EmailItem updated);            // swap an item after detail-sheet actions
}
final openUrgentCountProvider = FutureProvider<int>(...); // emails(categories:{urgent}, limit: 99).items.length
```
Rules: with `showDone == false`, `setDone(email, true)` removes the item from `items`; `setDone(email, false)` (Undo) re-inserts it at its id-ordered position. With `showDone == true` the item stays and its `isDone` flips. After `setDone` succeeds call `ref.invalidate(openUrgentCountProvider)`. If the category filter no longer matches after `reclassify`, remove the item.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/data/models.dart';
import 'package:sentinel/features/inbox/inbox_controller.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<ProviderContainer> containerWith(FakeAdapter adapter) async =>
      ProviderContainer.test(overrides: await testOverrides(adapter: adapter));

  test('loads the first page and pages with before_id', () async {
    final adapter = FakeAdapter({
      'GET /api/emails': const FakeResponse.fixture('email_page'),
    });
    final c = await containerWith(adapter);
    final first = await c.read(inboxControllerProvider.future);
    expect(first.items, hasLength(4));
    await c.read(inboxControllerProvider.notifier).loadMore();
    expect(adapter.requests.last.queryParameters['before_id'], first.nextCursor);
  });

  test('filter change refetches with the category', () async {
    final adapter = FakeAdapter({
      'GET /api/emails': const FakeResponse.fixture('email_page'),
    });
    final c = await containerWith(adapter);
    await c.read(inboxControllerProvider.future);
    c.read(inboxFilterProvider.notifier).setCategory(EmailCategory.urgentActionable);
    await c.read(inboxControllerProvider.future);
    expect(adapter.requests.last.queryParameters['category'], ['urgent_actionable']);
  });

  test('done is optimistic and reverts on failure', () async {
    final ok = FakeAdapter({
      'GET /api/emails': const FakeResponse.fixture('email_page'),
      'POST /api/emails/5/done': const FakeResponse.fixture('action_result'),
    });
    final c = await containerWith(ok);
    final page = await c.read(inboxControllerProvider.future);
    final email = page.items.firstWhere((e) => e.id == 5);
    await c.read(inboxControllerProvider.notifier).setDone(email, true);
    expect(c.read(inboxControllerProvider).value!.items.map((e) => e.id), isNot(contains(5)));

    final failing = FakeAdapter(
      {'GET /api/emails': const FakeResponse.fixture('email_page')},
    ); // POST not routed -> 404 -> ApiException
    final c2 = await containerWith(failing);
    final page2 = await c2.read(inboxControllerProvider.future);
    final email2 = page2.items.firstWhere((e) => e.id == 5);
    await expectLater(
      c2.read(inboxControllerProvider.notifier).setDone(email2, true),
      throwsA(anything),
    );
    expect(c2.read(inboxControllerProvider).value!.items.map((e) => e.id), contains(5));
  });
}
```

- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `Add inbox controller with paging and optimistic actions`.

### Task 2.6: EmailTile + swipe actions

**Files:** Create `lib/features/inbox/email_tile.dart`, `swipeable_email_tile.dart`; Test `test/features/inbox/email_tile_test.dart`

**Interfaces — Produces:**
- `EmailTile({required EmailItem email, VoidCallback? onTap, bool compact = false, Widget? trailing})` — exactly DESIGN_BRIEF §8 `EmailTile` spec (Card + 3 dp left accent bar in category color; rows: chips+time, sender, subject max 2 lines, summary max 2 lines (hidden when `compact`), pips + badges "Trashed" / "Unsubscribed" / "Dry run"). Done items: `Opacity(0.6)` + `Icons.check_circle_rounded` badge "Done". Time text uses `relativeTime(email.timestamp, ref.watch(clockProvider)())` (make it a `ConsumerWidget`). Whole tile is one `InkWell` with ripple.
- `SwipeableEmailTile({required EmailItem email, required VoidCallback onTap, required Future<void> Function() onDone, required Future<void> Function() onReclassify})` — `Dismissible(key: ValueKey('email-${email.id}'))`: `startToEnd` background success + `Icons.check_rounded` + "Done" → `confirmDismiss` returns true and calls `onDone`; `endToStart` background primary + `Icons.label_outline_rounded` + "Reclassify" → `confirmDismiss` calls `onReclassify` and returns false (snaps back). `HapticFeedback.lightImpact()` when a threshold is crossed (`onUpdate` with `details.reached && !details.previousReached`). Disabled (plain `EmailTile`) when `email.isDone`.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/utils/clock.dart';
import 'package:sentinel/data/models.dart';
import 'package:sentinel/features/inbox/email_tile.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets('shows category, subject, urgency and trashed badge', (tester) async {
    final email = EmailItem.fromJson({
      ...fixtureMap('email_item'),
      'is_trashed': true,
    });
    await pumpScreen(
      tester,
      Scaffold(body: EmailTile(email: email)),
      overrides: [
        ...await testOverrides(adapter: FakeAdapter({})),
        clockProvider.overrideWithValue(() => DateTime(2026, 9, 28, 23)),
      ],
    );
    expect(find.text('Urgent'), findsOneWidget);
    expect(find.text(email.subject), findsOneWidget);
    expect(find.text('Trashed'), findsOneWidget);
    expect(find.bySemanticsLabel('Urgency 5 of 5'), findsOneWidget);
  });

  testWidgets('survives 200% text scale without overflow', (tester) async {
    final email = EmailItem.fromJson(fixtureMap('email_item'));
    await pumpScreen(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(body: ListView(children: [EmailTile(email: email)])),
      ),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `Add email tile with swipe actions`.

### Task 2.7: Reclassify sheet + email detail

**Files:** Create `lib/features/inbox/reclassify_sheet.dart`, `email_detail_sheet.dart`; Modify `lib/app/routes.dart` (add `static String email(int id) => '/inbox/email/$id';`), `lib/app/router.dart` (child route `email/:id` under the Inbox `GoRoute` → `EmailDetailScreen(id: int.parse(state.pathParameters['id']!))`); Test `test/features/inbox/email_detail_test.dart`

**Interfaces — Produces:**
- `Future<EmailCategory?> showReclassifySheet(BuildContext context, EmailCategory current)` — `RadioGroup`/radio `ListTile`s for the 6 categories (icon + color + label, current selected); selecting one pops with it.
- `EmailDetailView({required EmailItem email, required ValueChanged<EmailItem> onChanged})` — ConsumerStatefulWidget, DESIGN_BRIEF §8 `EmailDetailSheet` layout. Buttons: `FilledButton` "Mark done"/"Mark not done" → `repositoryProvider.setDone`; `OutlinedButton` "Reclassify" → sheet → `reclassify`; `OutlinedButton` "Protect sender" → `protectSender` + snackbar with server `message`; "Restore from Trash" only when `email.isTrashed` → `restore`. Each shows a spinner while running, calls `onChanged(result.email!)` and shows errors as a snackbar with `ApiException.userMessage`.
- `Future<void> showEmailDetailSheet(BuildContext context, EmailItem email, {required ValueChanged<EmailItem> onChanged})` — `showModalBottomSheet(isScrollControlled: true, useSafeArea: true)` wrapping `DraggableScrollableSheet(initialChildSize: 0.7, maxChildSize: 0.95)`.
- `EmailDetailScreen({required int id})` — full-screen (for notification deep links): loads `repository.email(id)` with loading/error states, shows `EmailDetailView` in a `Scaffold` with `AppBar(title: Text('Email'))`.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/data/models.dart';
import 'package:sentinel/features/inbox/email_detail_sheet.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets('trashed email offers restore and calls the API', (tester) async {
    final email = EmailItem.fromJson({...fixtureMap('email_item'), 'is_trashed': true});
    final adapter = FakeAdapter({
      'POST /api/emails/1/restore': FakeResponse({
        'ok': true,
        'message': 'Restored to inbox',
        'email': {...fixtureMap('email_item'), 'is_trashed': false},
      }),
    });
    EmailItem? changed;
    await pumpScreen(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: EmailDetailView(email: email, onChanged: (e) => changed = e),
        ),
      ),
      overrides: await testOverrides(adapter: adapter),
    );
    expect(find.text('Protect sender'), findsOneWidget);
    await tester.tap(find.text('Restore from Trash'));
    await tester.pumpAndSettle();
    expect(adapter.requests.single.path, '/api/emails/1/restore');
    expect(changed!.isTrashed, isFalse);
  });

  testWidgets('non-trashed email hides restore', (tester) async {
    final email = EmailItem.fromJson(fixtureMap('email_item'));
    await pumpScreen(
      tester,
      Scaffold(body: SingleChildScrollView(child: EmailDetailView(email: email, onChanged: (_) {}))),
      overrides: await testOverrides(adapter: FakeAdapter({})),
    );
    expect(find.text('Restore from Trash'), findsNothing);
    expect(find.text('Mark done'), findsOneWidget);
  });
}
```

- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `Add email detail and reclassify sheets`.

### Task 2.8: Inbox screen + badge

**Files:** Modify `lib/features/inbox/inbox_screen.dart`, `lib/app/app_shell.dart` (`inboxBadgeProvider` → `ref.watch(openUrgentCountProvider).value ?? 0`); Test `test/features/inbox/inbox_screen_test.dart`

**Behaviour (DESIGN_BRIEF §9.3):** `TabScaffold(title: 'Inbox', onRefresh: controller.refresh, actions: [IconButton(tooltip: 'Scan now', icon: Icons.sync_rounded)])`. Slivers: `StatusBanner.scanRunning()` while `scanControllerProvider.busy`; horizontal filter chips (`ChoiceChip`s: All + 6 categories, label from `EmailCategory.label`); "Show done" `SwitchListTile`; then the feed: `SliverList` of day headers (`dayBucket(...).toUpperCase()`, `labelMedium`, muted) and `SwipeableEmailTile`s, gutter padding, `Space.s3` between tiles. Tap tile → `showEmailDetailSheet(... onChanged: controller.replace)`. Swipe right → `controller.setDone(email, true)` then `SnackBar('Marked done', action: 'Undo' → setDone(email, false))`, 5 s. Swipe left → `showReclassifySheet` → `controller.reclassify`. Load more when within 400 px of the end (`NotificationListener<ScrollNotification>`), with a centered small progress indicator row while `loadingMore`. Loading: 5 × `EmailTileSkeleton`. Error: `ErrorState(onRetry: () => ref.invalidate(inboxControllerProvider))`. Empty copy per filter: All → "All clear" / "Sentinel hasn't filed anything here yet."; Urgent → "Nothing urgent" / "Enjoy the quiet."; other categories → "Nothing here" / "No {label} emails right now.". When a scan finishes (`ref.listen(scanControllerProvider, ...)` busy true→false with a succeeded run) call `controller.refresh()` and show a snackbar "Scan complete · N new" (N = `run.processedCount`); on scan error show `userMessage`.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/utils/clock.dart';
import 'package:sentinel/features/inbox/inbox_screen.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<FakeAdapter> pumpInbox(WidgetTester tester, Map<String, FakeResponse> routes, {bool offline = false}) async {
    final adapter = FakeAdapter(routes, offline: offline);
    await pumpScreen(
      tester,
      const InboxScreen(),
      overrides: [
        ...await testOverrides(adapter: adapter),
        clockProvider.overrideWithValue(() => DateTime(2026, 9, 28, 23, 59)),
      ],
    );
    return adapter;
  }

  testWidgets('renders the feed under a day header', (tester) async {
    await pumpInbox(tester, {'GET /api/emails': const FakeResponse.fixture('email_page')});
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Team lunch on Friday'), findsOneWidget);
  });

  testWidgets('swipe right marks done and Undo restores', (tester) async {
    final adapter = await pumpInbox(tester, {
      'GET /api/emails': const FakeResponse.fixture('email_page'),
      'POST /api/emails/5/done': const FakeResponse.fixture('action_result'),
    });
    await tester.drag(find.byKey(const ValueKey('email-5')), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Team lunch on Friday'), findsNothing);
    expect(adapter.requests.last.data, {'done': true});
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(adapter.requests.last.data, {'done': false});
    expect(find.text('Team lunch on Friday'), findsOneWidget);
  });

  testWidgets('filter chip requests only that category', (tester) async {
    final adapter = await pumpInbox(tester, {'GET /api/emails': const FakeResponse.fixture('email_page')});
    await tester.tap(find.widgetWithText(ChoiceChip, 'Urgent'));
    await tester.pumpAndSettle();
    expect(adapter.requests.last.queryParameters['category'], ['urgent_actionable']);
  });

  testWidgets('empty feed shows the All clear state', (tester) async {
    await pumpInbox(tester, {
      'GET /api/emails': const FakeResponse({'items': <Object>[], 'next_cursor': null}),
    });
    expect(find.text('All clear'), findsOneWidget);
  });

  testWidgets('offline shows the Tailscale hint with Retry', (tester) async {
    await pumpInbox(tester, {}, offline: true);
    expect(find.textContaining('Tailscale'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
```

- [ ] **Steps 2–5:** FAIL → implement → PASS → commit `Build inbox triage feed`.
- [ ] **Step 6:** Bump version to `0.2.0+1`, run full verification, push, open PR, wait for green CI (`gh pr checks --watch`).

---

# Phase 3 — Briefing home + Projects

Branch `feat/app-phase-3-briefing-projects`. PR title `Phase 3: Briefing home and projects board`.

## File map

| Create | Responsibility |
|---|---|
| `lib/data/providers.dart` | `systemStatusProvider`, `statsProvider`, `latestBriefingProvider`, `briefingsProvider`, `needsYouProvider`, `projectsProvider`, `projectUpdatesProvider` |
| `lib/widgets/markdown_body.dart` | styled Markdown |
| `lib/widgets/stat_tile.dart` | `StatTile` |
| `lib/features/briefing/briefing_card.dart` | latest briefing card with expand |
| Modify `lib/features/briefing/briefing_screen.dart` | home |
| `lib/features/briefing/briefing_history_screen.dart` | past briefings |
| Modify `lib/features/projects/projects_screen.dart` | project list |
| `lib/features/projects/project_timeline_screen.dart` | one project's timeline |
| Modify `lib/app/routes.dart`, `router.dart` | `/briefing/history`, `/projects/:name` |

### Task 3.1: Data providers

**Interfaces — Produces** (all `FutureProvider`, auto-dispose NOT needed):
```dart
final systemStatusProvider = FutureProvider<SystemStatus>((ref) => ref.watch(repositoryProvider).status());
final statsProvider = FutureProvider<Stats>((ref) => ref.watch(repositoryProvider).stats());
final latestBriefingProvider = FutureProvider<Briefing?>((ref) => ref.watch(repositoryProvider).latestBriefing());
final briefingsProvider = FutureProvider<List<Briefing>>((ref) => ref.watch(repositoryProvider).briefings());
final needsYouProvider = FutureProvider<List<EmailItem>>((ref) async =>
    (await ref.watch(repositoryProvider).emails(categories: {EmailCategory.urgentActionable}, limit: 5)).items);
final projectsProvider = FutureProvider<List<ProjectSummary>>((ref) => ref.watch(repositoryProvider).projects());
final projectUpdatesProvider = FutureProvider.family<List<ProjectUpdate>, String>(
    (ref, name) => ref.watch(repositoryProvider).projectUpdates(name));
```
Test `test/data/providers_test.dart`: with `ProviderContainer.test`, `latestBriefingProvider` returns `null` when the route answers 404 and a `Briefing` for the `briefing` fixture; `projectUpdatesProvider('Murphy-Labs/core')` sends `project=Murphy-Labs/core`. Commit `Add shared data providers`.

### Task 3.2: MarkdownBody + StatTile

- `MarkdownBody({required String data, int? maxLines})` wraps `MarkdownBody` from `flutter_markdown_plus` with a `MarkdownStyleSheet.fromTheme(Theme.of(context))` adjusted to `context.text` (`p: bodyLarge`, `h2: titleLarge`, `h3: titleMedium`, `code:` monospace 13 on `surfaceContainerHigh`), `onTapLink` → `launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication)`; `selectable: true`.
- `StatTile({required IconData icon, required int value, required String label})` — flat `Card`, padding `Space.s4`, icon 20 in `colors.primary`, value `headlineSmall` with `FontFeature.tabularFigures()`, label `labelMedium` muted. `Semantics(label: '$value $label')`.
- Test `test/widgets/stat_markdown_test.dart`: StatTile semantics label `'3 Open actions'`; MarkdownBody renders `'## Needs you'` heading text `Needs you`. Commit `Add markdown body and stat tile`.

### Task 3.3: Briefing screen + history

**Behaviour (DESIGN_BRIEF §9.2):** `TabScaffold(title: 'Briefing', onRefresh: invalidate systemStatus/stats/latestBriefing/needsYou)`. Slivers:
1. Greeting (`displaySmall`): "Good morning" (05–11), "Good afternoon" (12–16), "Good evening" (else), from `clockProvider`. Below: `DateFormat('EEE d MMM')` + " · " + last-scan text (`'Scanned ${relativeTime(finishedAt ?? startedAt)}'`, or "No scans yet"); tapping it → `context.go(Routes.control)`.
2. `StatusBanner.dryRun()` when `status.settings.dryRun`; `StatusBanner.offline` when `systemStatusProvider` has an offline error.
3. `BriefingCard(briefing)`: card with `period chip (periodLabel) · relativeTime(createdAt)`, `title` (`titleLarge`), `MarkdownBody` collapsed to ~12 lines via `ConstrainedBox(maxHeight: 280)` + `ShaderMask` fade + "Read more"/"Show less" `TextButton` (only when content overflows — measure with `LayoutBuilder`/`TextPainter` or always show the toggle when body > 600 chars). Null briefing → `EmptyState(icon: Icons.wb_twilight_rounded, title: 'No briefing yet', body: 'Hermes writes one at 08:00 and 18:00.')`.
4. `SectionHeader('Needs you (N)', actionLabel: 'See all' → set inbox filter to urgent + `context.go(Routes.inbox)`)` + up to 5 `EmailTile(compact: true, trailing: IconButton(tooltip: 'Mark done', icon: Icons.check_rounded))`. Done → `repository.setDone` then `ref.invalidate(needsYouProvider)` and `ref.invalidate(openUrgentCountProvider)`. Empty → a single line "Nothing needs you right now." in `bodyMedium` muted.
5. `SectionHeader('At a glance')` + 2×2 grid of `StatTile`: Open actions (`Icons.task_alt_rounded`), Project updates (`Icons.account_tree_rounded`), Unsubscribed (`Icons.unsubscribe_rounded`), Trashed (`Icons.delete_sweep_rounded`).
6. `ListTile('Past briefings', trailing chevron)` → `context.push(Routes.briefingHistory)`.

`BriefingHistoryScreen`: `Scaffold(AppBar('Past briefings'))`, list of cards (period chip, title, summary 2 lines, date); tap expands inline to the full Markdown.

Routes: `static const briefingHistory = '/briefing/history';` (child route `history` of the briefing GoRoute).

Test `test/features/briefing_screen_test.dart` (routes: status, stats, briefing, `GET /api/emails` → email_page):
- shows `'Good evening'` with clock 20:00, the briefing title `'Morning briefing'`, `'Needs you'`, and stat label `'Trashed'`;
- with `'GET /api/briefings/latest'` → 404 shows `'No briefing yet'` and still shows `'At a glance'`;
- tapping the check on a Needs-you tile POSTs `/api/emails/{id}/done` with `{'done': true}`.

Commit `Build briefing home and history`.

### Task 3.4: Projects list + timeline

**Behaviour (DESIGN_BRIEF §9.4):** `ProjectsScreen`: `TabScaffold(title: 'Projects', onRefresh)`; each `ProjectSummary` → card: name `titleMedium` (ellipsis, 2 lines), right side caution-tinted badge with `openActions` when > 0 (semantics "N open actions"), meta line `'${updateCount} updates · ${relativeTime(lastUpdateAt)}'` + `UrgencyPips(maxUrgency)`. Tap → `context.push(Routes.project(name))`. Empty: `EmptyState(icon: Icons.account_tree_rounded, title: 'No projects yet', body: 'Project updates from GitHub, CI and clients appear here.')`.

`ProjectTimelineScreen(name)`: `Scaffold(AppBar(title: name))`, `ListView` timeline: left rail (2 dp `outlineVariant` line) with a 12 dp dot colored by urgency (same ramp as pips); node content: time (`labelMedium`), subject (`titleMedium`), summary (`bodyMedium`), action callout when `actionRequired` (primaryContainer 40 %, `Icons.task_alt_rounded`, `actionDescription`), done items at 60 % opacity. Tap a node with `emailId` → fetch `repository.email(emailId)` then `showEmailDetailSheet`.

Routes: `static String project(String name) => '/projects/${Uri.encodeComponent(name)}';` child route `:name` (decode with `Uri.decodeComponent`).

Test `test/features/projects_test.dart`: list shows `'Murphy-Labs/core'`, `'2 updates'` text fragment and `'1'` badge; timeline screen shows both fixture subjects and the action text `'Review and respond'`. Commit `Build projects board and timeline`.

- [ ] **Final:** bump `0.3.0+1`, verify, PR, green CI.

---

# Phase 4 — Control & settings

Branch `feat/app-phase-4-control`. PR title `Phase 4: Control center and settings`.

Add dependency: `flutter pub add package_info_plus` (only new dependency allowed).

## File map

| Create | Responsibility |
|---|---|
| `lib/features/control/settings_controller.dart` | optimistic runtime settings |
| Modify `lib/features/control/control_screen.dart` | control center |
| `lib/features/control/lists_editor_screen.dart` | protected senders / project keywords |
| `lib/features/control/unsubscribe_history_screen.dart` | audit log |
| `lib/features/control/scan_history_screen.dart` | recent scans |
| `lib/features/control/connection_sheet.dart` | edit URL/token |
| Modify `routes.dart`, `router.dart` | `/control/lists/:kind`, `/control/unsubscribes`, `/control/scans` |

### Task 4.1: Settings controller

```dart
final settingsControllerProvider = AsyncNotifierProvider<SettingsController, RuntimeSettings>(SettingsController.new);
class SettingsController extends AsyncNotifier<RuntimeSettings> {
  Future<RuntimeSettings> build();                  // repository.settings()
  Future<void> apply(RuntimeSettingsPatch patch);   // optimistic: merge patch into current state immediately,
                                                    // PATCH, then set state to the server response;
                                                    // on ApiException revert to the previous value and rethrow.
}
```
Also `ref.invalidate(systemStatusProvider)` after a successful apply. Test `test/features/settings_controller_test.dart`: apply(dryRun: true) sends `{'dry_run': true}` and state becomes the server response; a 422 reverts and throws `ApiException(kind: validation)`. Commit `Add optimistic settings controller`.

### Task 4.2: Control screen

**Behaviour (DESIGN_BRIEF §9.5):** `TabScaffold(title: 'Control', onRefresh)`. Sections:
1. **System** card from `systemStatusProvider`: status dot (success color + "Online" / error + "Offline"), `v{version}`, rows Mailbox / Model (`llmModel`) / Last scan (`relativeTime` + `' · ${processedCount} new'`, or error text in `error` color when `status == failed`; tap → scan history). Full-width `FilledButton.icon(Icons.sync_rounded, 'Scan now')` bound to `scanControllerProvider` (disabled + inline `LinearProgressIndicator` + "Scanning…" while busy; result line "Last run: N processed, M skipped" when done; 409 → "A scan is already running").
2. **Automation** (`SwitchListTile`s, each with a one-line subtitle): Dry run (subtitle "Simulate — nothing is trashed or unsubscribed"; when on, the tile uses `caution` color for its icon `Icons.science_outlined` and shows `StatusBanner.dryRun()` at the top of the screen), Auto-unsubscribe, Auto-trash marketing, Mark processed as read.
3. **Notifications**: Background alerts (`appPreferencesProvider.backgroundAlerts`; Phase 5 hooks registration), Urgent emails, Project updates, Minimum urgency `Slider(min 1, max 5, divisions 4, label: '$value')` applied on `onChangeEnd`.
4. **Lists**: "Protected senders (N)" → `/control/lists/protected`, "Project keywords (N)" → `/control/lists/keywords`, "Unsubscribe history" → `/control/unsubscribes`.
5. **Appearance**: `SegmentedButton<ThemeMode>` (System / Light / Dark) → `setThemeMode`; "Reduce transparency" switch → `setReduceTransparency`.
6. **Connection**: server host text (`Uri.parse(baseUrl).host`) → `showConnectionSheet` (URL + token fields, "Save" re-runs `connectionProvider.notifier.connect`); "Disconnect" `TextButton` in `colors.error` → confirm `AlertDialog` ("Disconnect from Sentinel?" / "You'll need the API token to reconnect.") → `disconnect()`.
7. **About**: "Sentinel {version} (build {buildNumber})" from `PackageInfo.fromPlatform()` (wrap in a `FutureProvider`; tests override it).

Every toggle calls `settingsControllerProvider.notifier.apply(...)`; on failure show a snackbar with `userMessage` (state already reverted).

### Task 4.3: Lists editor, unsubscribe history, scan history

- `ListsEditorScreen(kind: ListKind.protected | ListKind.keywords)`: `AppBar` title "Protected senders"/"Project keywords"; helper text ("Emails from these senders or domains are never unsubscribed or trashed." / "Emails whose subject or sender contains these words are treated as project updates."); `TextField` + "Add" (lower-cased, trimmed, ignores duplicates/empty); `Wrap` of `InputChip`s with delete (`onDeleted`, tooltip "Remove {value}"). Each change → `apply(RuntimeSettingsPatch(protectedDomains: …))` / `projectKeywords`.
- `UnsubscribeHistoryScreen`: list of `UnsubscribeLog`: leading icon (`check_circle` success / `error_outline` error), title `senderEmail`, subtitle `'${method} · HTTP ${httpStatus ?? '–'} · ${relativeTime(attemptedAt)}'`, error message in `error` color when failed.
- `ScanHistoryScreen`: list of `ScanRun`: trigger, status chip, processed/skipped, duration, error.

Tests `test/features/control_test.dart`:
- toggling "Dry run" PATCHes `{'dry_run': true}`;
- the slider change PATCHes `min_urgency_to_notify`;
- adding `Example.COM ` in the protected editor PATCHes a list containing `example.com`;
- Disconnect → confirm → the connection store is cleared (`MemoryConnectionStore.value == null`).

Commits: `Build control center`, `Add list editors and history screens`. Final: bump `0.4.0+1`, verify, PR, green CI.

---

# Phase 5 — Background alerts, deep links, icon, release polish

Branch `feat/app-phase-5-alerts`. PR title `Phase 5: Background alerts and 1.0 polish`.

## File map

| Create | Responsibility |
|---|---|
| `lib/core/notifications/notification_service.dart` | channels, show, tap routing |
| `lib/core/background/alert_poller.dart` | pure polling logic + WorkManager dispatcher |
| `lib/core/background/alert_scheduler.dart` | register/cancel periodic task |
| Modify `lib/main.dart`, `lib/app/app.dart` | init + tap → router |
| Modify `lib/features/control/control_screen.dart` | background alerts switch wiring |
| Android res: `mipmap-anydpi-v26/ic_launcher.xml`, `drawable/ic_launcher_foreground.xml`, `drawable/ic_launcher_monochrome.xml`, `values/colors.xml`, `drawable/ic_stat_sentinel.xml` | launcher + notification icons |

### Task 5.1: Alert poller (pure logic, fully unit-tested)

```dart
/// Storage of the alert cursor + last seen briefing id (SharedPreferences keys
/// 'alerts.cursor' and 'alerts.lastBriefingId').
class AlertCursorStore {
  AlertCursorStore(this._prefs);
  final SharedPreferences _prefs;
  int? get cursor;              Future<void> setCursor(int value);
  int? get lastBriefingId;      Future<void> setLastBriefingId(int value);
}

abstract interface class AlertNotifier {
  Future<void> showEmails(List<EmailItem> emails);   // ≥ 4 → one summary notification
  Future<void> showBriefing(Briefing briefing);
}

class PollResult { const PollResult({required this.notifiedEmails, required this.notifiedBriefing}); final int notifiedEmails; final bool notifiedBriefing; }

/// One poll: first run (cursor == null) only initialises the cursor via
/// alerts(afterId: -1) and remembers the current briefing id without notifying.
Future<PollResult> pollAlerts({
  required SentinelRepository repository,
  required AlertCursorStore store,
  required AlertNotifier notifier,
});
```

Test `test/core/alert_poller_test.dart` with a recording fake `AlertNotifier` and `SharedPreferences.setMockInitialValues`:
- first run → requests `after_id=-1`, stores the cursor, notifies nothing;
- next run with cursor 2 and a response `{'items': [<urgent email json>], 'cursor': 3}` → notifies 1 email and stores 3;
- a newer briefing id than stored → `showBriefing` called once; same id → not called;
- repository throws offline → rethrows nothing, returns `PollResult(0, false)` and keeps the old cursor.

Commit `Add alert poller`.

### Task 5.2: Notification service + WorkManager wiring

`NotificationService` (implements `AlertNotifier`):
- Channels: `urgent` ("Urgent email", `Importance.high`), `projects` ("Project updates", `Importance.defaultImportance`), `briefings` ("Briefings", default). Small icon `@drawable/ic_stat_sentinel`.
- `initialize({required void Function(String route) onTap})` using `FlutterLocalNotificationsPlugin().initialize(settings: InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_stat_sentinel')), onDidReceiveNotificationResponse: (r) => onTap(r.payload ?? Routes.inbox))`; also returns the launch route from `getNotificationAppLaunchDetails()` when the app was opened by a notification.
- `show(id: email.id, title: '${category.label} · ${senderName}', body: summary.isNotEmpty ? summary : subject, notificationDetails: NotificationDetails(android: AndroidNotificationDetails(channelId, channelName, importance, priority, groupKey: 'sentinel.emails')), payload: Routes.email(email.id))` — urgent emails use the `urgent` channel, everything else `projects`. For ≥ 4 emails show one summary (`id: 0`, `InboxStyleInformation` with the first 5 subjects, payload `Routes.inbox`).
- Briefing: `id: 1_000_000 + briefing.id`, title "Your ${periodLabel.toLowerCase()} briefing is ready", body `briefing.summary`, payload `Routes.briefing`.
- `requestPermission()` → `resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission()`; call it once after a successful connect and when the user turns on Background alerts.

`alert_poller.dart` also defines:
```dart
const kAlertTask = 'sentinel.pollAlerts';
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // build: ConnectionStore().read() → null ⇒ return true (nothing to do);
    // SentinelRepository(ApiClient(config)), AlertCursorStore(await SharedPreferences.getInstance()),
    // NotificationService() initialised without onTap; await pollAlerts(...); return true;
  });
}
```
`AlertScheduler.sync({required bool enabled, required bool connected})`: enabled && connected → `Workmanager().registerPeriodicTask(kAlertTask, kAlertTask, frequency: const Duration(minutes: 15), constraints: Constraints(networkType: NetworkType.connected), existingWorkPolicy: ExistingPeriodicWorkPolicy.keep)`; otherwise `Workmanager().cancelByUniqueName(kAlertTask)`.

`main.dart`: after `SharedPreferences.getInstance()` → `await Workmanager().initialize(callbackDispatcher);` Create the `NotificationService`, provide it through a `notificationServiceProvider` override. `SentinelApp`: `ref.listen` on `connectionProvider` + `appPreferencesProvider.backgroundAlerts` → `AlertScheduler.sync`; on notification tap → `ref.read(routerProvider).go(route)`; on cold start go to the launch route once the router is ready.

Tests: mock the plugin boundary by testing `NotificationService` routing helpers as pure functions (`channelFor(EmailItem)`, `payloadFor(EmailItem)`, `summaryNeeded(n)`); do not call platform channels in tests. Commit `Wire background alerts and notification deep links`.

### Task 5.3: Launcher + notification icons, splash

- `android/app/src/main/res/values/colors.xml`: `<color name="ic_launcher_background">#0F766E</color>`, `<color name="splash_background">#F8FAFC</color>`; `values-night/colors.xml`: splash `#0B1220`.
- `drawable/ic_launcher_foreground.xml`: 108 dp vector; white rounded shield path with a check mark, contained in the central 66 dp.
- `drawable/ic_launcher_monochrome.xml`: same glyph, single color.
- `mipmap-anydpi-v26/ic_launcher.xml`: `<adaptive-icon>` with background color, foreground and monochrome.
- `drawable/ic_stat_sentinel.xml`: 24 dp white shield glyph (status bar icon).
- `values/styles.xml` + `values-night/styles.xml`: `LaunchTheme` window background `@color/splash_background`; Android 12+ `android:windowSplashScreenBackground` + `windowSplashScreenAnimatedIcon` (`@drawable/ic_launcher_foreground`).
- Delete the template Flutter-logo PNGs in `mipmap-*dpi/` (minSdk 26 uses the adaptive icon). Commit `Add Sentinel launcher, notification icon and splash`.

### Task 5.4: Polish + accessibility pass

Run through DESIGN_BRIEF §11–§12 on every screen and fix findings. Add `test/a11y_test.dart` that pumps each tab (with fixtures) in dark theme at `TextScaler.linear(2)` and asserts `tester.takeException()` is null, and uses `expectLater(tester, meetsGuideline(androidTapTargetGuideline))` and `meetsGuideline(labeledTapTargetGuideline)` on the Inbox and Control screens. Commit `Accessibility and polish pass`.

- [ ] **Final:** bump `1.0.0+1`, update `app/README.md` (install from Releases, connect via Tailscale, where the token lives), verify, PR, green CI.

---

## Self-review (done by the architect)

- PRD coverage: Connect (Phase 1 ✔), Briefing (3.3), Inbox + actions (2.5–2.8), Projects (3.4), Control incl. lists/history/appearance/connection/about (4.x), background alerts + deep links (5.1–5.2), icon/splash (5.3), accessibility NFRs (5.4), releases (CI already).
- Names used across tasks: `clockProvider`, `relativeTime`, `dayBucket`, `CategoryStyle`, `CategoryChip`, `UrgencyPips`, `EmptyState`, `ErrorState`, `SkeletonBox`, `EmailTileSkeleton`, `StatusBanner`, `SectionHeader`, `scanControllerProvider`/`ScanController.pollInterval`, `inboxFilterProvider`, `inboxControllerProvider`, `openUrgentCountProvider`, `EmailTile`, `SwipeableEmailTile`, `showReclassifySheet`, `EmailDetailView`, `showEmailDetailSheet`, `EmailDetailScreen`, `Routes.email/briefingHistory/project`, `systemStatusProvider` … `projectUpdatesProvider`, `settingsControllerProvider`, `AlertCursorStore`, `AlertNotifier`, `pollAlerts`, `NotificationService`, `AlertScheduler`, `kAlertTask`, `callbackDispatcher`.
