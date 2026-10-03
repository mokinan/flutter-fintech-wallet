import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late TestBackend backend;

  setUp(() async {
    backend = TestBackend();
    await backend.login();
  });

  test('attaches the access token', () async {
    final response = await backend.dio.get<Map<String, dynamic>>('/rates');
    expect(response.statusCode, 200);
    expect(backend.server.refreshCount, 0);
  });

  test('refreshes an expired token once and replays the request', () async {
    final before = await backend.tokens.read();
    backend.server.expireAccessTokens();

    final response = await backend.dio.get<Map<String, dynamic>>('/rates');

    expect(response.statusCode, 200);
    expect(backend.server.refreshCount, 1);
    expect((await backend.tokens.read())!.accessToken, isNot(before!.accessToken));
  });

  test('concurrent 401s share a single refresh (rotating refresh tokens)', () async {
    backend.server.expireAccessTokens();

    final responses = await Future.wait(List.generate(5, (_) => backend.dio.get<Map<String, dynamic>>('/rates')));

    expect(responses.map((r) => r.statusCode), everyElement(200));
    // A second refresh would have reused a consumed refresh token and failed.
    expect(backend.server.refreshCount, 1);
    expect(backend.sessionExpiredCount, 0);
  });

  test('ends the session when the refresh token is rejected', () async {
    final tokens = (await backend.tokens.read())!;
    await backend.tokens.write((accessToken: tokens.accessToken, refreshToken: 'revoked'));
    backend.server.expireAccessTokens();

    await expectLater(
      backend.dio.get<Map<String, dynamic>>('/rates'),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 401)),
    );
    expect(backend.sessionExpiredCount, 1);
    expect(await backend.tokens.read(), isNull);
  });

  test('keeps the session when refresh fails because of the network', () async {
    backend.server.expireAccessTokens();
    backend.failingPaths.add('/auth/refresh');

    await expectLater(backend.dio.get<Map<String, dynamic>>('/rates'), throwsA(isA<DioException>()));
    expect(backend.sessionExpiredCount, 0);
    expect(await backend.tokens.read(), isNotNull, reason: 'a network blip must not wipe credentials');
  });
}
