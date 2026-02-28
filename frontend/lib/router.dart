/// Go Router configuration for Finance Tracker v2.
/// Provides URL-based navigation with deep linking support.
///
/// Routes:
///   /                    → Dashboard
///   /upload              → Statement Upload
///   /transactions        → All Transactions (unified)
///   /accounts            → Accounts & Statements
///   /budget              → Budget & Goals
///   /savings             → Savings Transactions
///   /credit-card         → Credit Card Transactions
///   /settings            → Settings
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/app_shell.dart';
import 'widgets/dashboard_widget.dart';
import 'widgets/statement_upload_widget.dart';
import 'widgets/unified_transaction_list_widget.dart';
import 'widgets/transaction_list_widget.dart';
import 'widgets/accounts_widget.dart';
import 'widgets/budget_goals_widget.dart';
import 'screens/settings_screen.dart';

/// Route path constants for type-safe navigation.
class AppRoutes {
  static const dashboard = '/';
  static const upload = '/upload';
  static const transactions = '/transactions';
  static const accounts = '/accounts';
  static const budget = '/budget';
  static const savings = '/savings';
  static const creditCard = '/credit-card';
  static const settings = '/settings';
}

/// Navigation destination metadata used by both the shell and router.
class NavDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;

  const NavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
  });
}

/// All navigation destinations in order.
const List<NavDestination> navDestinations = [
  NavDestination(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    path: AppRoutes.dashboard,
  ),
  NavDestination(
    label: 'Upload',
    icon: Icons.upload_file_outlined,
    selectedIcon: Icons.upload_file,
    path: AppRoutes.upload,
  ),
  NavDestination(
    label: 'Transactions',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    path: AppRoutes.transactions,
  ),
  NavDestination(
    label: 'Accounts',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    path: AppRoutes.accounts,
  ),
  NavDestination(
    label: 'Budget & Goals',
    icon: Icons.savings_outlined,
    selectedIcon: Icons.savings,
    path: AppRoutes.budget,
  ),
  NavDestination(
    label: 'Savings',
    icon: Icons.account_balance_outlined,
    selectedIcon: Icons.account_balance,
    path: AppRoutes.savings,
  ),
  NavDestination(
    label: 'Credit Card',
    icon: Icons.credit_card_outlined,
    selectedIcon: Icons.credit_card,
    path: AppRoutes.creditCard,
  ),
  NavDestination(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    path: AppRoutes.settings,
  ),
];

/// Build the [GoRouter] with a ShellRoute for the responsive app shell.
final GoRouter router = GoRouter(
  initialLocation: AppRoutes.dashboard,
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: AppRoutes.dashboard,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DashboardScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.upload,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: StatementUploadWidget(),
          ),
        ),
        GoRoute(
          path: AppRoutes.transactions,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: UnifiedTransactionListWidget(),
          ),
        ),
        GoRoute(
          path: AppRoutes.accounts,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: AccountsWidget(),
          ),
        ),
        GoRoute(
          path: AppRoutes.budget,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: BudgetGoalsWidget(),
          ),
        ),
        GoRoute(
          path: AppRoutes.savings,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TransactionListWidget(type: TransactionViewType.savings),
          ),
        ),
        GoRoute(
          path: AppRoutes.creditCard,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TransactionListWidget(type: TransactionViewType.creditCard),
          ),
        ),
        GoRoute(
          path: AppRoutes.settings,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
      ],
    ),
  ],
);
