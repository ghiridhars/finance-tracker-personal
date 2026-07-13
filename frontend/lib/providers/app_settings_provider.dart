/// AppSettingsNotifier — manages theme mode and user preferences.
/// Persists settings to shared_preferences.
library;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

/// State class holding app-wide settings.
class AppSettings {
  final ThemeMode themeMode;
  final String baseUrl;
  final String currency;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.baseUrl = 'http://127.0.0.1:8080',
    this.currency = '₹',
  });

  AppSettings copyWith({ThemeMode? themeMode, String? baseUrl, String? currency}) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      baseUrl: baseUrl ?? this.baseUrl,
      currency: currency ?? this.currency,
    );
  }
}

/// Notifier that manages app settings and persists them.
class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _themeKey = 'theme_mode';
  static const _baseUrlKey = 'base_url';
  static const _currencyKey = 'currency';

  @override
  AppSettings build() {
    _loadFromPrefs();
    return const AppSettings();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey);
    final baseUrl = prefs.getString(_baseUrlKey);
    final currency = prefs.getString(_currencyKey);

    final resolvedUrl = baseUrl ?? 'http://127.0.0.1:8080';

    // Sync base URL into ApiService on load
    ApiService.setBaseUrl(resolvedUrl);

    state = AppSettings(
      themeMode: themeIndex != null
          ? ThemeMode.values[themeIndex]
          : ThemeMode.system,
      baseUrl: resolvedUrl,
      currency: currency ?? '₹',
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
  }

  /// Cycle through: system → light → dark → system
  Future<void> toggleTheme() async {
    final next = switch (state.themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setThemeMode(next);
  }

  Future<void> setBaseUrl(String url) async {
    // Sync into ApiService immediately
    ApiService.setBaseUrl(url);
    state = state.copyWith(baseUrl: url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url);
  }

  Future<void> setCurrency(String symbol) async {
    state = state.copyWith(currency: symbol);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currencyKey, symbol);
  }
}

/// Provider for app settings.
final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(AppSettingsNotifier.new);
