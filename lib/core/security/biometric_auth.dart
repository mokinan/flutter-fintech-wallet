import 'package:fintech_wallet/core/security/secure_store.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Wraps `local_auth` and the user's opt-in preference.
class BiometricAuth {
  BiometricAuth(this._store, [LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  static const _enabledKey = 'biometrics_enabled';

  final SecureStore _store;
  final LocalAuthentication _auth;

  Future<bool> isAvailable() async {
    try {
      return await _auth.canCheckBiometrics && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }

  Future<bool> isEnabled() async => await _store.read(_enabledKey) == 'true' && await isAvailable();

  Future<void> setEnabled({required bool enabled}) =>
      enabled ? _store.write(_enabledKey, 'true') : _store.delete(_enabledKey);

  /// Returns `false` on cancel, lockout or any platform error; the PIN pad
  /// remains available as a fallback.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true, persistAcrossBackgrounding: true);
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }
}
