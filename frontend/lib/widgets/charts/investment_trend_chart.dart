import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/analytics_models.dart';
import 'chart_helpers.dart';

class InvestmentTrendChart extends StatefulWidget {
  final List<InvestmentTrend> data;

  const InvestmentTrendChart({super.key, required this.data});

  @override
  State<InvestmentTrendChart> createState() => _InvestmentTrendChartState();
}

class _InvestmentTrendChartState extends State<InvestmentTrendChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final amounts = widget.data.map((d) => d.amount).toList();
    final maxAmount = amounts.fold<double>(0, (m, d) => max(m, d));
    final minAmount = amounts.fold<double>(maxAmount, (m, d) => min(m, d));
    final maxY = maxAmount > 0 ? maxAmount * 1.2 : 1000.0;
    final minY = max(0.0, minAmount * 0.8);

    // Calculate total & average for context
    final totalVelocity = widget.data.fold<double>(0, (s, d) => s + d.amount);
    final avgVelocity = widget.data.isNotEmpty ? totalVelocity / widget.data.length : 0.0;

    final activeTrend = (_touchedIndex != null && _touchedIndex! >= 0 && _touchedIndex! < widget.data.length)
        ? widget.data[_touchedIndex!]
        : null;

    final spots = List.generate(
      widget.data.length,
      (i) => FlSpot(i.toDouble(), widget.data[i].amount),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with interactive scrub feedback indicator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.show_chart, size: 16, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Investment Velocity',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Monthly capital deployment trend',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              // Scrubbing metric card
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: activeTrend != null
                      ? cs.primaryContainer.withValues(alpha: 0.8)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: activeTrend != null ? cs.primary.withValues(alpha: 0.5) : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      activeTrend != null ? activeTrend.period : 'Avg / Month',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: activeTrend != null ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currencyFmt.format(activeTrend != null ? activeTrend.amount : avgVelocity),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: activeTrend != null ? cs.primary : cs.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Line chart container with touch scrubbing
        SizedBox(
          height: 220,
          child: Padding(
            padding: const EdgeInsets.only(right: 20.0, left: 8.0, top: 12.0, bottom: 8.0),
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > minY ? (maxY - minY) / 3 : 1,
                  getDrawingHorizontalLine: (val) => FlLine(
                    color: cs.outlineVariant.withValues(alpha: 0.25),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= widget.data.length) {
                          return const SizedBox.shrink();
                        }
                        final period = widget.data[index].period;
                        String label = period;
                        if (period.contains('-')) {
                          final parts = period.split('-');
                          if (parts.length >= 2) {
                            final m = int.tryParse(parts[1]);
                            if (m != null) {
                              label = '${monthAbbr(m)} \'${parts[0].substring(2)}';
                            }
                          }
                        }
                        final isTouched = _touchedIndex == index;
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            label,
                            style: TextStyle(
                              color: isTouched ? cs.primary : cs.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: isTouched ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      getTitlesWidget: (value, meta) {
                        if (value == minY || value == maxY) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            shortCurrency(value),
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
                    if (event is FlTapUpEvent || event is FlPanEndEvent || event is FlPointerExitEvent) {
                      setState(() => _touchedIndex = null);
                    } else if (touchResponse != null && touchResponse.lineBarSpots != null) {
                      final spot = touchResponse.lineBarSpots!.firstOrNull;
                      if (spot != null) {
                        setState(() => _touchedIndex = spot.x.toInt());
                      }
                    }
                  },
                  getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                    return spotIndexes.map((index) {
                      return TouchedSpotIndicatorData(
                        FlLine(
                          color: cs.primary.withValues(alpha: 0.6),
                          strokeWidth: 2,
                          dashArray: [3, 3],
                        ),
                        FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) {
                            return FlDotCirclePainter(
                              radius: 6,
                              color: cs.primary,
                              strokeWidth: 3,
                              strokeColor: cs.surface,
                            );
                          },
                        ),
                      );
                    }).toList();
                  },
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final index = spot.x.toInt();
                        if (index < 0 || index >= widget.data.length) return null;
                        final trend = widget.data[index];
                        return LineTooltipItem(
                          '${trend.period}\n',
                          TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          children: [
                            TextSpan(
                              text: currencyFmt.format(trend.amount),
                              style: TextStyle(
                                color: Colors.green.shade600,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    barWidth: 3.5,
                    color: cs.primary,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        final isTouched = _touchedIndex == index;
                        return FlDotCirclePainter(
                          radius: isTouched ? 5 : 3.5,
                          color: isTouched ? cs.primary : cs.primaryContainer,
                          strokeWidth: isTouched ? 2 : 1.5,
                          strokeColor: cs.primary,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          cs.primary.withValues(alpha: 0.35),
                          cs.primary.withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
