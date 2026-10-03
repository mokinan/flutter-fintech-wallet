import 'package:fintech_wallet/core/database/app_database.dart';
import 'package:fintech_wallet/core/network/fake_backend/fake_wallet_server.dart';
import 'package:fintech_wallet/core/result/failure.dart';
import 'package:fintech_wallet/core/security/biometric_auth.dart';
import 'package:fintech_wallet/core/security/pin_store.dart';
import 'package:fintech_wallet/core/security/secure_store.dart';
import 'package:fintech_wallet/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fakes.dart';

class _MockBiometrics extends Mock implements BiometricAuth {}

void main() {
  late AppDatabase db;
  late TestBackend backend;
  late PinStore pin;
  late AuthRepository repository;

  setUp(() {
    db = inMemoryDatabase();
    backend = TestBackend();
    pin = PinStore(InMemorySecureStore(), iterations: 1);
    final biometrics = _MockBiometrics();
    when(() => biometrics.setEnabled(enabled: any(named: 'enabled'))).thenAnswer((_) async {});
    repository = AuthRepository(dio: backend.dio, tokens: backend.tokens, pin: pin, biometrics: biometrics, db: db);
  });

  tearDown(() => db.close());

  test('logs in and stores tokens', () async {
    final result = await repository.login(email: ' Demo@Wallet.dev ', password: FakeWalletServer.demoPassword);
    expect(result.isSuccess, isTrue);
    expect(await repository.hasSession(), isTrue);
  });

  test('maps wrong credentials to a specific failure', () async {
    final result = await repository.login(email: FakeWalletServer.demoEmail, password: 'nope');
    expect(result.failureOrNull, const AuthFailure('invalid_credentials'));
    expect(await repository.hasSession(), isFalse);
  });

  test('maps no connection to a network failure', () async {
    backend.conditions.offline.value = true;
    final result = await repository.login(email: FakeWalletServer.demoEmail, password: FakeWalletServer.demoPassword);
    expect(result.failureOrNull, isA<NetworkFailure>());
  });

  test('logout wipes tokens, PIN and local data even when offline', () async {
    await repository.login(email: FakeWalletServer.demoEmail, password: FakeWalletServer.demoPassword);
    await pin.setPin('123456');
    await createAccount(db);
    backend.conditions.offline.value = true;

    await repository.logout();

    expect(await repository.hasSession(), isFalse);
    expect(await pin.hasPin(), isFalse);
    expect(await db.select(db.accounts).get(), isEmpty);
  });
}
