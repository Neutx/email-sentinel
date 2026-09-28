import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/features/briefing/briefing_screen.dart';
import 'package:sentinel/features/control/control_screen.dart';
import 'package:sentinel/features/inbox/inbox_screen.dart';
import 'package:sentinel/features/projects/projects_screen.dart';

import 'helpers/fake_api.dart';
import 'helpers/pump_app.dart';

final _allRoutes = {
  'GET /api/health': const FakeResponse.fixture('health'),
  'GET /api/status': const FakeResponse.fixture('status'),
  'GET /api/settings': const FakeResponse.fixture('settings'),
  'GET /api/briefings/latest': const FakeResponse.fixture('briefing'),
  'GET /api/briefings': const FakeResponse.fixture('briefings'),
  'GET /api/emails': const FakeResponse.fixture('email_page'),
  'GET /api/emails/1': const FakeResponse.fixture('email_item'),
  'GET /api/projects': const FakeResponse.fixture('projects'),
  'GET /api/project-updates': const FakeResponse.fixture('project_updates'),
  'GET /api/stats': const FakeResponse.fixture('stats'),
  'GET /api/scans': const FakeResponse.fixture('scans'),
  'GET /api/unsubscribes': const FakeResponse.fixture('unsubscribes'),
};

void main() {
  group('Accessibility & 200% Text Scaling Pass', () {
    testWidgets('Briefing screen scales to 200% text in dark theme without overflow', (
      tester,
    ) async {
      final overrides = await testOverrides(
        adapter: FakeAdapter(_allRoutes),
        connection: testConfig,
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2.0),
          ),
          child: Builder(
            builder: (context) {
              return SizedBox(
                width: 390,
                height: 844,
                child: FutureBuilder(
                  future: Future.value(true),
                  builder: (_, __) => const SizedBox(),
                ),
              );
            },
          ),
        ),
      );

      await pumpScreen(
        tester,
        const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2.0),
          ),
          child: BriefingScreen(),
        ),
        overrides: overrides,
        themeMode: ThemeMode.dark,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('Inbox screen scales to 200% text and meets tap target guidelines', (
      tester,
    ) async {
      final overrides = await testOverrides(
        adapter: FakeAdapter(_allRoutes),
        connection: testConfig,
      );

      await pumpScreen(
        tester,
        const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2.0),
          ),
          child: InboxScreen(),
        ),
        overrides: overrides,
        themeMode: ThemeMode.dark,
      );

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('Projects screen scales to 200% text in dark theme without overflow', (
      tester,
    ) async {
      final overrides = await testOverrides(
        adapter: FakeAdapter(_allRoutes),
        connection: testConfig,
      );

      await pumpScreen(
        tester,
        const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2.0),
          ),
          child: ProjectsScreen(),
        ),
        overrides: overrides,
        themeMode: ThemeMode.dark,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('Control screen scales to 200% text and meets tap target guidelines', (
      tester,
    ) async {
      final overrides = await testOverrides(
        adapter: FakeAdapter(_allRoutes),
        connection: testConfig,
      );

      await pumpScreen(
        tester,
        const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2.0),
          ),
          child: ControlScreen(),
        ),
        overrides: overrides,
        themeMode: ThemeMode.dark,
      );

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
