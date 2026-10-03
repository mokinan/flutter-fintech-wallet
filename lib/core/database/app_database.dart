import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:fintech_wallet/core/database/tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// Local source of truth for all wallet data. See ADR 0002.
@DriftDatabase(tables: [Accounts, Transactions, Outbox, ExchangeRates])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'wallet'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Keyset pagination on the history screen sorts by (occurred_at, id).
      await customStatement('CREATE INDEX idx_tx_occurred ON transactions (occurred_at DESC, id DESC)');
      await customStatement('CREATE INDEX idx_tx_account ON transactions (account_id)');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Removes every row; used on logout.
  Future<void> clearAll() => transaction(() async {
    for (final table in allTables.toList().reversed) {
      await delete(table).go();
    }
  });
}
