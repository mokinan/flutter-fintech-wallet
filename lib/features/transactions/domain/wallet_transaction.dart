import 'package:equatable/equatable.dart';
import 'package:fintech_wallet/core/database/tables.dart';
import 'package:fintech_wallet/core/money/money.dart';

export 'package:fintech_wallet/core/database/tables.dart' show SyncStatus;

enum TransactionCategory {
  groceries,
  dining,
  transport,
  shopping,
  bills,
  health,
  entertainment,
  salary,
  freelance,
  transfer,
  other;

  bool get isIncome => this == salary || this == freelance;

  static List<TransactionCategory> get expenses => values.where((c) => !c.isIncome && c != transfer).toList();
  static List<TransactionCategory> get incomes => values.where((c) => c.isIncome).toList();

  static TransactionCategory parse(String name) => values.firstWhere((c) => c.name == name, orElse: () => other);
}

class WalletTransaction extends Equatable {
  const WalletTransaction({
    required this.id,
    required this.accountId,
    required this.amount,
    required this.category,
    required this.note,
    required this.occurredAt,
    required this.syncStatus,
    this.transferId,
  });

  final String id;
  final String accountId;

  /// Negative for money leaving the account.
  final Money amount;
  final TransactionCategory category;
  final String note;
  final DateTime occurredAt;
  final SyncStatus syncStatus;
  final String? transferId;

  bool get isTransfer => transferId != null;

  @override
  List<Object?> get props => [id, accountId, amount, category, note, occurredAt, syncStatus, transferId];
}
