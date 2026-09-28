import 'package:dio/dio.dart';

import '../config/connection_config.dart';
import 'api_exception.dart';

/// Thin Dio wrapper: base URL, bearer token, timeouts, error mapping.
class ApiClient {
  ApiClient(ConnectionConfig config, {Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      baseUrl: config.baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.json,
      headers: {
        'Authorization': 'Bearer ${config.token}',
        'Accept': 'application/json',
      },
    );
  }

  final Dio _dio;

  Future<Object?> get(String path, {Map<String, Object?>? query}) =>
      _send(() => _dio.get<Object?>(path, queryParameters: query));

  Future<Object?> post(String path, {Object? body}) =>
      _send(() => _dio.post<Object?>(path, data: body ?? const {}));

  Future<Object?> patch(String path, {Object? body}) =>
      _send(() => _dio.patch<Object?>(path, data: body));

  Future<Object?> _send(Future<Response<Object?>> Function() call) async {
    try {
      final response = await call();
      return response.data;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
