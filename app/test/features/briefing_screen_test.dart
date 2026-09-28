import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/utils/clock.dart';
import 'package:sentinel/features/briefing/briefing_screen.dart';
import 'package:sentinel/widgets/section_header.dart';
import 'package:sentinel/widgets/stat_tile.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  final eveningTime = DateTime(2026, 9, 28, 20, 0);

  Map<String, FakeResponse> defaultRoutes() => {
    'GET /api/status': const FakeResponse.fixture('status'),
    'GET /api/stats': const FakeResponse.fixture('stats'),
    'GET /api/briefings/latest': const FakeResponse.fixture('briefing'),
    'GET /api/emails': const FakeResponse.fixture('email_page'),
  };

  testWidgets('shows greeting, briefing card, Needs you, and stats', (
    tester,
  ) async {
    final adapter = FakeAdapter(defaultRoutes());
    await pumpScreen(
      tester,
      const BriefingScreen(),
      overrides: [
        ...await testOverrides(adapter: adapter),
        clockProvider.overrideWithValue(() => eveningTime),
      ],
    );

    expect(find.text('Good evening'), findsOneWidget);
    expect(find.text('Morning briefing'), findsOneWidget);
    expect(find.widgetWithText(SectionHeader, 'Needs you (4)'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.widgetWithText(StatTile, 'Trashed'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.widgetWithText(StatTile, 'Trashed'), findsOneWidget);
    expect(find.widgetWithText(StatTile, 'Open actions'), findsOneWidget);
    expect(find.widgetWithText(StatTile, 'Project updates'), findsOneWidget);
    expect(find.widgetWithText(StatTile, 'Unsubscribed'), findsOneWidget);
  });

  testWidgets(
    '404 on latest briefing shows empty state and keeps at-a-glance stats',
    (tester) async {
      final routes = defaultRoutes()
        ..['GET /api/briefings/latest'] = const FakeResponse({
          'detail': 'No briefing yet',
        }, status: 404);
      final adapter = FakeAdapter(routes);
      await pumpScreen(
        tester,
        const BriefingScreen(),
        overrides: [
          ...await testOverrides(adapter: adapter),
          clockProvider.overrideWithValue(() => eveningTime),
        ],
      );

      expect(find.text('No briefing yet'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('At a glance'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('At a glance'), findsOneWidget);
      expect(find.widgetWithText(StatTile, 'Trashed'), findsOneWidget);
    },
  );

  testWidgets('tapping the check on a Needs-you tile marks done', (
    tester,
  ) async {
    final routes = defaultRoutes()
      ..['POST /api/emails/6/done'] = const FakeResponse.fixture(
        'action_result',
      );
    final adapter = FakeAdapter(routes);
    await pumpScreen(
      tester,
      const BriefingScreen(),
      overrides: [
        ...await testOverrides(adapter: adapter),
        clockProvider.overrideWithValue(() => eveningTime),
      ],
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();

    final doneButton = find
        .widgetWithIcon(IconButton, Icons.check_rounded)
        .first;
    await tester.tap(doneButton);
    await tester.pumpAndSettle();

    expect(
      adapter.requests.any(
        (r) =>
            r.path == '/api/emails/6/done' &&
            (r.data as Map<String, dynamic>?)?['done'] == true,
      ),
      isTrue,
    );
  });

  testWidgets('failed mark-done shows error snackbar without crashing', (
    tester,
  ) async {
    final routes = defaultRoutes()
      ..['POST /api/emails/6/done'] = const FakeResponse({
        'detail': 'Database write failed',
      }, status: 500);
    final adapter = FakeAdapter(routes);
    await pumpScreen(
      tester,
      const BriefingScreen(),
      overrides: [
        ...await testOverrides(adapter: adapter),
        clockProvider.overrideWithValue(() => eveningTime),
      ],
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();

    final doneButton = find
        .widgetWithIcon(IconButton, Icons.check_rounded)
        .first;
    await tester.tap(doneButton);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Database write failed'), findsOneWidget);
  });
}
