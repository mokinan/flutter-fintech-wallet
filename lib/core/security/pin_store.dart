import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:fintech_wallet/core/security/secure_store.dart';

sealed class PinCheck {
  const PinCheck();
}

final class PinAccepted extends PinCheck {
  const PinAccepted();
}

final class PinRejected extends PinCheck {
  const PinRejected(this.attemptsLeft);
  final int attemptsLeft;
}

/// Too many wrong attempts: the caller must end the session.
final class PinLockedOut extends PinCheck {
  const PinLockedOut();
}

/// Stores a salted, key-stretched hash of the app PIN — never the PIN itself —
/// and enforces a wrong-attempt limit that survives app restarts.
class PinStore {
  PinStore(this._store, {this.maxAttempts = 5, this.iterations = 10000, Random? random})
    : _random = random ?? Random.secure();

  static const _hashKey = 'pin_hash';
  static const _saltKey = 'pin_salt';
  static const _failuresKey = 'pin_failures';

  final SecureStore _store;
  final int maxAttempts;
  final int iterations;
  final Random _random;

  Future<bool> hasPin() async => await _store.read(_hashKey) != null;

  Future<void> setPin(String pin) async {
    final salt = base64Encode(List<int>.generate(16, (_) => _random.nextInt(256)));
    await _store.write(_saltKey, salt);
    await _store.write(_hashKey, _hash(pin, salt));
    await _store.write(_failuresKey, '0');
  }

  Future<PinCheck> verify(String pin) async {
    final salt = await _store.read(_saltKey);
    final expected = await _store.read(_hashKey);
    if (salt == null || expected == null) return const PinLockedOut();

    if (_constantTimeEquals(_hash(pin, salt), expected)) {
      await _store.write(_failuresKey, '0');
      return const PinAccepted();
    }
    final failures = int.parse(await _store.read(_failuresKey) ?? '0') + 1;
    await _store.write(_failuresKey, '$failures');
    if (failures >= maxAttempts) {
      await clear();
      return const PinLockedOut();
    }
    return PinRejected(maxAttempts - failures);
  }

  Future<void> clear() async {
    await _store.delete(_hashKey);
    await _store.delete(_saltKey);
    await _store.delete(_failuresKey);
  }

  String _hash(String pin, String salt) {
    var digest = sha256.convert(utf8.encode('$salt:$pin')).bytes;
    for (var i = 1; i < iterations; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return base64Encode(digest);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
