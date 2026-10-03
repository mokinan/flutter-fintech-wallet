import 'package:fintech_wallet/features/auth/presentation/session_cubit.dart';
import 'package:fintech_wallet/features/auth/presentation/widgets/pin_pad.dart';
import 'package:fintech_wallet/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LockPage extends StatefulWidget {
  const LockPage({super.key});

  @override
  State<LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<LockPage> {
  @override
  void initState() {
    super.initState();
    // Offer biometrics immediately; the PIN pad stays as the fallback.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  Future<void> _tryBiometrics() async {
    final session = context.read<SessionCubit>();
    if (session.state case SessionLocked(biometricsEnabled: true)) {
      await session.unlockWithBiometrics(context.l10n.unlockReason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return BlocBuilder<SessionCubit, SessionState>(
      builder: (context, state) {
        final locked = state is SessionLocked ? state : null;
        final attemptsLeft = locked?.attemptsLeft;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.lock_outline, size: 40, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(l10n.lockTitle, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 20,
                      child: attemptsLeft == null
                          ? null
                          : Text(l10n.wrongPin(attemptsLeft), style: TextStyle(color: theme.colorScheme.error)),
                    ),
                    const SizedBox(height: 32),
                    PinPad(
                      onCompleted: context.read<SessionCubit>().unlockWithPin,
                      leading: locked?.biometricsEnabled ?? false
                          ? IconButton(
                              tooltip: l10n.useBiometrics,
                              onPressed: _tryBiometrics,
                              icon: const Icon(Icons.fingerprint, size: 32),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
