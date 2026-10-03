import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/features/accounts/domain/account.dart';
import 'package:fintech_wallet/features/accounts/domain/accounts_repository.dart';
import 'package:fintech_wallet/features/rates/data/rates_repository.dart';
import 'package:fintech_wallet/features/rates/domain/rate_table.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AccountsOverviewState extends Equatable {
  const AccountsOverviewState({this.loading = true, this.accounts = const [], this.recent = const [], this.rates});

  final bool loading;
  final List<Account> accounts;
  final List<WalletTransaction> recent;
  final RateTable? rates;

  /// Sum of all balances in [baseCurrency]; `null` until rates are known.
  Money? get total {
    final table = rates;
    if (table == null || accounts.any((a) => !table.supports(a.currency))) return null;
    return table.total(accounts.map((a) => a.balance), baseCurrency);
  }

  static const Currency baseCurrency = Currency.sar;

  AccountsOverviewState copyWith({
    bool? loading,
    List<Account>? accounts,
    List<WalletTransaction>? recent,
    RateTable? rates,
  }) => AccountsOverviewState(
    loading: loading ?? this.loading,
    accounts: accounts ?? this.accounts,
    recent: recent ?? this.recent,
    rates: rates ?? this.rates,
  );

  @override
  List<Object?> get props => [loading, accounts, recent, rates];
}

class AccountsOverviewCubit extends Cubit<AccountsOverviewState> {
  AccountsOverviewCubit(this._accounts, this._transactions, this._rates) : super(const AccountsOverviewState());

  final AccountsRepository _accounts;
  final TransactionsRepository _transactions;
  final RatesRepository _rates;
  final _subscriptions = <StreamSubscription<Object?>>[];

  Future<void> start() async {
    _subscriptions
      ..add(_accounts.watchAccounts().listen((accounts) => emit(state.copyWith(loading: false, accounts: accounts))))
      ..add(_transactions.watchChanges().listen((_) => unawaited(_loadRecent())));
    await Future.wait([_loadRecent(), refreshRates()]);
  }

  Future<void> refreshRates({bool force = false}) async {
    final result = await _rates.rates(forceRefresh: force);
    final table = result.valueOrNull;
    if (table != null && !isClosed) emit(state.copyWith(rates: table));
  }

  Future<void> _loadRecent() async {
    final page = await _transactions.page(const TransactionQuery(), limit: 5);
    if (!isClosed) emit(state.copyWith(recent: page.items));
  }

  @override
  Future<void> close() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    return super.close();
  }
}
