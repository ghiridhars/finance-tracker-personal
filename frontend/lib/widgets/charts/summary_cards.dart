/// Summary cards — financial overview tiles (income, spending, net savings, etc.)
import 'package:flutter/material.dart';
import '../../models/analytics_models.dart';
import 'chart_helpers.dart';

class SummaryCards extends StatelessWidget {
  final DashboardSummary summary;
  const SummaryCards({super.key, required this.summary});

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
          value: currencyFmt.format(summary.totalIncome),
          color: Colors.green.shade700,
        ),
        _SummaryTile(
          icon: Icons.arrow_downward,
          label: 'Spending',
          value: currencyFmt.format(summary.totalSpending),
          color: Colors.red.shade700,
        ),
        _SummaryTile(
          icon: Icons.savings,
          label: 'Net Savings',
          value: currencyFmt.format(summary.netSavings),
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
          value: currencyFmt.format(summary.avgTransaction),
          color: cs.secondary,
        ),
        if (summary.topSpendingCategory != null)
          _SummaryTile(
            icon: Icons.category,
            label: 'Top Category',
            value: summary.topSpendingCategory!,
            subtitle: currencyFmt.format(summary.topSpendingAmount),
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
