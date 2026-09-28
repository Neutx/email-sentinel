import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sentinel/core/background/alert_poller.dart';
import 'package:sentinel/data/models.dart';

import '../helpers/fake_api.dart';

class RecordingAlertNotifier implements AlertNotifier {
  final List<List<EmailItem>> emailBatches = [];
  final List<Briefing> briefings = [];

  @override
  Future<void> showEmails(List<EmailItem> emails) async {
    emailBatches.add(emails);
  }

  @override
  Future<void> showBriefing(Briefing briefing) async {
    briefings.add(briefing);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'first run: requests after_id=-1, stores cursor, notifies nothing',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = AlertCursorStore(prefs);
      final notifier = RecordingAlertNotifier();
      final adapter = FakeAdapter({
        'GET /api/alerts': const FakeResponse({
          'items': <Object?>[],
          'cursor': 5,
        }),
        'GET /api/briefings/latest': const FakeResponse.fixture('briefing'),
      });
      final repository = fakeRepository(adapter);

      expect(store.cursor, isNull);
      expect(store.lastBriefingId, isNull);

      final result = await pollAlerts(
        repository: repository,
        store: store,
        notifier: notifier,
      );

      expect(result.notifiedEmails, 0);
      expect(result.notifiedBriefing, false);
      expect(store.cursor, 5);
      expect(store.lastBriefingId, 1);
      expect(notifier.emailBatches, isEmpty);
      expect(notifier.briefings, isEmpty);

      // Verify after_id=-1 was sent
      final alertsReq = adapter.requests.firstWhere(
        (r) => r.path == '/api/alerts',
      );
      expect(alertsReq.queryParameters['after_id'], -1);
    },
  );

  test(
    'next run with cursor 2: notifies emails and stores new cursor',
    () async {
      SharedPreferences.setMockInitialValues({
        'alerts.cursor': 2,
        'alerts.lastBriefingId': 1,
      });
      final prefs = await SharedPreferences.getInstance();
      final store = AlertCursorStore(prefs);
      final notifier = RecordingAlertNotifier();

      final urgentItem = (fixtureMap('alerts')['items'] as List<dynamic>).first;
      final adapter = FakeAdapter({
        'GET /api/alerts': FakeResponse({
          'items': [urgentItem],
          'cursor': 3,
        }),
        'GET /api/briefings/latest': const FakeResponse.fixture('briefing'),
      });
      final repository = fakeRepository(adapter);

      final result = await pollAlerts(
        repository: repository,
        store: store,
        notifier: notifier,
      );

      expect(result.notifiedEmails, 1);
      expect(result.notifiedBriefing, false);
      expect(store.cursor, 3);
      expect(notifier.emailBatches.length, 1);
      expect(notifier.emailBatches.first.first.id, 1);
      expect(notifier.briefings, isEmpty);

      final alertsReq = adapter.requests.firstWhere(
        (r) => r.path == '/api/alerts',
      );
      expect(alertsReq.queryParameters['after_id'], 2);
    },
  );

  test('newer briefing id triggers showBriefing, same id does not', () async {
    SharedPreferences.setMockInitialValues({
      'alerts.cursor': 10,
      'alerts.lastBriefingId': 1,
    });
    final prefs = await SharedPreferences.getInstance();
    final store = AlertCursorStore(prefs);
    final notifier = RecordingAlertNotifier();

    final briefingJson = Map<String, dynamic>.from(fixtureMap('briefing'));
    briefingJson['id'] = 2;

    final adapter = FakeAdapter({
      'GET /api/alerts': const FakeResponse({
        'items': <Object?>[],
        'cursor': 10,
      }),
      'GET /api/briefings/latest': FakeResponse(briefingJson),
    });
    final repository = fakeRepository(adapter);

    final result = await pollAlerts(
      repository: repository,
      store: store,
      notifier: notifier,
    );

    expect(result.notifiedEmails, 0);
    expect(result.notifiedBriefing, true);
    expect(store.lastBriefingId, 2);
    expect(notifier.briefings.length, 1);
    expect(notifier.briefings.first.id, 2);

    // Run again with same id
    final result2 = await pollAlerts(
      repository: repository,
      store: store,
      notifier: notifier,
    );
    expect(result2.notifiedBriefing, false);
    expect(notifier.briefings.length, 1);
  });

  test(
    'repository offline rethrows nothing, returns (0, false), keeps cursor',
    () async {
      SharedPreferences.setMockInitialValues({
        'alerts.cursor': 5,
        'alerts.lastBriefingId': 1,
      });
      final prefs = await SharedPreferences.getInstance();
      final store = AlertCursorStore(prefs);
      final notifier = RecordingAlertNotifier();
      final adapter = FakeAdapter({}, offline: true);
      final repository = fakeRepository(adapter);

      final result = await pollAlerts(
        repository: repository,
        store: store,
        notifier: notifier,
      );

      expect(result.notifiedEmails, 0);
      expect(result.notifiedBriefing, false);
      expect(store.cursor, 5);
      expect(store.lastBriefingId, 1);
      expect(notifier.emailBatches, isEmpty);
      expect(notifier.briefings, isEmpty);
    },
  );
}
