import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/preferences/app_preferences.dart';
import 'package:sentinel/core/providers.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

final _ok = {
  'GET /api/health': const FakeResponse.fixture('health'),
  'GET /api/status': const FakeResponse.fixture('status'),
};

void main() {
  test('connecting to a different server resets the alert cursor', () async {
    final container = ProviderContainer.test(
      overrides: await testOverrides(
        adapter: FakeAdapter(_ok),
        prefs: {'alerts.cursor': 700, 'alerts.lastBriefingId': 9},
      ),
    );
    await container.read(connectionProvider.future);
    await container
        .read(connectionProvider.notifier)
        .connect('http://other-host:8765', 'another-token-0123456789abcdef');
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getInt('alerts.cursor'), isNull);
    expect(prefs.getInt('alerts.lastBriefingId'), isNull);
  });

  test('reconnecting to the same server keeps the cursor', () async {
    final container = ProviderContainer.test(
      overrides: await testOverrides(
        adapter: FakeAdapter(_ok),
        prefs: {'alerts.cursor': 700},
      ),
    );
    await container.read(connectionProvider.future);
    await container
        .read(connectionProvider.notifier)
        .connect(testConfig.baseUrl, 'rotated-token-0123456789abcdef');
    expect(
      container.read(sharedPreferencesProvider).getInt('alerts.cursor'),
      700,
    );
  });
}
