import 'package:fintech_wallet/core/database/app_database.dart';
import 'package:fintech_wallet/features/accounts/data/demo_seeder.dart';
import 'package:fintech_wallet/features/accounts/data/local_accounts_repository.dart';
import 'package:fintech_wallet/features/sync/data/outbox_writer.dart';
import 'package:fintech_wallet/features/transactions/data/local_transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = inMemoryDatabase());
  tearDown(() => db.close());

  test('seeds once', () async {
    final seeder = DemoSeeder(db, clock: TestClock().call);
    await seeder.seedIfEmpty();
    final count = (await db.select(db.transactions).get()).length;
    await seeder.seedIfEmpty();

    expect(await db.select(db.accounts).get(), hasLength(5));
    expect(count, greaterThan(50));
    expect(await db.select(db.transactions).get(), hasLength(count));
  });

  // Regression: seeded history used to leave the cash wallet negative,
  // which the app itself never allows.
  test('only credit cards end up with a negative balance', () async {
    for (final seed in [1, 7, 42, 2026]) {
      await db.clearAll();
      await DemoSeeder(db, clock: TestClock().call, seed: seed).seedIfEmpty();
      final accounts = await LocalAccountsRepository(db).watchAccounts().first;
      for (final account in accounts.where((a) => a.type != AccountType.card)) {
        expect(account.balance.isNegative, isFalse, reason: '${account.name} with seed $seed');
      }
    }
  });

  test('seeded records are already synced', () async {
    await DemoSeeder(db, clock: TestClock().call).seedIfEmpty();
    final statuses = (await db.select(db.transactions).get()).map((t) => t.syncStatus).toSet();
    expect(statuses, {SyncStatus.synced});
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  // Regression: card payments were seeded without a transfer id, so reports
  // counted them as both income and spending.
  test('card payments are transfers and stay out of reports', () async {
    final clock = TestClock();
    await DemoSeeder(db, clock: clock.call).seedIfEmpty();
    final rows = await db.select(db.transactions).get();
    final payments = rows.where((t) => t.category == TransactionCategory.transfer.name);
    expect(payments, isNotEmpty);
    expect(payments.every((t) => t.transferId != null), isTrue);

    final reports = LocalTransactionsRepository(db, OutboxWriter(db));
    final byCategory = await reports.expensesByCategory(from: DateTime(2020), to: DateTime(2030));
    expect(byCategory.map((e) => e.category), isNot(contains(TransactionCategory.transfer)));
  });
}
