import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'alert_poller.dart';

typedef RegisterPeriodicTaskCallback = Future<void> Function(
  String uniqueName,
  String taskName, {
  Duration? frequency,
  Duration? flexInterval,
  Map<String, dynamic>? inputData,
  Duration? initialDelay,
  Constraints? constraints,
  ExistingPeriodicWorkPolicy? existingWorkPolicy,
  BackoffPolicy? backoffPolicy,
  Duration? backoffPolicyDelay,
  String? tag,
  ForegroundServiceConfig? foregroundServiceConfig,
});

typedef CancelByUniqueNameCallback = Future<void> Function(String uniqueName);

final alertSchedulerProvider = Provider<AlertScheduler>(
  (ref) => AlertScheduler(),
);

class AlertScheduler {
  AlertScheduler({
    RegisterPeriodicTaskCallback? registerPeriodicTask,
    CancelByUniqueNameCallback? cancelByUniqueName,
  }) : _registerPeriodicTask =
           registerPeriodicTask ??
           ((
             uniqueName,
             taskName, {
             frequency,
             flexInterval,
             inputData,
             initialDelay,
             constraints,
             existingWorkPolicy,
             backoffPolicy,
             backoffPolicyDelay,
             tag,
             foregroundServiceConfig,
           }) => Workmanager().registerPeriodicTask(
             uniqueName,
             taskName,
             frequency: frequency,
             flexInterval: flexInterval,
             inputData: inputData,
             initialDelay: initialDelay,
             constraints: constraints,
             existingWorkPolicy: existingWorkPolicy,
             backoffPolicy: backoffPolicy,
             backoffPolicyDelay: backoffPolicyDelay,
             tag: tag,
             foregroundServiceConfig: foregroundServiceConfig,
           )),
       _cancelByUniqueName =
           cancelByUniqueName ??
           ((uniqueName) => Workmanager().cancelByUniqueName(uniqueName));

  final RegisterPeriodicTaskCallback _registerPeriodicTask;
  final CancelByUniqueNameCallback _cancelByUniqueName;

  /// Syncs the WorkManager periodic task registration with the app state.
  /// When background alerts are enabled and the app is connected, registers
  /// a periodic task running every 15 minutes. Otherwise cancels it.
  Future<void> sync({required bool enabled, required bool connected}) async {
    try {
      if (enabled && connected) {
        await _registerPeriodicTask(
          kAlertTask,
          kAlertTask,
          frequency: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      } else {
        await _cancelByUniqueName(kAlertTask);
      }
    } on Object catch (_) {
      // Platform channels may not be implemented on desktop or in tests.
    }
  }
}
