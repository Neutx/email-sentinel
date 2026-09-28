import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentinel/core/config/connection_config.dart';
import 'package:sentinel/core/preferences/app_preferences.dart';
import 'package:sentinel/core/providers.dart';
import 'package:sentinel/core/utils/clock.dart';
import 'package:sentinel/data/providers.dart';
import 'package:sentinel/features/control/control_screen.dart';
import 'package:sentinel/features/control/scan_controller.dart';
import 'package:sentinel/widgets/status_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  final now = DateTime(2026, 9, 28, 20, 0);

  final mockPackageInfo = PackageInfo(
    appName: 'Sentinel',
    packageName: 'io.murphylabs.sentinel',
    version: '0.4.0',
    buildNumber: '1',
    buildSignature: '',
  );

  Future<List<Override>> baseOverrides({
    required FakeAdapter adapter,
    MemoryConnectionStore? store,
    ConnectionConfig? connection = testConfig,
  }) async {
    SharedPreferences.setMockInitialValues(const {});
    final sharedPrefs = await SharedPreferences.getInstance();
    final connectionStore = store ?? MemoryConnectionStore(connection);
    return [
      sharedPreferencesProvider.overrideWithValue(sharedPrefs),
      connectionStoreProvider.overrideWithValue(connectionStore),
      apiClientFactoryProvider.overrideWithValue(
        (config) => fakeClient(adapter, config),
      ),
      clockProvider.overrideWithValue(() => now),
      packageInfoProvider.overrideWith((ref) async => mockPackageInfo),
    ];
  }

  setUp(() {
    ScanController.pollInterval = Duration.zero;
  });

  testWidgets(
    'ControlScreen renders all sections: System, Automation, Notifications, Lists, Appearance, Connection, About',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final adapter = FakeAdapter({
        'GET /api/status': const FakeResponse.fixture('status'),
        'GET /api/settings': const FakeResponse.fixture('settings'),
      });

      await pumpScreen(
        tester,
        const ControlScreen(),
        overrides: await baseOverrides(adapter: adapter),
      );

      // System section
      expect(find.text('Online · v0.2.0'), findsOneWidget);
      expect(find.text('ow***@example.com'), findsOneWidget);
      expect(find.text('gemini-3.7-flash'), findsOneWidget);
      expect(find.textContaining('6 new'), findsOneWidget);
      expect(find.text('Scan now'), findsOneWidget);

      // Automation section
      expect(find.text('Automation'), findsOneWidget);
      expect(find.text('Dry run'), findsOneWidget);
      expect(find.text('Auto-unsubscribe'), findsOneWidget);
      expect(find.text('Auto-trash marketing'), findsOneWidget);
      expect(find.text('Mark processed as read'), findsOneWidget);

      // Notifications section
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Background alerts'), findsOneWidget);
      expect(find.text('Urgent emails'), findsOneWidget);
      expect(find.text('Project updates'), findsOneWidget);
      expect(find.text('Minimum urgency to notify'), findsOneWidget);

      // Lists section
      expect(find.text('Lists'), findsOneWidget);
      expect(find.text('Protected senders (6)'), findsOneWidget);
      expect(find.text('Project keywords (9)'), findsOneWidget);
      expect(find.text('Unsubscribe history'), findsOneWidget);

      // Appearance section
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Reduce transparency'), findsOneWidget);

      // Connection section
      expect(find.text('Connection'), findsOneWidget);
      expect(find.text('Server'), findsOneWidget);
      expect(find.text('sentinel.test'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);

      // About section
      expect(find.text('About'), findsOneWidget);
      expect(find.text('Version 0.4.0 (build 1)'), findsOneWidget);
    },
  );

  testWidgets(
    'toggling Dry run PATCHes dry_run: true and shows StatusBanner.dryRun',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final initialSettings = fixtureMap('settings');
      final updatedSettings = Map<String, Object?>.from(initialSettings)
        ..['dry_run'] = true;

      final adapter = FakeAdapter({
        'GET /api/status': const FakeResponse.fixture('status'),
        'GET /api/settings': FakeResponse(initialSettings),
        'PATCH /api/settings': FakeResponse(updatedSettings),
      });

      await pumpScreen(
        tester,
        const ControlScreen(),
        overrides: await baseOverrides(adapter: adapter),
      );

      expect(find.byType(StatusBanner), findsNothing);

      // Find Dry run switch and toggle it
      final dryRunSwitch = find.widgetWithText(SwitchListTile, 'Dry run');
      expect(dryRunSwitch, findsOneWidget);

      await tester.tap(dryRunSwitch);
      await tester.pumpAndSettle();

      final patchReq = adapter.requests.firstWhere(
        (r) => r.method == 'PATCH' && r.path == '/api/settings',
      );
      expect(patchReq.data, {'dry_run': true});
      expect(find.byType(StatusBanner), findsOneWidget);
    },
  );

  testWidgets('toggling Dry run failure shows error snackbar', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = FakeAdapter({
      'GET /api/status': const FakeResponse.fixture('status'),
      'GET /api/settings': const FakeResponse.fixture('settings'),
      'PATCH /api/settings': const FakeResponse({
        'detail': 'Failed to apply settings',
      }, status: 500),
    });

    await pumpScreen(
      tester,
      const ControlScreen(),
      overrides: await baseOverrides(adapter: adapter),
    );

    final dryRunSwitch = find.widgetWithText(SwitchListTile, 'Dry run');
    await tester.tap(dryRunSwitch);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Failed to apply settings'), findsOneWidget);
  });

  testWidgets('slider change PATCHes min_urgency_to_notify', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final initialSettings = fixtureMap('settings');
    final updatedSettings = Map<String, Object?>.from(initialSettings)
      ..['min_urgency_to_notify'] = 4;

    final adapter = FakeAdapter({
      'GET /api/status': const FakeResponse.fixture('status'),
      'GET /api/settings': FakeResponse(initialSettings),
      'PATCH /api/settings': FakeResponse(updatedSettings),
    });

    await pumpScreen(
      tester,
      const ControlScreen(),
      overrides: await baseOverrides(adapter: adapter),
    );

    // Initial value is 2
    expect(find.text('2'), findsOneWidget);

    final sliderFinder = find.byType(Slider);
    expect(sliderFinder, findsOneWidget);

    // Drag slider to 4
    final slider = tester.widget<Slider>(sliderFinder);
    slider.onChanged!(4.0);
    slider.onChangeEnd!(4.0);
    await tester.pumpAndSettle();

    final patchReq = adapter.requests.firstWhere(
      (r) => r.method == 'PATCH' && r.path == '/api/settings',
    );
    expect(patchReq.data, {'min_urgency_to_notify': 4});
  });

  testWidgets('slider change failure shows error snackbar', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = FakeAdapter({
      'GET /api/status': const FakeResponse.fixture('status'),
      'GET /api/settings': const FakeResponse.fixture('settings'),
      'PATCH /api/settings': const FakeResponse({
        'detail': 'Validation error',
      }, status: 422),
    });

    await pumpScreen(
      tester,
      const ControlScreen(),
      overrides: await baseOverrides(adapter: adapter),
    );

    final sliderFinder = find.byType(Slider);
    final slider = tester.widget<Slider>(sliderFinder);
    slider.onChangeEnd!(5.0);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('Scan button starts scan and shows progress and results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final runRunning = {
      'id': 2,
      'trigger': 'api',
      'status': 'running',
      'started_at': '2026-09-28T18:00:00Z',
      'finished_at': null,
      'processed_count': 0,
      'skipped_count': 0,
      'summary': <String, Object?>{},
      'error': null,
    };

    final runDone = {
      'id': 2,
      'trigger': 'api',
      'status': 'succeeded',
      'started_at': '2026-09-28T18:00:00Z',
      'finished_at': '2026-09-28T18:00:05Z',
      'processed_count': 8,
      'skipped_count': 1,
      'summary': <String, Object?>{},
      'error': null,
    };

    final adapter = FakeAdapter({
      'GET /api/status': const FakeResponse.fixture('status'),
      'GET /api/settings': const FakeResponse.fixture('settings'),
      'POST /api/scan': FakeResponse(runRunning, status: 202),
      'GET /api/scans/2': FakeResponse(runDone),
    });

    await pumpScreen(
      tester,
      const ControlScreen(),
      overrides: await baseOverrides(adapter: adapter),
    );

    final scanBtn = find.widgetWithText(FilledButton, 'Scan now');
    expect(scanBtn, findsOneWidget);

    await tester.tap(scanBtn);
    await tester.pumpAndSettle();

    expect(find.text('Last run: 8 processed, 1 skipped'), findsOneWidget);
  });

  testWidgets('Scan button 409 conflict shows "A scan is already running"', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = FakeAdapter({
      'GET /api/status': const FakeResponse.fixture('status'),
      'GET /api/settings': const FakeResponse.fixture('settings'),
      'POST /api/scan': const FakeResponse({
        'detail': 'Scan 1 is already running',
      }, status: 409),
    });

    await pumpScreen(
      tester,
      const ControlScreen(),
      overrides: await baseOverrides(adapter: adapter),
    );

    final scanBtn = find.widgetWithText(FilledButton, 'Scan now');
    await tester.tap(scanBtn);
    await tester.pumpAndSettle();

    expect(find.text('A scan is already running'), findsOneWidget);
  });

  testWidgets(
    'Disconnect button opens dialog, cancel does nothing, confirm clears connection',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final adapter = FakeAdapter({
        'GET /api/status': const FakeResponse.fixture('status'),
        'GET /api/settings': const FakeResponse.fixture('settings'),
      });

      final store = MemoryConnectionStore(testConfig);

      await pumpScreen(
        tester,
        const ControlScreen(),
        overrides: await baseOverrides(adapter: adapter, store: store),
      );

      // Tap Disconnect button
      final disconnectBtn = find.widgetWithText(TextButton, 'Disconnect');
      await tester.tap(disconnectBtn);
      await tester.pumpAndSettle();

      expect(find.text('Disconnect from Sentinel?'), findsOneWidget);
      expect(
        find.text("You'll need the API token to reconnect."),
        findsOneWidget,
      );

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(store.value, isNotNull);

      // Tap Disconnect again and confirm
      await tester.tap(disconnectBtn);
      await tester.pumpAndSettle();

      // Find the filled Disconnect button in the dialog
      final confirmBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Disconnect'),
      );
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(store.value, isNull);
    },
  );

  testWidgets('Appearance controls update preferences', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = FakeAdapter({
      'GET /api/status': const FakeResponse.fixture('status'),
      'GET /api/settings': const FakeResponse.fixture('settings'),
    });

    await pumpScreen(
      tester,
      const ControlScreen(),
      overrides: await baseOverrides(adapter: adapter),
    );

    // Tap Dark mode segment
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    // Toggle Reduce transparency
    final reduceTile = find.widgetWithText(
      SwitchListTile,
      'Reduce transparency',
    );
    await tester.tap(reduceTile);
    await tester.pumpAndSettle();
  });

  testWidgets('Server tap opens ConnectionSheet and saves new connection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = FakeAdapter({
      'GET /api/status': const FakeResponse.fixture('status'),
      'GET /api/settings': const FakeResponse.fixture('settings'),
      'GET /api/health': const FakeResponse.fixture('health'),
    });

    final store = MemoryConnectionStore(testConfig);

    await pumpScreen(
      tester,
      const ControlScreen(),
      overrides: await baseOverrides(adapter: adapter, store: store),
    );

    // Tap Server row
    await tester.tap(find.text('Server'));
    await tester.pumpAndSettle();

    expect(find.text('Server connection'), findsOneWidget);
    expect(find.text('Save & reconnect'), findsOneWidget);

    // Edit token field and tap Save
    final tokenField = find.widgetWithText(TextFormField, 'API token');
    await tester.enterText(tokenField, 'new-token-1234567890abcdef');
    await tester.tap(find.text('Save & reconnect'));
    await tester.pumpAndSettle();

    expect(store.value?.token, 'new-token-1234567890abcdef');
  });

  testWidgets('ConnectionSheet shows error snackbar on connection failure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = FakeAdapter({
      'GET /api/status': const FakeResponse.fixture('status'),
      'GET /api/settings': const FakeResponse.fixture('settings'),
      'GET /api/health': const FakeResponse({
        'detail': 'Server error',
      }, status: 500),
    });

    await pumpScreen(
      tester,
      const ControlScreen(),
      overrides: await baseOverrides(adapter: adapter),
    );

    await tester.tap(find.text('Server'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save & reconnect'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
