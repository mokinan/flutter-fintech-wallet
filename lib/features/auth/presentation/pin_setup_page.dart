import 'package:fintech_wallet/features/auth/presentation/session_cubit.dart';
import 'package:fintech_wallet/features/auth/presentation/widgets/pin_pad.dart';
import 'package:fintech_wallet/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PinSetupPage extends StatefulWidget {
  const PinSetupPage({super.key});

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  String? _first;
  bool _mismatch = false;
  bool _biometrics = true;

  Future<void> _onCompleted(String pin) async {
    if (_first == null) {
      return setState(() {
        _first = pin;
        _mismatch = false;
      });
    }
    if (pin != _first) {
      return setState(() {
        _first = null;
        _mismatch = true;
      });
    }
    final session = context.read<SessionCubit>();
    final available = switch (session.state) {
      SessionNeedsPin(:final biometricsAvailable) => biometricsAvailable,
      _ => false,
    };
    await session.createPin(pin, enableBiometrics: available && _biometrics);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final biometricsAvailable = switch (context.watch<SessionCubit>().state) {
      SessionNeedsPin(:final biometricsAvailable) => biometricsAvailable,
      _ => false,
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(_first == null ? l10n.createPinTitle : l10n.confirmPinTitle, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  _mismatch ? l10n.pinMismatch : l10n.createPinSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(color: _mismatch ? theme.colorScheme.error : null),
                ),
                const SizedBox(height: 40),
                PinPad(onCompleted: _onCompleted),
                if (biometricsAvailable) ...[
                  const SizedBox(height: 24),
                  SwitchListTile(
                    value: _biometrics,
                    onChanged: (v) => setState(() => _biometrics = v),
                    title: Text(l10n.enableBiometrics),
                    secondary: const Icon(Icons.fingerprint),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
