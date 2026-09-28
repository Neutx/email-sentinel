import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/preferences/app_preferences.dart';
import 'package:sentinel/core/providers.dart';
import 'package:sentinel/core/utils/clock.dart';
import 'package:sentinel/features/control/scan_history_screen.dart';
import 'package:sentinel/features/control/unsubscribe_history_screen.dart';
import 'package:sentinel/widgets/empty_state.dart';
import 'package:sentinel/widgets/error_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  final now = DateTime(2026, 9, 28, 20, 0);

  Future<List<Override>> baseOverrides({required FakeAdapter adapter}) async {
    SharedPreferences.setMockInitialValues(const {});
    final sharedPrefs = await SharedPreferences.getInstance();
    return [
      sharedPreferencesProvider.overrideWithValue(sharedPrefs),
      connectionStoreProvider.overrideWithValue(
        MemoryConnectionStore(testConfig),
      ),
      apiClientFactoryProvider.overrideWithValue(
        (config) => fakeClient(adapter, config),
      ),
      clockProvider.overrideWithValue(() => now),
    ];
  }

  group('UnsubscribeHistoryScreen', () {
    testWidgets('renders unsubscribe logs with success icon and details', (
      tester,
    ) async {
      final adapter = FakeAdapter({
        'GET /api/unsubscribes': const FakeResponse.fixture('unsubscribes'),
      });

      await pumpScreen(
        tester,
        const UnsubscribeHistoryScreen(),
        overrides: await baseOverrides(adapter: adapter),
      );

      expect(find.text('Unsubscribe history'), findsOneWidget);
      expect(find.text('deals@shop.com'), findsOneWidget);
      expect(find.textContaining('rfc8058_post'), findsOneWidget);
      expect(find.textContaining('HTTP 200'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('renders empty state when no unsubscribe logs', (tester) async {
      final adapter = FakeAdapter({
        'GET /api/unsubscribes': const FakeResponse(<Object>[]),
      });

      await pumpScreen(
        tester,
        const UnsubscribeHistoryScreen(),
        overrides: await baseOverrides(adapter: adapter),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No unsubscribes yet'), findsOneWidget);
    });

    testWidgets('renders error state on fetch failure', (tester) async {
      final adapter = FakeAdapter({
        'GET /api/unsubscribes': const FakeResponse({
          'detail': 'Server error',
        }, status: 500),
      });

      await pumpScreen(
        tester,
        const UnsubscribeHistoryScreen(),
        overrides: await baseOverrides(adapter: adapter),
      );

      expect(find.byType(ErrorState), findsOneWidget);
    });
  });

  group('ScanHistoryScreen', () {
    testWidgets('renders scan runs with status chips and details', (
      tester,
    ) async {
      final adapter = FakeAdapter({
        'GET /api/scans': const FakeResponse.fixture('scans'),
      });

      await pumpScreen(
        tester,
        const ScanHistoryScreen(),
        overrides: await baseOverrides(adapter: adapter),
      );

      expect(find.text('Scan history'), findsOneWidget);
      expect(find.text('hermes-cron'), findsOneWidget);
      expect(find.text('SUCCEEDED'), findsOneWidget);
      expect(find.textContaining('6 processed · 2 skipped'), findsOneWidget);
    });

    testWidgets('renders empty state when no scan runs', (tester) async {
      final adapter = FakeAdapter({
        'GET /api/scans': const FakeResponse(<Object>[]),
      });

      await pumpScreen(
        tester,
        const ScanHistoryScreen(),
        overrides: await baseOverrides(adapter: adapter),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No scans yet'), findsOneWidget);
    });

    testWidgets('renders error state on fetch failure', (tester) async {
      final adapter = FakeAdapter({
        'GET /api/scans': const FakeResponse({
          'detail': 'Server error',
        }, status: 500),
      });

      await pumpScreen(
        tester,
        const ScanHistoryScreen(),
        overrides: await baseOverrides(adapter: adapter),
      );

      expect(find.byType(ErrorState), findsOneWidget);
    });
  });
}
