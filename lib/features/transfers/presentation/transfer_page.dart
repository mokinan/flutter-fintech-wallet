import 'package:fintech_wallet/app/di.dart';
import 'package:fintech_wallet/core/money/currency.dart';
import 'package:fintech_wallet/core/money/money_format.dart';
import 'package:fintech_wallet/core/presentation/form_status.dart';
import 'package:fintech_wallet/features/accounts/domain/account.dart';
import 'package:fintech_wallet/features/accounts/domain/accounts_repository.dart';
import 'package:fintech_wallet/features/rates/data/rates_repository.dart';
import 'package:fintech_wallet/features/rates/domain/rate_table.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:fintech_wallet/features/transfers/presentation/transfer_cubit.dart';
import 'package:fintech_wallet/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show NumberFormat;

class TransferPage extends StatelessWidget {
  const TransferPage({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Account>>(
    stream: getIt<AccountsRepository>().watchAccounts(),
    builder: (context, snapshot) {
      final accounts = snapshot.data;
      if (accounts == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return BlocProvider(
        create: (_) => TransferCubit(
          getIt<TransactionsRepository>(),
          getIt<RatesRepository>(),
          from: accounts.firstOrNull,
          to: accounts.skip(1).firstOrNull,
        )..loadRates(),
        child: _TransferView(accounts: accounts),
      );
    },
  );
}

class _TransferView extends StatelessWidget {
  const _TransferView({required this.accounts});

  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<TransferCubit>();

    return BlocConsumer<TransferCubit, TransferState>(
      listenWhen: (a, b) => a.status != b.status || a.failure != b.failure,
      listener: (context, state) {
        if (state.status == FormStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.transferDone)));
          context.pop();
        } else if (state.failure != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.failureMessage(state.failure!))));
        }
      },
      builder: (context, state) {
        final received = state.received;
        final from = state.from;

        return Scaffold(
          appBar: AppBar(title: Text(l10n.transfer)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _AccountPicker(
                label: l10n.fromAccount,
                accounts: accounts,
                selected: state.from,
                onChanged: cubit.fromChanged,
              ),
              const SizedBox(height: 16),
              _AccountPicker(label: l10n.toAccount, accounts: accounts, selected: state.to, onChanged: cubit.toChanged),
              if (state.sameAccount)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l10n.errorSameAccount, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 16),
              TextField(
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: cubit.amountChanged,
                style: Theme.of(context).textTheme.headlineSmall,
                decoration: InputDecoration(
                  labelText: l10n.amountLabel,
                  suffixText: from?.currency.code,
                  errorText: state.showErrors && state.sent == null && from != null
                      ? l10n.errorAmountInvalid(from.currency.decimals)
                      : null,
                ),
              ),
              if (state.isCrossCurrency) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.recipientReceives, style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 4),
                        Text(
                          received == null ? '—' : MoneyFormat.format(received, context.localeName),
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (state.rates != null && from != null && state.to != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            l10n.exchangeRate(
                              from.currency.code,
                              _formatRate(state.rates!, from.currency, state.to!.currency, context.localeName),
                              state.to!.currency.code,
                            ),
                            textDirection: TextDirection.ltr,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                onChanged: cubit.noteChanged,
                maxLength: 80,
                decoration: InputDecoration(labelText: l10n.noteLabel),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: state.status == FormStatus.submitting ? null : cubit.submit,
                icon: const Icon(Icons.swap_horiz),
                label: Text(l10n.transfer),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Display-only: the exact conversion never goes through this double.
String _formatRate(RateTable rates, Currency from, Currency to, String locale) {
  final rate = rates.rateMicros[from]! / rates.rateMicros[to]!;
  return NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: 4).format(rate);
}

class _AccountPicker extends StatelessWidget {
  const _AccountPicker({required this.label, required this.accounts, required this.selected, required this.onChanged});

  final String label;
  final List<Account> accounts;
  final Account? selected;
  final ValueChanged<Account> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('$label-${selected?.id}'),
    initialValue: selected?.id,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final a in accounts)
        DropdownMenuItem(
          value: a.id,
          child: Text(
            '${a.name} · ${MoneyFormat.format(a.balance, context.localeName)}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (id) => onChanged(accounts.firstWhere((a) => a.id == id)),
  );
}
