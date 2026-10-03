import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState extends Equatable {
  const SettingsState({this.locale, this.themeMode = ThemeMode.system});

  /// `null` follows the device language.
  final Locale? locale;
  final ThemeMode themeMode;

  @override
  List<Object?> get props => [locale, themeMode];
}

/// Non-sensitive preferences, kept in SharedPreferences.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._prefs)
    : super(
        SettingsState(
          locale: switch (_prefs.getString(_localeKey)) {
            final String code => Locale(code),
            null => null,
          },
          themeMode: ThemeMode.values.asNameMap()[_prefs.getString(_themeKey)] ?? ThemeMode.system,
        ),
      );

  static const _localeKey = 'locale';
  static const _themeKey = 'theme_mode';

  final SharedPreferences _prefs;

  Future<void> setLocale(Locale? locale) async {
    emit(SettingsState(locale: locale, themeMode: state.themeMode));
    locale == null ? await _prefs.remove(_localeKey) : await _prefs.setString(_localeKey, locale.languageCode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    emit(SettingsState(locale: state.locale, themeMode: mode));
    await _prefs.setString(_themeKey, mode.name);
  }
}
