import 'package:flutter/material.dart';

/// Covers the UI whenever the app is not in the foreground, so balances are
/// not visible in the iOS / Android app switcher snapshot.
class PrivacyGuard extends StatefulWidget {
  const PrivacyGuard({required this.child, super.key});

  final Widget child;

  @override
  State<PrivacyGuard> createState() => _PrivacyGuardState();
}

class _PrivacyGuardState extends State<PrivacyGuard> with WidgetsBindingObserver {
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final obscured = state != AppLifecycleState.resumed;
    if (obscured != _obscured) setState(() => _obscured = obscured);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        widget.child,
        if (_obscured)
          Positioned.fill(
            child: ColoredBox(
              color: scheme.primary,
              child: Icon(Icons.account_balance_wallet_rounded, size: 72, color: scheme.onPrimary),
            ),
          ),
      ],
    );
  }
}
