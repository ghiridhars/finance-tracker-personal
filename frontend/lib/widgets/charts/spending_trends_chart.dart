/// Spending trends line chart.
library;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/analytics_models.dart';
import 'chart_helpers.dart';

class SpendingTrendsChart extends StatelessWidget {
  final List<SpendingTrend> data;
  const SpendingTrendsChart({super.key, required this.data});

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
                          child: Text(shortCurrency(value), style: const TextStyle(fontSize: 10)),
                        ),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: 0,
                  maxY: maxY > 0 ? maxY : 1,
                  lineBarsData: [
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
                          '${isSpending ? "Spending" : "Income"}\n${currencyFmtDec.format(s.y)}',
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
                LegendDot(color: Colors.red.shade400, label: 'Spending'),
                const SizedBox(width: 20),
                LegendDot(color: Colors.green.shade400, label: 'Income'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _shortLabel(String period) {
    if (period.contains('W')) return period.split('-').last;
    final parts = period.split('-');
    if (parts.length == 3) {
      final m = monthAbbr(int.tryParse(parts[1]) ?? 0);
      return '$m ${int.tryParse(parts[2]) ?? parts[2]}';
    }
    if (parts.length == 2) {
      return monthAbbr(int.tryParse(parts[1]) ?? 0);
    }
    return period;
  }
}
