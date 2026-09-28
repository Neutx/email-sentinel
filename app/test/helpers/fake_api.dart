import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sentinel/core/config/connection_config.dart';
import 'package:sentinel/core/network/api_client.dart';
import 'package:sentinel/data/models.dart';
import 'package:sentinel/data/sentinel_repository.dart';

/// Loads `test/fixtures/NAME.json` (generated from the real backend by
/// scripts/export_app_fixtures.py).
Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

Json fixtureMap(String name) => fixture(name)! as Json;

/// A canned HTTP response.
class FakeResponse {
  const FakeResponse(this.body, {this.status = 200});
  const FakeResponse.fixture(String name, {this.status = 200}) : body = name;
  final Object? body;
  final int status;
}

/// Dio adapter that records requests and answers from a route table keyed by
/// "METHOD /path". A value of type String is treated as a fixture name.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.routes, {this.offline = false});

  final Map<String, FakeResponse> routes;
  final bool offline;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final key = '${options.method} ${options.path}';
    final route = routes[key];
    if (route == null) {
      return ResponseBody.fromString(
        jsonEncode({'detail': 'Not Found'}),
        404,
        headers: _json,
      );
    }
    final body = route.body is String
        ? fixture(route.body! as String)
        : route.body;
    return ResponseBody.fromString(
      jsonEncode(body),
      route.status,
      headers: _json,
    );
  }

  static final _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  @override
  void close({bool force = false}) {}
}

const testConfig = ConnectionConfig(
  baseUrl: 'http://sentinel.test:8765',
  token: 'test-token-0123456789abcdef',
);

ApiClient fakeClient(
  FakeAdapter adapter, [
  ConnectionConfig config = testConfig,
]) => ApiClient(config, dio: Dio()..httpClientAdapter = adapter);

SentinelRepository fakeRepository(FakeAdapter adapter) =>
    SentinelRepository(fakeClient(adapter));
