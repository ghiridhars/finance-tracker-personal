/// Top merchants card — ranked list of highest-spending merchants.
library;
import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/analytics_models.dart';
import 'chart_helpers.dart';

class TopMerchantsCard extends StatelessWidget {
  final List<MerchantSpending> data;
  const TopMerchantsCard({super.key, required this.data});

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
                      Text(currencyFmt.format(m.amount),
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
