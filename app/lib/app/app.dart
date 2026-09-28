import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/background/alert_scheduler.dart';
import '../core/notifications/notification_service.dart';
import '../core/preferences/app_preferences.dart';
import '../core/providers.dart';
import '../core/theme/app_theme.dart';
import 'router.dart';

class SentinelApp extends ConsumerStatefulWidget {
  const SentinelApp({super.key, this.launchRoute});

  final String? launchRoute;

  @override
  ConsumerState<SentinelApp> createState() => _SentinelAppState();
}

class _SentinelAppState extends ConsumerState<SentinelApp> {
  bool _coldStartNavigated = false;

  void _checkColdStart() {
    if (_coldStartNavigated || widget.launchRoute == null) return;
    final conn = ref.read(connectionProvider);
    if (conn.hasValue && conn.value != null) {
      _coldStartNavigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(routerProvider).go(widget.launchRoute!);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Warm notification taps: route through routerProvider.
    ref.read(notificationServiceProvider).setOnTap((route) {
      ref.read(routerProvider).go(route);
    });

    _checkColdStart();
  }

  @override
  Widget build(BuildContext context) {
    // Keep AlertScheduler in sync when connection or backgroundAlerts preference changes.
    ref.listen(connectionProvider, (_, next) {
      final connected = next.value != null;
      final alerts = ref.read(appPreferencesProvider).backgroundAlerts;
      ref
          .read(alertSchedulerProvider)
          .sync(enabled: alerts, connected: connected);

      if (connected && widget.launchRoute != null && !_coldStartNavigated) {
        _coldStartNavigated = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(routerProvider).go(widget.launchRoute!);
          }
        });
      }
    });

    ref.listen(appPreferencesProvider.select((p) => p.backgroundAlerts), (
      _,
      alerts,
    ) {
      final connected = ref.read(connectionProvider).value != null;
      ref
          .read(alertSchedulerProvider)
          .sync(enabled: alerts, connected: connected);
    });

    return MaterialApp.router(
      title: 'Sentinel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(appPreferencesProvider).themeMode,
      routerConfig: ref.watch(routerProvider),
      // Screens without an AppBar (Connect, splash) still get readable
      // status bar icons.
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.overlayFor(Theme.of(context).brightness),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
