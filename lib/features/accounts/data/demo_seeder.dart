import 'dart:math';

import 'package:drift/drift.dart';
import 'package:fintech_wallet/core/database/app_database.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:uuid/uuid.dart';

/// Fills an empty database with three months of realistic history, as if it
/// had been downloaded from the server (so it is already marked synced).
class DemoSeeder {
  DemoSeeder(this._db, {DateTime Function()? clock, int seed = 7})
    : _clock = clock ?? DateTime.now,
      _random = Random(seed);

  final AppDatabase _db;
  final DateTime Function() _clock;
  final Random _random;
  final _uuid = const Uuid();

  Future<void> seedIfEmpty() async {
    if (await (_db.select(_db.accounts)..limit(1)).getSingleOrNull() != null) return;
    final now = _clock();
    final start = DateTime(now.year, now.month - 2);

    final accounts = [
      _account('Main bank account', AccountType.bank, 'SAR', 1250000, start),
      _account('Cash wallet', AccountType.cash, 'SAR', 150000, start.add(const Duration(seconds: 1))),
      _account('Credit card', AccountType.card, 'SAR', 0, start.add(const Duration(seconds: 2))),
      _account('USD savings', AccountType.savings, 'USD', 520000, start.add(const Duration(seconds: 3))),
      _account('Kuwait account', AccountType.bank, 'KWD', 450000, start.add(const Duration(seconds: 4))),
    ];

    final rows = <TransactionsCompanion>[];
    final balances = {for (final a in accounts) a.id.value: a.openingBalanceMinor.value};
    void add(
      AccountsCompanion account,
      int minor,
      TransactionCategory category,
      String note,
      DateTime at, {
      String? transferId,
    }) {
      balances[account.id.value] = balances[account.id.value]! + minor;
      rows.add(
        TransactionsCompanion.insert(
          id: _uuid.v4(),
          accountId: account.id.value,
          amountMinor: minor,
          currency: account.currency.value,
          category: category.name,
          note: Value(note),
          occurredAt: at,
          transferId: Value(transferId),
          syncStatus: SyncStatus.synced,
          createdAt: at,
        ),
      );
    }

    final bank = accounts[0];
    final cash = accounts[1];
    final card = accounts[2];
    final usd = accounts[3];
    final kwd = accounts[4];

    final recurring = [
      (27, bank, 1850000, TransactionCategory.salary, 'Monthly salary', 9),
      (1, bank, -450000, TransactionCategory.bills, 'Rent', 10),
      (5, card, -29900, TransactionCategory.bills, 'Mobile & internet', 12),
      (20, kwd, -35500, TransactionCategory.bills, 'Utilities', 11),
    ];

    const expenses = [
      (TransactionCategory.groceries, 'Weekly groceries', 18000, 42000),
      (TransactionCategory.dining, 'Dinner out', 9000, 26000),
      (TransactionCategory.dining, 'Coffee', 1600, 3200),
      (TransactionCategory.transport, 'Fuel', 9000, 15000),
      (TransactionCategory.transport, 'Ride to office', 2400, 5500),
      (TransactionCategory.shopping, 'Clothes', 15000, 60000),
      (TransactionCategory.health, 'Pharmacy', 4000, 12000),
      (TransactionCategory.entertainment, 'Cinema tickets', 7000, 12000),
    ];

    for (
      var day = DateTime(start.year, start.month, start.day);
      day.isBefore(now);
      day = day.add(const Duration(days: 1))
    ) {
      for (final (dayOfMonth, account, minor, category, note, hour) in recurring) {
        if (day.day == dayOfMonth) add(account, minor, category, note, day.add(Duration(hours: hour)));
      }
      // Pay off the credit card from the bank account each month.
      final cardDebt = -balances[card.id.value]!;
      if (day.day == 25 && cardDebt > 0) {
        final transferId = _uuid.v4();
        final at = day.add(const Duration(hours: 18));
        add(bank, -cardDebt, TransactionCategory.transfer, 'Credit card payment', at, transferId: transferId);
        add(card, cardDebt, TransactionCategory.transfer, 'Credit card payment', at, transferId: transferId);
      }
      if (day.day == 15 && day.month.isEven) {
        add(usd, 120000, TransactionCategory.freelance, 'Freelance project', day.add(const Duration(hours: 16)));
      }

      final count = _random.nextInt(3);
      for (var i = 0; i < count; i++) {
        final (category, note, min, max) = expenses[_random.nextInt(expenses.length)];
        final amount = min + _random.nextInt(max - min) ~/ 100 * 100;
        var account = [bank, card, card, cash][_random.nextInt(4)];
        // Respect the same rule as the app: only cards may go negative.
        if (account.type.value != AccountType.card && balances[account.id.value]! < amount) account = card;
        final at = day.add(Duration(hours: 8 + _random.nextInt(13), minutes: _random.nextInt(60)));
        if (at.isAfter(now)) continue;
        add(account, -amount, category, note, at);
      }
    }

    await _db.batch((b) {
      b
        ..insertAll(_db.accounts, accounts)
        ..insertAll(_db.transactions, rows);
    });
  }

  AccountsCompanion _account(String name, AccountType type, String currency, int opening, DateTime createdAt) =>
      AccountsCompanion.insert(
        id: _uuid.v4(),
        name: name,
        type: type,
        currency: currency,
        openingBalanceMinor: Value(opening),
        createdAt: createdAt,
      );
}
