import 'dart:async';

import 'package:fintech_wallet/app/widgets/app_shell.dart';
import 'package:fintech_wallet/features/accounts/presentation/home_page.dart';
import 'package:fintech_wallet/features/auth/presentation/lock_page.dart';
import 'package:fintech_wallet/features/auth/presentation/login_page.dart';
import 'package:fintech_wallet/features/auth/presentation/pin_setup_page.dart';
import 'package:fintech_wallet/features/auth/presentation/session_cubit.dart';
import 'package:fintech_wallet/features/auth/presentation/splash_page.dart';
import 'package:fintech_wallet/features/insights/presentation/insights_page.dart';
import 'package:fintech_wallet/features/settings/presentation/settings_page.dart';
import 'package:fintech_wallet/features/transactions/presentation/add/add_transaction_page.dart';
import 'package:fintech_wallet/features/transactions/presentation/history/history_page.dart';
import 'package:fintech_wallet/features/transfers/presentation/transfer_page.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

abstract final class Routes {
  static const login = '/login';
  static const pinSetup = '/pin-setup';
  static const lock = '/lock';
  static const home = '/home';
  static const history = '/history';
  static const insights = '/insights';
  static const settings = '/settings';
  static const addTransaction = '/add-transaction';
  static const transfer = '/transfer';
  static const splash = '/';
}

/// Navigation is a pure function of [SessionState]: the session decides which
/// part of the app is reachable, screens never push auth routes themselves.
GoRouter createRouter(SessionCubit session) => GoRouter(
  initialLocation: Routes.splash,
  refreshListenable: _StreamListenable(session.stream),
  redirect: (context, state) {
    final location = state.matchedLocation;
    final target = switch (session.state) {
      SessionLoading() => Routes.splash,
      SessionSignedOut() => Routes.login,
      SessionNeedsPin() => Routes.pinSetup,
      SessionLocked() => Routes.lock,
      SessionUnlocked() => null,
    };
    if (target != null) return location == target ? null : target;
    const gated = {Routes.splash, Routes.login, Routes.pinSetup, Routes.lock};
    return gated.contains(location) ? Routes.home : null;
  },
  routes: [
    GoRoute(path: Routes.splash, builder: (_, _) => const SplashPage()),
    GoRoute(path: Routes.login, builder: (_, _) => const LoginPage()),
    GoRoute(path: Routes.pinSetup, builder: (_, _) => const PinSetupPage()),
    GoRoute(path: Routes.lock, builder: (_, _) => const LockPage()),
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomePage())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: Routes.history, builder: (_, _) => const HistoryPage())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: Routes.insights, builder: (_, _) => const InsightsPage())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: Routes.settings, builder: (_, _) => const SettingsPage())],
        ),
      ],
    ),
    GoRoute(path: Routes.addTransaction, builder: (_, _) => const AddTransactionPage()),
    GoRoute(path: Routes.transfer, builder: (_, _) => const TransferPage()),
  ],
);

class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<Object?> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
