import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/app/app.dart';
import 'package:sentinel/app/routes.dart';
import 'package:sentinel/core/notifications/notification_service.dart';
import 'package:sentinel/features/control/control_screen.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

class FakeNotificationService extends NotificationService {
  NotificationTapHandler? tapHandler;
  int requestPermissionCalls = 0;

  @override
  void setOnTap(NotificationTapHandler onTap) {
    tapHandler = onTap;
  }

  @override
  Future<bool?> requestPermission() async {
    requestPermissionCalls++;
    return true;
  }
}

final _routes = {
  'GET /api/health': const FakeResponse.fixture('health'),
  'GET /api/status': const FakeResponse.fixture('status'),
  'GET /api/settings': const FakeResponse.fixture('settings'),
  'GET /api/briefings/latest': const FakeResponse.fixture('briefing'),
  'GET /api/briefings': const FakeResponse.fixture('briefings'),
  'GET /api/emails': const FakeResponse.fixture('email_page'),
  'GET /api/emails/1': const FakeResponse.fixture('email_item'),
  'GET /api/stats': const FakeResponse.fixture('stats'),
};

void main() {
  testWidgets('warm notification tap routes to deep link payload', (
    tester,
  ) async {
    final fakeNotifications = FakeNotificationService();
    final overrides = await testOverrides(
      adapter: FakeAdapter(_routes),
      connection: testConfig,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides,
          notificationServiceProvider.overrideWithValue(fakeNotifications),
        ],
        child: const SentinelApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Briefing'), findsWidgets);

    // Simulate warm notification tap
    expect(fakeNotifications.tapHandler, isNotNull);
    fakeNotifications.tapHandler!(Routes.email(1));
    await tester.pumpAndSettle();

    expect(
      find.text('Invoice overdue: contract renewal needs signature'),
      findsOneWidget,
    );
  });

  testWidgets('cold start notification tap navigates to launchRoute', (
    tester,
  ) async {
    final fakeNotifications = FakeNotificationService();
    final overrides = await testOverrides(
      adapter: FakeAdapter(_routes),
      connection: testConfig,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides,
          notificationServiceProvider.overrideWithValue(fakeNotifications),
        ],
        child: SentinelApp(launchRoute: Routes.email(1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Invoice overdue: contract renewal needs signature'),
      findsOneWidget,
    );
  });

  testWidgets(
    'enabling Background alerts in ControlScreen requests permission',
    (tester) async {
      final fakeNotifications = FakeNotificationService();
      final overrides = await testOverrides(
        adapter: FakeAdapter(_routes),
        connection: testConfig,
        prefs: {'pref.backgroundAlerts': false},
      );

      await pumpScreen(
        tester,
        const ControlScreen(),
        overrides: [
          ...overrides,
          notificationServiceProvider.overrideWithValue(fakeNotifications),
        ],
      );

      final switchFinder = find.widgetWithText(
        SwitchListTile,
        'Background alerts',
      );
      await tester.scrollUntilVisible(switchFinder, 200);
      expect(switchFinder, findsOneWidget);

      final tile = tester.widget<SwitchListTile>(switchFinder);
      expect(tile.value, isFalse);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(fakeNotifications.requestPermissionCalls, 1);
    },
  );
}
