/// Finance Tracker v2 — Flutter Web Frontend
/// Replaces: React frontend (App.tsx, main.tsx)
///
/// Architecture: Material Design 3, Riverpod state management, go_router navigation
library;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router.dart';
import 'theme.dart';
import 'providers/app_settings_provider.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const ProviderScope(child: FinanceTrackerApp()));
}

class FinanceTrackerApp extends ConsumerWidget {
  const FinanceTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final authState = ref.watch(authProvider);

    return MaterialApp.router(
      title: 'Finance Tracker v2',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: settings.themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Show loading spinner while checking auth state
        if (authState.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // Show login screen if not authenticated
        if (!authState.isAuthenticated) {
          return Overlay(
            initialEntries: [
              OverlayEntry(builder: (_) => const LoginScreen()),
            ],
          );
        }
        // Show app content
        return child!;
      },
    );
  }
}
