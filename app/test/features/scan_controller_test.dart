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
      'POST /api/scan': const FakeResponse({
        'detail': 'Scan 3 is already running',
      }, status: 409),
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
