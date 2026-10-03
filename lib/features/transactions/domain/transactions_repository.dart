import 'package:equatable/equatable.dart';
import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/core/result/result.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';

enum TransactionKind { all, income, expense, transfer }

/// Filters for the history screen.
class TransactionQuery extends Equatable {
  const TransactionQuery({this.accountId, this.kind = TransactionKind.all, this.search = ''});

  final String? accountId;
  final TransactionKind kind;
  final String search;

  TransactionQuery copyWith({String? Function()? accountId, TransactionKind? kind, String? search}) => TransactionQuery(
    accountId: accountId != null ? accountId() : this.accountId,
    kind: kind ?? this.kind,
    search: search ?? this.search,
  );

  @override
  List<Object?> get props => [accountId, kind, search];
}

/// Position after the last item of a page — keyset pagination stays correct
/// while new transactions are inserted, unlike offset pagination.
class PageCursor extends Equatable {
  const PageCursor(this.occurredAt, this.id);

  final DateTime occurredAt;
  final String id;

  @override
  List<Object> get props => [occurredAt, id];
}

class TransactionPage {
  const TransactionPage(this.items, this.next);

  final List<WalletTransaction> items;

  /// `null` when there are no more pages.
  final PageCursor? next;
}

/// Spending in one category and currency over a period.
typedef CategoryTotal = ({TransactionCategory category, Money total});

abstract interface class TransactionsRepository {
  Future<TransactionPage> page(TransactionQuery query, {PageCursor? after, int limit = 20});

  /// Emits on any change to transactions, so lists can refresh.
  Stream<void> watchChanges();

  Future<Result<WalletTransaction>> add({
    required String accountId,
    required Money amount,
    required TransactionCategory category,
    required String note,
    required DateTime occurredAt,
  });

  /// Moves money between two accounts atomically. [received] is in the
  /// destination currency (equal to [sent] when currencies match).
  Future<Result<void>> transfer({
    required String fromAccountId,
    required String toAccountId,
    required Money sent,
    required Money received,
    required String note,
  });

  Future<Result<void>> delete(WalletTransaction transaction);

  /// Expense totals per category since [from], grouped by currency.
  Future<List<CategoryTotal>> expensesByCategory({required DateTime from, required DateTime to});

  /// Total income and expenses since [from], grouped by currency.
  Future<({Map<Currency, Money> income, Map<Currency, Money> expenses})> totals({
    required DateTime from,
    required DateTime to,
  });
}
