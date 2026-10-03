import 'package:dio/dio.dart';
import 'package:fintech_wallet/core/database/app_database.dart';
import 'package:fintech_wallet/core/network/api_client.dart';
import 'package:fintech_wallet/core/network/auth_interceptor.dart';
import 'package:fintech_wallet/core/result/failure.dart';
import 'package:fintech_wallet/core/result/result.dart';
import 'package:fintech_wallet/core/security/biometric_auth.dart';
import 'package:fintech_wallet/core/security/pin_store.dart';
import 'package:fintech_wallet/core/security/token_storage.dart';

class AuthRepository {
  AuthRepository({
    required Dio dio,
    required TokenStorage tokens,
    required PinStore pin,
    required BiometricAuth biometrics,
    required AppDatabase db,
  }) : _dio = dio,
       _tokens = tokens,
       _pin = pin,
       _biometrics = biometrics,
       _db = db;

  final Dio _dio;
  final TokenStorage _tokens;
  final PinStore _pin;
  final BiometricAuth _biometrics;
  final AppDatabase _db;

  Future<bool> hasSession() async => await _tokens.read() != null;

  Future<Result<void>> login({required String email, required String password}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email.trim().toLowerCase(), 'password': password},
        options: AuthInterceptor.skipAuth(),
      );
      final body = response.data!;
      await _tokens.write((accessToken: body['accessToken'] as String, refreshToken: body['refreshToken'] as String));
      return const Ok(null);
    } on DioException catch (e) {
      return Err(e.response?.statusCode == 401 ? const AuthFailure('invalid_credentials') : failureFromDio(e));
    }
  }

  /// Ends the session and wipes everything stored on the device.
  Future<void> logout() async {
    final tokens = await _tokens.read();
    if (tokens != null) {
      try {
        await _dio.post<void>('/auth/logout', data: {'refreshToken': tokens.refreshToken});
      } on DioException {
        // Best effort: local logout must never depend on the network.
      }
    }
    await _tokens.clear();
    await _pin.clear();
    await _biometrics.setEnabled(enabled: false);
    await _db.clearAll();
  }

  /// Clears tokens only, keeping unsynced local data for the next login.
  Future<void> expireSession() => _tokens.clear();
}
