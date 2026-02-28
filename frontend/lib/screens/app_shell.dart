/// Responsive App Shell — adapts layout based on screen width.
///
/// Breakpoints:
///   ≥ 900px  → Expanded NavigationRail (sidebar with labels)
///   600–899  → Compact NavigationRail (icons only)
///   < 600    → Bottom NavigationBar (mobile)
///
/// The shell wraps all routes via GoRouter ShellRoute.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/app_settings_provider.dart';
import '../router.dart';

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final currentIdx = _currentIndex(context);

        // ── Desktop: expanded rail (sidebar with labels) ──
        if (width >= 900) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  extended: true,
                  minExtendedWidth: 220,
                  selectedIndex: currentIdx,
                  onDestinationSelected: (i) =>
                      _onDestinationSelected(context, i),
                  leading: _RailHeader(settings: settings, ref: ref, extended: true),
                  destinations: navDestinations
                      .map((d) => NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: child),
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
                  leading: _RailHeader(settings: settings, ref: ref, extended: false),
                  destinations: navDestinations
                      .map((d) => NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: child),
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
              _ThemeToggleButton(settings: settings, ref: ref),
              const SizedBox(width: 8),
            ],
          ),
          body: child,
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

/// Rail header — shows app title + theme toggle.
class _RailHeader extends StatelessWidget {
  final AppSettings settings;
  final WidgetRef ref;
  final bool extended;

  const _RailHeader({
    required this.settings,
    required this.ref,
    required this.extended,
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
          _ThemeToggleButton(settings: settings, ref: ref),
          const Divider(),
        ],
      ),
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
