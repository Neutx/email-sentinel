import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/network/api_exception.dart';
import 'package:sentinel/data/models.dart';
import 'package:sentinel/data/providers.dart';
import 'package:sentinel/features/control/settings_controller.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  test('initial build loads runtime settings from repository', () async {
    final adapter = FakeAdapter({
      'GET /api/settings': const FakeResponse.fixture('settings'),
    });
    final container = ProviderContainer.test(
      overrides: await testOverrides(adapter: adapter),
    );

    final settings = await container.read(settingsControllerProvider.future);
    expect(settings.dryRun, isFalse);
    expect(settings.autoUnsubscribe, isTrue);
    expect(settings.minUrgencyToNotify, 2);
    expect(settings.protectedDomains, contains('github.com'));
  });

  test('apply(dryRun: true) sends dry_run patch, updates state, and invalidates systemStatus', () async {
    final initialSettings = fixtureMap('settings');
    final updatedSettings = Map<String, Object?>.from(initialSettings)
      ..['dry_run'] = true;

    final adapter = FakeAdapter({
      'GET /api/settings': FakeResponse(initialSettings),
      'PATCH /api/settings': FakeResponse(updatedSettings),
      'GET /api/status': const FakeResponse.fixture('status'),
    });

    final container = ProviderContainer.test(
      overrides: await testOverrides(adapter: adapter),
    );

    // Pre-warm systemStatusProvider
    await container.read(systemStatusProvider.future);

    await container.read(settingsControllerProvider.future);
    await container
        .read(settingsControllerProvider.notifier)
        .apply(const RuntimeSettingsPatch(dryRun: true));

    final state = container.read(settingsControllerProvider).value!;
    expect(state.dryRun, isTrue);

    final patchReq = adapter.requests.firstWhere(
      (r) => r.method == 'PATCH' && r.path == '/api/settings',
    );
    expect(patchReq.data, {'dry_run': true});
  });

  test(
    'apply failure reverts to previous state and rethrows ApiException',
    () async {
      final initialSettings = fixtureMap('settings');
      final adapter = FakeAdapter({
        'GET /api/settings': FakeResponse(initialSettings),
        'PATCH /api/settings': const FakeResponse.fixture(
          'error_422',
          status: 422,
        ),
      });

      final container = ProviderContainer.test(
        overrides: await testOverrides(adapter: adapter),
      );

      await container.read(settingsControllerProvider.future);

      await expectLater(
        container
            .read(settingsControllerProvider.notifier)
            .apply(const RuntimeSettingsPatch(minUrgencyToNotify: 99)),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.validation,
          ),
        ),
      );

      final state = container.read(settingsControllerProvider).value!;
      expect(state.minUrgencyToNotify, 2);
    },
  );
}
