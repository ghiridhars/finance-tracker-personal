import 'package:flutter/material.dart';

/// BadgePill — compact badge container for tags, status indicators, and counters.
class BadgePill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const BadgePill({
    super.key,
    required this.label,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.fontSize = 11.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  });

  factory BadgePill.success({
    required String label,
    IconData? icon = Icons.check_circle_outline,
  }) {
    return BadgePill(
      label: label,
      icon: icon,
      backgroundColor: Colors.green.shade900.withValues(alpha: 0.15),
      textColor: Colors.green.shade400,
    );
  }

  factory BadgePill.warning({
    required String label,
    IconData? icon = Icons.warning_amber_rounded,
  }) {
    return BadgePill(
      label: label,
      icon: icon,
      backgroundColor: Colors.amber.shade900.withValues(alpha: 0.15),
      textColor: Colors.amber.shade400,
    );
  }

  factory BadgePill.info({
    required String label,
    IconData? icon = Icons.info_outline,
  }) {
    return BadgePill(
      label: label,
      icon: icon,
      backgroundColor: Colors.blue.shade900.withValues(alpha: 0.15),
      textColor: Colors.blue.shade300,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bg = backgroundColor ?? cs.secondaryContainer;
    final fg = textColor ?? cs.onSecondaryContainer;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 3, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: fg,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
