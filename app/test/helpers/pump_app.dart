import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/background/alert_scheduler.dart';
import 'package:sentinel/core/config/connection_config.dart';
import 'package:sentinel/core/preferences/app_preferences.dart';
import 'package:sentinel/core/providers.dart';
import 'package:sentinel/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_api.dart';

/// In-memory replacement for the secure-storage backed store.
class MemoryConnectionStore extends ConnectionStore {
  MemoryConnectionStore([this.value]);
  ConnectionConfig? value;

  @override
  Future<ConnectionConfig?> read() async => value;

  @override
  Future<void> save(ConnectionConfig config) async => value = config;

  @override
  Future<void> clear() async => value = null;
}

/// Standard overrides: fake HTTP, in-memory connection, mock prefs.
Future<List<Override>> testOverrides({
  required FakeAdapter adapter,
  ConnectionConfig? connection = testConfig,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(sharedPrefs),
    connectionStoreProvider.overrideWithValue(
      MemoryConnectionStore(connection),
    ),
    apiClientFactoryProvider.overrideWithValue(
      (config) => fakeClient(adapter, config),
    ),
    alertSchedulerProvider.overrideWithValue(
      AlertScheduler(
        registerPeriodicTask: (
          uniqueName,
          taskName, {
          backoffPolicy,
          backoffPolicyDelay,
          constraints,
          existingWorkPolicy,
          flexInterval,
          foregroundServiceConfig,
          frequency,
          initialDelay,
          inputData,
          tag,
        }) async {},
        cancelByUniqueName: (uniqueName) async {},
      ),
    ),
  ];
}

/// Pumps [child] inside ProviderScope + themed MaterialApp.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  required List<Override> overrides,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
