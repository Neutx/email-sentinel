import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/data/models.dart';
import 'package:sentinel/data/providers.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump_app.dart';

void main() {
  Future<ProviderContainer> containerWith(FakeAdapter adapter) async =>
      ProviderContainer.test(overrides: await testOverrides(adapter: adapter));

  test(
    'latestBriefingProvider returns briefing when available and null on 404',
    () async {
      final okAdapter = FakeAdapter({
        'GET /api/briefings/latest': const FakeResponse.fixture('briefing'),
      });
      final c1 = await containerWith(okAdapter);
      final briefing = await c1.read(latestBriefingProvider.future);
      expect(briefing, isNotNull);
      expect(briefing!.title, 'Morning briefing');
      expect(briefing.id, 1);

      final notFoundAdapter = FakeAdapter({
        'GET /api/briefings/latest': const FakeResponse({
          'detail': 'No briefing yet',
        }, status: 404),
      });
      final c2 = await containerWith(notFoundAdapter);
      final emptyBriefing = await c2.read(latestBriefingProvider.future);
      expect(emptyBriefing, isNull);
    },
  );

  test('projectUpdatesProvider sends project query param', () async {
    final adapter = FakeAdapter({
      'GET /api/project-updates': const FakeResponse.fixture('project_updates'),
    });
    final c = await containerWith(adapter);
    final updates = await c.read(
      projectUpdatesProvider('Murphy-Labs/core').future,
    );
    expect(updates, hasLength(2));
    expect(
      adapter.requests.last.queryParameters['project'],
      'Murphy-Labs/core',
    );
  });

  test('systemStatusProvider fetches system status', () async {
    final adapter = FakeAdapter({
      'GET /api/status': const FakeResponse.fixture('status'),
    });
    final c = await containerWith(adapter);
    final status = await c.read(systemStatusProvider.future);
    expect(status.mailbox, 'ow***@example.com');
    expect(status.version, '0.2.0');
  });

  test('statsProvider fetches stats', () async {
    final adapter = FakeAdapter({
      'GET /api/stats': const FakeResponse.fixture('stats'),
    });
    final c = await containerWith(adapter);
    final stats = await c.read(statsProvider.future);
    expect(stats.totalEmailsProcessed, 6);
    expect(stats.openActionsCount, 2);
  });

  test('briefingsProvider fetches briefings list', () async {
    final adapter = FakeAdapter({
      'GET /api/briefings': const FakeResponse.fixture('briefings'),
    });
    final c = await containerWith(adapter);
    final list = await c.read(briefingsProvider.future);
    expect(list, hasLength(1));
    expect(list.first.title, 'Morning briefing');
  });

  test('needsYouProvider fetches urgent emails with limit 5', () async {
    final adapter = FakeAdapter({
      'GET /api/emails': const FakeResponse.fixture('email_page'),
    });
    final c = await containerWith(adapter);
    final items = await c.read(needsYouProvider.future);
    expect(items, isNotEmpty);
    expect(adapter.requests.last.queryParameters['category'], [
      'urgent_actionable',
    ]);
    expect(adapter.requests.last.queryParameters['limit'], 5);
  });

  test('projectsProvider fetches project summaries', () async {
    final adapter = FakeAdapter({
      'GET /api/projects': const FakeResponse.fixture('projects'),
    });
    final c = await containerWith(adapter);
    final projects = await c.read(projectsProvider.future);
    expect(projects, hasLength(1));
    expect(projects.first.name, 'Murphy-Labs/core');
  });

  test('unsubscribesProvider fetches unsubscribe logs', () async {
    final adapter = FakeAdapter({
      'GET /api/unsubscribes': const FakeResponse.fixture('unsubscribes'),
    });
    final c = await containerWith(adapter);
    final list = await c.read(unsubscribesProvider.future);
    expect(list, hasLength(1));
    expect(list.first.senderEmail, 'deals@shop.com');
  });

  test('scansProvider fetches scan runs', () async {
    final adapter = FakeAdapter({
      'GET /api/scans': const FakeResponse.fixture('scans'),
    });
    final c = await containerWith(adapter);
    final list = await c.read(scansProvider.future);
    expect(list, hasLength(1));
    expect(list.first.status, ScanStatus.succeeded);
  });
}
