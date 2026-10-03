import 'dart:convert';
import 'dart:math';

import 'package:fintech_wallet/core/database/app_database.dart';
import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/features/accounts/domain/account.dart';
import 'package:fintech_wallet/features/sync/data/outbox_writer.dart';
import 'package:fintech_wallet/features/sync/data/sync_engine.dart';
import 'package:fintech_wallet/features/transactions/data/local_transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late AppDatabase db;
  late TestBackend backend;
  late TestClock clock;
  late FakeConnectivity connectivity;
  late LocalTransactionsRepository repository;
  late SyncEngine engine;
  late Account account;

  setUp(() async {
    clock = TestClock();
    db = inMemoryDatabase();
    backend = TestBackend(clock: clock.call);
    await backend.login();
    connectivity = FakeConnectivity();
    repository = LocalTransactionsRepository(db, OutboxWriter(db, clock: clock.call), clock: clock.call);
    engine = SyncEngine(db: db, dio: backend.dio, connectivity: connectivity, clock: clock.call, random: Random(1));
    account = await createAccount(db);
  });

  tearDown(() => db.close());

  Future<WalletTransaction> addExpense([int minor = 1500]) async => (await repository.add(
    accountId: account.id,
    amount: Money(-minor, Currency.sar),
    category: TransactionCategory.dining,
    note: 'Lunch',
    occurredAt: clock(),
  )).valueOrNull!;

  Future<SyncStatus> statusOf(String id) async =>
      (await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle()).syncStatus;

  test('a local write is queued in the same transaction and synced', () async {
    final tx = await addExpense();
    expect(tx.syncStatus, SyncStatus.pending);
    expect(await db.select(db.outbox).get(), hasLength(1));

    final report = await engine.syncNow();

    expect(report, (sent: 1, failed: 0, interrupted: false));
    expect(backend.server.transactions.keys, [tx.id]);
    expect(await statusOf(tx.id), SyncStatus.synced);
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('a lost response is retried with the same key and creates no duplicate', () async {
    final tx = await addExpense();
    backend.conditions.dropResponseRate = 1;

    final first = await engine.syncNow();
    expect(first.interrupted, isTrue);
    // The server already has it, but the client does not know.
    expect(backend.server.transactions, hasLength(1));
    expect(await statusOf(tx.id), SyncStatus.pending);

    backend.conditions.dropResponseRate = 0;
    clock.advance(SyncEngine.maxBackoff);
    final second = await engine.syncNow();

    expect(second.sent, 1);
    expect(backend.server.transactions, hasLength(1));
    expect(await statusOf(tx.id), SyncStatus.synced);
  });

  test('does nothing while offline and drains when back online', () async {
    await addExpense();
    connectivity.setOnline(online: false);

    expect(await engine.syncNow(), (sent: 0, failed: 0, interrupted: true));
    expect(backend.server.transactions, isEmpty);

    connectivity.setOnline(online: true);
    expect((await engine.syncNow()).sent, 1);
  });

  test('backs off exponentially after transient failures', () async {
    await addExpense();
    backend.conditions.failureRate = 1;

    await engine.syncNow();
    final entry = await db.select(db.outbox).getSingle();
    expect(entry.attempts, 1);
    expect(entry.nextAttemptAt.isAfter(clock()), isTrue);

    // Not due yet: the engine must not hammer the server.
    backend.conditions.failureRate = 0;
    expect((await engine.syncNow()).sent, 0);

    clock.advance(const Duration(seconds: 5));
    expect((await engine.syncNow()).sent, 1);
  });

  test('backoff grows and is capped', () {
    expect(engine.backoff(1).inSeconds, inInclusiveRange(2, 3));
    expect(engine.backoff(4).inSeconds, inInclusiveRange(16, 17));
    expect(engine.backoff(30), lessThanOrEqualTo(SyncEngine.maxBackoff + const Duration(seconds: 1)));
  });

  test('a permanent rejection marks records failed and moves on', () async {
    // Queue a payload the server rejects with 422, followed by a valid write.
    await OutboxWriter(db, clock: clock.call).enqueue(
      operation: OutboxOperation.createTransaction,
      payload: {'id': 'bad', 'amountMinor': 0, 'currency': 'SAR'},
      recordIds: const [],
    );
    final good = await addExpense();

    final report = await engine.syncNow();

    expect(report, (sent: 1, failed: 1, interrupted: false));
    expect(await statusOf(good.id), SyncStatus.synced);
    final rejected = await db.select(db.outbox).getSingle();
    expect(rejected.lastError, contains('422'));
    expect(await engine.watchPendingCount().first, 0);
  });

  test('sends in order, so a delete never overtakes its create', () async {
    final tx = await addExpense();
    // Make the create "attempted" so deleting it must go through the server.
    backend.conditions.offline.value = true;
    await engine.syncNow();
    backend.conditions.offline.value = false;
    await repository.delete(tx);

    final operations = (await db.select(db.outbox).get()).map((e) => e.operation).toList();
    expect(operations, [OutboxOperation.createTransaction, OutboxOperation.deleteTransaction]);

    clock.advance(SyncEngine.maxBackoff);
    final report = await engine.syncNow();
    expect(report.sent, 2);
    expect(backend.server.transactions, isEmpty);
  });

  test('concurrent sync calls share one pass', () async {
    await addExpense();
    final results = await Future.wait([engine.syncNow(), engine.syncNow(), engine.syncNow()]);
    expect(results.map((r) => r.sent), [1, 1, 1]);
    expect(backend.server.transactions, hasLength(1));
  });

  test('transfers sync both legs in one request', () async {
    final usd = await createAccount(db, name: 'USD', currency: Currency.usd);
    await repository.transfer(
      fromAccountId: account.id,
      toAccountId: usd.id,
      sent: const Money(37500, Currency.sar),
      received: const Money(10000, Currency.usd),
      note: '',
    );
    final entry = await db.select(db.outbox).getSingle();
    final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
    expect((payload['from'] as Map)['amountMinor'], -37500);
    expect((payload['to'] as Map)['amountMinor'], 10000);

    expect((await engine.syncNow()).sent, 1);
    expect(backend.server.transactions, hasLength(2));
  });
}
