import 'package:dio/dio.dart';
import 'package:fintech_wallet/core/database/app_database.dart';
import 'package:fintech_wallet/core/network/api_client.dart';
import 'package:fintech_wallet/core/network/connectivity_service.dart';
import 'package:fintech_wallet/core/network/fake_backend/fake_backend_adapter.dart';
import 'package:fintech_wallet/core/network/fake_backend/fake_wallet_server.dart';
import 'package:fintech_wallet/core/network/fake_backend/network_conditions.dart';
import 'package:fintech_wallet/core/security/biometric_auth.dart';
import 'package:fintech_wallet/core/security/pin_store.dart';
import 'package:fintech_wallet/core/security/secure_store.dart';
import 'package:fintech_wallet/core/security/token_storage.dart';
import 'package:fintech_wallet/features/accounts/data/demo_seeder.dart';
import 'package:fintech_wallet/features/accounts/data/local_accounts_repository.dart';
import 'package:fintech_wallet/features/accounts/domain/accounts_repository.dart';
import 'package:fintech_wallet/features/auth/data/auth_repository.dart';
import 'package:fintech_wallet/features/auth/presentation/session_cubit.dart';
import 'package:fintech_wallet/features/rates/data/rates_repository.dart';
import 'package:fintech_wallet/features/settings/presentation/settings_cubit.dart';
import 'package:fintech_wallet/features/sync/data/outbox_writer.dart';
import 'package:fintech_wallet/features/sync/data/sync_engine.dart';
import 'package:fintech_wallet/features/transactions/data/local_transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GetIt getIt = GetIt.instance;

/// Composition root: the only place that knows concrete implementations.
Future<void> configureDependencies() async {
  final prefs = await SharedPreferences.getInstance();
  final secureStore = KeychainSecureStore();
  final conditions = NetworkConditions();
  final server = FakeWalletServer();
  final tokens = TokenStorage(secureStore);
  final db = AppDatabase();
  final pin = PinStore(secureStore);
  final biometrics = BiometricAuth(secureStore);

  final dio = ApiClient.create(
    tokens: tokens,
    // Resolved lazily: the cubit depends on the client through AuthRepository.
    onSessionExpired: () => getIt<SessionCubit>().sessionExpired(),
    adapter: FakeBackendAdapter(server, conditions),
  );
  final connectivity = DeviceConnectivityService(conditions);
  final auth = AuthRepository(dio: dio, tokens: tokens, pin: pin, biometrics: biometrics, db: db);

  getIt
    ..registerSingleton<NetworkConditions>(conditions)
    ..registerSingleton<FakeWalletServer>(server)
    ..registerSingleton<AppDatabase>(db)
    ..registerSingleton<Dio>(dio)
    ..registerSingleton<ConnectivityService>(connectivity)
    ..registerSingleton<BiometricAuth>(biometrics)
    ..registerSingleton<AuthRepository>(auth)
    ..registerSingleton<AccountsRepository>(LocalAccountsRepository(db))
    ..registerSingleton<TransactionsRepository>(LocalTransactionsRepository(db, OutboxWriter(db)))
    ..registerSingleton<RatesRepository>(RatesRepository(db, dio))
    ..registerSingleton<SyncEngine>(SyncEngine(db: db, dio: dio, connectivity: connectivity))
    ..registerSingleton<SettingsCubit>(SettingsCubit(prefs))
    ..registerSingleton<SessionCubit>(
      SessionCubit(auth: auth, pin: pin, biometrics: biometrics, seeder: DemoSeeder(db)),
    );
}
