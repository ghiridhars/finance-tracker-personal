/// Month-over-month comparison card.
import 'package:flutter/material.dart';
import '../../models/analytics_models.dart';
import 'chart_helpers.dart';

class MonthOverMonthCard extends StatelessWidget {
  final MonthOverMonth data;
  const MonthOverMonthCard({super.key, required this.data});

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
                    child: ChangeBadge(pct: data.totalChangePct!),
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
          currencyFmt.format(amount),
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
              currencyFmt.format(item.current),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'vs ${currencyFmt.format(item.previous)}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: item.changePct != null
                ? ChangeBadge(pct: item.changePct!, small: true)
                : const Text('New', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}

class ChangeBadge extends StatelessWidget {
  final double pct;
  final bool small;

  const ChangeBadge({super.key, required this.pct, this.small = false});

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
