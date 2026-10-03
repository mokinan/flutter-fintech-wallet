import 'package:fintech_wallet/app/di.dart';
import 'package:fintech_wallet/app/router.dart';
import 'package:fintech_wallet/core/money/money_format.dart';
import 'package:fintech_wallet/features/accounts/domain/account.dart';
import 'package:fintech_wallet/features/accounts/domain/accounts_repository.dart';
import 'package:fintech_wallet/features/accounts/presentation/accounts_overview_cubit.dart';
import 'package:fintech_wallet/features/rates/data/rates_repository.dart';
import 'package:fintech_wallet/features/sync/presentation/sync_banner.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/presentation/widgets/transaction_tile.dart';
import 'package:fintech_wallet/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        AccountsOverviewCubit(getIt<AccountsRepository>(), getIt<TransactionsRepository>(), getIt<RatesRepository>())
          ..start(),
    child: const _HomeView(),
  );
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<AccountsOverviewCubit>().state;
    final names = {for (final a in state.accounts) a.id: a.name};

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.addTransaction),
        icon: const Icon(Icons.add),
        label: Text(l10n.addTransaction),
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<AccountsOverviewCubit>().refreshRates(force: true),
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                children: [
                  _TotalCard(state: state),
                  const SizedBox(height: 12),
                  const SyncBanner(),
                  const SizedBox(height: 24),
                  _SectionHeader(
                    title: l10n.accountsTitle,
                    action: TextButton.icon(
                      onPressed: () => context.push(Routes.transfer),
                      icon: const Icon(Icons.swap_horiz),
                      label: Text(l10n.transfer),
                    ),
                  ),
                  for (final account in state.accounts) ...[
                    _AccountCard(account: account),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 16),
                  _SectionHeader(
                    title: l10n.recentActivity,
                    action: TextButton(onPressed: () => context.go(Routes.history), child: Text(l10n.seeAll)),
                  ),
                  Card(
                    child: Column(
                      children: [
                        for (final tx in state.recent)
                          TransactionTile(transaction: tx, accountName: names[tx.accountId]),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.state});

  final AccountsOverviewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = state.total;
    final rates = state.rates;

    return Card(
      color: scheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.totalBalance,
              style: theme.textTheme.titleSmall?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 8),
            Text(
              total == null ? '—' : MoneyFormat.format(total, context.localeName),
              textDirection: TextDirection.ltr,
              style: theme.textTheme.headlineMedium?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              rates != null && rates.isStale
                  ? l10n.ratesStale(DateFormat.MMMd(context.localeName).add_jm().format(rates.fetchedAt))
                  : l10n.convertedTo(AccountsOverviewState.baseCurrency.code),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account});

  final Account account;

  IconData get _icon => switch (account.type) {
    AccountType.bank => Icons.account_balance_outlined,
    AccountType.cash => Icons.payments_outlined,
    AccountType.card => Icons.credit_card,
    AccountType.savings => Icons.savings_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(_icon, size: 20)),
        title: Text(account.name),
        subtitle: Text(account.currency.code),
        trailing: Text(
          MoneyFormat.format(account.balance, context.localeName),
          textDirection: TextDirection.ltr,
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            color: account.balance.isNegative ? theme.colorScheme.error : null,
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        ?action,
      ],
    ),
  );
}
