import 'package:equatable/equatable.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/core/presentation/form_status.dart';
import 'package:fintech_wallet/core/result/failure.dart';
import 'package:fintech_wallet/core/result/result.dart';
import 'package:fintech_wallet/features/accounts/domain/account.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AddTransactionState extends Equatable {
  const AddTransactionState({
    required this.occurredAt,
    this.isIncome = false,
    this.account,
    this.category = TransactionCategory.groceries,
    this.amountText = '',
    this.note = '',
    this.status = FormStatus.editing,
    this.showErrors = false,
    this.failure,
  });

  final bool isIncome;
  final Account? account;
  final TransactionCategory category;
  final String amountText;
  final String note;
  final DateTime occurredAt;
  final FormStatus status;

  /// Errors are shown only after the first submit attempt.
  final bool showErrors;
  final Failure? failure;

  /// Parsed in the account currency; `null` when invalid or non-positive.
  Money? get amount {
    final selected = account;
    if (selected == null) return null;
    final parsed = Money.tryParse(amountText, selected.currency);
    return parsed != null && parsed.isPositive ? parsed : null;
  }

  bool get isValid => account != null && amount != null;

  AddTransactionState copyWith({
    bool? isIncome,
    Account? account,
    TransactionCategory? category,
    String? amountText,
    String? note,
    DateTime? occurredAt,
    FormStatus? status,
    bool? showErrors,
    Failure? Function()? failure,
  }) => AddTransactionState(
    isIncome: isIncome ?? this.isIncome,
    account: account ?? this.account,
    category: category ?? this.category,
    amountText: amountText ?? this.amountText,
    note: note ?? this.note,
    occurredAt: occurredAt ?? this.occurredAt,
    status: status ?? this.status,
    showErrors: showErrors ?? this.showErrors,
    failure: failure != null ? failure() : this.failure,
  );

  @override
  List<Object?> get props => [isIncome, account, category, amountText, note, occurredAt, status, showErrors, failure];
}

class AddTransactionCubit extends Cubit<AddTransactionState> {
  AddTransactionCubit(this._repository, {DateTime Function()? clock, Account? initialAccount})
    : super(AddTransactionState(occurredAt: (clock ?? DateTime.now)(), account: initialAccount));

  final TransactionsRepository _repository;

  void typeChanged({required bool isIncome}) => emit(
    state.copyWith(
      isIncome: isIncome,
      category: isIncome ? TransactionCategory.incomes.first : TransactionCategory.expenses.first,
    ),
  );

  void accountChanged(Account account) => emit(state.copyWith(account: account));
  void categoryChanged(TransactionCategory category) => emit(state.copyWith(category: category));
  void amountChanged(String text) => emit(state.copyWith(amountText: text, failure: () => null));
  void noteChanged(String note) => emit(state.copyWith(note: note));
  void dateChanged(DateTime date) => emit(state.copyWith(occurredAt: date));

  Future<void> submit() async {
    if (state.status == FormStatus.submitting) return;
    if (!state.isValid) return emit(state.copyWith(showErrors: true));

    emit(state.copyWith(status: FormStatus.submitting, showErrors: true, failure: () => null));
    final amount = state.amount!;
    final result = await _repository.add(
      accountId: state.account!.id,
      amount: state.isIncome ? amount : -amount,
      category: state.category,
      note: state.note,
      occurredAt: state.occurredAt,
    );
    emit(switch (result) {
      Ok() => state.copyWith(status: FormStatus.success),
      Err(:final failure) => state.copyWith(status: FormStatus.editing, failure: () => failure),
    });
  }
}
