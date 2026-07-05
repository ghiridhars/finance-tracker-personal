/// Go Router configuration for Finance Tracker v2.
/// Provides URL-based navigation with deep linking support.
///
/// Routes:
///   /                    → Dashboard
///   /import              → Import Data (upload + directory)
///   /accounts            → Accounts & Statements
///   /settings            → Settings
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/app_shell.dart';
import 'screens/calendar_screen.dart';
import 'widgets/dashboard_widget.dart';
import 'screens/import_screen.dart';
import 'widgets/accounts_widget.dart';
import 'screens/settings_screen.dart';
import 'screens/review_screen.dart';
import 'screens/investments_screen.dart';

/// Route path constants for type-safe navigation.
class AppRoutes {
  static const dashboard = '/';
  static const calendar = '/calendar';
  static const upload = '/upload';
  static const import_ = '/import';
  static const accounts = '/accounts';
  static const settings = '/settings';
  static const review = '/review';
  static const investments = '/investments';
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
    label: 'Calendar',
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month,
    path: AppRoutes.calendar,
  ),
  NavDestination(
    label: 'Investments',
    icon: Icons.stacked_line_chart_outlined,
    selectedIcon: Icons.stacked_line_chart,
    path: AppRoutes.investments,
  ),
  NavDestination(
    label: 'Import',
    icon: Icons.publish_outlined,
    selectedIcon: Icons.publish,
    path: AppRoutes.import_,
  ),
  NavDestination(
    label: 'Accounts',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    path: AppRoutes.accounts,
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
          path: AppRoutes.calendar,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: CalendarScreen(),
          ),
        ),

        GoRoute(
          path: AppRoutes.import_,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ImportScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.investments,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: InvestmentsScreen(),
          ),
        ),
        // Legacy redirect: /upload → /import
        GoRoute(
          path: AppRoutes.upload,
          redirect: (_, __) => AppRoutes.import_,
        ),
        GoRoute(
          path: AppRoutes.accounts,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: AccountsWidget(),
          ),
        ),
        GoRoute(
          path: AppRoutes.settings,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
        GoRoute(
          path: AppRoutes.review,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ReviewScreen(),
          ),
        ),
      ],
    ),
  ],
);
