// Glassmorphic App Sidebar — replaces NavigationRail.
//
// Features:
//   • Grouped navigation: CORE / MANAGE / TOOLS
//   • Animated expand (240px) ↔ collapse (72px)
//   • Inline review-count badge on the Review item
//   • Section labels (expanded) / dividers (compact)
//   • Pill active state with gradient left accent
//   • Hover ripple on each item
//   • Mobile "More" bottom-sheet for MANAGE/TOOLS items
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../router.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/transactions_provider.dart';

// ─────────────────────────────────────────────
// Public widget
// ─────────────────────────────────────────────

class AppSidebar extends ConsumerWidget {
  final bool compact;
  final VoidCallback? onToggleExpanded;

  const AppSidebar({
    super.key,
    required this.compact,
    this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.path;
    final reviewAsync = ref.watch(needsReviewCountProvider);
    final reviewBadge = reviewAsync.when(
      data: (n) => n,
      loading: () => 0,
      error: (_, __) => 0,
    );
    final cs = Theme.of(context).colorScheme;

    final coreItems =
        navDestinations.where((d) => d.group == NavGroup.core).toList();
    final manageItems =
        navDestinations.where((d) => d.group == NavGroup.manage).toList();
    final toolsItems =
        navDestinations.where((d) => d.group == NavGroup.tools).toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: compact ? 72 : 240,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  cs.surface.withValues(alpha: 0.96),
                  cs.surfaceContainerLow.withValues(alpha: 0.92),
                ],
              ),
              border: Border(
                right: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                _SidebarHeader(compact: compact),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SidebarSection(
                          label: 'CORE',
                          items: coreItems,
                          compact: compact,
                          currentPath: currentPath,
                          reviewBadge: reviewBadge,
                        ),
                        const SizedBox(height: 4),
                        _SidebarSection(
                          label: 'MANAGE',
                          items: manageItems,
                          compact: compact,
                          currentPath: currentPath,
                        ),
                        const SizedBox(height: 4),
                        _SidebarSection(
                          label: 'TOOLS',
                          items: toolsItems,
                          compact: compact,
                          currentPath: currentPath,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                _SidebarFooter(
                  compact: compact,
                  onToggleExpanded: onToggleExpanded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Header — logo mark + wordmark
// ─────────────────────────────────────────────

class _SidebarHeader extends StatelessWidget {
  final bool compact;

  const _SidebarHeader({required this.compact});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final logoMark = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(Icons.account_balance, color: cs.onPrimary, size: 22),
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(child: logoMark),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Row(
        children: [
          logoMark,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [cs.primary, cs.tertiary],
                  ).createShader(bounds),
                  child: Text(
                    'Finance Tracker',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'Personal Finance',
                  style: tt.labelSmall?.copyWith(color: cs.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Section — label + items
// ─────────────────────────────────────────────

class _SidebarSection extends StatelessWidget {
  final String label;
  final List<NavDestination> items;
  final bool compact;
  final String currentPath;
  final int reviewBadge;

  const _SidebarSection({
    required this.label,
    required this.items,
    required this.compact,
    required this.currentPath,
    this.reviewBadge = 0,
  });

  bool _isActive(NavDestination d) {
    if (d.path == '/') return currentPath == '/';
    return currentPath.startsWith(d.path);
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Divider(
              height: 1,
              thickness: 1,
              color: cs.outlineVariant.withValues(alpha: 0.3),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.outline,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ...items.map(
          (d) => _SidebarItem(
            destination: d,
            isActive: _isActive(d),
            compact: compact,
            badge: d.path == AppRoutes.review && reviewBadge > 0
                ? reviewBadge
                : null,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Item — pill + badge + hover + tooltip
// ─────────────────────────────────────────────

class _SidebarItem extends StatefulWidget {
  final NavDestination destination;
  final bool isActive;
  final bool compact;
  final int? badge;

  const _SidebarItem({
    required this.destination,
    required this.isActive,
    required this.compact,
    this.badge,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = widget.destination;
    final active = widget.isActive;

    Widget tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => context.go(d.path),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: active
                ? cs.primaryContainer.withValues(alpha: 0.75)
                : _hovered
                    ? cs.surfaceContainerHighest.withValues(alpha: 0.55)
                    : Colors.transparent,
          ),
          // Use LayoutBuilder so content switches on ACTUAL width, not the state bool.
          // This prevents RenderFlex overflow during the sidebar expand/collapse animation.
          child: ClipRect(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showExpanded = constraints.maxWidth >= 120;
                if (!showExpanded) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: _CompactContent(
                      destination: d,
                      active: active,
                      badge: widget.badge,
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 10),
                  child: _ExpandedContent(
                    destination: d,
                    active: active,
                    badge: widget.badge,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    if (widget.compact) {
      return Tooltip(
        message: '${d.label}\n${d.description}',
        preferBelow: false,
        waitDuration: const Duration(milliseconds: 350),
        child: tile,
      );
    }

    return tile;
  }
}

class _CompactContent extends StatelessWidget {
  final NavDestination destination;
  final bool active;
  final int? badge;

  const _CompactContent({
    required this.destination,
    required this.active,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              active ? destination.selectedIcon : destination.icon,
              color: active ? cs.primary : cs.onSurfaceVariant,
              size: 22,
            ),
            if ((badge ?? 0) > 0)
              Positioned(
                right: -10,
                top: -8,
                child: _BadgeChip(count: badge!, cs: cs),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExpandedContent extends StatelessWidget {
  final NavDestination destination;
  final bool active;
  final int? badge;

  const _ExpandedContent({
    required this.destination,
    required this.active,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        // Gradient accent strip (visible only when active)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 3,
          height: active ? 22 : 0,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [cs.primary, cs.tertiary],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Icon(
          active ? destination.selectedIcon : destination.icon,
          color: active ? cs.primary : cs.onSurfaceVariant,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            destination.label,
            style: tt.bodyMedium?.copyWith(
              color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if ((badge ?? 0) > 0) _BadgeChip(count: badge!, cs: cs),
      ],
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final int count;
  final ColorScheme cs;

  const _BadgeChip({required this.count, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: TextStyle(
          color: cs.onError,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Footer — theme toggle + collapse button
// ─────────────────────────────────────────────

class _SidebarFooter extends ConsumerWidget {
  final bool compact;
  final VoidCallback? onToggleExpanded;

  const _SidebarFooter({
    required this.compact,
    this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final settings = ref.watch(appSettingsProvider);

    final themeIcon = switch (settings.themeMode) {
      ThemeMode.system => Icons.brightness_auto_outlined,
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
    };
    final themeTooltip = switch (settings.themeMode) {
      ThemeMode.system => 'Theme: System',
      ThemeMode.light => 'Theme: Light',
      ThemeMode.dark => 'Theme: Dark',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(themeIcon, size: 20, color: cs.onSurfaceVariant),
                  tooltip: themeTooltip,
                  onPressed: () =>
                      ref.read(appSettingsProvider.notifier).toggleTheme(),
                ),
                if (onToggleExpanded != null)
                  IconButton(
                    icon: Icon(Icons.chevron_right,
                        size: 20, color: cs.onSurfaceVariant),
                    tooltip: 'Expand Sidebar',
                    onPressed: onToggleExpanded,
                  ),
              ],
            )
          : Row(
              children: [
                IconButton(
                  icon: Icon(themeIcon, size: 20, color: cs.onSurfaceVariant),
                  tooltip: themeTooltip,
                  onPressed: () =>
                      ref.read(appSettingsProvider.notifier).toggleTheme(),
                ),
                const Spacer(),
                if (onToggleExpanded != null)
                  IconButton(
                    icon: Icon(Icons.chevron_left,
                        size: 20, color: cs.onSurfaceVariant),
                    tooltip: 'Collapse Sidebar',
                    onPressed: onToggleExpanded,
                  ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────
// Mobile "More" bottom sheet
// ─────────────────────────────────────────────

void showMoreSheet(BuildContext context) {
  final allExtra = navDestinations
      .where((d) => d.group == NavGroup.manage || d.group == NavGroup.tools)
      .toList();
  final currentPath = GoRouterState.of(context).uri.path;
  final cs = Theme.of(context).colorScheme;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'More',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            ...allExtra.map((d) {
              final active = d.path == '/'
                  ? currentPath == '/'
                  : currentPath.startsWith(d.path);
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                leading: Icon(
                  active ? d.selectedIcon : d.icon,
                  color: active ? cs.primary : cs.onSurfaceVariant,
                ),
                title: Text(
                  d.label,
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: active ? cs.primary : null,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.normal,
                      ),
                ),
                subtitle: Text(
                  d.description,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: cs.outline,
                      ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.go(d.path);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
