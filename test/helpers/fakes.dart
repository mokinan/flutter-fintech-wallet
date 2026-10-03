import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:fintech_wallet/core/database/app_database.dart';
import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/core/network/api_client.dart';
import 'package:fintech_wallet/core/network/connectivity_service.dart';
import 'package:fintech_wallet/core/network/fake_backend/fake_backend_adapter.dart';
import 'package:fintech_wallet/core/network/fake_backend/fake_wallet_server.dart';
import 'package:fintech_wallet/core/network/fake_backend/network_conditions.dart';
import 'package:fintech_wallet/core/security/secure_store.dart';
import 'package:fintech_wallet/core/security/token_storage.dart';
import 'package:fintech_wallet/features/accounts/data/local_accounts_repository.dart';
import 'package:fintech_wallet/features/accounts/domain/account.dart';

AppDatabase inMemoryDatabase() => AppDatabase(NativeDatabase.memory());

/// A clock tests can move forward explicitly.
class TestClock {
  TestClock([DateTime? start]) : now = start ?? DateTime(2026, 3, 15, 12);

  DateTime now;

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

class FakeConnectivity implements ConnectivityService {
  FakeConnectivity({bool online = true}) : _online = online;

  bool _online;
  final _controller = StreamController<bool>.broadcast();

  void setOnline({required bool online}) {
    _online = online;
    _controller.add(online);
  }

  @override
  bool get isOnline => _online;

  @override
  Stream<bool> get onlineChanges => _controller.stream;
}

/// A fully wired client talking to an in-memory server with no latency.
class TestBackend {
  TestBackend({Duration accessTokenTtl = const Duration(minutes: 5), DateTime Function()? clock})
    : server = FakeWalletServer(accessTokenTtl: accessTokenTtl, clock: clock),
      conditions = NetworkConditions(latency: Duration.zero) {
    tokens = TokenStorage(InMemorySecureStore());
    dio = ApiClient.create(
      tokens: tokens,
      onSessionExpired: () => sessionExpiredCount++,
      adapter: _FailingPathsAdapter(FakeBackendAdapter(server, conditions), failingPaths),
    );
  }

  /// Requests to these paths fail with a connection error.
  final Set<String> failingPaths = {};

  final FakeWalletServer server;
  final NetworkConditions conditions;
  late final TokenStorage tokens;
  late final Dio dio;
  int sessionExpiredCount = 0;

  Future<void> login() async {
    final response = await dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': FakeWalletServer.demoEmail, 'password': FakeWalletServer.demoPassword},
    );
    await tokens.write((
      accessToken: response.data!['accessToken'] as String,
      refreshToken: response.data!['refreshToken'] as String,
    ));
  }
}

Future<Account> createAccount(
  AppDatabase db, {
  String name = 'Main',
  AccountType type = AccountType.bank,
  Currency currency = Currency.sar,
  int openingMinor = 100000,
  DateTime Function()? clock,
}) async {
  final result = await LocalAccountsRepository(
    db,
    clock: clock,
  ).create(name: name, type: type, openingBalance: Money(openingMinor, currency));
  return result.valueOrNull!;
}

class _FailingPathsAdapter implements HttpClientAdapter {
  _FailingPathsAdapter(this._inner, this._failing);

  final HttpClientAdapter _inner;
  final Set<String> _failing;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    if (_failing.contains(options.path)) {
      throw DioException.connectionError(requestOptions: options, reason: 'test');
    }
    return _inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => _inner.close(force: force);
}
