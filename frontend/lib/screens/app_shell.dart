// Responsive App Shell — delegates navigation to AppSidebar.
//
// Breakpoints:
//   ≥ 1100px  → Expanded sidebar (240px, labels + sections)
//   700–1099  → Compact sidebar (72px, icons + tooltips)
//   < 700     → Bottom NavigationBar (4 CORE items + "More" button)
//
// Sidebar expand state persists via SharedPreferences.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_settings_provider.dart';
import '../providers/accounts_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/investment_rule_provider.dart';
import '../providers/transactions_provider.dart';
import '../providers/upi_provider.dart';
import '../router.dart';
import '../widgets/sidebar/app_sidebar.dart';

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _isRefreshing = false;
  bool _isSidebarExpanded = true;

  // Mobile bottom nav: first 4 CORE items + "More"
  static const int _mobileNavCount = 4;

  // Per-route refresh label (shown in snackbar)
  static const Map<String, String> _routeLabels = {
    AppRoutes.dashboard:           'Dashboard',
    AppRoutes.calendar:            'Calendar',
    AppRoutes.investments:         'Investments',
    AppRoutes.accounts:            'Accounts',
    AppRoutes.settings:            'Settings',
    AppRoutes.review:              'Review',
    AppRoutes.import_:             'Import',
    AppRoutes.upiDirectory:        'UPI Directory',
    AppRoutes.classificationRules: 'Rules',
  };

  @override
  void initState() {
    super.initState();
    _loadSidebarPreference();
  }

  Future<void> _loadSidebarPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isSidebarExpanded = prefs.getBool('sidebar_expanded') ?? true;
      });
    }
  }

  Future<void> _toggleSidebar() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isSidebarExpanded = !_isSidebarExpanded);
    await prefs.setBool('sidebar_expanded', _isSidebarExpanded);
  }

  String _currentPath(BuildContext context) =>
      GoRouterState.of(context).uri.path;

  /// Returns which mobile bottom-bar tab is active (0-3 = CORE items, 4 = More).
  int _mobileIndex(BuildContext context) {
    final path = _currentPath(context);
    final coreItems = navDestinations
        .where((d) => d.group == NavGroup.core)
        .take(_mobileNavCount)
        .toList();
    for (int i = 0; i < coreItems.length; i++) {
      final d = coreItems[i];
      final active = d.path == '/' ? path == '/' : path.startsWith(d.path);
      if (active) return i;
    }
    return 4; // "More" tab is active
  }

  Future<void> _refreshCurrentPage(BuildContext context) async {
    if (_isRefreshing) return;
    final path = _currentPath(context);
    setState(() => _isRefreshing = true);
    try {
      ref.invalidate(needsReviewCountProvider);
      switch (path) {
        case AppRoutes.dashboard:
          await Future.wait<dynamic>([
            ref.read(dashboardProvider.notifier).loadDashboard(),
            ref.read(categoriesProvider.notifier).loadCategories(),
          ]);
        case AppRoutes.calendar:
          await ref.read(dashboardProvider.notifier).loadDashboard();
        case AppRoutes.investments:
          ref.invalidate(investmentRuleProvider);
          await ref.read(dashboardProvider.notifier).loadDashboard();
        case AppRoutes.accounts:
          await Future.wait<dynamic>([
            ref.read(accountsProvider.notifier).loadAccounts(),
            ref.read(unifiedTransactionsProvider.notifier).loadTransactions(),
          ]);
        case AppRoutes.settings:
          await Future.wait<dynamic>([
            ref.read(categoriesProvider.notifier).loadCategories(),
            ref.read(upiProvider.notifier).loadUpiIds(),
          ]);
        case AppRoutes.review:
        case AppRoutes.import_:
          break; // managed internally
        default:
          await Future.wait<dynamic>([
            ref.read(dashboardProvider.notifier).loadDashboard(),
            ref.read(accountsProvider.notifier).loadAccounts(),
            ref.read(categoriesProvider.notifier).loadCategories(),
          ]);
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
        final label = _routeLabels[path] ?? 'Page';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label refreshed'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // ── Desktop (≥1100) / Tablet (700-1099) ──────────────
        if (width >= 700) {
          final forceCompact = width < 1100;
          final compact = forceCompact || !_isSidebarExpanded;

          return Scaffold(
            body: Row(
              children: [
                AppSidebar(
                  compact: compact,
                  // Only show collapse toggle on wide desktop
                  onToggleExpanded: forceCompact ? null : _toggleSidebar,
                ),
                Expanded(
                  child: Scaffold(
                    appBar: _DesktopAppBar(
                      isRefreshing: _isRefreshing,
                      onRefresh: () => _refreshCurrentPage(context),
                      routeLabels: _routeLabels,
                    ),
                    body: widget.child,
                  ),
                ),
              ],
            ),
          );
        }

        // ── Mobile (<700) ─────────────────────────────────────
        final coreItems = navDestinations
            .where((d) => d.group == NavGroup.core)
            .take(_mobileNavCount)
            .toList();
        final mobileIdx = _mobileIndex(context);

        return Scaffold(
          appBar: _MobileAppBar(
            isRefreshing: _isRefreshing,
            onRefresh: () => _refreshCurrentPage(context),
            routeLabels: _routeLabels,
          ),
          body: widget.child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: mobileIdx > _mobileNavCount - 1 ? 0 : mobileIdx,
            onDestinationSelected: (i) {
              if (i < _mobileNavCount) {
                context.go(coreItems[i].path);
              } else {
                showMoreSheet(context);
              }
            },
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            destinations: [
              ...coreItems.map(
                (d) => NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
              ),
              const NavigationDestination(
                icon: Icon(Icons.more_horiz_outlined),
                selectedIcon: Icon(Icons.more_horiz),
                label: 'More',
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Desktop AppBar — minimal, transparent
// ─────────────────────────────────────────────

class _DesktopAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final bool isRefreshing;
  final VoidCallback onRefresh;
  final Map<String, String> routeLabels;

  const _DesktopAppBar({
    required this.isRefreshing,
    required this.onRefresh,
    required this.routeLabels,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final title = routeLabels[path] ?? '';

    return AppBar(
      title: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      actions: [
        IconButton(
          icon: isRefreshing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: isRefreshing ? 'Refreshing…' : 'Refresh ${routeLabels[path] ?? "Page"}',
          onPressed: isRefreshing ? null : onRefresh,
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Mobile AppBar
// ─────────────────────────────────────────────

class _MobileAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final bool isRefreshing;
  final VoidCallback onRefresh;
  final Map<String, String> routeLabels;

  const _MobileAppBar({
    required this.isRefreshing,
    required this.onRefresh,
    required this.routeLabels,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final title = routeLabels[path] ?? '';
    final settings = ref.watch(appSettingsProvider);

    final themeIcon = switch (settings.themeMode) {
      ThemeMode.system => Icons.brightness_auto,
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
    };

    return AppBar(
      title: Text(title),
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      actions: [
        IconButton(
          icon: isRefreshing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: isRefreshing ? 'Refreshing…' : 'Refresh',
          onPressed: isRefreshing ? null : onRefresh,
        ),
        IconButton(
          icon: Icon(themeIcon),
          tooltip: 'Toggle theme',
          onPressed: () => ref.read(appSettingsProvider.notifier).toggleTheme(),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
