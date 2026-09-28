import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../data/models.dart';
import '../../data/sentinel_repository.dart';
import '../config/connection_config.dart';
import '../network/api_client.dart';
import '../notifications/notification_service.dart';

const kAlertTask = 'sentinel.pollAlerts';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final config = await ConnectionStore().read();
      if (config == null) return true;
      final prefs = await SharedPreferences.getInstance();
      final repository = SentinelRepository(ApiClient(config));
      final store = AlertCursorStore(prefs);
      final notifier = NotificationService();
      await notifier.initialize();
      await pollAlerts(
        repository: repository,
        store: store,
        notifier: notifier,
      );
      return true;
    } catch (_) {
      return true;
    }
  });
}

/// Storage of the alert cursor + last seen briefing id (SharedPreferences keys
/// 'alerts.cursor' and 'alerts.lastBriefingId').
class AlertCursorStore {
  AlertCursorStore(this._prefs);
  final SharedPreferences _prefs;

  int? get cursor => _prefs.getInt('alerts.cursor');
  Future<void> setCursor(int value) => _prefs.setInt('alerts.cursor', value);

  int? get lastBriefingId => _prefs.getInt('alerts.lastBriefingId');
  Future<void> setLastBriefingId(int value) =>
      _prefs.setInt('alerts.lastBriefingId', value);
}

abstract interface class AlertNotifier {
  Future<void> showEmails(
    List<EmailItem> emails,
  ); // ≥ 4 → one summary notification
  Future<void> showBriefing(Briefing briefing);
}

class PollResult {
  const PollResult({
    required this.notifiedEmails,
    required this.notifiedBriefing,
  });

  final int notifiedEmails;
  final bool notifiedBriefing;
}

/// One poll: first run (cursor == null) only initialises the cursor via
/// alerts(afterId: -1) and remembers the current briefing id without notifying.
Future<PollResult> pollAlerts({
  required SentinelRepository repository,
  required AlertCursorStore store,
  required AlertNotifier notifier,
}) async {
  try {
    final currentCursor = store.cursor;
    if (currentCursor == null) {
      final response = await repository.alerts(afterId: -1);
      await store.setCursor(response.cursor);
      final briefing = await repository.latestBriefing();
      if (briefing != null) {
        await store.setLastBriefingId(briefing.id);
      }
      return const PollResult(notifiedEmails: 0, notifiedBriefing: false);
    }

    final response = await repository.alerts(afterId: currentCursor);
    int notifiedCount = 0;
    if (response.items.isNotEmpty) {
      await notifier.showEmails(response.items);
      notifiedCount = response.items.length;
    }
    await store.setCursor(response.cursor);

    final briefing = await repository.latestBriefing();
    bool notifiedBriefing = false;
    if (briefing != null) {
      final lastId = store.lastBriefingId;
      if (lastId == null || briefing.id > lastId) {
        await notifier.showBriefing(briefing);
        await store.setLastBriefingId(briefing.id);
        notifiedBriefing = true;
      }
    }

    return PollResult(
      notifiedEmails: notifiedCount,
      notifiedBriefing: notifiedBriefing,
    );
  } catch (_) {
    return const PollResult(notifiedEmails: 0, notifiedBriefing: false);
  }
}
