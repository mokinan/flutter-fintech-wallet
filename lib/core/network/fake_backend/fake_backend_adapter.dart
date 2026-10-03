import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fintech_wallet/core/network/fake_backend/fake_wallet_server.dart';
import 'package:fintech_wallet/core/network/fake_backend/network_conditions.dart';

/// Routes Dio requests to [FakeWalletServer] instead of the network.
///
/// Because it plugs in at the adapter level, the real interceptors, error
/// mapping and retry logic all run exactly as they would in production.
class FakeBackendAdapter implements HttpClientAdapter {
  FakeBackendAdapter(this.server, this.conditions);

  final FakeWalletServer server;
  final NetworkConditions conditions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (conditions.latency > Duration.zero) {
      await Future<void>.delayed(conditions.latency);
    }
    if (conditions.offline.value) {
      throw DioException.connectionError(requestOptions: options, reason: 'Simulated offline mode');
    }
    if (conditions.roll(conditions.failureRate)) {
      return _encode(503, {'error': 'service_unavailable'}, const {});
    }

    final headers = options.headers.map((k, v) => MapEntry(k.toLowerCase(), '$v'));
    final response = server.handle(options.method, options.path, headers, _body(options.data));

    if (conditions.roll(conditions.dropResponseRate)) {
      // The server committed the write, but the client never hears back.
      throw DioException.receiveTimeout(
        timeout: options.receiveTimeout ?? const Duration(seconds: 10),
        requestOptions: options,
      );
    }
    return _encode(response.status, response.body, response.headers);
  }

  Map<String, dynamic> _body(Object? data) => switch (data) {
    final Map<String, dynamic> map => map,
    final String text when text.isNotEmpty => jsonDecode(text) as Map<String, dynamic>,
    _ => const {},
  };

  ResponseBody _encode(int status, Map<String, dynamic> body, Map<String, String> headers) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      for (final e in headers.entries) e.key: [e.value],
    },
  );

  @override
  void close({bool force = false}) {}
}
