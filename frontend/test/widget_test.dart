/// Widget test — verifies app renders with Riverpod ProviderScope.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:finance_tracker_frontend/main.dart';

void main() {
  testWidgets('App renders with title and tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: FinanceTrackerApp()),
    );

    // App title is visible
    expect(find.text('Finance Tracker v2'), findsOneWidget);

    // All three tabs are present
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('Credit Card'), findsOneWidget);

    // Theme toggle button is present
    expect(find.byIcon(Icons.brightness_auto), findsOneWidget);
  });
}
