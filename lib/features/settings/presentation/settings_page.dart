import 'package:fintech_wallet/app/di.dart';
import 'package:fintech_wallet/core/network/fake_backend/fake_wallet_server.dart';
import 'package:fintech_wallet/core/network/fake_backend/network_conditions.dart';
import 'package:fintech_wallet/core/security/biometric_auth.dart';
import 'package:fintech_wallet/features/auth/presentation/session_cubit.dart';
import 'package:fintech_wallet/features/settings/presentation/settings_cubit.dart';
import 'package:fintech_wallet/features/sync/presentation/sync_status_cubit.dart';
import 'package:fintech_wallet/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final NetworkConditions _conditions = getIt<NetworkConditions>();
  final BiometricAuth _biometrics = getIt<BiometricAuth>();
  bool? _biometricsEnabled;
  bool _biometricsAvailable = false;

  @override
  void initState() {
    super.initState();
    Future.wait([_biometrics.isAvailable(), _biometrics.isEnabled()]).then((r) {
      if (mounted) {
        setState(() {
          _biometricsAvailable = r[0];
          _biometricsEnabled = r[1];
        });
      }
    });
  }

  Future<void> _signOut() async {
    final l10n = context.l10n;
    final session = context.read<SessionCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.signOut),
        content: Text(l10n.signOutConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.signOut)),
        ],
      ),
    );
    if (confirmed ?? false) await session.logout();
  }

  void _expireTokens() {
    getIt<FakeWalletServer>().expireAccessTokens();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.tokenExpired)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = context.watch<SettingsCubit>();
    final theme = Theme.of(context);

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          header(l10n.appearance),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l10n.language),
            trailing: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'en', label: Text('EN')),
                ButtonSegment(value: 'ar', label: Text('ع')),
              ],
              selected: {settings.state.locale?.languageCode ?? Localizations.localeOf(context).languageCode},
              onSelectionChanged: (v) => settings.setLocale(Locale(v.first)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: Text(l10n.theme),
            trailing: DropdownButton<ThemeMode>(
              value: settings.state.themeMode,
              underline: const SizedBox.shrink(),
              onChanged: (m) => settings.setThemeMode(m!),
              items: [
                DropdownMenuItem(value: ThemeMode.system, child: Text(l10n.themeSystem)),
                DropdownMenuItem(value: ThemeMode.light, child: Text(l10n.themeLight)),
                DropdownMenuItem(value: ThemeMode.dark, child: Text(l10n.themeDark)),
              ],
            ),
          ),
          header(l10n.security),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: Text(l10n.biometricUnlock),
            value: _biometricsEnabled ?? false,
            onChanged: _biometricsAvailable
                ? (v) async {
                    await _biometrics.setEnabled(enabled: v);
                    setState(() => _biometricsEnabled = v);
                  }
                : null,
          ),
          header(l10n.developerTools),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l10n.developerToolsHint, style: theme.textTheme.bodySmall),
          ),
          ValueListenableBuilder(
            valueListenable: _conditions.offline,
            builder: (_, offline, _) => SwitchListTile(
              secondary: const Icon(Icons.cloud_off_outlined),
              title: Text(l10n.simulateOffline),
              subtitle: Text(l10n.simulateOfflineHint),
              value: offline,
              onChanged: (v) => _conditions.offline.value = v,
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.network_check),
            title: Text(l10n.flakyNetwork),
            subtitle: Text(l10n.flakyNetworkHint),
            value: _conditions.failureRate > 0,
            onChanged: (v) => setState(() => _conditions.failureRate = v ? 0.3 : 0),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.call_missed_outgoing),
            title: Text(l10n.lostResponses),
            subtitle: Text(l10n.lostResponsesHint),
            value: _conditions.dropResponseRate > 0,
            onChanged: (v) => setState(() => _conditions.dropResponseRate = v ? 0.5 : 0),
          ),
          ListTile(
            leading: const Icon(Icons.key_off_outlined),
            title: Text(l10n.expireToken),
            subtitle: Text(l10n.expireTokenHint),
            onTap: _expireTokens,
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: Text(l10n.syncNow),
            onTap: () => context.read<SyncStatusCubit>().syncNow(),
          ),
          const Divider(height: 32),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(l10n.signOut, style: TextStyle(color: theme.colorScheme.error)),
            onTap: _signOut,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
