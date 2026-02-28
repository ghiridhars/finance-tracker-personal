/// Widget test — verifies app renders with Riverpod ProviderScope + GoRouter.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:finance_tracker_frontend/main.dart';

void main() {
  testWidgets('App renders and shows navigation', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: FinanceTrackerApp()),
    );

    // Allow GoRouter to resolve its initial route and the shell to build
    await tester.pumpAndSettle();

    // The app should render a MaterialApp with navigation destinations.
    // On wide screens we get a NavigationRail, on narrow a NavigationBar.
    // Either way, the 'Dashboard' destination should be present (it's the initial route).
    expect(find.text('Dashboard'), findsWidgets);

    // At least one navigation icon should be visible
    expect(find.byIcon(Icons.dashboard), findsOneWidget);
  });
}
