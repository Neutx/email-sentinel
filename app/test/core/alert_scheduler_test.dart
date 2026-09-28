import 'package:flutter_test/flutter_test.dart';
import 'package:sentinel/core/background/alert_poller.dart';
import 'package:sentinel/core/background/alert_scheduler.dart';
import 'package:workmanager/workmanager.dart';

void main() {
  group('AlertScheduler', () {
    test('sync registers periodic task when enabled and connected', () async {
      String? registeredUniqueName;
      String? registeredTaskName;
      Duration? registeredFrequency;
      Constraints? registeredConstraints;
      ExistingPeriodicWorkPolicy? registeredPolicy;
      String? cancelledUniqueName;

      final scheduler = AlertScheduler(
        registerPeriodicTask:
            (
              uniqueName,
              taskName, {
              frequency,
              constraints,
              existingWorkPolicy,
              backoffPolicy,
              backoffPolicyDelay,
              flexInterval,
              foregroundServiceConfig,
              initialDelay,
              inputData,
              tag,
            }) async {
              registeredUniqueName = uniqueName;
              registeredTaskName = taskName;
              registeredFrequency = frequency;
              registeredConstraints = constraints;
              registeredPolicy = existingWorkPolicy;
            },
        cancelByUniqueName: (uniqueName) async {
          cancelledUniqueName = uniqueName;
        },
      );

      await scheduler.sync(enabled: true, connected: true);

      expect(registeredUniqueName, kAlertTask);
      expect(registeredTaskName, kAlertTask);
      expect(registeredFrequency, const Duration(minutes: 15));
      expect(registeredConstraints?.networkType, NetworkType.connected);
      expect(registeredPolicy, ExistingPeriodicWorkPolicy.keep);
      expect(cancelledUniqueName, isNull);
    });

    test('sync cancels task when disabled or disconnected', () async {
      final cancelledList = <String>[];
      int registeredCount = 0;

      final scheduler = AlertScheduler(
        registerPeriodicTask:
            (
              uniqueName,
              taskName, {
              frequency,
              constraints,
              existingWorkPolicy,
              backoffPolicy,
              backoffPolicyDelay,
              flexInterval,
              foregroundServiceConfig,
              initialDelay,
              inputData,
              tag,
            }) async {
              registeredCount++;
            },
        cancelByUniqueName: (uniqueName) async {
          cancelledList.add(uniqueName);
        },
      );

      await scheduler.sync(enabled: false, connected: true);
      expect(cancelledList, [kAlertTask]);
      expect(registeredCount, 0);

      await scheduler.sync(enabled: true, connected: false);
      expect(cancelledList, [kAlertTask, kAlertTask]);
      expect(registeredCount, 0);

      await scheduler.sync(enabled: false, connected: false);
      expect(cancelledList, [kAlertTask, kAlertTask, kAlertTask]);
      expect(registeredCount, 0);
    });
  });
}
