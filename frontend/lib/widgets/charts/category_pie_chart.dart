/// Category breakdown pie chart.
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/analytics_models.dart';
import 'chart_helpers.dart';

class CategoryPieChart extends StatefulWidget {
  final List<CategorySpending> data;
  const CategoryPieChart({super.key, required this.data});

  @override
  State<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<CategoryPieChart> {
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
      final color = parseColor(item.color);

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
                ? parseColor(item.color).withValues(alpha: 0.15)
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
                  color: parseColor(item.color),
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
