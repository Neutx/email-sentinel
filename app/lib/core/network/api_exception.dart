import 'package:dio/dio.dart';

enum ApiErrorKind {
  offline,
  unauthorized,
  notFound,
  conflict,
  validation,
  server,
  unknown,
}

/// Every network failure is converted into this type (see docs/api/API.md
/// "Error model"). UI code shows [userMessage]; never raw exception text.
class ApiException implements Exception {
  const ApiException(this.kind, this.detail, {this.statusCode});

  factory ApiException.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const ApiException(ApiErrorKind.offline, '');
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode ?? 0;
        final detail = _detail(e.response?.data);
        final kind = switch (status) {
          401 || 403 => ApiErrorKind.unauthorized,
          404 => ApiErrorKind.notFound,
          409 => ApiErrorKind.conflict,
          422 => ApiErrorKind.validation,
          >= 500 => ApiErrorKind.server,
          _ => ApiErrorKind.unknown,
        };
        return ApiException(kind, detail, statusCode: status);
      case DioExceptionType.badCertificate:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return ApiException(ApiErrorKind.unknown, e.message ?? '');
    }
  }

  final ApiErrorKind kind;
  final String detail;
  final int? statusCode;

  /// FastAPI errors: {"detail": "text"} or {"detail": [{"msg": "..."}]}.
  static String _detail(Object? data) {
    if (data is Map && data['detail'] != null) {
      final detail = data['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) {
          return first['msg'] as String;
        }
      }
    }
    return '';
  }

  String get userMessage => switch (kind) {
    ApiErrorKind.offline =>
      "Can't reach Sentinel. Is Tailscale connected on this phone?",
    ApiErrorKind.unauthorized =>
      'The server rejected the API token. Reconnect with the current token.',
    ApiErrorKind.notFound =>
      detail.isNotEmpty ? detail : 'That item no longer exists.',
    ApiErrorKind.conflict => detail.isNotEmpty ? detail : 'Please try again.',
    ApiErrorKind.validation =>
      detail.isNotEmpty ? detail : 'The server rejected that value.',
    ApiErrorKind.server =>
      detail.isNotEmpty
          ? 'Server error: $detail'
          : 'The Sentinel server hit an error.',
    ApiErrorKind.unknown => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => 'ApiException($kind, $statusCode, $detail)';
}
