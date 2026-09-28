import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../data/models.dart';
import '../background/alert_poller.dart';

typedef NotificationTapHandler = void Function(String route);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

class NotificationService implements AlertNotifier {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  NotificationTapHandler? _onTap;

  void setOnTap(NotificationTapHandler onTap) {
    _onTap = onTap;
  }

  /// Initializes notification channels and handlers. Returns the launch route
  /// if the app was opened from a notification.
  Future<String?> initialize({NotificationTapHandler? onTap}) async {
    if (onTap != null) _onTap = onTap;

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_sentinel'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload ?? Routes.inbox;
        _onTap?.call(payload);
      },
    );

    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      return details?.notificationResponse?.payload ?? Routes.inbox;
    }
    return null;
  }

  /// Request POST_NOTIFICATIONS permission on Android 13+.
  Future<bool?> requestPermission() async {
    try {
      return await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> showEmails(List<EmailItem> emails) async {
    if (emails.isEmpty) return;

    if (summaryNeeded(emails.length)) {
      final summaryLines = emails
          .take(5)
          .map((e) => '${e.senderName}: ${e.subject}')
          .toList();
      final hasUrgent = emails.any(
        (e) => e.category == EmailCategory.urgentActionable,
      );
      final channel = hasUrgent ? 'urgent' : 'projects';
      final channelName = hasUrgent ? 'Urgent email' : 'Project updates';
      final importance = hasUrgent
          ? Importance.high
          : Importance.defaultImportance;
      final priority = hasUrgent ? Priority.high : Priority.defaultPriority;

      await _plugin.show(
        id: 0,
        title: '${emails.length} new alerts',
        body: '${emails.length} new emails need attention',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel,
            channelName,
            importance: importance,
            priority: priority,
            groupKey: 'sentinel.emails',
            styleInformation: InboxStyleInformation(
              summaryLines,
              contentTitle: '${emails.length} new alerts',
              summaryText: '${emails.length} new alerts',
            ),
          ),
        ),
        payload: Routes.inbox,
      );
      return;
    }

    for (final email in emails) {
      final channel = channelFor(email);
      final isUrgent = channel == 'urgent';
      await _plugin.show(
        id: email.id,
        title: emailTitle(email),
        body: emailBody(email),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel,
            isUrgent ? 'Urgent email' : 'Project updates',
            importance: isUrgent
                ? Importance.high
                : Importance.defaultImportance,
            priority: isUrgent ? Priority.high : Priority.defaultPriority,
            groupKey: 'sentinel.emails',
          ),
        ),
        payload: payloadFor(email),
      );
    }
  }

  @override
  Future<void> showBriefing(Briefing briefing) async {
    await _plugin.show(
      id: 1000000 + briefing.id,
      title: briefingTitle(briefing),
      body: briefing.summary,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'briefings',
          'Briefings',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      payload: Routes.briefing,
    );
  }

  // Pure helpers (unit tested without platform channels)

  static String channelFor(EmailItem email) =>
      email.category == EmailCategory.urgentActionable ? 'urgent' : 'projects';

  static String payloadFor(EmailItem email) => Routes.email(email.id);

  static bool summaryNeeded(int count) => count >= 4;

  static String briefingTitle(Briefing briefing) =>
      'Your ${briefing.periodLabel.toLowerCase()} briefing is ready';

  static String emailTitle(EmailItem email) =>
      '${email.category.label} · ${email.senderName}';

  static String emailBody(EmailItem email) =>
      email.summary.isNotEmpty ? email.summary : email.subject;
}
