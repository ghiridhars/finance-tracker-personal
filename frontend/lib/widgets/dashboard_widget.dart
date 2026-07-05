/// Dashboard screen — financial overview with charts and summary cards.
///
/// Chart widgets are in charts/ subdirectory.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/dashboard_provider.dart';
import '../providers/dashboard_layout_provider.dart';
import '../models/analytics_models.dart';
import 'skeleton_widgets.dart';
import 'charts/summary_cards.dart';
import 'charts/spending_trends_chart.dart';
import 'charts/category_pie_chart.dart';
import 'charts/income_expense_chart.dart';
import 'charts/month_over_month_card.dart';
import 'charts/top_merchants_card.dart';
import 'charts/investment_portfolio_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  /// Check whether a tile has data to display.
  bool _hasData(DashboardTileId id, DashboardState dash) => switch (id) {
        DashboardTileId.summary => dash.summary != null,
        DashboardTileId.trends => dash.spendingTrends.isNotEmpty,
        DashboardTileId.categories => dash.categorySpending.isNotEmpty,
        DashboardTileId.incomeExpense => dash.incomeVsExpense.isNotEmpty,
        DashboardTileId.monthOverMonth => dash.monthOverMonth != null,
        DashboardTileId.topMerchants => dash.topMerchants.isNotEmpty,
        DashboardTileId.investments => dash.investmentAnalytics != null &&
            dash.investmentAnalytics!.totalInvested > 0,
      };

  /// Build the raw content widget for a tile.
  Widget _buildTile(DashboardTileId id, DashboardState dash, WidgetRef ref, BuildContext context) {
    return switch (id) {
      DashboardTileId.summary => SummaryCards(summary: dash.summary!),
      DashboardTileId.trends =>
          SpendingTrendsChart(data: dash.spendingTrends),
      DashboardTileId.categories =>
          CategoryPieChart(data: dash.categorySpending),
      DashboardTileId.incomeExpense =>
          IncomeExpenseChart(data: dash.incomeVsExpense),
      DashboardTileId.monthOverMonth =>
          MonthOverMonthCard(data: dash.monthOverMonth!),
      DashboardTileId.topMerchants =>
          TopMerchantsCard(data: dash.topMerchants),
      DashboardTileId.investments => InvestmentPortfolioCard(
          data: dash.investmentAnalytics!,
          isDark: Theme.of(context).brightness == Brightness.dark,
        ),
    };
  }

  /// Section title and icon for each tile.
  static const Map<DashboardTileId, (String, IconData)> _tileMeta = {
    DashboardTileId.summary: ('Summary', Icons.dashboard),
    DashboardTileId.trends: ('Spending Trends', Icons.trending_up),
    DashboardTileId.categories: ('Where Does Your Money Go?', Icons.pie_chart),
    DashboardTileId.incomeExpense: ('Income vs Expense', Icons.bar_chart),
    DashboardTileId.monthOverMonth: ('Month-over-Month', Icons.compare_arrows),
    DashboardTileId.topMerchants: ('Top Merchants', Icons.storefront),
    DashboardTileId.investments: ('Investment Portfolio', Icons.stacked_line_chart),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(dashboardProvider);
    final layout = ref.watch(dashboardLayoutProvider);

    if (dash.isLoading && dash.summary == null) {
      return const SkeletonDashboard();
    }

    if (dash.error != null && dash.summary == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('Failed to load dashboard',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(dash.error!,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(dashboardProvider.notifier).loadDashboard(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final editing = layout.isEditMode;
    final visibleTiles = <TileConfig>[];
    for (final t in layout.tiles) {
      if (editing || (t.visible && _hasData(t.id, dash))) {
        visibleTiles.add(t);
      }
    }

    return Stack(
      children: [
        Column(
          children: [
            if (editing)
              _EditToolbar(
                onReset: () => ref
                    .read(dashboardLayoutProvider.notifier)
                    .resetToDefaults(),
                onDone: () => ref
                    .read(dashboardLayoutProvider.notifier)
                    .exitEditMode(),
              ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    ref.read(dashboardProvider.notifier).loadDashboard(),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final totalWidth = constraints.maxWidth - 32;
                    final tier = screenTierFor(constraints.maxWidth);
                    const gap = 12.0;

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (!editing) ...[
                          _DateRangeChips(
                            selected: dash.range,
                            onChanged: (r) => ref
                                .read(dashboardProvider.notifier)
                                .setRange(r),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (dash.isLoading)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: LinearProgressIndicator(),
                          ),
                        if (visibleTiles.isEmpty && !editing && !dash.isLoading)
                          Padding(
                            padding: const EdgeInsets.only(top: 64),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.query_stats, size: 64, color: Theme.of(context).colorScheme.primaryContainer),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Nothing to see here yet',
                                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Import a bank statement to see your financial overview.',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 24),
                                  FilledButton.icon(
                                    onPressed: () => context.go('/import'),
                                    icon: const Icon(Icons.upload_file),
                                    label: const Text('Upload your first statement \u2192'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          ..._buildGridRows(
                            tiles: visibleTiles,
                            totalWidth: totalWidth,
                            tier: tier,
                            gap: gap,
                            editing: editing,
                            dash: dash,
                            ref: ref,
                            context: context,
                          ),
                        ],
                        const SizedBox(height: 60),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),

        if (!editing)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.extended(
              onPressed: () => ref
                  .read(dashboardLayoutProvider.notifier)
                  .toggleEditMode(),
              tooltip: 'Customize dashboard',
              icon: const Icon(Icons.dashboard_customize),
              label: const Text('Customize'),
            ),
          ),
      ],
    );
  }

  /// Flow tiles into rows based on effective colSpan (responsive).
  List<Widget> _buildGridRows({
    required List<TileConfig> tiles,
    required double totalWidth,
    required ScreenTier tier,
    required double gap,
    required bool editing,
    required DashboardState dash,
    required WidgetRef ref,
    required BuildContext context,
  }) {
    final rows = <Widget>[];
    var currentRow = <(TileConfig, int)>[];
    var usedCols = 0;

    for (final tile in tiles) {
      final origIdx = ref.read(dashboardLayoutProvider).tiles.indexOf(tile);
      final span = effectiveColSpan(tile, tier);

      if (usedCols + span > kGridColumns && currentRow.isNotEmpty) {
        rows.add(_buildRow(currentRow, totalWidth, tier, gap, editing, dash, ref, context));
        rows.add(const SizedBox(height: 12));
        currentRow = [];
        usedCols = 0;
      }
      currentRow.add((tile, origIdx));
      usedCols += span;
    }
    if (currentRow.isNotEmpty) {
      rows.add(_buildRow(currentRow, totalWidth, tier, gap, editing, dash, ref, context));
    }
    return rows;
  }

  /// Build a single row of tiles with proper flex + spacer.
  Widget _buildRow(
    List<(TileConfig, int)> rowTiles,
    double totalWidth,
    ScreenTier tier,
    double gap,
    bool editing,
    DashboardState dash,
    WidgetRef ref,
    BuildContext context,
  ) {
    final totalCount = ref.read(dashboardLayoutProvider).tiles.length;
    final usedCols = rowTiles.fold<int>(
        0, (s, t) => s + effectiveColSpan(t.$1, tier));
    final remaining = kGridColumns - usedCols;

    final double maxTileHeight = rowTiles.fold<double>(
        0, (max, t) => t.$1.height > max ? t.$1.height : max);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < rowTiles.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            flex: effectiveColSpan(rowTiles[i].$1, tier),
            child: _buildSingleTile(
              rowTiles[i].$1,
              rowTiles[i].$2,
              totalCount,
              editing,
              tier,
              dash,
              ref,
              context,
              maxTileHeight,
            ),
          ),
        ],
        if (remaining > 0) ...[
          SizedBox(width: gap),
          Expanded(flex: remaining, child: const SizedBox()),
        ],
      ],
    );
  }

  /// Build a single tile — either normal or edit-wrapped.
  Widget _buildSingleTile(
    TileConfig tile,
    int index,
    int totalCount,
    bool editing,
    ScreenTier tier,
    DashboardState dash,
    WidgetRef ref,
    BuildContext context,
    double renderHeight,
  ) {
    final hasData = _hasData(tile.id, dash);

    Widget content;
    if (hasData) {
      try {
        content = _buildTile(tile.id, dash, ref, context);
      } catch (e) {
        content = Center(
          child: Text('Error rendering tile: $e'),
        );
      }
    } else {
      content = Center(
        child: Text(
          'No data for ${_tileMeta[tile.id]!.$1}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (editing) {
      return _EditableTileWrapper(
        tile: tile,
        index: index,
        totalCount: totalCount,
        tier: tier,
        renderHeight: renderHeight,
        child: content,
      );
    }

    // Normal mode — animated height transitions
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tile.id != DashboardTileId.summary) ...[
          _SectionTitle(
            title: _tileMeta[tile.id]!.$1,
            icon: _tileMeta[tile.id]!.$2,
          ),
          const SizedBox(height: 8),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          height: renderHeight,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: content,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Edit-mode toolbar
// ═══════════════════════════════════════════════════════════════

class _EditToolbar extends StatelessWidget {
  final VoidCallback onReset;
  final VoidCallback onDone;
  const _EditToolbar({required this.onReset, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(Icons.dashboard_customize,
              color: cs.onPrimaryContainer, size: 20),
          const SizedBox(width: 8),
          Text(
            'Customize Dashboard',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          TextButton(onPressed: onReset, child: const Text('Reset')),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onDone,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Editable tile wrapper — button-based resize controls
// ═══════════════════════════════════════════════════════════════

class _EditableTileWrapper extends ConsumerWidget {
  final TileConfig tile;
  final int index;
  final int totalCount;
  final ScreenTier tier;
  final double renderHeight;
  final Widget child;

  const _EditableTileWrapper({
    required this.tile,
    required this.index,
    required this.totalCount,
    required this.tier,
    required this.renderHeight,
    required this.child,
  });

  String _getFriendlySizeLabel(int colSpan, double height) {
    final widthStr = switch (colSpan) {
      12 => 'Full Width',
      >= 8 => 'Large',
      >= 6 => 'Medium',
      _ => 'Small',
    };
    final heightStr = height > 400 ? 'Tall' : (height > 250 ? 'Regular' : 'Short');
    return '$widthStr \u00B7 $heightStr';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final meta = DashboardScreen._tileMeta[tile.id]!;
    final notifier = ref.read(dashboardLayoutProvider.notifier);
    final isFirst = index == 0;
    final isLast = index == totalCount - 1;
    final visible = tile.visible;
    final canWiden = tile.colSpan < kGridColumns;
    final canNarrow = tile.colSpan > kMinColSpan;
    final canTaller = tile.height < kMaxTileHeight;
    final canShorter = tile.height > kMinTileHeight;
    final isCompact = tier == ScreenTier.compact;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: visible ? 1.0 : 0.45,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        height: renderHeight,
        decoration: BoxDecoration(
          border: Border.all(
            color: visible
                ? cs.primary.withValues(alpha: 0.5)
                : cs.error.withValues(alpha: 0.4),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            // ── Tile content (clipped, non-interactive) ──
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: AbsorbPointer(child: child),
              ),
            ),

            // ── Semi-transparent overlay for clarity ──
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
            ),

            // ── Label badge (top-left) ──
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(meta.$2, color: cs.onPrimary, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      meta.$1,
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: cs.onPrimary.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getFriendlySizeLabel(tile.colSpan, tile.height),
                        style: TextStyle(
                          color: cs.onPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Control pill (top-right): reorder + visibility ──
            Positioned(
              top: 6,
              right: 6,
              child: _ControlPill(
                cs: cs,
                children: [
                  _TinyIconButton(
                    icon: Icons.arrow_upward,
                    color: cs.onSurface,
                    onPressed: isFirst
                        ? null
                        : () => notifier.reorder(index, index - 1),
                  ),
                  _TinyIconButton(
                    icon: Icons.arrow_downward,
                    color: cs.onSurface,
                    onPressed: isLast
                        ? null
                        : () => notifier.reorder(index, index + 2),
                  ),
                  Container(width: 1, height: 18, color: cs.outlineVariant),
                  _TinyIconButton(
                    icon:
                        visible ? Icons.visibility : Icons.visibility_off,
                    color: visible ? cs.primary : cs.error,
                    onPressed: () => notifier.toggleVisibility(tile.id),
                  ),
                ],
              ),
            ),

            // ── Resize controls (bottom-center) ──
            Positioned(
              bottom: 6,
              left: 0,
              right: 0,
              child: Center(
                child: _ControlPill(
                  cs: cs,
                  children: [
                    // Width controls (hidden on compact screens)
                    if (!isCompact) ...[
                      _TinyIconButton(
                        icon: Icons.chevron_left,
                        color: cs.secondary,
                        onPressed:
                            canNarrow ? () => notifier.narrowTile(tile.id) : null,
                        tooltip: 'Narrower',
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(Icons.width_normal,
                            size: 14, color: cs.outline),
                      ),
                      _TinyIconButton(
                        icon: Icons.chevron_right,
                        color: cs.secondary,
                        onPressed:
                            canWiden ? () => notifier.widenTile(tile.id) : null,
                        tooltip: 'Wider',
                      ),
                      Container(
                          width: 1, height: 18, color: cs.outlineVariant),
                    ],
                    // Height controls
                    _TinyIconButton(
                      icon: Icons.expand_less,
                      color: cs.tertiary,
                      onPressed:
                          canShorter ? () => notifier.shorterTile(tile.id) : null,
                      tooltip: 'Shorter',
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(Icons.height, size: 14, color: cs.outline),
                    ),
                    _TinyIconButton(
                      icon: Icons.expand_more,
                      color: cs.tertiary,
                      onPressed:
                          canTaller ? () => notifier.tallerTile(tile.id) : null,
                      tooltip: 'Taller',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded pill container for floating control buttons.
class _ControlPill extends StatelessWidget {
  final ColorScheme cs;
  final List<Widget> children;
  const _ControlPill({required this.cs, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Compact icon button for the edit overlay toolbar.
class _TinyIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final String? tooltip;
  const _TinyIconButton(
      {required this.icon, required this.color, this.onPressed, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: Icon(icon, size: 16, color: onPressed != null ? color : color.withValues(alpha: 0.35)),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        tooltip: tooltip,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Date Range Chips
// ═══════════════════════════════════════════════════════════════

class _DateRangeChips extends StatelessWidget {
  final DashboardRange selected;
  final ValueChanged<DashboardRange> onChanged;

  const _DateRangeChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: DashboardRange.values.map((r) {
          final isSelected = r == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(r.label),
              selected: isSelected,
              onSelected: (_) => onChanged(r),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Section Title
// ═══════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
