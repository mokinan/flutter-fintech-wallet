import 'package:equatable/equatable.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/core/presentation/form_status.dart';
import 'package:fintech_wallet/core/result/failure.dart';
import 'package:fintech_wallet/core/result/result.dart';
import 'package:fintech_wallet/features/accounts/domain/account.dart';
import 'package:fintech_wallet/features/rates/data/rates_repository.dart';
import 'package:fintech_wallet/features/rates/domain/rate_table.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TransferState extends Equatable {
  const TransferState({
    this.from,
    this.to,
    this.amountText = '',
    this.note = '',
    this.rates,
    this.status = FormStatus.editing,
    this.showErrors = false,
    this.failure,
  });

  final Account? from;
  final Account? to;
  final String amountText;
  final String note;
  final RateTable? rates;
  final FormStatus status;
  final bool showErrors;
  final Failure? failure;

  Money? get sent {
    final account = from;
    if (account == null) return null;
    final parsed = Money.tryParse(amountText, account.currency);
    return parsed != null && parsed.isPositive ? parsed : null;
  }

  /// What the destination account receives, converted if needed.
  Money? get received {
    final amount = sent;
    final destination = to;
    if (amount == null || destination == null) return null;
    if (amount.currency == destination.currency) return amount;
    final table = rates;
    if (table == null || !table.supports(amount.currency) || !table.supports(destination.currency)) return null;
    return table.convert(amount, destination.currency);
  }

  bool get isCrossCurrency => from != null && to != null && from!.currency != to!.currency;
  bool get sameAccount => from != null && from?.id == to?.id;
  bool get isValid => sent != null && received != null && !sameAccount;

  TransferState copyWith({
    Account? from,
    Account? to,
    String? amountText,
    String? note,
    RateTable? rates,
    FormStatus? status,
    bool? showErrors,
    Failure? Function()? failure,
  }) => TransferState(
    from: from ?? this.from,
    to: to ?? this.to,
    amountText: amountText ?? this.amountText,
    note: note ?? this.note,
    rates: rates ?? this.rates,
    status: status ?? this.status,
    showErrors: showErrors ?? this.showErrors,
    failure: failure != null ? failure() : this.failure,
  );

  @override
  List<Object?> get props => [from, to, amountText, note, rates, status, showErrors, failure];
}

class TransferCubit extends Cubit<TransferState> {
  TransferCubit(this._transactions, this._rates, {Account? from, Account? to})
    : super(TransferState(from: from, to: to));

  final TransactionsRepository _transactions;
  final RatesRepository _rates;

  Future<void> loadRates() async {
    final table = (await _rates.rates()).valueOrNull;
    if (table != null && !isClosed) emit(state.copyWith(rates: table));
  }

  void fromChanged(Account account) => emit(state.copyWith(from: account, failure: () => null));
  void toChanged(Account account) => emit(state.copyWith(to: account, failure: () => null));
  void amountChanged(String text) => emit(state.copyWith(amountText: text, failure: () => null));
  void noteChanged(String note) => emit(state.copyWith(note: note));

  Future<void> submit() async {
    if (state.status == FormStatus.submitting) return;
    if (!state.isValid) return emit(state.copyWith(showErrors: true));

    emit(state.copyWith(status: FormStatus.submitting, showErrors: true, failure: () => null));
    final result = await _transactions.transfer(
      fromAccountId: state.from!.id,
      toAccountId: state.to!.id,
      sent: state.sent!,
      received: state.received!,
      note: state.note,
    );
    emit(switch (result) {
      Ok() => state.copyWith(status: FormStatus.success),
      Err(:final failure) => state.copyWith(status: FormStatus.editing, failure: () => failure),
    });
  }
}
