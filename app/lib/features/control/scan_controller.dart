import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models.dart';

class ScanState {
  const ScanState({this.run, this.error, this.busy = false});
  final ScanRun? run; // latest known run (running or finished)
  final Object? error; // ApiException from start/poll
  final bool busy; // true while starting or polling
}

class ScanController extends Notifier<ScanState> {
  /// Poll interval; tests override via [pollInterval].
  static Duration pollInterval = const Duration(seconds: 2);

  @override
  ScanState build() => const ScanState();

  Future<void> start({int limit = 20}) async {
    state = ScanState(run: state.run, busy: true);
    try {
      await ref.read(connectionProvider.future);
      final repo = ref.read(repositoryProvider);
      var run = await repo.startScan(limit: limit);
      if (!ref.mounted) return;
      state = ScanState(run: run, busy: run.isRunning);
      if (!run.isRunning) return;

      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (run.isRunning && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(pollInterval);
        if (!ref.mounted) return;
        run = await repo.scan(run.id);
        if (!ref.mounted) return;
        state = ScanState(run: run, busy: run.isRunning);
        if (!run.isRunning) break;
      }
    } catch (e) {
      if (!ref.mounted) return;
      state = ScanState(run: state.run, error: e, busy: false);
    }
  }
}

final scanControllerProvider = NotifierProvider<ScanController, ScanState>(
  ScanController.new,
);
