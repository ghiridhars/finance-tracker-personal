/// Shared chart helpers — formatters, legend dot, color parser.
library;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final currencyFmtDec = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

String shortCurrency(double v) {
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
  return '₹${v.toInt()}';
}

String monthAbbr(int m) =>
    const ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
        .elementAtOrNull(m) ??
    '';

Color parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return Colors.grey;
  try {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return Colors.grey;
  }
}

class LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const LegendDot({super.key, required this.color, required this.label});

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

IconData getIconDataFromString(String name) {
  switch (name) {
    case 'pie_chart': return Icons.pie_chart;
    case 'show_chart': return Icons.show_chart;
    case 'account_balance': return Icons.account_balance;
    case 'diamond': return Icons.diamond;
    case 'currency_bitcoin': return Icons.currency_bitcoin;
    case 'house': return Icons.house;
    case 'business': return Icons.business;
    case 'savings': return Icons.savings;
    case 'attach_money': return Icons.attach_money;
    case 'trending_up': return Icons.trending_up;
    default: return Icons.account_balance_wallet;
  }
}
