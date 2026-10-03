import 'package:dio/dio.dart';
import 'package:fintech_wallet/core/network/auth_interceptor.dart';
import 'package:fintech_wallet/core/result/failure.dart';
import 'package:fintech_wallet/core/security/token_storage.dart';

/// Builds the app's configured [Dio] instance.
abstract final class ApiClient {
  static const baseUrl = 'https://api.wallet.example';

  static Dio create({
    required TokenStorage tokens,
    required void Function() onSessionExpired,
    HttpClientAdapter? adapter,
  }) {
    BaseOptions options() => BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
    );

    final refreshDio = Dio(options());
    final dio = Dio(options());
    if (adapter != null) {
      refreshDio.httpClientAdapter = adapter;
      dio.httpClientAdapter = adapter;
    }
    dio.interceptors.add(
      AuthInterceptor(dio: dio, refreshDio: refreshDio, tokens: tokens, onSessionExpired: onSessionExpired),
    );
    return dio;
  }
}

/// Maps transport errors to domain [Failure]s.
Failure failureFromDio(DioException e) {
  final status = e.response?.statusCode;
  if (status == null) return NetworkFailure(e.message);
  final error = switch (e.response?.data) {
    final Map<String, dynamic> body => body['error']?.toString(),
    _ => null,
  };
  return switch (status) {
    401 || 403 => AuthFailure(error),
    400 || 409 || 422 => ValidationFailure(error),
    _ when status >= 500 => ServerFailure(error),
    _ => ServerFailure('HTTP $status: $error'),
  };
}
