import 'package:drift/drift.dart';

/// Where a locally created record is in its journey to the server.
enum SyncStatus { pending, synced, failed }

enum AccountType { bank, cash, card, savings }

@DataClassName('AccountRow')
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get type => intEnum<AccountType>()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  IntColumn get openingBalanceMinor => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TransactionRow')
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text().references(Accounts, #id)();

  /// Signed amount in minor units of the account currency: negative = money out.
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  TextColumn get category => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get occurredAt => dateTime()();

  /// Both legs of a transfer share the same id.
  TextColumn get transferId => text().nullable()();
  IntColumn get syncStatus => intEnum<SyncStatus>()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Writes waiting to be sent to the server. See ADR 0003.
@DataClassName('OutboxRow')
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Sent as the `Idempotency-Key` header; stable across retries.
  TextColumn get idempotencyKey => text().unique()();
  TextColumn get operation => text()();
  TextColumn get payload => text()();

  /// Local record ids whose sync status follows this entry.
  TextColumn get recordIds => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Cached FX rates against the base currency, scaled by 1,000,000.
@DataClassName('ExchangeRateRow')
class ExchangeRates extends Table {
  TextColumn get currency => text()();
  IntColumn get rateMicros => integer()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {currency};
}
