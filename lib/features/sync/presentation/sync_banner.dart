import 'package:fintech_wallet/features/sync/presentation/sync_status_cubit.dart';
import 'package:fintech_wallet/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Tells the user whether their changes have reached the server.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final status = context.watch<SyncStatusCubit>().state;

    final (icon, text, background, foreground) = switch (status) {
      SyncIndicator(online: false, :final pending) => (
        Icons.cloud_off_outlined,
        l10n.offlinePending(pending),
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      SyncIndicator(:final pending) when pending > 0 => (
        Icons.cloud_upload_outlined,
        l10n.pendingChanges(pending),
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _ => (Icons.cloud_done_outlined, l10n.allSynced, scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: foreground)),
          ),
          if (status.online && status.pending > 0)
            SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: foreground)),
        ],
      ),
    );
  }
}
