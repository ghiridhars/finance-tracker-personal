// Responsive App Shell — adapts layout based on screen width.
//
// Breakpoints:
//   ≥ 900px  → Expanded NavigationRail (sidebar with labels)
//   600–899  → Compact NavigationRail (icons only)
//   < 600    → Bottom NavigationBar (mobile)
//
// The shell wraps all routes via GoRouter ShellRoute.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/app_settings_provider.dart';
import '../providers/accounts_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/transfers_provider.dart';
import '../providers/transactions_provider.dart';
import '../providers/upi_provider.dart';
import '../services/auth_service.dart';
import '../router.dart';

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _isRefreshing = false;
  bool _isSidebarExpanded = true;

  /// Determine which nav index is active based on the current route.
  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    for (int i = 0; i < navDestinations.length; i++) {
      if (navDestinations[i].path == location) return i;
    }
    return 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    context.go(navDestinations[index].path);
  }

  Future<void> _refreshAll() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      ref.invalidate(needsReviewCountProvider);
      
      await Future.wait<dynamic>([
        ref.read(dashboardProvider.notifier).loadDashboard(),
        ref.read(accountsProvider.notifier).loadAccounts(),
        ref.read(categoriesProvider.notifier).loadCategories(),
        ref.read(upiProvider.notifier).loadUpiIds(),
        ref.read(transfersProvider.notifier).loadAll(),
        ref.read(unifiedTransactionsProvider.notifier).loadTransactions(),
      ]);
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data refreshed'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final currentIdx = _currentIndex(context);

        // ── Desktop: expanded/collapsible rail ──
        if (width >= 900) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  extended: _isSidebarExpanded,
                  minExtendedWidth: 220,
                  selectedIndex: currentIdx,
                  onDestinationSelected: (i) =>
                      _onDestinationSelected(context, i),
                  leading: _RailHeader(
                    settings: settings,
                    ref: ref,
                    extended: _isSidebarExpanded,
                    isRefreshing: _isRefreshing,
                    onRefresh: _refreshAll,
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PopupMenuButton<String>(
                              offset: const Offset(40, -40),
                              tooltip: 'Account',
                              onSelected: (val) {
                                if (val == 'logout') {
                                  ref.read(authProvider.notifier).logout();
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'logout',
                                  child: Row(
                                    children: [
                                      Icon(Icons.logout, size: 18),
                                      SizedBox(width: 8),
                                      Text('Sign Out'),
                                    ],
                                  ),
                                ),
                              ],
                              child: CircleAvatar(
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                child: Icon(Icons.person, color: Theme.of(context).colorScheme.onPrimaryContainer),
                              ),
                            ),
                            const SizedBox(height: 16),
                            IconButton(
                              icon: Icon(_isSidebarExpanded
                                  ? Icons.chevron_left
                                  : Icons.chevron_right),
                              onPressed: () {
                                setState(() {
                                  _isSidebarExpanded = !_isSidebarExpanded;
                                });
                              },
                              tooltip: _isSidebarExpanded
                                  ? 'Collapse Sidebar'
                                  : 'Expand Sidebar',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  destinations: navDestinations
                      .map((d) => NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text(navDestinations[currentIdx].label),
                      elevation: 0,
                      backgroundColor: Colors.transparent,
                    ),
                    body: widget.child,
                  ),
                ),
              ],
            ),
          );
        }

        // ── Tablet: compact rail (icons only) ──
        if (width >= 600) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: currentIdx,
                  onDestinationSelected: (i) =>
                      _onDestinationSelected(context, i),
                  labelType: NavigationRailLabelType.selected,
                  leading: _RailHeader(
                    settings: settings,
                    ref: ref,
                    extended: false,
                    isRefreshing: _isRefreshing,
                    onRefresh: _refreshAll,
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: PopupMenuButton<String>(
                          offset: const Offset(40, -40),
                          tooltip: 'Account',
                          onSelected: (val) {
                            if (val == 'logout') {
                              ref.read(authProvider.notifier).logout();
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'logout',
                              child: Row(
                                children: [
                                  Icon(Icons.logout, size: 18),
                                  SizedBox(width: 8),
                                  Text('Sign Out'),
                                ],
                              ),
                            ),
                          ],
                          child: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: Icon(Icons.person, color: Theme.of(context).colorScheme.onPrimaryContainer),
                          ),
                        ),
                      ),
                    ),
                  ),
                  destinations: navDestinations
                      .map((d) => NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text(navDestinations[currentIdx].label),
                      elevation: 0,
                      backgroundColor: Colors.transparent,
                    ),
                    body: widget.child,
                  ),
                ),
              ],
            ),
          );
        }

        // ── Mobile: bottom navigation bar ──
        return Scaffold(
          appBar: AppBar(
            title: Text(navDestinations[currentIdx].label),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: [
              _NeedsReviewBadge(ref: ref),
              _RefreshButton(isRefreshing: _isRefreshing, onRefresh: _refreshAll),
              _ThemeToggleButton(settings: settings, ref: ref),
              const SizedBox(width: 8),
            ],
          ),
          body: widget.child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: currentIdx,
            onDestinationSelected: (i) =>
                _onDestinationSelected(context, i),
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            destinations: navDestinations
                .map((d) => NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: d.label,
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}

/// Rail header — shows app title + theme toggle + refresh button.
class _RailHeader extends StatelessWidget {
  final AppSettings settings;
  final WidgetRef ref;
  final bool extended;
  final bool isRefreshing;
  final VoidCallback onRefresh;

  const _RailHeader({
    required this.settings,
    required this.ref,
    required this.extended,
    required this.isRefreshing,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          if (extended) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.account_balance,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Finance Tracker',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ] else ...[
            Icon(
              Icons.account_balance,
              color: Theme.of(context).colorScheme.primary,
              size: 28,
            ),
            const SizedBox(height: 4),
          ],
          _NeedsReviewBadge(ref: ref),
          _ThemeToggleButton(settings: settings, ref: ref),
          _RefreshButton(isRefreshing: isRefreshing, onRefresh: onRefresh),
          const Divider(),
        ],
      ),
    );
  }
}

/// Refresh button — shows a spinner while data is loading, refresh icon when idle.
class _RefreshButton extends StatelessWidget {
  final bool isRefreshing;
  final VoidCallback onRefresh;

  const _RefreshButton({required this.isRefreshing, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: isRefreshing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
      tooltip: isRefreshing ? 'Refreshing…' : 'Refresh all data',
      onPressed: isRefreshing ? null : onRefresh,
    );
  }
}

/// Theme toggle button reused in rail header and mobile app bar.
class _ThemeToggleButton extends StatelessWidget {
  final AppSettings settings;
  final WidgetRef ref;

  const _ThemeToggleButton({required this.settings, required this.ref});

  IconData _icon(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto,
        ThemeMode.light => Icons.light_mode,
        ThemeMode.dark => Icons.dark_mode,
      };

  String _tooltip(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'Theme: System',
        ThemeMode.light => 'Theme: Light',
        ThemeMode.dark => 'Theme: Dark',
      };

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(_icon(settings.themeMode)),
      tooltip: _tooltip(settings.themeMode),
      onPressed: () => ref.read(appSettingsProvider.notifier).toggleTheme(),
    );
  }
}

/// Needs review badge — navigates to review pane.
class _NeedsReviewBadge extends StatelessWidget {
  final WidgetRef ref;

  const _NeedsReviewBadge({required this.ref});

  @override
  Widget build(BuildContext context) {
    final countAsync = ref.watch(needsReviewCountProvider);
    
    return countAsync.when(
      data: (count) {
        if (count == 0) return const SizedBox.shrink();
        return IconButton(
          icon: Badge(
            label: Text(count.toString()),
            child: const Icon(Icons.notifications),
          ),
          tooltip: '$count transactions need review',
          onPressed: () => context.go('/review'),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
