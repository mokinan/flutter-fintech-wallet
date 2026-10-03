import 'package:fintech_wallet/app/di.dart';
import 'package:fintech_wallet/app/router.dart';
import 'package:fintech_wallet/app/theme.dart';
import 'package:fintech_wallet/app/widgets/privacy_guard.dart';
import 'package:fintech_wallet/core/network/connectivity_service.dart';
import 'package:fintech_wallet/features/auth/presentation/session_cubit.dart';
import 'package:fintech_wallet/features/settings/presentation/settings_cubit.dart';
import 'package:fintech_wallet/features/sync/data/sync_engine.dart';
import 'package:fintech_wallet/features/sync/presentation/sync_status_cubit.dart';
import 'package:fintech_wallet/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

class WalletApp extends StatefulWidget {
  const WalletApp({super.key});

  @override
  State<WalletApp> createState() => _WalletAppState();
}

class _WalletAppState extends State<WalletApp> {
  late final SessionCubit _session = getIt<SessionCubit>();
  late final GoRouter _router = createRouter(_session);
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _session.appBackgrounded, onShow: _session.appResumed);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _session),
        BlocProvider.value(value: getIt<SettingsCubit>()),
        BlocProvider(create: (_) => SyncStatusCubit(getIt<SyncEngine>(), getIt<ConnectivityService>())),
      ],
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, settings) => MaterialApp.router(
          onGenerateTitle: (context) => context.l10n.appTitle,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: settings.themeMode,
          locale: settings.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: _router,
          builder: (context, child) => PrivacyGuard(child: child!),
        ),
      ),
    );
  }
}
