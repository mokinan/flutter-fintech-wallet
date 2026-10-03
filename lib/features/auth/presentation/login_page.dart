import 'package:fintech_wallet/app/di.dart';
import 'package:fintech_wallet/core/network/fake_backend/fake_wallet_server.dart';
import 'package:fintech_wallet/features/auth/data/auth_repository.dart';
import 'package:fintech_wallet/features/auth/presentation/login_cubit.dart';
import 'package:fintech_wallet/features/auth/presentation/session_cubit.dart';
import 'package:fintech_wallet/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => LoginCubit(getIt<AuthRepository>(), context.read<SessionCubit>()),
    child: const _LoginView(),
  );
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<LoginCubit>().submit(email: _email.text, password: _password.text);
  }

  void _fillDemo() {
    _email.text = FakeWalletServer.demoEmail;
    _password.text = FakeWalletServer.demoPassword;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final reason = switch (context.watch<SessionCubit>().state) {
      SessionSignedOut(reason: SignOutReason.sessionExpired) => l10n.sessionExpiredMessage,
      SessionSignedOut(reason: SignOutReason.tooManyPinAttempts) => l10n.tooManyAttemptsMessage,
      _ => null,
    };
    final login = context.watch<LoginCubit>().state;
    final message = login.failure != null ? l10n.failureMessage(login.failure!) : reason;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.account_balance_wallet_rounded, size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 24),
                    Text(l10n.loginTitle, style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(l10n.loginSubtitle, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: l10n.emailLabel),
                      validator: (v) => _emailPattern.hasMatch(v?.trim() ?? '') ? null : l10n.errorEmailInvalid,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(labelText: l10n.passwordLabel),
                      validator: (v) => (v ?? '').isEmpty ? l10n.errorPasswordRequired : null,
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        message,
                        style: TextStyle(color: theme.colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: login.submitting ? null : _submit,
                      child: login.submitting
                          ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : Text(l10n.signIn),
                    ),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _fillDemo, child: Text(l10n.useDemoAccount)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
