import 'package:bloc_test/bloc_test.dart';
import 'package:fintech_wallet/core/security/biometric_auth.dart';
import 'package:fintech_wallet/core/security/pin_store.dart';
import 'package:fintech_wallet/core/security/secure_store.dart';
import 'package:fintech_wallet/features/accounts/data/demo_seeder.dart';
import 'package:fintech_wallet/features/auth/data/auth_repository.dart';
import 'package:fintech_wallet/features/auth/presentation/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fakes.dart';

class _MockAuth extends Mock implements AuthRepository {}

class _MockBiometrics extends Mock implements BiometricAuth {}

class _MockSeeder extends Mock implements DemoSeeder {}

void main() {
  late _MockAuth auth;
  late _MockBiometrics biometrics;
  late PinStore pin;
  late TestClock clock;

  SessionCubit build() => SessionCubit(
    auth: auth,
    pin: pin,
    biometrics: biometrics,
    seeder: _MockSeeder(),
    clock: clock.call,
  );

  setUp(() {
    auth = _MockAuth();
    biometrics = _MockBiometrics();
    pin = PinStore(InMemorySecureStore(), iterations: 1, maxAttempts: 3);
    clock = TestClock();
    when(() => auth.hasSession()).thenAnswer((_) async => true);
    when(() => auth.logout()).thenAnswer((_) async {});
    when(() => auth.expireSession()).thenAnswer((_) async {});
    when(() => biometrics.isAvailable()).thenAnswer((_) async => true);
    when(() => biometrics.isEnabled()).thenAnswer((_) async => false);
    when(() => biometrics.setEnabled(enabled: any(named: 'enabled'))).thenAnswer((_) async {});
  });

  group('bootstrap', () {
    blocTest<SessionCubit, SessionState>(
      'signed out without a session',
      setUp: () => when(() => auth.hasSession()).thenAnswer((_) async => false),
      build: build,
      act: (cubit) => cubit.bootstrap(),
      expect: () => [const SessionSignedOut()],
    );

    blocTest<SessionCubit, SessionState>(
      'asks for a PIN when the session has none',
      build: build,
      act: (cubit) => cubit.bootstrap(),
      expect: () => [const SessionNeedsPin(biometricsAvailable: true)],
    );

    blocTest<SessionCubit, SessionState>(
      'starts locked when a PIN exists',
      setUp: () async => pin.setPin('123456'),
      build: build,
      act: (cubit) => cubit.bootstrap(),
      expect: () => [const SessionLocked(biometricsEnabled: false)],
    );
  });

  group('unlock', () {
    blocTest<SessionCubit, SessionState>(
      'counts down wrong PINs, then signs out and wipes data',
      setUp: () async => pin.setPin('123456'),
      build: build,
      seed: () => const SessionLocked(biometricsEnabled: false),
      act: (cubit) async {
        await cubit.unlockWithPin('000000');
        await cubit.unlockWithPin('000000');
        await cubit.unlockWithPin('000000');
      },
      expect: () => [
        const SessionLocked(biometricsEnabled: false, attemptsLeft: 2),
        const SessionLocked(biometricsEnabled: false, attemptsLeft: 1),
        const SessionSignedOut(SignOutReason.tooManyPinAttempts),
      ],
      verify: (_) => verify(() => auth.logout()).called(1),
    );

    blocTest<SessionCubit, SessionState>(
      'unlocks with the right PIN',
      setUp: () async => pin.setPin('123456'),
      build: build,
      seed: () => const SessionLocked(biometricsEnabled: false),
      act: (cubit) => cubit.unlockWithPin('123456'),
      expect: () => [const SessionUnlocked()],
    );

    blocTest<SessionCubit, SessionState>(
      'unlocks with biometrics, ignores a cancelled prompt',
      setUp: () {
        var calls = 0;
        when(() => biometrics.authenticate(any())).thenAnswer((_) async => ++calls > 1);
      },
      build: build,
      seed: () => const SessionLocked(biometricsEnabled: true),
      act: (cubit) async {
        await cubit.unlockWithBiometrics('reason');
        await cubit.unlockWithBiometrics('reason');
      },
      expect: () => [const SessionUnlocked()],
    );
  });

  group('auto-lock', () {
    blocTest<SessionCubit, SessionState>(
      'stays unlocked after a short trip to the background',
      build: build,
      seed: () => const SessionUnlocked(),
      act: (cubit) async {
        cubit.appBackgrounded();
        clock.advance(const Duration(seconds: 10));
        await cubit.appResumed();
      },
      expect: () => <SessionState>[],
    );

    blocTest<SessionCubit, SessionState>(
      'locks after the timeout',
      build: build,
      seed: () => const SessionUnlocked(),
      act: (cubit) async {
        cubit.appBackgrounded();
        clock.advance(const Duration(seconds: 31));
        await cubit.appResumed();
      },
      expect: () => [const SessionLocked(biometricsEnabled: false)],
    );
  });

  blocTest<SessionCubit, SessionState>(
    'an expired session keeps local data',
    build: build,
    seed: () => const SessionUnlocked(),
    act: (cubit) => cubit.sessionExpired(),
    expect: () => [const SessionSignedOut(SignOutReason.sessionExpired)],
    verify: (_) {
      verify(() => auth.expireSession()).called(1);
      verifyNever(() => auth.logout());
    },
  );
}
