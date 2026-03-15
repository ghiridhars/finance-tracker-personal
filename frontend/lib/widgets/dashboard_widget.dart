/// Dashboard screen — financial overview with charts and summary cards.
///
/// Sections:
///   1. Summary cards (income, spending, net savings, etc.)
///   2. Spending trends (line chart)
///   3. Category breakdown (pie chart)
///   4. Income vs Expense (bar chart)
///   5. Month-over-month comparison
///   6. Top merchants
library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../providers/dashboard_provider.dart';
import '../providers/dashboard_layout_provider.dart';
import '../models/analytics_models.dart';
import 'skeleton_widgets.dart';

final _currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _currencyFmtDec = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

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
      };

  /// Build the raw content widget for a tile.
  Widget _buildTile(DashboardTileId id, DashboardState dash, WidgetRef ref) {
    return switch (id) {
      DashboardTileId.summary => _SummaryCards(summary: dash.summary!),
      DashboardTileId.trends =>
          _SpendingTrendsChart(data: dash.spendingTrends),
      DashboardTileId.categories =>
          _CategoryPieChart(data: dash.categorySpending),
      DashboardTileId.incomeExpense =>
          _IncomeVsExpenseChart(data: dash.incomeVsExpense),
      DashboardTileId.monthOverMonth =>
          _MonthOverMonthCard(data: dash.monthOverMonth!),
      DashboardTileId.topMerchants =>
          _TopMerchantsCard(data: dash.topMerchants),
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
            child: FloatingActionButton.small(
              onPressed: () => ref
                  .read(dashboardLayoutProvider.notifier)
                  .toggleEditMode(),
              tooltip: 'Customize dashboard',
              child: const Icon(Icons.dashboard_customize),
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
      content = _buildTile(tile.id, dash, ref);
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
                        '${tile.colSpan}col · ${tile.height.round()}px',
                        style: TextStyle(
                          color: cs.onPrimary,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
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

// ═══════════════════════════════════════════════════════════════
// 1. Summary Cards
// ═══════════════════════════════════════════════════════════════

class _SummaryCards extends StatelessWidget {
  final DashboardSummary summary;
  const _SummaryCards({required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _SummaryTile(
          icon: Icons.arrow_upward,
          label: 'Income',
          value: _currencyFmt.format(summary.totalIncome),
          color: Colors.green.shade700,
        ),
        _SummaryTile(
          icon: Icons.arrow_downward,
          label: 'Spending',
          value: _currencyFmt.format(summary.totalSpending),
          color: Colors.red.shade700,
        ),
        _SummaryTile(
          icon: Icons.savings,
          label: 'Net Savings',
          value: _currencyFmt.format(summary.netSavings),
          color: summary.netSavings >= 0 ? Colors.teal.shade700 : Colors.orange.shade800,
        ),
        _SummaryTile(
          icon: Icons.receipt_long,
          label: 'Transactions',
          value: summary.transactionCount.toString(),
          color: cs.primary,
        ),
        _SummaryTile(
          icon: Icons.calculate,
          label: 'Avg. Transaction',
          value: _currencyFmt.format(summary.avgTransaction),
          color: cs.secondary,
        ),
        if (summary.topSpendingCategory != null)
          _SummaryTile(
            icon: Icons.category,
            label: 'Top Category',
            value: summary.topSpendingCategory!,
            subtitle: _currencyFmt.format(summary.topSpendingAmount),
            color: Colors.deepPurple,
          ),
        _SummaryTile(
          icon: Icons.account_balance,
          label: 'Active Banks',
          value: summary.activeBanks.toString(),
          color: Colors.blueGrey,
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color color;

  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(label,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: color)),
              if (subtitle != null)
                Text(subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 2. Spending Trends (Line Chart)
// ═══════════════════════════════════════════════════════════════

class _SpendingTrendsChart extends StatelessWidget {
  final List<SpendingTrend> data;
  const _SpendingTrendsChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final maxSpending = data.fold<double>(0, (m, d) => max(m, d.spending));
    final maxIncome = data.fold<double>(0, (m, d) => max(m, d.income));
    final maxY = max(maxSpending, maxIncome) * 1.15;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: Column(
          children: [
            Expanded(
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY > 0 ? maxY / 4 : 1,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: max(1, (data.length / 6).ceil().toDouble()),
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                          final label = _shortLabel(data[idx].period);
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(label, style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 56,
                        interval: maxY > 0 ? maxY / 4 : 1,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(_shortCurrency(value), style: const TextStyle(fontSize: 10)),
                        ),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: 0,
                  maxY: maxY > 0 ? maxY : 1,
                  lineBarsData: [
                    // Spending line
                    LineChartBarData(
                      spots: List.generate(data.length, (i) => FlSpot(i.toDouble(), data[i].spending)),
                      isCurved: true,
                      color: Colors.red.shade400,
                      barWidth: 2.5,
                      dotData: FlDotData(show: data.length < 15),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.red.shade400.withValues(alpha: 0.08),
                      ),
                    ),
                    // Income line
                    LineChartBarData(
                      spots: List.generate(data.length, (i) => FlSpot(i.toDouble(), data[i].income)),
                      isCurved: true,
                      color: Colors.green.shade400,
                      barWidth: 2.5,
                      dotData: FlDotData(show: data.length < 15),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.green.shade400.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                        final isSpending = s.barIndex == 0;
                        return LineTooltipItem(
                          '${isSpending ? "Spending" : "Income"}\n${_currencyFmtDec.format(s.y)}',
                          TextStyle(
                            color: isSpending ? Colors.red.shade300 : Colors.green.shade300,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: Colors.red.shade400, label: 'Spending'),
                const SizedBox(width: 20),
                _LegendDot(color: Colors.green.shade400, label: 'Income'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _shortLabel(String period) {
    // "2026-02-15" → "Feb 15", "2026-02" → "Feb", "2026-W08" → "W08"
    if (period.contains('W')) return period.split('-').last;
    final parts = period.split('-');
    if (parts.length == 3) {
      final m = _monthAbbr(int.tryParse(parts[1]) ?? 0);
      return '$m ${int.tryParse(parts[2]) ?? parts[2]}';
    }
    if (parts.length == 2) {
      return _monthAbbr(int.tryParse(parts[1]) ?? 0);
    }
    return period;
  }

  static String _monthAbbr(int m) =>
      const ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
          .elementAtOrNull(m) ??
      '';

  static String _shortCurrency(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toInt()}';
  }
}

// ═══════════════════════════════════════════════════════════════
// 3. Category Breakdown (Pie Chart)
// ═══════════════════════════════════════════════════════════════

class _CategoryPieChart extends StatefulWidget {
  final List<CategorySpending> data;
  const _CategoryPieChart({required this.data});

  @override
  State<_CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<_CategoryPieChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: PieChart(
                PieChartData(
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            response == null ||
                            response.touchedSection == null) {
                          _touchedIndex = -1;
                          return;
                        }
                        _touchedIndex = response.touchedSection!.touchedSectionIndex;
                      });
                    },
                  ),
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: _buildSections(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _CategoryLegend(
              data: widget.data,
              touchedIndex: _touchedIndex,
            ),
          ],
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildSections() {
    return List.generate(widget.data.length, (i) {
      final item = widget.data[i];
      final isTouched = i == _touchedIndex;
      final radius = isTouched ? 55.0 : 45.0;
      final color = _parseColor(item.color);

      return PieChartSectionData(
        value: item.amount,
        title: isTouched ? '${item.percentage}%' : '',
        color: color,
        radius: radius,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    });
  }
}

class _CategoryLegend extends StatelessWidget {
  final List<CategorySpending> data;
  final int touchedIndex;

  const _CategoryLegend({required this.data, required this.touchedIndex});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: List.generate(data.length, (i) {
        final item = data[i];
        final isTouched = i == touchedIndex;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isTouched
                ? _parseColor(item.color).withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _parseColor(item.color),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${item.category} (${item.percentage}%)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isTouched ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 4. Income vs Expense (Bar Chart)
// ═══════════════════════════════════════════════════════════════

class _IncomeVsExpenseChart extends StatelessWidget {
  final List<IncomeVsExpense> data;
  const _IncomeVsExpenseChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final maxVal = data.fold<double>(0, (m, d) => max(m, max(d.income, d.expense)));
    final maxY = maxVal * 1.15;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: Column(
          children: [
            Expanded(
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY > 0 ? maxY / 4 : 1,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              _shortMonth(data[idx].month),
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 56,
                        interval: maxY > 0 ? maxY / 4 : 1,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(_shortCurrency(value), style: const TextStyle(fontSize: 10)),
                        ),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  maxY: maxY > 0 ? maxY : 1,
                  barGroups: List.generate(data.length, (i) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: data[i].income,
                          color: Colors.green.shade400,
                          width: 12,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                        BarChartRodData(
                          toY: data[i].expense,
                          color: Colors.red.shade400,
                          width: 12,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final isIncome = rodIndex == 0;
                        return BarTooltipItem(
                          '${isIncome ? "Income" : "Expense"}\n${_currencyFmtDec.format(rod.toY)}',
                          TextStyle(
                            color: isIncome ? Colors.green.shade300 : Colors.red.shade300,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: Colors.green.shade400, label: 'Income'),
                const SizedBox(width: 20),
                _LegendDot(color: Colors.red.shade400, label: 'Expense'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _shortMonth(String m) {
    final parts = m.split('-');
    if (parts.length == 2) {
      return _SpendingTrendsChart._monthAbbr(int.tryParse(parts[1]) ?? 0);
    }
    return m;
  }

  static String _shortCurrency(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toInt()}';
  }
}

// ═══════════════════════════════════════════════════════════════
// 5. Month-over-Month Comparison
// ═══════════════════════════════════════════════════════════════

class _MonthOverMonthCard extends StatelessWidget {
  final MonthOverMonth data;
  const _MonthOverMonthCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.hardEdge,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header summary
            Row(
              children: [
                Expanded(
                  child: _MomTotal(
                    label: data.currentMonth,
                    amount: data.currentTotal,
                    isCurrent: true,
                  ),
                ),
                Icon(Icons.arrow_forward, color: cs.outline),
                Expanded(
                  child: _MomTotal(
                    label: data.previousMonth,
                    amount: data.previousTotal,
                    isCurrent: false,
                  ),
                ),
                if (data.totalChangePct != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _ChangeBadge(pct: data.totalChangePct!),
                  ),
              ],
            ),
            if (data.comparison.isNotEmpty) ...[
              const Divider(height: 24),
              ...data.comparison.take(8).map((c) => _MomRow(item: c)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MomTotal extends StatelessWidget {
  final String label;
  final double amount;
  final bool isCurrent;

  const _MomTotal({required this.label, required this.amount, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          _currencyFmt.format(amount),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isCurrent ? Colors.red.shade700 : Colors.grey.shade600,
              ),
        ),
      ],
    );
  }
}

class _MomRow extends StatelessWidget {
  final MonthComparison item;
  const _MomRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(item.category,
                style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _currencyFmt.format(item.current),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'vs ${_currencyFmt.format(item.previous)}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: item.changePct != null
                ? _ChangeBadge(pct: item.changePct!, small: true)
                : const Text('New', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  final double pct;
  final bool small;

  const _ChangeBadge({required this.pct, this.small = false});

  @override
  Widget build(BuildContext context) {
    final isUp = pct > 0;
    final color = isUp ? Colors.red : Colors.green;
    final icon = isUp ? Icons.arrow_upward : Icons.arrow_downward;
    final text = '${pct.abs().toStringAsFixed(1)}%';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 4 : 8,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: small ? 12 : 14, color: color),
          Text(text, style: TextStyle(fontSize: small ? 10 : 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 6. Top Merchants
// ═══════════════════════════════════════════════════════════════

class _TopMerchantsCard extends StatelessWidget {
  final List<MerchantSpending> data;
  const _TopMerchantsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxAmount = data.isNotEmpty ? data.first.amount : 0.0;

    return Card(
      clipBehavior: Clip.hardEdge,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: min(10, data.length),
        itemBuilder: (context, i) {
            final m = data[i];
            final barWidth = maxAmount > 0 ? m.amount / maxAmount : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.outline),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.merchant,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: barWidth,
                            minHeight: 5,
                            backgroundColor: cs.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(
                              cs.primary.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_currencyFmt.format(m.amount),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('${m.count} txns',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    ],
                  ),
                ],
              ),
            );
        },
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════
// Shared Helpers
// ═══════════════════════════════════════════════════════════════

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

Color _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return Colors.grey;
  try {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return Colors.grey;
  }
}
