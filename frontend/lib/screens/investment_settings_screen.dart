import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/investment_rule.dart';
import '../models/unified_transaction_models.dart';
import '../providers/asset_classes_provider.dart';
import '../providers/investment_rule_provider.dart';
import '../providers/unmapped_investments_provider.dart';
import '../widgets/charts/chart_helpers.dart';

final _currencyFmt = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

class InvestmentSettingsScreen extends ConsumerStatefulWidget {
  const InvestmentSettingsScreen({super.key});

  @override
  ConsumerState<InvestmentSettingsScreen> createState() =>
      _InvestmentSettingsScreenState();
}

class _InvestmentSettingsScreenState
    extends ConsumerState<InvestmentSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Investment Settings'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          tabs: const [
            Tab(text: 'Asset Classes', icon: Icon(Icons.pie_chart_outline)),
            Tab(text: 'Mapping Rules', icon: Icon(Icons.rule_folder_outlined)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _AssetClassesTab(),
          _MappingRulesTab(),
        ],
      ),
    );
  }
}

// ── Asset Classes Tab ──────────────────────────────────────────────────
class _AssetClassesTab extends ConsumerWidget {
  const _AssetClassesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(assetClassesProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (classes) {
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddClassDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('New Asset Class'),
          ),
          body: classes.isEmpty
              ? Center(
                  child: Text(
                    'No asset classes configured.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: classes.length,
                  itemBuilder: (context, index) {
                    final c = classes[index];
                    final color = parseColor(c.colorHex);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      elevation: 0,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.2),
                          child: Icon(
                            getIconDataFromString(c.iconName),
                            color: color,
                          ),
                        ),
                        title: Text(
                          c.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Color: ${c.colorHex} • Icon: ${c.iconName}',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          color: cs.error,
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Asset Class?'),
                                content: Text(
                                  'Are you sure you want to delete "${c.name}"?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(
                                      'Delete',
                                      style: TextStyle(color: cs.error),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              ref
                                  .read(assetClassesProvider.notifier)
                                  .deleteClass(c.id);
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  void _showAddClassDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();

    final predefinedColors = [
      '#4CAF50',
      '#2196F3',
      '#9C27B0',
      '#FF9800',
      '#E91E63',
      '#00BCD4',
      '#607D8B',
      '#F44336',
    ];

    final predefinedIcons = [
      'pie_chart',
      'show_chart',
      'account_balance',
      'diamond',
      'currency_bitcoin',
      'house',
      'business',
      'savings',
      'attach_money',
      'trending_up',
      'account_balance_wallet',
    ];

    String selectedColor = predefinedColors[0];
    String selectedIcon = predefinedIcons[0];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final cs = Theme.of(context).colorScheme;
          return AlertDialog(
            title: const Text('New Asset Class'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Asset Name',
                      hintText: 'e.g. Mutual Funds, Stocks, Gold',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Select Color',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: predefinedColors.map((colorHex) {
                      final isSelected = selectedColor == colorHex;
                      return GestureDetector(
                        onTap: () => setState(() => selectedColor = colorHex),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: parseColor(colorHex),
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: cs.onSurface, width: 3)
                                : null,
                            boxShadow: [
                              if (isSelected)
                                BoxShadow(
                                  color: parseColor(colorHex)
                                      .withValues(alpha: 0.5),
                                  blurRadius: 8,
                                ),
                            ],
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Select Icon',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: predefinedIcons.map((iconName) {
                      final isSelected = selectedIcon == iconName;
                      return ChoiceChip(
                        label: Icon(
                          getIconDataFromString(iconName),
                          color: isSelected
                              ? cs.onPrimaryContainer
                              : cs.onSurface,
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) setState(() => selectedIcon = iconName);
                        },
                        showCheckmark: false,
                        backgroundColor: cs.surfaceContainerHighest,
                        selectedColor: cs.primaryContainer,
                        padding: const EdgeInsets.all(8),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (nameCtrl.text.isNotEmpty) {
                    ref.read(assetClassesProvider.notifier).addClass(
                          nameCtrl.text,
                          selectedColor,
                          selectedIcon,
                        );
                    Navigator.pop(ctx);
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Save'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Mapping Rules Tab ──────────────────────────────────────────────────
class _MappingRulesTab extends ConsumerWidget {
  const _MappingRulesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesState = ref.watch(investmentRuleProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return rulesState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (rules) {
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddOrEditRuleDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('New Rule'),
          ),
          body: Column(
            children: [
              // Top Banner & Batch Dry Run Action Card
              Card(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                elevation: 0,
                color: cs.primaryContainer.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: cs.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.alt_route,
                          color: cs.onPrimary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Automated Classification Rules',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Rules match categories, merchants, or keywords to map transactions into investment asset classes.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: rules.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.rule_outlined,
                                size: 56,
                                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No mapping rules configured yet',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Create a mapping rule to automatically classify transactions from Groww, Zerodha, PPF, NPS, or bank statements.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: rules.length,
                        itemBuilder: (context, index) {
                          final rule = rules[index];
                          final assetClassColor = parseColor(
                            rule.assetClass?.colorHex ?? '#4CAF50',
                          );

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.5),
                              ),
                            ),
                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          rule.platformName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.arrow_right_alt,
                                        size: 18,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: assetClassColor
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              getIconDataFromString(
                                                rule.assetClass?.iconName ??
                                                    'account_balance_wallet',
                                              ),
                                              size: 14,
                                              color: assetClassColor,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              rule.assetClass?.name ??
                                                  'Unmapped',
                                              style: TextStyle(
                                                color: assetClassColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      // Edit Rule
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 20),
                                        tooltip: 'Edit Rule',
                                        onPressed: () =>
                                            _showAddOrEditRuleDialog(
                                          context,
                                          ref,
                                          rule: rule,
                                        ),
                                      ),
                                      // Delete Rule
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 20,
                                        ),
                                        color: cs.error,
                                        tooltip: 'Delete Rule',
                                        onPressed: () async {
                                          final confirm =
                                              await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text(
                                                'Delete Rule?',
                                              ),
                                              content: Text(
                                                'Are you sure you want to delete the rule for "${rule.platformName}"?',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, false),
                                                  child: const Text('Cancel'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  child: Text(
                                                    'Delete',
                                                    style: TextStyle(
                                                      color: cs.error,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            ref
                                                .read(
                                                  investmentRuleProvider
                                                      .notifier,
                                                )
                                                .deleteRule(rule.id);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        'Matching Keywords:',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      ...rule.keywords
                                          .split(',')
                                          .map((k) => k.trim())
                                          .where((k) => k.isNotEmpty)
                                          .map(
                                            (kw) => Chip(
                                              label: Text(
                                                kw,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                              padding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              side: BorderSide.none,
                                              backgroundColor: cs
                                                  .surfaceContainerHighest
                                                  .withValues(alpha: 0.6),
                                            ),
                                          ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Individual Dry Run Button
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton.tonalIcon(
                                      onPressed: () =>
                                          _runSingleDryRun(context, ref, rule),
                                      icon: const Icon(
                                        Icons.science_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('Dry Run Rule'),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Single Rule Dry Run Modal ──────────────────────────────────────────
  void _runSingleDryRun(
    BuildContext context,
    WidgetRef ref,
    InvestmentRule rule,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final unmapped = await ref.read(unmappedInvestmentsProvider.future);
      final keywords =
          rule.keywords.toLowerCase().split(',').map((k) => k.trim()).toList();

      final matches = unmapped.where((tx) {
        final desc = (tx.description ?? '').toLowerCase();
        final merchant = (tx.merchantName ?? '').toLowerCase();
        final platform = rule.platformName.toLowerCase();

        final matchesPlatform = desc.contains(platform) || merchant.contains(platform);
        final matchesKeyword = keywords.any(
          (kw) => kw.isNotEmpty && (desc.contains(kw) || merchant.contains(kw)),
        );
        return matchesPlatform || matchesKeyword;
      }).toList();

      if (context.mounted) Navigator.pop(context); // dismiss loader

      if (context.mounted) {
        _showDryRunResultsDialog(
          context,
          title: 'Dry Run Result: ${rule.platformName}',
          matches: matches,
          targetAssetClass: rule.assetClass?.name ?? 'Target Asset Class',
        );
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dry Run Error: $e')),
        );
      }
    }
  }

  void _showDryRunResultsDialog(
    BuildContext context, {
    required String title,
    required List<UnifiedTransaction> matches,
    required String targetAssetClass,
  }) {
    final cs = Theme.of(context).colorScheme;
    final totalSum = matches.fold<double>(0, (s, tx) => s + (tx.amount ?? 0.0));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.analytics_outlined, color: Colors.teal),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Matching Transactions',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                          Text(
                            '${matches.length}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Capital Target: $targetAssetClass',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSecondaryContainer,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _currencyFmt.format(totalSum),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sample Matched Transactions:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              if (matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No existing unmapped transactions match this rule.'),
                  ),
                )
              else
                SizedBox(
                  height: 240,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final tx = matches[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.receipt, size: 20),
                        title: Text(
                          tx.merchantName ?? tx.description ?? 'Transaction',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${tx.date ?? ''} • ${tx.bank ?? ''}'),
                        trailing: Text(
                          _currencyFmt.format(tx.amount ?? 0.0),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAddOrEditRuleDialog(
    BuildContext context,
    WidgetRef ref, {
    InvestmentRule? rule,
  }) {
    final isEditing = rule != null;
    final platformCtrl = TextEditingController(text: rule?.platformName ?? '');
    final keywordsCtrl = TextEditingController(text: rule?.keywords ?? '');
    int? selectedAssetClassId = rule?.assetClassId;

    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final classesState = ref.watch(assetClassesProvider);
          return AlertDialog(
            title: Text(isEditing ? 'Edit Mapping Rule' : 'New Mapping Rule'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: platformCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Platform / Merchant Name',
                      hintText: 'e.g. Zerodha, Groww, PPF, NPS',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business),
                    ),
                  ),
                  const SizedBox(height: 16),
                  classesState.when(
                    data: (classes) {
                      if (selectedAssetClassId == null && classes.isNotEmpty) {
                        selectedAssetClassId = classes.first.id;
                      }
                      return DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Target Asset Class',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        initialValue: selectedAssetClassId,
                        items: classes
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: parseColor(c.colorHex),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(c.name),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) => selectedAssetClassId = val,
                      );
                    },
                    loading: () => const CircularProgressIndicator(),
                    error: (e, _) => Text('Error loading classes: $e'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: keywordsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Match Keywords (comma-separated)',
                      hintText: 'e.g. mutual fund, sip, zerodha, groww',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.vpn_key),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (platformCtrl.text.isNotEmpty &&
                      selectedAssetClassId != null &&
                      keywordsCtrl.text.isNotEmpty) {
                    if (isEditing) {
                      ref.read(investmentRuleProvider.notifier).updateRule(
                            rule.id,
                            platformCtrl.text,
                            selectedAssetClassId!,
                            keywordsCtrl.text,
                          );
                    } else {
                      ref.read(investmentRuleProvider.notifier).addRule(
                            platformCtrl.text,
                            selectedAssetClassId!,
                            keywordsCtrl.text,
                          );
                    }
                    Navigator.pop(ctx);
                  }
                },
                icon: const Icon(Icons.check),
                label: Text(isEditing ? 'Update Rule' : 'Save Rule'),
              ),
            ],
          );
        },
      ),
    );
  }
}
