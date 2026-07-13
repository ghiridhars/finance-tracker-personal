/// Widget test — verifies app renders with Riverpod ProviderScope + GoRouter.
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:finance_tracker_frontend/main.dart';
import 'package:finance_tracker_frontend/services/auth_service.dart';

class MockAuthNotifier extends Notifier<AuthState> implements AuthNotifier {
  @override
  AuthState build() => const AuthState(isLoading: false, token: 'mock-token', username: 'tester');

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> register(String username, String password) async {}

  @override
  Future<void> logout() async {}
}

void main() {
  testWidgets('App renders and shows navigation', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(MockAuthNotifier.new),
        ],
        child: const FinanceTrackerApp(),
      ),
    );

    // Allow GoRouter to resolve its initial route and the shell to build.
    // We cannot use pumpAndSettle because the dashboard shimmer has an infinite animation.
    for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byIcon(Icons.dashboard).evaluate().isNotEmpty) {
          break;
        }
    }

    // The app should render a MaterialApp with navigation destinations.
    // On wide screens we get a NavigationRail, on narrow a NavigationBar.
    // Either way, the dashboard icon should be present.
    expect(find.byIcon(Icons.dashboard), findsWidgets);
  });
}
