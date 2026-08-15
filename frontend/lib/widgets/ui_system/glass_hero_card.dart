import 'dart:ui';
import 'package:flutter/material.dart';

/// Glassmorphic Hero Card — reusable top-of-page header component
/// supporting backdrop blur, smooth theme-aware gradients, subtle glass borders,
/// and flexible metric callouts & action buttons.
class GlassHeroCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? icon;
  final List<Color>? gradientColors;
  final List<Widget>? metrics;
  final List<Widget>? actions;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const GlassHeroCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.gradientColors,
    this.metrics,
    this.actions,
    this.padding = const EdgeInsets.all(24.0),
    this.margin = const EdgeInsets.all(16.0),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final colors = gradientColors ??
        (isDark
            ? [
                Colors.teal.shade900.withValues(alpha: 0.85),
                Colors.indigo.shade900.withValues(alpha: 0.70),
                cs.surface.withValues(alpha: 0.90),
              ]
            : [
                cs.primary.withValues(alpha: 0.90),
                cs.secondary.withValues(alpha: 0.80),
                cs.tertiary.withValues(alpha: 0.85),
              ]);

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? Colors.black : cs.primary.withValues(alpha: 0.2))
                      .withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (icon != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.25),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: icon,
                      ),
                      const SizedBox(width: 16),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (actions != null && actions!.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Row(children: actions!),
                    ],
                  ],
                ),
                if (metrics != null && metrics!.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 24,
                    runSpacing: 16,
                    children: metrics!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
