import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'app/app.dart';
import 'core/background/alert_poller.dart';
import 'core/notifications/notification_service.dart';
import 'core/preferences/app_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the status and navigation bars on every Android version
  // (Android 15+ enforces this; older versions need it requested).
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final prefs = await SharedPreferences.getInstance();
  await Workmanager().initialize(callbackDispatcher);
  final notificationService = NotificationService();
  final launchRoute = await notificationService.initialize();

  runApp(
    ProviderScope(
      // Screens own their retry UX (Retry buttons); no silent auto-retries.
      retry: (retryCount, error) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: SentinelApp(launchRoute: launchRoute),
    ),
  );
}
