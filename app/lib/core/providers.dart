import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sentinel_repository.dart';
import 'config/connection_config.dart';
import 'network/api_client.dart';

final connectionStoreProvider = Provider<ConnectionStore>(
  (ref) => ConnectionStore(),
);

/// Seam for tests: swap in an ApiClient backed by a fake Dio adapter.
final apiClientFactoryProvider = Provider<ApiClient Function(ConnectionConfig)>(
  (ref) => ApiClient.new,
);

/// The saved server connection; null = not connected (router shows Connect).
class ConnectionController extends AsyncNotifier<ConnectionConfig?> {
  @override
  Future<ConnectionConfig?> build() => ref.read(connectionStoreProvider).read();

  /// Verifies reachability and the token, then persists the connection.
  /// Throws [ApiException] on failure and leaves the state unchanged.
  Future<void> connect(String url, String token) async {
    final config = ConnectionConfig(
      baseUrl: ConnectionConfig.normalizeUrl(url),
      token: token.trim(),
    );
    final repo = SentinelRepository(ref.read(apiClientFactoryProvider)(config));
    await repo.health();
    await repo.status(); // 401 here means the token is wrong
    await ref.read(connectionStoreProvider).save(config);
    state = AsyncData(config);
  }

  Future<void> disconnect() async {
    await ref.read(connectionStoreProvider).clear();
    state = const AsyncData(null);
  }
}

final connectionProvider =
    AsyncNotifierProvider<ConnectionController, ConnectionConfig?>(
      ConnectionController.new,
    );

/// Repository for the current connection. Only read it from screens that
/// the router shows while connected.
final repositoryProvider = Provider<SentinelRepository>((ref) {
  final config = ref.watch(connectionProvider).value;
  if (config == null) {
    throw StateError('repositoryProvider read while not connected');
  }
  return SentinelRepository(ref.watch(apiClientFactoryProvider)(config));
});
