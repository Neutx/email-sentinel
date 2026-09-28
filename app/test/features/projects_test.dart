import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/utils/clock.dart';
import 'package:sentinel/features/inbox/email_detail_sheet.dart';
import 'package:sentinel/features/projects/project_timeline_screen.dart';
import 'package:sentinel/features/projects/projects_screen.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  final now = DateTime(2026, 9, 28, 20, 0);

  testWidgets(
    'ProjectsScreen renders project list with name, updates count, and open actions badge',
    (tester) async {
      final adapter = FakeAdapter({
        'GET /api/projects': const FakeResponse.fixture('projects'),
      });
      await pumpScreen(
        tester,
        const ProjectsScreen(),
        overrides: [
          ...await testOverrides(adapter: adapter),
          clockProvider.overrideWithValue(() => now),
        ],
      );

      expect(find.text('Murphy-Labs/core'), findsOneWidget);
      expect(find.textContaining('2 updates'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.bySemanticsLabel('1 open actions'), findsOneWidget);
    },
  );

  testWidgets('ProjectsScreen shows empty state when no projects', (
    tester,
  ) async {
    final adapter = FakeAdapter({
      'GET /api/projects': const FakeResponse(<Object>[]),
    });
    await pumpScreen(
      tester,
      const ProjectsScreen(),
      overrides: await testOverrides(adapter: adapter),
    );

    expect(find.text('No projects yet'), findsOneWidget);
  });

  testWidgets(
    'ProjectTimelineScreen renders updates, action callout, and opens email detail on tap',
    (tester) async {
      final adapter = FakeAdapter({
        'GET /api/project-updates': const FakeResponse.fixture(
          'project_updates',
        ),
        'GET /api/emails/3': const FakeResponse.fixture('email_item'),
      });
      await pumpScreen(
        tester,
        const ProjectTimelineScreen(name: 'Murphy-Labs/core'),
        overrides: [
          ...await testOverrides(adapter: adapter),
          clockProvider.overrideWithValue(() => now),
        ],
      );

      expect(find.text('Murphy-Labs/core'), findsOneWidget);
      expect(find.text('[Murphy-Labs/core] CI failed on main'), findsOneWidget);
      expect(
        find.text('[Murphy-Labs/core] Pull request #88 merged'),
        findsOneWidget,
      );
      expect(find.text('Review and respond'), findsOneWidget);

      // Tap on the first update node that has email_id = 3
      await tester.tap(find.text('[Murphy-Labs/core] CI failed on main'));
      await tester.pumpAndSettle();

      expect(adapter.requests.any((r) => r.path == '/api/emails/3'), isTrue);
      expect(find.byType(EmailDetailView), findsOneWidget);
    },
  );

  testWidgets(
    'ProjectTimelineScreen email fetch failure shows error snackbar',
    (tester) async {
      final adapter = FakeAdapter({
        'GET /api/project-updates': const FakeResponse.fixture(
          'project_updates',
        ),
        'GET /api/emails/3': const FakeResponse({
          'detail': 'Email not found',
        }, status: 404),
      });
      await pumpScreen(
        tester,
        const ProjectTimelineScreen(name: 'Murphy-Labs/core'),
        overrides: [
          ...await testOverrides(adapter: adapter),
          clockProvider.overrideWithValue(() => now),
        ],
      );

      await tester.tap(find.text('[Murphy-Labs/core] CI failed on main'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Email not found'), findsOneWidget);
    },
  );
}
