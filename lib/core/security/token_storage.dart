import 'package:fintech_wallet/core/security/secure_store.dart';

typedef AuthTokens = ({String accessToken, String refreshToken});

/// Persists auth tokens in the platform keystore with an in-memory cache —
/// every request needs the token and keystore reads are slow.
class TokenStorage {
  TokenStorage(this._store);

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  final SecureStore _store;
  AuthTokens? _cache;

  Future<AuthTokens?> read() async {
    if (_cache != null) return _cache;
    final access = await _store.read(_accessKey);
    final refresh = await _store.read(_refreshKey);
    if (access == null || refresh == null) return null;
    return _cache = (accessToken: access, refreshToken: refresh);
  }

  Future<void> write(AuthTokens tokens) async {
    _cache = tokens;
    await _store.write(_accessKey, tokens.accessToken);
    await _store.write(_refreshKey, tokens.refreshToken);
  }

  Future<void> clear() async {
    _cache = null;
    await _store.delete(_accessKey);
    await _store.delete(_refreshKey);
  }
}
