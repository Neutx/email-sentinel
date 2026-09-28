import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/data/models.dart';
import 'package:sentinel/features/inbox/inbox_controller.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<ProviderContainer> containerWith(FakeAdapter adapter) async =>
      ProviderContainer.test(overrides: await testOverrides(adapter: adapter));

  test('loads the first page and pages with before_id', () async {
    final adapter = FakeAdapter({
      'GET /api/emails': const FakeResponse.fixture('email_page'),
    });
    final c = await containerWith(adapter);
    final first = await c.read(inboxControllerProvider.future);
    expect(first.items, hasLength(4));
    await c.read(inboxControllerProvider.notifier).loadMore();
    expect(
      adapter.requests.last.queryParameters['before_id'],
      first.nextCursor,
    );
  });

  test('filter change refetches with the category', () async {
    final adapter = FakeAdapter({
      'GET /api/emails': const FakeResponse.fixture('email_page'),
    });
    final c = await containerWith(adapter);
    await c.read(inboxControllerProvider.future);
    c
        .read(inboxFilterProvider.notifier)
        .setCategory(EmailCategory.urgentActionable);
    await c.read(inboxControllerProvider.future);
    expect(adapter.requests.last.queryParameters['category'], [
      'urgent_actionable',
    ]);
  });

  test('done is optimistic and reverts on failure', () async {
    final ok = FakeAdapter({
      'GET /api/emails': const FakeResponse.fixture('email_page'),
      'POST /api/emails/5/done': const FakeResponse.fixture('action_result'),
    });
    final c = await containerWith(ok);
    final page = await c.read(inboxControllerProvider.future);
    final email = page.items.firstWhere((e) => e.id == 5);
    await c.read(inboxControllerProvider.notifier).setDone(email, true);
    expect(
      c.read(inboxControllerProvider).value!.items.map((e) => e.id),
      isNot(contains(5)),
    );

    final failing = FakeAdapter({
      'GET /api/emails': const FakeResponse.fixture('email_page'),
    }); // POST not routed -> 404 -> ApiException
    final c2 = await containerWith(failing);
    final page2 = await c2.read(inboxControllerProvider.future);
    final email2 = page2.items.firstWhere((e) => e.id == 5);
    await expectLater(
      c2.read(inboxControllerProvider.notifier).setDone(email2, true),
      throwsA(anything),
    );
    expect(
      c2.read(inboxControllerProvider).value!.items.map((e) => e.id),
      contains(5),
    );
  });
}
