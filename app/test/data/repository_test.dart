import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/network/api_exception.dart';
import 'package:sentinel/data/models.dart';

import '../helpers/fake_api.dart';

void main() {
  test('sends the bearer token and filters emails', () async {
    final adapter = FakeAdapter({
      'GET /api/emails': const FakeResponse.fixture('email_page'),
    });
    final page = await fakeRepository(adapter).emails(
      categories: {EmailCategory.urgentActionable, EmailCategory.projectUpdate},
      beforeId: 10,
      limit: 4,
    );
    expect(page.items, hasLength(4));
    final req = adapter.requests.single;
    expect(req.headers['Authorization'], 'Bearer ${testConfig.token}');
    expect(
      req.queryParameters['category'],
      containsAll(['urgent_actionable', 'project_update']),
    );
    expect(req.queryParameters['before_id'], 10);
    expect(req.queryParameters['include_done'], false);
  });

  test('actions post the documented bodies', () async {
    final adapter = FakeAdapter({
      'POST /api/emails/1/done': const FakeResponse.fixture('action_result'),
      'POST /api/emails/1/reclassify': const FakeResponse.fixture(
        'action_result',
      ),
      'PATCH /api/settings': const FakeResponse.fixture('settings'),
    });
    final repo = fakeRepository(adapter);
    await repo.setDone(1, done: true);
    await repo.reclassify(1, EmailCategory.projectUpdate);
    await repo.updateSettings(const RuntimeSettingsPatch(dryRun: true));
    expect(adapter.requests[0].data, {'done': true});
    expect(adapter.requests[1].data, {'category': 'project_update'});
    expect(adapter.requests[2].data, {'dry_run': true});
  });

  test('latestBriefing returns null on 404', () async {
    final adapter = FakeAdapter({
      'GET /api/briefings/latest': const FakeResponse({
        'detail': 'No briefing yet',
      }, status: 404),
    });
    expect(await fakeRepository(adapter).latestBriefing(), isNull);
  });

  test('maps HTTP and network failures to ApiException kinds', () async {
    final unauthorized = FakeAdapter({
      'GET /api/status': const FakeResponse({'detail': 'nope'}, status: 401),
    });
    await expectLater(
      fakeRepository(unauthorized).status(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.kind,
          'kind',
          ApiErrorKind.unauthorized,
        ),
      ),
    );

    final invalid = FakeAdapter({
      'PATCH /api/settings': const FakeResponse.fixture(
        'error_422',
        status: 422,
      ),
    });
    await expectLater(
      fakeRepository(invalid)
          .updateSettings(const RuntimeSettingsPatch(minUrgencyToNotify: 9)),
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.validation)
            .having((e) => e.userMessage, 'message', contains('less than')),
      ),
    );

    await expectLater(
      fakeRepository(FakeAdapter({}, offline: true)).stats(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.offline)
            .having((e) => e.userMessage, 'message', contains('Tailscale')),
      ),
    );
  });
}
