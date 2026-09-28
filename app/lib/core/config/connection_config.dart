import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Default server: this PC's Tailscale MagicDNS name (docs/api/API.md).
const kDefaultServerUrl = 'http://desktop-h4gp2e6.tail87425d.ts.net:8765';

@immutable
class ConnectionConfig {
  const ConnectionConfig({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  /// Trims, adds http:// when no scheme is given, drops trailing slashes.
  static String normalizeUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;
    if (!url.contains('://')) url = 'http://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Returns an error message, or null when [input] is a usable server URL.
  static String? validateUrl(String input) {
    final uri = Uri.tryParse(normalizeUrl(input));
    if (input.trim().isEmpty) return 'Enter the server URL.';
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return 'Use a URL like http://my-pc.tailnet.ts.net:8765';
    }
    return null;
  }

  /// Returns an error message, or null when [input] looks like a valid token.
  static String? validateToken(String input) {
    if (input.trim().isEmpty) return 'Paste the API token.';
    if (input.trim().length < 24) return 'That token is too short.';
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ConnectionConfig &&
      other.baseUrl == baseUrl &&
      other.token == token;

  @override
  int get hashCode => Object.hash(baseUrl, token);
}

/// Persists the connection in Android Keystore-backed secure storage.
class ConnectionStore {
  ConnectionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _urlKey = 'sentinel.baseUrl';
  static const _tokenKey = 'sentinel.token';

  final FlutterSecureStorage _storage;

  Future<ConnectionConfig?> read() async {
    final url = await _storage.read(key: _urlKey);
    final token = await _storage.read(key: _tokenKey);
    if (url == null || token == null) return null;
    return ConnectionConfig(baseUrl: url, token: token);
  }

  Future<void> save(ConnectionConfig config) async {
    await _storage.write(key: _urlKey, value: config.baseUrl);
    await _storage.write(key: _tokenKey, value: config.token);
  }

  Future<void> clear() async {
    await _storage.delete(key: _urlKey);
    await _storage.delete(key: _tokenKey);
  }
}
