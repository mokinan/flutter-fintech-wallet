import 'package:dio/dio.dart';
import 'package:fintech_wallet/core/network/api_client.dart';
import 'package:fintech_wallet/core/result/failure.dart';
import 'package:fintech_wallet/core/result/result.dart';
import 'package:fintech_wallet/features/settings/presentation/settings_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DioException _http(int status, [Object? body]) {
  final options = RequestOptions(path: '/x');
  return DioException.badResponse(
    statusCode: status,
    requestOptions: options,
    response: Response<Object?>(requestOptions: options, statusCode: status, data: body),
  );
}

void main() {
  group('Result', () {
    test('folds both branches', () {
      const Result<int> ok = Ok(2);
      const Result<int> err = Err(NetworkFailure());
      expect(ok.when(success: (v) => v * 2, failure: (_) => -1), 4);
      expect(err.when(success: (v) => v, failure: (f) => f is NetworkFailure ? -1 : 0), -1);
      expect(ok.valueOrNull, 2);
      expect(err.valueOrNull, isNull);
      expect(ok.failureOrNull, isNull);
      expect(err.isSuccess, isFalse);
    });
  });

  group('failureFromDio', () {
    test('maps transport errors to domain failures', () {
      final options = RequestOptions(path: '/x');
      expect(failureFromDio(DioException.connectionError(requestOptions: options, reason: 'x')), isA<NetworkFailure>());
      expect(failureFromDio(_http(401)), isA<AuthFailure>());
      expect(failureFromDio(_http(422, {'error': 'invalid_amount'})), const ValidationFailure('invalid_amount'));
      expect(failureFromDio(_http(503)), isA<ServerFailure>());
      expect(failureFromDio(_http(418)), isA<ServerFailure>());
    });
  });

  group('SettingsCubit', () {
    test('persists locale and theme', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cubit = SettingsCubit(prefs);
      expect(cubit.state, const SettingsState());

      await cubit.setLocale(const Locale('ar'));
      await cubit.setThemeMode(ThemeMode.dark);

      final restored = SettingsCubit(prefs);
      expect(restored.state, const SettingsState(locale: Locale('ar'), themeMode: ThemeMode.dark));

      await restored.setLocale(null);
      expect(SettingsCubit(prefs).state.locale, isNull);
    });
  });
}
