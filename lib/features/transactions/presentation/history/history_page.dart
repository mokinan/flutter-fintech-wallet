import 'package:fintech_wallet/app/di.dart';
import 'package:fintech_wallet/core/money/money_format.dart';
import 'package:fintech_wallet/features/accounts/domain/account.dart';
import 'package:fintech_wallet/features/accounts/domain/accounts_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:fintech_wallet/features/transactions/presentation/history/history_bloc.dart';
import 'package:fintech_wallet/features/transactions/presentation/widgets/transaction_tile.dart';
import 'package:fintech_wallet/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => HistoryBloc(getIt<TransactionsRepository>())..add(const HistoryStarted()),
    child: StreamBuilder<List<Account>>(
      stream: getIt<AccountsRepository>().watchAccounts(),
      builder: (context, snapshot) => _HistoryView(accounts: snapshot.data ?? const []),
    ),
  );
}

class _HistoryView extends StatefulWidget {
  const _HistoryView({required this.accounts});

  final List<Account> accounts;

  @override
  State<_HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<_HistoryView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) context.read<HistoryBloc>().add(const HistoryNextPageRequested());
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(WalletTransaction transaction) async {
    final l10n = context.l10n;
    final bloc = context.read<HistoryBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                MoneyFormat.format(transaction.amount, context.localeName, signed: true),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                [
                  l10n.category(transaction.category),
                  DateFormat.yMMMd(context.localeName).format(transaction.occurredAt),
                ].join(' · '),
                textAlign: TextAlign.center,
              ),
              if (transaction.isTransfer) ...[
                const SizedBox(height: 16),
                Text(l10n.deleteTransferHint, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.deleteTransaction),
              ),
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
            ],
          ),
        ),
      ),
    );
    if (confirmed ?? false) {
      bloc.add(HistoryDeleteRequested(transaction));
      messenger.showSnackBar(SnackBar(content: Text(l10n.transactionDeleted)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<HistoryBloc>().state;
    final names = {for (final a in widget.accounts) a.id: a.name};

    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => context.read<HistoryBloc>().add(HistorySearchChanged(v)),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.searchNotes,
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final (kind, label) in [
                  (TransactionKind.all, l10n.filterAll),
                  (TransactionKind.expense, l10n.filterExpense),
                  (TransactionKind.income, l10n.filterIncome),
                  (TransactionKind.transfer, l10n.filterTransfer),
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: state.query.kind == kind,
                      onSelected: (_) => context.read<HistoryBloc>().add(HistoryKindChanged(kind)),
                    ),
                  ),
                _AccountFilter(accounts: widget.accounts, selected: state.query.accountId),
              ],
            ),
          ),
          Expanded(
            child: switch (state.status) {
              HistoryStatus.loading when state.items.isEmpty => const Center(child: CircularProgressIndicator()),
              HistoryStatus.failure => Center(
                child: TextButton(
                  onPressed: () => context.read<HistoryBloc>().add(const HistoryStarted()),
                  child: Text(l10n.retry),
                ),
              ),
              _ when state.items.isEmpty => Center(child: Text(l10n.noTransactions)),
              _ => ListView.builder(
                controller: _scroll,
                itemCount: state.items.length + (state.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == state.items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final tx = state.items[index];
                  final showHeader = index == 0 || !_sameDay(state.items[index - 1].occurredAt, tx.occurredAt);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showHeader) _DayHeader(date: tx.occurredAt),
                      TransactionTile(
                        transaction: tx,
                        accountName: names[tx.accountId],
                        showDate: false,
                        onTap: () => _confirmDelete(tx),
                      ),
                    ],
                  );
                },
              ),
            },
          ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

class _AccountFilter extends StatelessWidget {
  const _AccountFilter({required this.accounts, required this.selected});

  final List<Account> accounts;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = accounts.where((a) => a.id == selected).firstOrNull?.name ?? l10n.allAccounts;
    return PopupMenuButton<String?>(
      onSelected: (id) => context.read<HistoryBloc>().add(HistoryAccountChanged(id)),
      itemBuilder: (_) => [
        PopupMenuItem(child: Text(l10n.allAccounts)),
        for (final a in accounts) PopupMenuItem(value: a.id, child: Text(a.name)),
      ],
      child: Chip(
        avatar: const Icon(Icons.account_balance_wallet_outlined, size: 18),
        label: Text(name),
        deleteIcon: const Icon(Icons.arrow_drop_down),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final label = switch (today.difference(day).inDays) {
      0 => l10n.today,
      1 => l10n.yesterday,
      _ => DateFormat.yMMMMEEEEd(context.localeName).format(date),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
