import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/dashboard_provider.dart';
import 'ui_system/ui_system.dart';

class NetWorthCard extends ConsumerWidget {
  const NetWorthCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(netWorthProvider);

    return asyncData.when(
      data: (data) => _NetWorthContent(data: data),
      loading: () => const _NetWorthShimmer(),
      error: (e, st) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 48),
              const SizedBox(height: 8),
              Text('Unable to load net worth', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => ref.invalidate(netWorthProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _NetWorthContent extends StatefulWidget {
  final Map<String, dynamic> data;
  const _NetWorthContent({required this.data});

  @override
  State<_NetWorthContent> createState() => _NetWorthContentState();
}

class _NetWorthContentState extends State<_NetWorthContent> {
  String _format(num amount) {
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(amount.abs());
  }

  String _formatSigned(num amount) {
    final prefix = amount < 0 ? '-' : '';
    return '$prefix${_format(amount)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final netWorth = widget.data['net_worth'] as num? ?? 0;
    final banks = widget.data['bank_balances'] as num? ?? 0;
    final investments = widget.data['investment_value'] as num? ?? 0;
    final cards = widget.data['credit_card_dues'] as num? ?? 0;
    final loans = widget.data['loan_outstanding'] as num? ?? 0;
    
    final lastUpdatedStr = widget.data['last_updated'] as String?;
    final lastUpdated = lastUpdatedStr != null ? DateTime.tryParse(lastUpdatedStr) : null;
    final lastUpdatedText = lastUpdated != null 
        ? 'Last updated ${DateFormat.yMMMd().add_jm().format(lastUpdated)}' 
        : '';

    final breakdown = (widget.data['breakdown'] as List<dynamic>?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: GlassHeroCard(
            title: 'Net Worth',
            subtitle: _formatSigned(netWorth),
            icon: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 28),
            padding: const EdgeInsets.all(24),
            margin: EdgeInsets.zero,
            gradientColors: isDark
                ? [
                    Colors.teal.shade900.withValues(alpha: 0.85),
                    Colors.indigo.shade900.withValues(alpha: 0.70),
                    cs.surface.withValues(alpha: 0.90),
                  ]
                : [
                    Colors.teal.shade700.withValues(alpha: 0.90),
                    Colors.indigo.shade700.withValues(alpha: 0.85),
                    cs.primary.withValues(alpha: 0.95),
                  ],
            metrics: [
              _GlassMetricCallout(
                icon: Icons.account_balance,
                label: 'Banks',
                value: _formatSigned(banks),
              ),
              _GlassMetricCallout(
                icon: Icons.trending_up,
                label: 'Investments',
                value: _formatSigned(investments),
              ),
              _GlassMetricCallout(
                icon: Icons.credit_card,
                label: 'Credit Cards',
                value: _formatSigned(cards),
              ),
              _GlassMetricCallout(
                icon: Icons.home_work,
                label: 'Loans',
                value: _formatSigned(loans),
              ),
            ],
          ),
        ),
        if (breakdown.isNotEmpty)
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(
                'View Breakdown',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.primary,
                ),
              ),
              iconColor: cs.primary,
              collapsedIconColor: cs.primary,
              children: [
                Container(
                  color: cs.surfaceContainerLowest.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Column(
                    children: breakdown.map((item) {
                      final balance = item['balance'] as num? ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['name']?.toString() ?? 'Account',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (item['bank'] != null)
                                    Text(
                                      item['bank'].toString(),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              _formatSigned(balance),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: balance >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                )
              ],
            ),
          ),
        if (lastUpdatedText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0, top: 4.0),
            child: Text(
              lastUpdatedText,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}



class _NetWorthShimmer extends StatelessWidget {
  const _NetWorthShimmer();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(width: 100, height: 16, color: baseColor),
            const SizedBox(height: 12),
            Container(width: 200, height: 36, color: baseColor),
            const SizedBox(height: 24),
            for (int i = 0; i < 4; i++) ...[
              Row(
                children: [
                  Container(width: 36, height: 36, decoration: BoxDecoration(color: baseColor, borderRadius: BorderRadius.circular(8))),
                  const SizedBox(width: 12),
                  Container(width: 120, height: 16, color: baseColor),
                  const Spacer(),
                  Container(width: 80, height: 16, color: baseColor),
                ],
              ),
              if (i < 3) const SizedBox(height: 12),
            ]
          ],
        ),
      ),
    );
  }
}

class _GlassMetricCallout extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _GlassMetricCallout({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

