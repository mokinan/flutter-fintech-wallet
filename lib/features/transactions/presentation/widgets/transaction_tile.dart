import 'package:fintech_wallet/app/theme.dart';
import 'package:fintech_wallet/core/money/money_format.dart';
import 'package:fintech_wallet/features/transactions/domain/wallet_transaction.dart';
import 'package:fintech_wallet/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

class TransactionTile extends StatelessWidget {
  const TransactionTile({required this.transaction, this.accountName, this.onTap, this.showDate = true, super.key});

  final WalletTransaction transaction;
  final String? accountName;
  final VoidCallback? onTap;

  /// Off when the list already groups rows under day headers.
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final category = transaction.category;
    final title = transaction.note.isEmpty ? l10n.category(category) : transaction.note;
    final format = showDate ? DateFormat.MMMd(context.localeName).add_jm() : DateFormat.jm(context.localeName);
    final time = format.format(transaction.occurredAt);
    final subtitle = [l10n.category(category), ?accountName, time].join(' · ');

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: category.color.withValues(alpha: 0.14),
        foregroundColor: category.color,
        child: Icon(category.icon, size: 20),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            MoneyFormat.format(transaction.amount, context.localeName, signed: true),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: transaction.amount.isNegative ? scheme.onSurface : scheme.positive,
            ),
          ),
          if (transaction.syncStatus != SyncStatus.synced) _SyncBadge(status: transaction.syncStatus),
        ],
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final failed = status == SyncStatus.failed;
    final color = failed ? scheme.error : scheme.tertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(failed ? Icons.error_outline : Icons.schedule, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          failed ? l10n.syncFailed : l10n.syncPending,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
