import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

extension RuntimeSettingsMerge on RuntimeSettings {
  RuntimeSettings merge(RuntimeSettingsPatch patch) {
    return RuntimeSettings(
      dryRun: patch.dryRun ?? dryRun,
      autoUnsubscribe: patch.autoUnsubscribe ?? autoUnsubscribe,
      autoDeleteMarketing: patch.autoDeleteMarketing ?? autoDeleteMarketing,
      autoMarkReadProcessed:
          patch.autoMarkReadProcessed ?? autoMarkReadProcessed,
      notifyOnProjectUpdates:
          patch.notifyOnProjectUpdates ?? notifyOnProjectUpdates,
      notifyOnUrgent: patch.notifyOnUrgent ?? notifyOnUrgent,
      minUrgencyToNotify: patch.minUrgencyToNotify ?? minUrgencyToNotify,
      protectedDomains: patch.protectedDomains ?? protectedDomains,
      projectKeywords: patch.projectKeywords ?? projectKeywords,
    );
  }
}

class SettingsController extends AsyncNotifier<RuntimeSettings> {
  @override
  Future<RuntimeSettings> build() async {
    await ref.watch(connectionProvider.future);
    return ref.watch(repositoryProvider).settings();
  }

  Future<void> apply(RuntimeSettingsPatch patch) async {
    final previous = state.value;
    if (previous != null) {
      state = AsyncData(previous.merge(patch));
    }
    try {
      final updated = await ref.read(repositoryProvider).updateSettings(patch);
      state = AsyncData(updated);
      ref.invalidate(systemStatusProvider);
    } catch (e) {
      if (previous != null) {
        state = AsyncData(previous);
      }
      rethrow;
    }
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, RuntimeSettings>(
      SettingsController.new,
    );
