import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fintech_wallet/core/security/token_storage.dart';

/// Attaches the access token and transparently refreshes it on 401.
///
/// Refresh is **single-flight**: when several requests fail at once, only one
/// refresh call is made and the others wait for it. This matters because
/// refresh tokens rotate — a second concurrent refresh with the same token
/// would be rejected and log the user out.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.dio, required this.refreshDio, required this.tokens, required this.onSessionExpired});

  /// The client to retry requests on.
  final Dio dio;

  /// A bare client without this interceptor, used for the refresh call.
  final Dio refreshDio;
  final TokenStorage tokens;
  final void Function() onSessionExpired;

  Future<_RefreshOutcome>? _refreshing;

  static const _retriedKey = 'auth_retried';
  static const _skipAuthKey = 'skip_auth';

  /// Mark a request as not needing a token (e.g. login).
  static Options skipAuth() => Options(extra: {_skipAuthKey: true});

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra[_skipAuthKey] != true) {
      final current = await tokens.read();
      if (current != null) {
        options.headers['Authorization'] = 'Bearer ${current.accessToken}';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final isUnauthorized = err.response?.statusCode == 401;
    if (!isUnauthorized || request.extra[_skipAuthKey] == true || request.extra[_retriedKey] == true) {
      return handler.next(err);
    }

    final usedToken = (request.headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
    final current = await tokens.read();

    // Another request already refreshed while this one was in flight.
    final String freshToken;
    if (current != null && current.accessToken != usedToken) {
      freshToken = current.accessToken;
    } else {
      switch (await (_refreshing ??= _refresh().whenComplete(() => _refreshing = null))) {
        case _Refreshed(:final accessToken):
          freshToken = accessToken;
        case _Rejected():
          onSessionExpired();
          return handler.next(err);
        case _Unreachable():
          // Transient: keep the session and let the caller retry later.
          return handler.next(err);
      }
    }

    try {
      request
        ..headers['Authorization'] = 'Bearer $freshToken'
        ..extra[_retriedKey] = true;
      handler.resolve(await dio.fetch<dynamic>(request));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<_RefreshOutcome> _refresh() async {
    final current = await tokens.read();
    if (current == null) return const _Rejected();
    try {
      final response = await refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': current.refreshToken},
      );
      final body = response.data!;
      final next = (accessToken: body['accessToken'] as String, refreshToken: body['refreshToken'] as String);
      await tokens.write(next);
      return _Refreshed(next.accessToken);
    } on DioException catch (e) {
      // Only a definitive rejection ends the session; a network blip does not.
      if (e.response?.statusCode == 401) {
        await tokens.clear();
        return const _Rejected();
      }
      return const _Unreachable();
    }
  }
}

sealed class _RefreshOutcome {
  const _RefreshOutcome();
}

final class _Refreshed extends _RefreshOutcome {
  const _Refreshed(this.accessToken);
  final String accessToken;
}

final class _Rejected extends _RefreshOutcome {
  const _Rejected();
}

final class _Unreachable extends _RefreshOutcome {
  const _Unreachable();
}
