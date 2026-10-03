import 'package:drift/drift.dart' show Value;
import 'package:fintech_wallet/core/database/app_database.dart';
import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/core/result/failure.dart';
import 'package:fintech_wallet/features/accounts/data/local_accounts_repository.dart';
import 'package:fintech_wallet/features/accounts/domain/account.dart';
import 'package:fintech_wallet/features/sync/data/outbox_writer.dart';
import 'package:fintech_wallet/features/transactions/data/local_transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late AppDatabase db;
  late TestClock clock;
  late LocalTransactionsRepository repository;
  late Account bank;

  setUp(() async {
    clock = TestClock();
    db = inMemoryDatabase();
    repository = LocalTransactionsRepository(db, OutboxWriter(db, clock: clock.call), clock: clock.call);
    bank = await createAccount(db, openingMinor: 1000000, clock: clock.call);
  });

  tearDown(() => db.close());

  Future<WalletTransaction> add(
    int minor, {
    String note = '',
    DateTime? at,
    String? accountId,
    Currency? currency,
  }) async => (await repository.add(
    accountId: accountId ?? bank.id,
    amount: Money(minor, currency ?? Currency.sar),
    category: minor > 0 ? TransactionCategory.salary : TransactionCategory.groceries,
    note: note,
    occurredAt: at ?? clock(),
  )).valueOrNull!;

  Future<Money> balanceOf(String id) async => (await LocalAccountsRepository(db).findById(id))!.balance;

  group('pagination', () {
    test('keyset pages cover every row exactly once, even with equal timestamps', () async {
      // 45 rows, many sharing a timestamp — the tie is broken by id.
      for (var i = 0; i < 45; i++) {
        await add(-100 - i, at: clock().subtract(Duration(hours: i ~/ 3)));
      }

      final seen = <String>[];
      PageCursor? cursor;
      var pages = 0;
      do {
        final page = await repository.page(const TransactionQuery(), after: cursor, limit: 10);
        seen.addAll(page.items.map((t) => t.id));
        cursor = page.next;
        pages++;
      } while (cursor != null);

      expect(pages, 5);
      expect(seen, hasLength(45));
      expect(seen.toSet(), hasLength(45));
    });

    test('results are newest first', () async {
      final old = await add(-100, at: clock().subtract(const Duration(days: 2)));
      final recent = await add(-200);
      final page = await repository.page(const TransactionQuery());
      expect(page.items.map((t) => t.id), [recent.id, old.id]);
      expect(page.next, isNull);
    });
  });

  group('filters', () {
    test('by kind and account', () async {
      final cash = await createAccount(db, name: 'Cash', type: AccountType.cash, openingMinor: 50000);
      await add(5000);
      await add(-700);
      await add(-300, accountId: cash.id);
      await repository.transfer(
        fromAccountId: bank.id,
        toAccountId: cash.id,
        sent: const Money(1000, Currency.sar),
        received: const Money(1000, Currency.sar),
        note: '',
      );

      Future<int> count(TransactionQuery q) async => (await repository.page(q)).items.length;
      expect(await count(const TransactionQuery()), 5);
      expect(await count(const TransactionQuery(kind: TransactionKind.income)), 1);
      expect(await count(const TransactionQuery(kind: TransactionKind.expense)), 2);
      expect(await count(const TransactionQuery(kind: TransactionKind.transfer)), 2);
      expect(await count(TransactionQuery(accountId: cash.id)), 2);
      expect(await count(TransactionQuery(accountId: cash.id, kind: TransactionKind.expense)), 1);
    });

    test('search matches notes case-insensitively and escapes wildcards', () async {
      await add(-100, note: 'Coffee with Sara');
      await add(-100, note: '100% refund');
      await add(-100, note: '1000 refund');

      Future<List<String>> search(String s) async =>
          (await repository.page(TransactionQuery(search: s))).items.map((t) => t.note).toList();
      expect(await search('coffee'), ['Coffee with Sara']);
      expect(await search('100%'), ['100% refund']);
      expect(await search('_'), isEmpty);
    });
  });

  group('add', () {
    test('rejects zero amounts and currency mismatches', () async {
      final zero = await repository.add(
        accountId: bank.id,
        amount: const Money.zero(Currency.sar),
        category: TransactionCategory.other,
        note: '',
        occurredAt: clock(),
      );
      expect(zero.failureOrNull, isA<ValidationFailure>());

      final mismatch = await repository.add(
        accountId: bank.id,
        amount: const Money(-100, Currency.usd),
        category: TransactionCategory.other,
        note: '',
        occurredAt: clock(),
      );
      expect(mismatch.failureOrNull, isA<ValidationFailure>());
      expect(await db.select(db.outbox).get(), isEmpty);
    });

    test('prevents overspending, except on credit cards', () async {
      final overspend = await repository.add(
        accountId: bank.id,
        amount: const Money(-1000001, Currency.sar),
        category: TransactionCategory.shopping,
        note: '',
        occurredAt: clock(),
      );
      expect(overspend.failureOrNull, isA<InsufficientFundsFailure>());

      final card = await createAccount(db, name: 'Card', type: AccountType.card, openingMinor: 0);
      final onCredit = await repository.add(
        accountId: card.id,
        amount: const Money(-5000, Currency.sar),
        category: TransactionCategory.shopping,
        note: '',
        occurredAt: clock(),
      );
      expect(onCredit.isSuccess, isTrue);
      expect(await balanceOf(card.id), const Money(-5000, Currency.sar));
    });
  });

  group('transfer', () {
    test('moves money atomically across currencies', () async {
      final usd = await createAccount(db, name: 'USD', currency: Currency.usd, openingMinor: 0);
      final result = await repository.transfer(
        fromAccountId: bank.id,
        toAccountId: usd.id,
        sent: const Money(37500, Currency.sar),
        received: const Money(10000, Currency.usd),
        note: 'Savings',
      );

      expect(result.isSuccess, isTrue);
      expect(await balanceOf(bank.id), const Money(962500, Currency.sar));
      expect(await balanceOf(usd.id), const Money(10000, Currency.usd));
      final legs = await db.select(db.transactions).get();
      expect(legs.map((l) => l.transferId).toSet(), hasLength(1));
    });

    test('fails without side effects when funds are insufficient', () async {
      final cash = await createAccount(db, name: 'Cash', type: AccountType.cash, openingMinor: 0);
      final result = await repository.transfer(
        fromAccountId: cash.id,
        toAccountId: bank.id,
        sent: const Money(100, Currency.sar),
        received: const Money(100, Currency.sar),
        note: '',
      );
      expect(result.failureOrNull, isA<InsufficientFundsFailure>());
      expect(await db.select(db.transactions).get(), isEmpty);
      expect(await db.select(db.outbox).get(), isEmpty);
    });

    test('rejects transfers to the same account', () async {
      final result = await repository.transfer(
        fromAccountId: bank.id,
        toAccountId: bank.id,
        sent: const Money(100, Currency.sar),
        received: const Money(100, Currency.sar),
        note: '',
      );
      expect(result.failureOrNull, const ValidationFailure('same_account'));
    });
  });

  group('delete', () {
    test('an unsent write is dropped from the queue, not sent then deleted', () async {
      final tx = await add(-500);
      await repository.delete(tx);
      expect(await db.select(db.transactions).get(), isEmpty);
      expect(await db.select(db.outbox).get(), isEmpty);
    });

    test('a write that may have reached the server is deleted remotely', () async {
      final tx = await add(-500);
      await db.update(db.outbox).write(const OutboxCompanion(attempts: Value(1)));
      await repository.delete(tx);
      final ops = (await db.select(db.outbox).get()).map((o) => o.operation);
      expect(ops, [OutboxOperation.createTransaction, OutboxOperation.deleteTransaction]);
    });

    test('deleting one leg removes the whole transfer', () async {
      final cash = await createAccount(db, name: 'Cash', type: AccountType.cash, openingMinor: 0);
      await repository.transfer(
        fromAccountId: bank.id,
        toAccountId: cash.id,
        sent: const Money(100, Currency.sar),
        received: const Money(100, Currency.sar),
        note: '',
      );
      final leg = (await repository.page(const TransactionQuery())).items.first;
      await repository.delete(leg);
      expect(await db.select(db.transactions).get(), isEmpty);
    });
  });

  group('reports', () {
    test('groups expenses by category and currency within the range', () async {
      final usd = await createAccount(db, name: 'USD', currency: Currency.usd);
      await add(-1000);
      await add(-500);
      await add(-200, accountId: usd.id, currency: Currency.usd);
      await add(-999, at: DateTime(2026, 2));
      await add(250000);

      final from = DateTime(2026, 3);
      final to = DateTime(2026, 4);
      final totals = await repository.expensesByCategory(from: from, to: to);
      expect(totals, hasLength(2));
      expect(
        totals.map((t) => t.total),
        containsAll([const Money(1500, Currency.sar), const Money(200, Currency.usd)]),
      );

      final summary = await repository.totals(from: from, to: to);
      expect(summary.income[Currency.sar], const Money(250000, Currency.sar));
      expect(summary.expenses[Currency.sar], const Money(1500, Currency.sar));
    });
  });
}
