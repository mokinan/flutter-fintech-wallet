import 'package:drift/drift.dart';
import 'package:fintech_wallet/core/database/app_database.dart';
import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/core/result/failure.dart';
import 'package:fintech_wallet/core/result/result.dart';
import 'package:fintech_wallet/features/accounts/domain/account.dart';
import 'package:fintech_wallet/features/accounts/domain/accounts_repository.dart';
import 'package:uuid/uuid.dart';

class LocalAccountsRepository implements AccountsRepository {
  LocalAccountsRepository(this._db, {Uuid uuid = const Uuid(), DateTime Function()? clock})
    : _uuid = uuid,
      _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _clock;

  // Balance is derived, never stored: it cannot drift out of sync with the
  // transactions it is computed from.
  static const _balancesSql = '''
    SELECT a.id, a.name, a.type, a.currency,
           a.opening_balance_minor + COALESCE(SUM(t.amount_minor), 0) AS balance
    FROM accounts a
    LEFT JOIN transactions t ON t.account_id = a.id
    WHERE (?1 IS NULL OR a.id = ?1)
    GROUP BY a.id
    ORDER BY a.created_at, a.id
  ''';

  Selectable<Account> _query([String? id]) => _db
      .customSelect(_balancesSql, variables: [Variable<String>(id)], readsFrom: {_db.accounts, _db.transactions})
      .map(
        (row) => Account(
          id: row.read<String>('id'),
          name: row.read<String>('name'),
          type: AccountType.values[row.read<int>('type')],
          balance: Money(row.read<int>('balance'), Currency.fromCode(row.read<String>('currency'))),
        ),
      );

  @override
  Stream<List<Account>> watchAccounts() => _query().watch();

  @override
  Future<Account?> findById(String id) => _query(id).getSingleOrNull();

  @override
  Future<Result<Account>> create({
    required String name,
    required AccountType type,
    required Money openingBalance,
  }) async {
    final id = _uuid.v4();
    try {
      await _db
          .into(_db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: id,
              name: name.trim(),
              type: type,
              currency: openingBalance.currency.code,
              openingBalanceMinor: Value(openingBalance.minorUnits),
              createdAt: _clock(),
            ),
          );
      return Ok(Account(id: id, name: name.trim(), type: type, balance: openingBalance));
    } on Exception catch (e) {
      return Err(StorageFailure('$e'));
    }
  }
}
