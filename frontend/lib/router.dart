/// Go Router configuration for Finance Tracker v2.
/// Provides URL-based navigation with deep linking support.
///
/// Routes:
///   /                    → Dashboard
///   /import              → Import Data (upload + directory)
///   /accounts            → Accounts & Statements
///   /settings            → Settings
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/app_shell.dart';
import 'screens/calendar_screen.dart';
import 'widgets/dashboard_widget.dart';
import 'screens/import_screen.dart';
import 'widgets/accounts_widget.dart';
import 'screens/account_detail_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/review_screen.dart';
import 'screens/investments_screen.dart';
import 'screens/upi_directory_screen.dart';
import 'screens/classification_rules_screen.dart';

/// Route path constants for type-safe navigation.
class AppRoutes {
  static const dashboard = '/';
  static const calendar = '/calendar';
  static const upload = '/upload';
  static const import_ = '/import';
  static const accounts = '/accounts';
  static const accountNew = '/accounts/new';
  static const accountDetail = '/accounts/:id';
  static const settings = '/settings';
  static const review = '/review';
  static const investments = '/investments';
  static const upiDirectory = '/upi-directory';
  static const classificationRules = '/classification-rules';
}

/// Navigation group — controls visual section in the sidebar.
enum NavGroup { core, manage, tools }

/// Navigation destination metadata used by both the shell and router.
class NavDestination {
  final String label;
  final String description;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
  final NavGroup group;

  const NavDestination({
    required this.label,
    required this.description,
    required this.icon,
    required this.selectedIcon,
    required this.path,
    required this.group,
  });
}

/// All navigation destinations in order.
/// Grouped as: CORE (daily use), MANAGE (import), TOOLS (config).
const List<NavDestination> navDestinations = [
  // ── CORE ──────────────────────────────────────────────────
  NavDestination(
    label: 'Dashboard',
    description: 'Net worth, spending overview and recent transactions',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    path: AppRoutes.dashboard,
    group: NavGroup.core,
  ),
  NavDestination(
    label: 'Review',
    description: 'Categorise and confirm pending transactions',
    icon: Icons.rate_review_outlined,
    selectedIcon: Icons.rate_review,
    path: AppRoutes.review,
    group: NavGroup.core,
  ),
  NavDestination(
    label: 'Calendar',
    description: 'Browse transactions by date and month',
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month,
    path: AppRoutes.calendar,
    group: NavGroup.core,
  ),
  NavDestination(
    label: 'Investments',
    description: 'Portfolio performance and holdings',
    icon: Icons.stacked_line_chart_outlined,
    selectedIcon: Icons.stacked_line_chart,
    path: AppRoutes.investments,
    group: NavGroup.core,
  ),
  NavDestination(
    label: 'Accounts',
    description: 'Bank accounts, statements and balances',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    path: AppRoutes.accounts,
    group: NavGroup.core,
  ),
  // ── MANAGE ────────────────────────────────────────────────
  NavDestination(
    label: 'Import',
    description: 'Upload bank statement PDFs for automatic parsing',
    icon: Icons.upload_file_outlined,
    selectedIcon: Icons.upload_file,
    path: AppRoutes.import_,
    group: NavGroup.manage,
  ),
  // ── TOOLS ─────────────────────────────────────────────────
  NavDestination(
    label: 'Rules',
    description: 'Auto-classify transactions by keyword or merchant',
    icon: Icons.rule_outlined,
    selectedIcon: Icons.rule,
    path: AppRoutes.classificationRules,
    group: NavGroup.tools,
  ),
  NavDestination(
    label: 'UPI Directory',
    description: 'Map UPI handles to contacts and bank accounts',
    icon: Icons.contacts_outlined,
    selectedIcon: Icons.contacts,
    path: AppRoutes.upiDirectory,
    group: NavGroup.tools,
  ),
  NavDestination(
    label: 'Settings',
    description: 'App preferences, theme and data management',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    path: AppRoutes.settings,
    group: NavGroup.tools,
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
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: DashboardScreen()),
        ),
        GoRoute(
          path: AppRoutes.calendar,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: CalendarScreen()),
        ),

        GoRoute(
          path: AppRoutes.import_,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ImportScreen()),
        ),
        GoRoute(
          path: AppRoutes.investments,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: InvestmentsScreen()),
        ),
        // Legacy redirect: /upload → /import
        GoRoute(path: AppRoutes.upload, redirect: (_, __) => AppRoutes.import_),
        GoRoute(
          path: AppRoutes.accounts,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: AccountsWidget()),
        ),
        GoRoute(
          path: AppRoutes.accountNew,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: AccountDetailScreen(accountId: null),
          ),
        ),
        GoRoute(
          path: AppRoutes.accountDetail,
          pageBuilder: (context, state) {
            final idParam = state.pathParameters['id'];
            final id = idParam != null ? int.tryParse(idParam) : null;
            return NoTransitionPage(child: AccountDetailScreen(accountId: id));
          },
        ),
        GoRoute(
          path: AppRoutes.settings,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SettingsScreen()),
        ),
        GoRoute(
          path: AppRoutes.review,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ReviewScreen()),
        ),
        GoRoute(
          path: AppRoutes.upiDirectory,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: UpiDirectoryScreen()),
        ),
        GoRoute(
          path: AppRoutes.classificationRules,
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ClassificationRulesScreen()),
        ),
      ],
    ),
  ],
);
