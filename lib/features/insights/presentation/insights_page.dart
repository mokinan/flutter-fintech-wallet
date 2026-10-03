import 'package:fintech_wallet/app/di.dart';
import 'package:fintech_wallet/app/theme.dart';
import 'package:fintech_wallet/core/money/money.dart';
import 'package:fintech_wallet/core/money/money_format.dart';
import 'package:fintech_wallet/features/insights/presentation/insights_cubit.dart';
import 'package:fintech_wallet/features/rates/data/rates_repository.dart';
import 'package:fintech_wallet/features/transactions/domain/transactions_repository.dart';
import 'package:fintech_wallet/l10n/l10n.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;

class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => InsightsCubit(getIt<TransactionsRepository>(), getIt<RatesRepository>())..load(),
    child: const _InsightsView(),
  );
}

class _InsightsView extends StatelessWidget {
  const _InsightsView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<InsightsCubit>();
    final state = context.watch<InsightsCubit>().state;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.insightsTitle)),
      body: RefreshIndicator(
        onRefresh: cubit.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: cubit.previousMonth,
                  icon: const Icon(Icons.chevron_left),
                  tooltip: MaterialLocalizations.of(context).previousMonthTooltip,
                ),
                Expanded(
                  child: Text(
                    DateFormat.yMMMM(context.localeName).format(state.month),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: cubit.canGoForward ? cubit.nextMonth : null,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: MaterialLocalizations.of(context).nextMonthTooltip,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (state.loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _StatCard(label: l10n.income, amount: state.income, color: theme.colorScheme.positive),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatCard(
                      label: l10n.expensesLabel,
                      amount: state.expenses,
                      color: theme.colorScheme.negative,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatCard(label: l10n.netLabel, amount: state.net),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(l10n.spendingByCategory, style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              if (state.slices.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text(l10n.noSpending)),
                )
              else ...[
                SizedBox(
                  height: 220,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 56,
                      sections: [
                        for (final s in state.slices)
                          PieChartSectionData(
                            value: s.amount.minorUnits.toDouble(),
                            color: s.category.color,
                            radius: 44,
                            title: s.share >= 0.08 ? '${(s.share * 100).round()}%' : '',
                            titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                for (final s in state.slices)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: s.category.color.withValues(alpha: 0.14),
                      foregroundColor: s.category.color,
                      child: Icon(s.category.icon, size: 20),
                    ),
                    title: Text(l10n.category(s.category)),
                    subtitle: LinearProgressIndicator(
                      value: s.share,
                      color: s.category.color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    trailing: Text(MoneyFormat.format(s.amount, context.localeName), textDirection: TextDirection.ltr),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.amount, this.color});

  final String label;
  final Money? amount;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = amount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value == null ? '—' : MoneyFormat.format(value, context.localeName),
                textDirection: TextDirection.ltr,
                style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
