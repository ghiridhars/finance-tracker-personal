/// Dashboard screen — financial overview with charts and summary cards.
///
/// Sections:
///   1. Summary cards (income, spending, net savings, etc.)
///   2. Spending trends (line chart)
///   3. Category breakdown (pie chart)
///   4. Income vs Expense (bar chart)
///   5. Month-over-month comparison
///   6. Top merchants
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../providers/dashboard_provider.dart';
import '../models/analytics_models.dart';
import 'skeleton_widgets.dart';

final _currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _currencyFmtDec = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(dashboardProvider);

    if (dash.isLoading && dash.summary == null) {
      return const SkeletonDashboard();
    }

    if (dash.error != null && dash.summary == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('Failed to load dashboard', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(dash.error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref.read(dashboardProvider.notifier).loadDashboard(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(dashboardProvider.notifier).loadDashboard(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Date range selector
          _DateRangeChips(
            selected: dash.range,
            onChanged: (r) => ref.read(dashboardProvider.notifier).setRange(r),
          ),
          const SizedBox(height: 16),

          // Loading overlay
          if (dash.isLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(),
            ),

          // 1. Summary cards
          if (dash.summary != null) _SummaryCards(summary: dash.summary!),
          const SizedBox(height: 24),

          // 1.5 Calendar heatmap
          _SectionTitle(title: 'Spending Calendar', icon: Icons.calendar_month),
          const SizedBox(height: 8),
          _SpendingCalendar(
            data: dash.calendarData,
            focusedMonth: dash.calendarMonth,
            onMonthChanged: (m) =>
                ref.read(dashboardProvider.notifier).setCalendarMonth(m),
          ),
          const SizedBox(height: 24),

          // 2. Spending trends
          if (dash.spendingTrends.isNotEmpty) ...[
            _SectionTitle(title: 'Spending Trends', icon: Icons.trending_up),
            const SizedBox(height: 8),
            _SpendingTrendsChart(data: dash.spendingTrends),
            const SizedBox(height: 24),
          ],

          // 3. Category breakdown
          if (dash.categorySpending.isNotEmpty) ...[
            _SectionTitle(title: 'Where Does Your Money Go?', icon: Icons.pie_chart),
            const SizedBox(height: 8),
            _CategoryPieChart(data: dash.categorySpending),
            const SizedBox(height: 24),
          ],

          // 4. Income vs Expense
          if (dash.incomeVsExpense.isNotEmpty) ...[
            _SectionTitle(title: 'Income vs Expense', icon: Icons.bar_chart),
            const SizedBox(height: 8),
            _IncomeVsExpenseChart(data: dash.incomeVsExpense),
            const SizedBox(height: 24),
          ],

          // 5. Month-over-month
          if (dash.monthOverMonth != null) ...[
            _SectionTitle(title: 'Month-over-Month', icon: Icons.compare_arrows),
            const SizedBox(height: 8),
            _MonthOverMonthCard(data: dash.monthOverMonth!),
            const SizedBox(height: 24),
          ],

          // 6. Top merchants
          if (dash.topMerchants.isNotEmpty) ...[
            _SectionTitle(title: 'Top Merchants', icon: Icons.storefront),
            const SizedBox(height: 8),
            _TopMerchantsCard(data: dash.topMerchants),
          ],

          const SizedBox(height: 32),
        ],
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
            SizedBox(
              height: 220,
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
            SizedBox(
              height: 220,
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
            SizedBox(
              height: 220,
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
      child: Padding(
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: List.generate(min(10, data.length), (i) {
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
          }),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 1.5 Spending Calendar (Heatmap)
// ═══════════════════════════════════════════════════════════════

class _SpendingCalendar extends StatelessWidget {
  final List<SpendingTrend> data;
  final DateTime focusedMonth;
  final ValueChanged<DateTime> onMonthChanged;

  const _SpendingCalendar({
    required this.data,
    required this.focusedMonth,
    required this.onMonthChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Build a map from date string → spending amount
    final Map<DateTime, double> spendingByDay = {};
    double maxSpending = 0;
    for (final d in data) {
      final parts = d.period.split('-');
      if (parts.length == 3) {
        final dt = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        spendingByDay[dt] = d.spending;
        if (d.spending > maxSpending) maxSpending = d.spending;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TableCalendar<void>(
          firstDay: DateTime(2020),
          lastDay: DateTime(2030, 12, 31),
          focusedDay: focusedMonth,
          calendarFormat: CalendarFormat.month,
          availableCalendarFormats: const {CalendarFormat.month: 'Month'},
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: Theme.of(context)
                .textTheme
                .titleSmall!
                .copyWith(fontWeight: FontWeight.w600),
            leftChevronIcon: Icon(Icons.chevron_left, color: cs.primary),
            rightChevronIcon: Icon(Icons.chevron_right, color: cs.primary),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
            weekendStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: cs.error.withValues(alpha: 0.7),
            ),
          ),
          onPageChanged: (focusedDay) => onMonthChanged(focusedDay),
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (context, day, focusedDay) {
              return _CalendarCell(
                day: day,
                spending: spendingByDay[DateTime(day.year, day.month, day.day)] ?? 0,
                maxSpending: maxSpending,
                isToday: false,
              );
            },
            todayBuilder: (context, day, focusedDay) {
              return _CalendarCell(
                day: day,
                spending: spendingByDay[DateTime(day.year, day.month, day.day)] ?? 0,
                maxSpending: maxSpending,
                isToday: true,
              );
            },
            outsideBuilder: (context, day, focusedDay) {
              return Center(
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.2),
                  ),
                ),
              );
            },
          ),
          calendarStyle: const CalendarStyle(
            cellMargin: EdgeInsets.all(2),
            outsideDaysVisible: true,
          ),
        ),
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  final DateTime day;
  final double spending;
  final double maxSpending;
  final bool isToday;

  const _CalendarCell({
    required this.day,
    required this.spending,
    required this.maxSpending,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Compute intensity (0.0 – 1.0)
    final intensity = maxSpending > 0 ? (spending / maxSpending).clamp(0.0, 1.0) : 0.0;

    Color bgColor;
    if (spending > 0) {
      // Gradient from light to dark based on intensity
      bgColor = Color.lerp(
        Colors.red.shade50,
        Colors.red.shade600,
        intensity,
      )!;
    } else {
      bgColor = Colors.transparent;
    }

    return Tooltip(
      message: spending > 0
          ? '${DateFormat.MMMd().format(day)}: ${_currencyFmt.format(spending)}'
          : DateFormat.MMMd().format(day),
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: isToday
              ? Border.all(color: cs.primary, width: 2)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '${day.day}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
            color: spending > 0 && intensity > 0.5
                ? Colors.white
                : cs.onSurface,
          ),
        ),
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
