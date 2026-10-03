import 'package:uuid/uuid.dart';

/// A response produced by [FakeWalletServer].
typedef FakeResponse = ({int status, Map<String, dynamic> body, Map<String, String> headers});

/// In-memory stand-in for the wallet API.
///
/// It implements the parts of a real payments backend that the client must
/// cope with: short-lived access tokens with rotating refresh tokens, and
/// idempotent writes keyed by the `Idempotency-Key` header.
class FakeWalletServer {
  FakeWalletServer({this.accessTokenTtl = const Duration(minutes: 5), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const demoEmail = 'demo@wallet.dev';
  static const demoPassword = 'Demo1234';

  /// Demo FX rates: price of one unit of each currency in SAR, scaled by 1e6.
  static const rates = <String, int>{
    'SAR': 1000000,
    'USD': 3750000,
    'AED': 1021100,
    'KWD': 12195000,
    'EUR': 4050000,
    'JPY': 25200,
  };

  final Duration accessTokenTtl;
  final DateTime Function() _clock;
  final _uuid = const Uuid();

  final _accessTokens = <String, DateTime>{};
  final _refreshTokens = <String>{};
  final _idempotentResponses = <String, FakeResponse>{};

  /// Stored transactions by id — exposed so tests can assert no duplicates.
  final transactions = <String, Map<String, dynamic>>{};

  /// Number of successful token refreshes — exposed for tests.
  int refreshCount = 0;

  FakeResponse handle(String method, String path, Map<String, String> headers, Map<String, dynamic> body) {
    if (path == '/auth/login' && method == 'POST') return _login(body);
    if (path == '/auth/refresh' && method == 'POST') return _refresh(body);

    if (!_isAuthorized(headers['authorization'])) {
      return _json(401, {'error': 'unauthorized'});
    }
    if (path == '/rates' && method == 'GET') {
      return _json(200, {'base': 'SAR', 'rates': rates});
    }
    if (path == '/auth/logout' && method == 'POST') {
      _refreshTokens.remove(body['refreshToken']);
      return _json(204, {});
    }

    final key = headers['idempotency-key'];
    if (key == null || key.isEmpty) {
      return _json(400, {'error': 'missing_idempotency_key'});
    }
    final previous = _idempotentResponses[key];
    if (previous != null) {
      return (
        status: previous.status,
        body: previous.body,
        headers: {...previous.headers, 'idempotent-replayed': 'true'},
      );
    }

    final FakeResponse response;
    if (path == '/transactions' && method == 'POST') {
      response = _createTransaction(body);
    } else if (path == '/transfers' && method == 'POST') {
      response = _createTransfer(body);
    } else if (path.startsWith('/transactions/') && method == 'DELETE') {
      transactions.remove(path.substring('/transactions/'.length));
      response = _json(204, {});
    } else {
      return _json(404, {'error': 'not_found'});
    }
    // Only completed requests are remembered; a 4xx is also final.
    if (response.status < 500) _idempotentResponses[key] = response;
    return response;
  }

  FakeResponse _login(Map<String, dynamic> body) {
    if (body['email'] != demoEmail || body['password'] != demoPassword) {
      return _json(401, {'error': 'invalid_credentials'});
    }
    return _json(200, _issueTokens());
  }

  FakeResponse _refresh(Map<String, dynamic> body) {
    final token = body['refreshToken'];
    // Refresh tokens rotate: each one is single-use.
    if (token is! String || !_refreshTokens.remove(token)) {
      return _json(401, {'error': 'invalid_refresh_token'});
    }
    refreshCount++;
    return _json(200, _issueTokens());
  }

  Map<String, dynamic> _issueTokens() {
    final access = _uuid.v4();
    final refresh = _uuid.v4();
    _accessTokens[access] = _clock().add(accessTokenTtl);
    _refreshTokens.add(refresh);
    return {'accessToken': access, 'refreshToken': refresh, 'expiresIn': accessTokenTtl.inSeconds};
  }

  /// Expires every access token, forcing clients to refresh.
  void expireAccessTokens() => _accessTokens.updateAll((_, _) => DateTime.fromMillisecondsSinceEpoch(0));

  bool _isAuthorized(String? header) {
    if (header == null || !header.startsWith('Bearer ')) return false;
    final expiry = _accessTokens[header.substring(7)];
    return expiry != null && _clock().isBefore(expiry);
  }

  FakeResponse _createTransaction(Map<String, dynamic> body) {
    final error = _validateLeg(body);
    if (error != null) return _json(422, {'error': error});
    transactions[body['id'] as String] = body;
    return _json(201, {'id': body['id'], 'serverTime': _clock().toIso8601String()});
  }

  FakeResponse _createTransfer(Map<String, dynamic> body) {
    final from = body['from'];
    final to = body['to'];
    if (from is! Map<String, dynamic> || to is! Map<String, dynamic>) {
      return _json(422, {'error': 'invalid_transfer'});
    }
    final error = _validateLeg(from) ?? _validateLeg(to);
    if (error != null) return _json(422, {'error': error});
    transactions[from['id'] as String] = from;
    transactions[to['id'] as String] = to;
    return _json(201, {'transferId': body['transferId'], 'serverTime': _clock().toIso8601String()});
  }

  String? _validateLeg(Map<String, dynamic> leg) {
    if (leg['id'] is! String) return 'missing_id';
    final amount = leg['amountMinor'];
    if (amount is! int || amount == 0) return 'invalid_amount';
    if (!rates.containsKey(leg['currency'])) return 'unsupported_currency';
    return null;
  }

  FakeResponse _json(int status, Map<String, dynamic> body) => (status: status, body: body, headers: const {});
}
