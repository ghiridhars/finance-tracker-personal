/// Income vs Expense bar chart.
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/analytics_models.dart';
import 'chart_helpers.dart';

class IncomeExpenseChart extends StatelessWidget {
  final List<IncomeVsExpense> data;
  const IncomeExpenseChart({super.key, required this.data});

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
                          child: Text(shortCurrency(value), style: const TextStyle(fontSize: 10)),
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
                          '${isIncome ? "Income" : "Expense"}\n${currencyFmtDec.format(rod.toY)}',
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
                LegendDot(color: Colors.green.shade400, label: 'Income'),
                const SizedBox(width: 20),
                LegendDot(color: Colors.red.shade400, label: 'Expense'),
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
      return monthAbbr(int.tryParse(parts[1]) ?? 0);
    }
    return m;
  }
}
