import 'package:equatable/equatable.dart';
import 'package:fintech_wallet/core/security/biometric_auth.dart';
import 'package:fintech_wallet/core/security/pin_store.dart';
import 'package:fintech_wallet/features/accounts/data/demo_seeder.dart';
import 'package:fintech_wallet/features/auth/data/auth_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum SignOutReason { none, sessionExpired, tooManyPinAttempts }

sealed class SessionState extends Equatable {
  const SessionState();

  @override
  List<Object?> get props => [];
}

final class SessionLoading extends SessionState {
  const SessionLoading();
}

final class SessionSignedOut extends SessionState {
  const SessionSignedOut([this.reason = SignOutReason.none]);
  final SignOutReason reason;

  @override
  List<Object?> get props => [reason];
}

/// Logged in for the first time on this device: a PIN must be created.
final class SessionNeedsPin extends SessionState {
  const SessionNeedsPin({required this.biometricsAvailable});
  final bool biometricsAvailable;

  @override
  List<Object?> get props => [biometricsAvailable];
}

final class SessionLocked extends SessionState {
  const SessionLocked({required this.biometricsEnabled, this.attemptsLeft});
  final bool biometricsEnabled;

  /// Set after a wrong PIN.
  final int? attemptsLeft;

  @override
  List<Object?> get props => [biometricsEnabled, attemptsLeft];
}

final class SessionUnlocked extends SessionState {
  const SessionUnlocked();
}

/// Owns the authentication and app-lock lifecycle.
class SessionCubit extends Cubit<SessionState> {
  SessionCubit({
    required AuthRepository auth,
    required PinStore pin,
    required BiometricAuth biometrics,
    required DemoSeeder seeder,
    this.lockAfter = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _auth = auth,
       _pin = pin,
       _biometrics = biometrics,
       _seeder = seeder,
       _clock = clock ?? DateTime.now,
       super(const SessionLoading());

  final AuthRepository _auth;
  final PinStore _pin;
  final BiometricAuth _biometrics;
  final DemoSeeder _seeder;
  final DateTime Function() _clock;

  /// How long the app may stay in the background before it locks.
  final Duration lockAfter;

  DateTime? _backgroundedAt;

  Future<void> bootstrap() async {
    if (!await _auth.hasSession()) return emit(const SessionSignedOut());
    if (!await _pin.hasPin()) {
      return emit(SessionNeedsPin(biometricsAvailable: await _biometrics.isAvailable()));
    }
    emit(SessionLocked(biometricsEnabled: await _biometrics.isEnabled()));
  }

  Future<void> loggedIn() async {
    await _seeder.seedIfEmpty();
    // Re-login after an expired session keeps the existing PIN.
    if (await _pin.hasPin()) return emit(const SessionUnlocked());
    emit(SessionNeedsPin(biometricsAvailable: await _biometrics.isAvailable()));
  }

  Future<void> createPin(String pin, {required bool enableBiometrics}) async {
    await _pin.setPin(pin);
    await _biometrics.setEnabled(enabled: enableBiometrics);
    emit(const SessionUnlocked());
  }

  Future<void> unlockWithPin(String pin) async {
    final current = state;
    if (current is! SessionLocked) return;
    switch (await _pin.verify(pin)) {
      case PinAccepted():
        emit(const SessionUnlocked());
      case PinRejected(:final attemptsLeft):
        emit(SessionLocked(biometricsEnabled: current.biometricsEnabled, attemptsLeft: attemptsLeft));
      case PinLockedOut():
        await _auth.logout();
        emit(const SessionSignedOut(SignOutReason.tooManyPinAttempts));
    }
  }

  Future<void> unlockWithBiometrics(String reason) async {
    if (state is! SessionLocked) return;
    if (await _biometrics.authenticate(reason)) emit(const SessionUnlocked());
  }

  void appBackgrounded() => _backgroundedAt ??= _clock();

  Future<void> appResumed() async {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (state is SessionUnlocked && since != null && _clock().difference(since) >= lockAfter) {
      emit(SessionLocked(biometricsEnabled: await _biometrics.isEnabled()));
    }
  }

  /// The refresh token was rejected: keep local data, require a new login.
  Future<void> sessionExpired() async {
    if (state is SessionSignedOut) return;
    await _auth.expireSession();
    emit(const SessionSignedOut(SignOutReason.sessionExpired));
  }

  Future<void> logout() async {
    await _auth.logout();
    emit(const SessionSignedOut());
  }
}
