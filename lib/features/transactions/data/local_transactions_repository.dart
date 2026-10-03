import 'package:drift/drift.dart';
import 'package:fintech_wallet/core/database/app_database.dart';
import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/core/result/failure.dart';
import 'package:fintech_wallet/core/result/result.dart';
import 'package:fintech_wallet/features/sync/data/outbox_writer.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:uuid/uuid.dart';

/// Writes go to the local database first and are queued for sync in the same
/// database transaction (ADR 0002, ADR 0003).
class LocalTransactionsRepository implements TransactionsRepository {
  LocalTransactionsRepository(this._db, this._outbox, {Uuid uuid = const Uuid(), DateTime Function()? clock})
    : _uuid = uuid,
      _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final OutboxWriter _outbox;
  final Uuid _uuid;
  final DateTime Function() _clock;

  @override
  Future<TransactionPage> page(TransactionQuery query, {PageCursor? after, int limit = 20}) async {
    final t = _db.transactions;
    final select = _db.select(t)
      ..where((row) {
        final conditions = <Expression<bool>>[
          if (query.accountId != null) row.accountId.equals(query.accountId!),
          ...switch (query.kind) {
            TransactionKind.all => const <Expression<bool>>[],
            TransactionKind.income => [row.amountMinor.isBiggerThanValue(0), row.transferId.isNull()],
            TransactionKind.expense => [row.amountMinor.isSmallerThanValue(0), row.transferId.isNull()],
            TransactionKind.transfer => [row.transferId.isNotNull()],
          },
          if (query.search.trim().isNotEmpty)
            row.note.lower().like('%${_escapeLike(query.search.trim().toLowerCase())}%', escapeChar: r'\'),
          if (after != null)
            row.occurredAt.isSmallerThanValue(after.occurredAt) |
                (row.occurredAt.equals(after.occurredAt) & row.id.isSmallerThanValue(after.id)),
        ];
        return conditions.isEmpty ? const Constant(true) : Expression.and(conditions);
      })
      ..orderBy([(row) => OrderingTerm.desc(row.occurredAt), (row) => OrderingTerm.desc(row.id)])
      // Fetch one extra row to know whether another page exists.
      ..limit(limit + 1);

    final rows = await select.get();
    final hasMore = rows.length > limit;
    final items = rows.take(limit).map(_toDomain).toList();
    return TransactionPage(items, hasMore ? PageCursor(items.last.occurredAt, items.last.id) : null);
  }

  @override
  Stream<void> watchChanges() => _db.tableUpdates(TableUpdateQuery.onTable(_db.transactions));

  @override
  Future<Result<WalletTransaction>> add({
    required String accountId,
    required Money amount,
    required TransactionCategory category,
    required String note,
    required DateTime occurredAt,
  }) async {
    if (amount.isZero) return const Err(ValidationFailure('zero_amount'));
    try {
      return await _db.transaction(() async {
        final account = await _account(accountId);
        if (account == null) return const Err(ValidationFailure('unknown_account'));
        if (amount.currency.code != account.currency) return const Err(ValidationFailure('currency_mismatch'));
        if (amount.isNegative && !await _canSpend(account, -amount.minorUnits)) {
          return const Err(InsufficientFundsFailure());
        }

        final row = TransactionsCompanion.insert(
          id: _uuid.v4(),
          accountId: accountId,
          amountMinor: amount.minorUnits,
          currency: amount.currency.code,
          category: category.name,
          note: Value(note.trim()),
          occurredAt: occurredAt,
          syncStatus: SyncStatus.pending,
          createdAt: _clock(),
        );
        await _db.into(_db.transactions).insert(row);
        await _outbox.enqueue(
          operation: OutboxOperation.createTransaction,
          payload: _payload(row),
          recordIds: [row.id.value],
        );
        return Ok(_toDomain(await (_db.select(_db.transactions)..where((t) => t.id.equals(row.id.value))).getSingle()));
      });
    } on Exception catch (e) {
      return Err(StorageFailure('$e'));
    }
  }

  @override
  Future<Result<void>> transfer({
    required String fromAccountId,
    required String toAccountId,
    required Money sent,
    required Money received,
    required String note,
  }) async {
    if (fromAccountId == toAccountId) return const Err(ValidationFailure('same_account'));
    if (!sent.isPositive || !received.isPositive) return const Err(ValidationFailure('invalid_amount'));
    try {
      return await _db.transaction(() async {
        final from = await _account(fromAccountId);
        final to = await _account(toAccountId);
        if (from == null || to == null) return const Err(ValidationFailure('unknown_account'));
        if (sent.currency.code != from.currency || received.currency.code != to.currency) {
          return const Err(ValidationFailure('currency_mismatch'));
        }
        if (!await _canSpend(from, sent.minorUnits)) return const Err(InsufficientFundsFailure());

        final transferId = _uuid.v4();
        final now = _clock();
        TransactionsCompanion leg(String accountId, Money amount) => TransactionsCompanion.insert(
          id: _uuid.v4(),
          accountId: accountId,
          amountMinor: amount.minorUnits,
          currency: amount.currency.code,
          category: TransactionCategory.transfer.name,
          note: Value(note.trim()),
          occurredAt: now,
          transferId: Value(transferId),
          syncStatus: SyncStatus.pending,
          createdAt: now,
        );
        final out = leg(fromAccountId, -sent);
        final into = leg(toAccountId, received);
        await _db.batch((b) => b.insertAll(_db.transactions, [out, into]));
        await _outbox.enqueue(
          operation: OutboxOperation.createTransfer,
          payload: {'transferId': transferId, 'from': _payload(out), 'to': _payload(into)},
          recordIds: [out.id.value, into.id.value],
        );
        return const Ok(null);
      });
    } on Exception catch (e) {
      return Err(StorageFailure('$e'));
    }
  }

  @override
  Future<Result<void>> delete(WalletTransaction transaction) async {
    try {
      await _db.transaction(() async {
        final ids = transaction.transferId == null
            ? [transaction.id]
            : await (_db.selectOnly(_db.transactions)
                    ..addColumns([_db.transactions.id])
                    ..where(_db.transactions.transferId.equals(transaction.transferId!)))
                  .map((r) => r.read(_db.transactions.id)!)
                  .get();

        // If the create was never attempted, the server has never seen it:
        // drop it from the queue instead of sending create + delete. Once an
        // attempt was made the outcome is unknown (the response may have been
        // lost), so a delete must follow.
        final unsent = await (_db.select(
          _db.outbox,
        )..where((o) => o.attempts.equals(0) & o.recordIds.like('%"${ids.first}"%'))).getSingleOrNull();

        await (_db.delete(_db.transactions)..where((t) => t.id.isIn(ids))).go();
        if (unsent != null) {
          await (_db.delete(_db.outbox)..where((o) => o.id.equals(unsent.id))).go();
        } else {
          for (final id in ids) {
            await _outbox.enqueue(
              operation: OutboxOperation.deleteTransaction,
              payload: {'id': id},
              recordIds: const [],
            );
          }
        }
      });
      return const Ok(null);
    } on Exception catch (e) {
      return Err(StorageFailure('$e'));
    }
  }

  @override
  Future<List<CategoryTotal>> expensesByCategory({required DateTime from, required DateTime to}) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT category, currency, SUM(amount_minor) AS total
          FROM transactions
          WHERE amount_minor < 0 AND transfer_id IS NULL AND occurred_at >= ?1 AND occurred_at < ?2
          GROUP BY category, currency
          ''',
          variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
          readsFrom: {_db.transactions},
        )
        .get();
    return [
      for (final row in rows)
        (
          category: TransactionCategory.parse(row.read<String>('category')),
          total: Money(-row.read<int>('total'), Currency.fromCode(row.read<String>('currency'))),
        ),
    ];
  }

  @override
  Future<({Map<Currency, Money> income, Map<Currency, Money> expenses})> totals({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT currency,
                 SUM(CASE WHEN amount_minor > 0 THEN amount_minor ELSE 0 END) AS income,
                 SUM(CASE WHEN amount_minor < 0 THEN -amount_minor ELSE 0 END) AS expenses
          FROM transactions
          WHERE transfer_id IS NULL AND occurred_at >= ?1 AND occurred_at < ?2
          GROUP BY currency
          ''',
          variables: [Variable<DateTime>(from), Variable<DateTime>(to)],
          readsFrom: {_db.transactions},
        )
        .get();
    final income = <Currency, Money>{};
    final expenses = <Currency, Money>{};
    for (final row in rows) {
      final currency = Currency.fromCode(row.read<String>('currency'));
      income[currency] = Money(row.read<int>('income'), currency);
      expenses[currency] = Money(row.read<int>('expenses'), currency);
    }
    return (income: income, expenses: expenses);
  }

  Future<AccountRow?> _account(String id) =>
      (_db.select(_db.accounts)..where((a) => a.id.equals(id))).getSingleOrNull();

  /// Cards may go negative (credit); every other account type may not.
  Future<bool> _canSpend(AccountRow account, int minorUnits) async {
    if (account.type == AccountType.card) return true;
    final sum = _db.transactions.amountMinor.sum();
    final spent =
        await (_db.selectOnly(_db.transactions)
              ..addColumns([sum])
              ..where(_db.transactions.accountId.equals(account.id)))
            .map((r) => r.read(sum) ?? 0)
            .getSingle();
    return account.openingBalanceMinor + spent >= minorUnits;
  }

  Map<String, Object?> _payload(TransactionsCompanion row) => {
    'id': row.id.value,
    'accountId': row.accountId.value,
    'amountMinor': row.amountMinor.value,
    'currency': row.currency.value,
    'category': row.category.value,
    'note': row.note.value,
    'occurredAt': row.occurredAt.value.toUtc().toIso8601String(),
    if (row.transferId.present) 'transferId': row.transferId.value,
  };

  static String _escapeLike(String input) => input.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');

  WalletTransaction _toDomain(TransactionRow row) => WalletTransaction(
    id: row.id,
    accountId: row.accountId,
    amount: Money(row.amountMinor, Currency.fromCode(row.currency)),
    category: TransactionCategory.parse(row.category),
    note: row.note,
    occurredAt: row.occurredAt,
    syncStatus: row.syncStatus,
    transferId: row.transferId,
  );
}
