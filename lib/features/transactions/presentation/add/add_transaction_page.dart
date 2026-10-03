import 'package:fintech_wallet/app/di.dart';
import 'package:fintech_wallet/app/theme.dart';
import 'package:fintech_wallet/core/presentation/form_status.dart';
import 'package:fintech_wallet/features/accounts/domain/account.dart';
import 'package:fintech_wallet/features/accounts/domain/accounts_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:fintech_wallet/features/transactions/presentation/add/add_transaction_cubit.dart';
import 'package:fintech_wallet/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

class AddTransactionPage extends StatelessWidget {
  const AddTransactionPage({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Account>>(
    stream: getIt<AccountsRepository>().watchAccounts(),
    builder: (context, snapshot) {
      final accounts = snapshot.data;
      if (accounts == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return BlocProvider(
        create: (_) => AddTransactionCubit(getIt<TransactionsRepository>(), initialAccount: accounts.firstOrNull),
        child: AddTransactionView(accounts: accounts),
      );
    },
  );
}

class AddTransactionView extends StatelessWidget {
  const AddTransactionView({required this.accounts, super.key});

  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<AddTransactionCubit>();

    return BlocConsumer<AddTransactionCubit, AddTransactionState>(
      listenWhen: (a, b) => a.status != b.status || a.failure != b.failure,
      listener: (context, state) {
        if (state.status == FormStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.transactionSaved)));
          context.pop();
        } else if (state.failure != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.failureMessage(state.failure!))));
        }
      },
      builder: (context, state) {
        final account = state.account;
        final categories = state.isIncome ? TransactionCategory.incomes : TransactionCategory.expenses;

        return Scaffold(
          appBar: AppBar(title: Text(l10n.addTransaction)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(l10n.expense), icon: const Icon(Icons.arrow_upward)),
                  ButtonSegment(value: true, label: Text(l10n.income), icon: const Icon(Icons.arrow_downward)),
                ],
                selected: {state.isIncome},
                onSelectionChanged: (v) => cubit.typeChanged(isIncome: v.first),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('amount'),
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: cubit.amountChanged,
                style: Theme.of(context).textTheme.headlineSmall,
                decoration: InputDecoration(
                  labelText: l10n.amountLabel,
                  suffixText: account?.currency.code,
                  errorText: state.showErrors && state.amount == null && account != null
                      ? l10n.errorAmountInvalid(account.currency.decimals)
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: account?.id,
                decoration: InputDecoration(labelText: l10n.accountLabel),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(value: a.id, child: Text('${a.name} · ${a.currency.code}')),
                ],
                onChanged: (id) => cubit.accountChanged(accounts.firstWhere((a) => a.id == id)),
              ),
              const SizedBox(height: 16),
              Text(l10n.categoryLabel, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in categories)
                    ChoiceChip(
                      avatar: Icon(c.icon, size: 18, color: c.color),
                      label: Text(l10n.category(c)),
                      selected: state.category == c,
                      onSelected: (_) => cubit.categoryChanged(c),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: cubit.noteChanged,
                maxLength: 80,
                decoration: InputDecoration(labelText: l10n.noteLabel),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(l10n.dateLabel),
                trailing: Text(DateFormat.yMMMd(context.localeName).format(state.occurredAt)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: state.occurredAt,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    final now = DateTime.now();
                    cubit.dateChanged(DateTime(picked.year, picked.month, picked.day, now.hour, now.minute));
                  }
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('save'),
                onPressed: state.status == FormStatus.submitting ? null : cubit.submit,
                child: Text(l10n.save),
              ),
            ],
          ),
        );
      },
    );
  }
}
