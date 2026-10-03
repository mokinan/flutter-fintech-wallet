import 'package:equatable/equatable.dart';
import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/features/rates/data/rates_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

typedef CategorySlice = ({TransactionCategory category, Money amount, double share});

class InsightsState extends Equatable {
  const InsightsState({required this.month, this.loading = true, this.income, this.expenses, this.slices = const []});

  /// First day of the month being shown.
  final DateTime month;
  final bool loading;
  final Money? income;
  final Money? expenses;

  /// Sorted by amount, largest first.
  final List<CategorySlice> slices;

  Money? get net => income != null && expenses != null ? income! - expenses! : null;

  @override
  List<Object?> get props => [month, loading, income, expenses, slices];
}

/// Monthly income, expenses and category split, converted to the base
/// currency so accounts in different currencies can be compared.
class InsightsCubit extends Cubit<InsightsState> {
  InsightsCubit(this._transactions, this._rates, {DateTime Function()? clock, this.baseCurrency = Currency.sar})
    : _clock = clock ?? DateTime.now,
      super(InsightsState(month: _firstOfMonth((clock ?? DateTime.now)())));

  final TransactionsRepository _transactions;
  final RatesRepository _rates;
  final DateTime Function() _clock;
  final Currency baseCurrency;

  bool get canGoForward => state.month.isBefore(_firstOfMonth(_clock()));

  Future<void> load() => _load(state.month);
  Future<void> previousMonth() => _load(DateTime(state.month.year, state.month.month - 1));
  Future<void> nextMonth() => canGoForward ? _load(DateTime(state.month.year, state.month.month + 1)) : Future.value();

  Future<void> _load(DateTime month) async {
    emit(InsightsState(month: month));
    final to = DateTime(month.year, month.month + 1);
    final rates = (await _rates.rates()).valueOrNull;
    final byCategory = await _transactions.expensesByCategory(from: month, to: to);
    final totals = await _transactions.totals(from: month, to: to);
    if (isClosed) return;
    if (rates == null) return emit(InsightsState(month: month, loading: false));

    final perCategory = <TransactionCategory, Money>{};
    for (final entry in byCategory) {
      final converted = rates.convert(entry.total, baseCurrency);
      perCategory.update(entry.category, (sum) => sum + converted, ifAbsent: () => converted);
    }
    final expenses = rates.total(totals.expenses.values, baseCurrency);
    final slices = [
      for (final e in perCategory.entries)
        (category: e.key, amount: e.value, share: expenses.isZero ? 0.0 : e.value.minorUnits / expenses.minorUnits),
    ]..sort((a, b) => b.amount.compareTo(a.amount));

    emit(
      InsightsState(
        month: month,
        loading: false,
        income: rates.total(totals.income.values, baseCurrency),
        expenses: expenses,
        slices: slices,
      ),
    );
  }

  static DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month);
}
