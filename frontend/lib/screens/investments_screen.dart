import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/analytics_models.dart';
import '../models/unified_transaction_models.dart';
import '../providers/dashboard_provider.dart';
import '../services/api/analytics_api.dart';
import '../services/api/transaction_api.dart';
import '../widgets/charts/chart_helpers.dart';
import '../widgets/charts/investment_trend_chart.dart';
import 'investment_settings_screen.dart';

final _currencyFmt = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
final _currencyFmtDec = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

class InvestmentsScreen extends ConsumerWidget {
  const InvestmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashState = ref.watch(dashboardProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final analytics = dashState.investmentAnalytics;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Investment Portfolio'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh Portfolio',
                onPressed: () => ref.read(dashboardProvider.notifier).loadDashboard(),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Investment Settings',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const InvestmentSettingsScreen(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          if (dashState.isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (analytics == null || analytics.totalInvested == 0)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.trending_up,
                          size: 64,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'No Investments Tracked Yet',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Import bank statements with investment transactions, then configure mapping rules to classify them into Stocks, Mutual Funds, PPF, Gold, FD, and more.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const InvestmentSettingsScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.settings),
                        label: const Text('Configure Mapping Rules'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            // ── Glassmorphic Hero Header ──
            SliverToBoxAdapter(
              child: _GlassmorphicHeroHeader(analytics: analytics),
            ),

            // ── Investment Velocity Trend Chart ──
            if (analytics.trends.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: InvestmentTrendChart(data: analytics.trends),
                    ),
                  ),
                ),
              ),

            // ── Asset Class Breakdown Section Header ──
            if (analytics.assetClasses.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 8.0),
                  child: Row(
                    children: [
                      Text(
                        'Asset Allocation Breakdown',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${analytics.assetClasses.length} Classes',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Tap cards for breakdown',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Modern Asset Class Cards Grid ──
            if (analytics.assetClasses.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    mainAxisSpacing: 12.0,
                    crossAxisSpacing: 12.0,
                    childAspectRatio: 1.25,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final asset = analytics.assetClasses[index];
                      return _AssetClassCard(
                        asset: asset,
                        onTap: () => _showAssetBreakdownModal(
                          context,
                          asset,
                          analytics.platforms,
                        ),
                      );
                    },
                    childCount: analytics.assetClasses.length,
                  ),
                ),
              ),

            // ── Top Platforms Section ──
            if (analytics.platforms.isNotEmpty)
              SliverToBoxAdapter(
                child: _TopPlatformsSection(platforms: analytics.platforms),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ],
      ),
    );
  }

  void _showAssetBreakdownModal(
    BuildContext context,
    InvestmentAsset asset,
    List<InvestmentPlatform> platforms,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AssetClassDetailSheet(
        asset: asset,
        allPlatforms: platforms,
      ),
    );
  }
}

// ── Glassmorphic Hero Header ─────────────────────────────────────────────
class _GlassmorphicHeroHeader extends StatelessWidget {
  final InvestmentAnalytics analytics;

  const _GlassmorphicHeroHeader({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final topPlatform = analytics.platforms.isNotEmpty
        ? analytics.platforms.first.platform
        : 'N/A';

    return Container(
      margin: const EdgeInsets.all(16.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
          child: Container(
            padding: const EdgeInsets.all(28.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        Colors.teal.shade900.withValues(alpha: 0.85),
                        Colors.green.shade900.withValues(alpha: 0.70),
                        cs.surface.withValues(alpha: 0.90),
                      ]
                    : [
                        Colors.green.shade700.withValues(alpha: 0.90),
                        Colors.teal.shade600.withValues(alpha: 0.85),
                        cs.primary.withValues(alpha: 0.95),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? Colors.black : Colors.green.shade800)
                      .withValues(alpha: 0.3),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Decorative ambient glass circle background blur
                Positioned(
                  right: -30,
                  top: -30,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_user_outlined,
                                size: 14,
                                color: Colors.white,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Portfolio Summary',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Top: $topPlatform',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Total Capital Deployed',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Animated Counting Number for Monetary Totals
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 0.0,
                        end: analytics.totalInvested,
                      ),
                      duration: const Duration(milliseconds: 1400),
                      curve: Curves.easeOutCubic,
                      builder: (context, val, child) {
                        return FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _currencyFmt.format(val),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.8,
                              fontFeatures: [FontFeature.tabularFigures()],
                              shadows: [
                                Shadow(
                                  color: Colors.black38,
                                  offset: Offset(0, 2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _HeroMiniChip(
                          icon: Icons.pie_chart,
                          label: '${analytics.assetClasses.length} Asset Classes',
                        ),
                        const SizedBox(width: 12),
                        _HeroMiniChip(
                          icon: Icons.account_balance,
                          label: '${analytics.platforms.length} Platforms',
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroMiniChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroMiniChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Asset Class Card Widget ──────────────────────────────────────────────
class _AssetClassCard extends StatelessWidget {
  final InvestmentAsset asset;
  final VoidCallback onTap;

  const _AssetClassCard({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = parseColor(asset.color);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: onTap,
        splashColor: color.withValues(alpha: 0.15),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      getIconDataFromString(asset.icon),
                      color: color,
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${asset.percentage.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                asset.assetClass,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _currencyFmt.format(asset.totalInvested),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.green.shade600,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Asset Class Detail Modal Sheet ───────────────────────────────────────
class _AssetClassDetailSheet extends StatefulWidget {
  final InvestmentAsset asset;
  final List<InvestmentPlatform> allPlatforms;

  const _AssetClassDetailSheet({
    required this.asset,
    required this.allPlatforms,
  });

  @override
  State<_AssetClassDetailSheet> createState() => _AssetClassDetailSheetState();
}

class _AssetClassDetailSheetState extends State<_AssetClassDetailSheet> {
  bool _isLoading = true;
  List<UnifiedTransaction> _transactions = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchBreakdownData();
  }

  Future<void> _fetchBreakdownData() async {
    try {
      final txs = await AnalyticsApi.getAssetClassTransactions(
        widget.asset.assetClass,
      );
      if (mounted) {
        setState(() {
          _transactions = txs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = parseColor(widget.asset.color);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle indicator
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Sheet Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  radius: 22,
                  child: Icon(
                    getIconDataFromString(widget.asset.icon),
                    color: color,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.asset.assetClass,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${widget.asset.percentage.toStringAsFixed(1)}% of total portfolio',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _currencyFmt.format(widget.asset.totalInvested),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.green.shade600,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      'Total Deployed',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(
                          'Error loading breakdown: $_error',
                          style: TextStyle(color: cs.error),
                        ),
                      )
                    : _transactions.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.receipt_long,
                                    size: 48,
                                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No specific transaction logs found',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Transactions for this asset class may be mapped via automated investment rules.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(20),
                            itemCount: _transactions.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final tx = _transactions[index];
                              return Card(
                                elevation: 0,
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: cs.outlineVariant.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: color.withValues(alpha: 0.15),
                                    child: Icon(
                                      Icons.account_balance_wallet,
                                      color: color,
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    tx.merchantName ?? tx.description ?? 'Transaction',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${tx.date ?? ''} • ${tx.bank ?? 'Bank'} ${tx.accountIdentifier ?? ''}',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: Text(
                                    _currencyFmtDec.format(tx.amount ?? 0.0),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.green.shade600,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ── Top Platforms Section (capped, expandable) ──────────────
class _TopPlatformsSection extends StatefulWidget {
  final List<InvestmentPlatform> platforms;

  const _TopPlatformsSection({required this.platforms});

  @override
  State<_TopPlatformsSection> createState() => _TopPlatformsSectionState();
}

class _TopPlatformsSectionState extends State<_TopPlatformsSection> {
  static const _defaultVisibleCount = 4;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final allPlatforms = widget.platforms;
    final displayList = _showAll
        ? allPlatforms
        : allPlatforms.take(_defaultVisibleCount).toList();

    final maxInvested = allPlatforms.isNotEmpty
        ? allPlatforms.map((p) => p.totalInvested).reduce((a, b) => a > b ? a : b)
        : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 8.0),
          child: Row(
            children: [
              Text(
                'Top Platforms & Brokerages',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (allPlatforms.length > _defaultVisibleCount)
                TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(
                    _showAll
                        ? 'Show Less'
                        : 'View All (${allPlatforms.length})',
                  ),
                ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          itemCount: displayList.length,
          itemBuilder: (context, index) {
            final p = displayList[index];
            final ratio = (p.totalInvested / maxInvested).clamp(0.0, 1.0);

            return Card(
              margin: const EdgeInsets.only(bottom: 10.0),
              elevation: 0,
              color: cs.surfaceContainerLowest,
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: cs.primaryContainer,
                          child: Icon(
                            Icons.business_outlined,
                            color: cs.onPrimaryContainer,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                p.platform,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${p.percentage.toStringAsFixed(1)}% of portfolio',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _currencyFmt.format(p.totalInvested),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.green.shade600,
                            fontWeight: FontWeight.bold,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: cs.surfaceContainerHighest,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
