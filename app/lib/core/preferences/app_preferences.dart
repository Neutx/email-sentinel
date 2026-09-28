import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in main() with the real instance (and in tests with a mock).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

/// Device-local UI preferences (not synced to the server).
@immutable
class AppPreferences {
  const AppPreferences({
    this.themeMode = ThemeMode.system,
    this.reduceTransparency = false,
    this.backgroundAlerts = true,
  });

  final ThemeMode themeMode;
  final bool reduceTransparency;
  final bool backgroundAlerts;

  AppPreferences copyWith({
    ThemeMode? themeMode,
    bool? reduceTransparency,
    bool? backgroundAlerts,
  }) => AppPreferences(
    themeMode: themeMode ?? this.themeMode,
    reduceTransparency: reduceTransparency ?? this.reduceTransparency,
    backgroundAlerts: backgroundAlerts ?? this.backgroundAlerts,
  );
}

class AppPreferencesController extends Notifier<AppPreferences> {
  static const _theme = 'pref.themeMode';
  static const _reduce = 'pref.reduceTransparency';
  static const _alerts = 'pref.backgroundAlerts';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppPreferences build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppPreferences(
      themeMode: ThemeMode.values.byName(
        prefs.getString(_theme) ?? ThemeMode.system.name,
      ),
      reduceTransparency: prefs.getBool(_reduce) ?? false,
      backgroundAlerts: prefs.getBool(_alerts) ?? true,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(_theme, mode.name);
  }

  Future<void> setReduceTransparency(bool value) async {
    state = state.copyWith(reduceTransparency: value);
    await _prefs.setBool(_reduce, value);
  }

  Future<void> setBackgroundAlerts(bool value) async {
    state = state.copyWith(backgroundAlerts: value);
    await _prefs.setBool(_alerts, value);
  }
}

final appPreferencesProvider =
    NotifierProvider<AppPreferencesController, AppPreferences>(
      AppPreferencesController.new,
    );

final reduceTransparencyProvider = Provider<bool>(
  (ref) => ref.watch(appPreferencesProvider).reduceTransparency,
);
