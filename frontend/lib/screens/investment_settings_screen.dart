import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/asset_classes_provider.dart';
import '../providers/investment_rule_provider.dart';
import '../providers/unmapped_investments_provider.dart';
import '../models/unified_transaction_models.dart';
import '../widgets/charts/chart_helpers.dart';

class InvestmentSettingsScreen extends ConsumerStatefulWidget {
  const InvestmentSettingsScreen({super.key});

  @override
  ConsumerState<InvestmentSettingsScreen> createState() => _InvestmentSettingsScreenState();
}

class _InvestmentSettingsScreenState extends ConsumerState<InvestmentSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
            Tab(text: 'Asset Classes', icon: Icon(Icons.pie_chart)),
            Tab(text: 'Mapping Rules', icon: Icon(Icons.rule)),
            Tab(text: 'Inbox', icon: Icon(Icons.inbox)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _AssetClassesTab(),
          _MappingRulesTab(),
          _UnmappedInboxTab(),
        ],
      ),
    );
  }
}

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
                  child: Text('No asset classes configured.',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: classes.length,
                  itemBuilder: (context, index) {
                    final c = classes[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      elevation: 0,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: parseColor(c.colorHex).withValues(alpha: 0.2),
                          child: Icon(getIconDataFromString(c.iconName), color: parseColor(c.colorHex)),
                        ),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          color: cs.error,
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Asset Class?'),
                                content: const Text('Are you sure you want to delete this class?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text('Delete', style: TextStyle(color: cs.error)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              ref.read(assetClassesProvider.notifier).deleteClass(c.id);
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
      '#4CAF50', '#2196F3', '#9C27B0', '#FF9800', 
      '#E91E63', '#00BCD4', '#607D8B', '#F44336',
    ];
    
    final predefinedIcons = [
      'pie_chart', 'show_chart', 'account_balance', 'diamond',
      'currency_bitcoin', 'house', 'business', 'savings',
      'attach_money', 'trending_up', 'account_balance_wallet',
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
                      hintText: 'e.g. Mutual Funds',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Select Color', style: TextStyle(fontWeight: FontWeight.bold)),
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
                            border: isSelected ? Border.all(color: cs.onSurface, width: 3) : null,
                            boxShadow: [
                              if (isSelected) BoxShadow(color: parseColor(colorHex).withValues(alpha: 0.5), blurRadius: 8)
                            ],
                          ),
                          child: isSelected ? const Icon(Icons.check, color: Colors.white) : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text('Select Icon', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: predefinedIcons.map((iconName) {
                      final isSelected = selectedIcon == iconName;
                      return ChoiceChip(
                        label: Icon(getIconDataFromString(iconName), color: isSelected ? cs.onPrimaryContainer : cs.onSurface),
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
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton.icon(
                onPressed: () {
                  if (nameCtrl.text.isNotEmpty) {
                    ref.read(assetClassesProvider.notifier).addClass(nameCtrl.text, selectedColor, selectedIcon);
                    Navigator.pop(ctx);
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Save'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          );
        }
      ),
    );
  }
}

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
        if (rules.isEmpty) {
          return Center(
            child: Text('No mapping rules yet.', style: TextStyle(color: cs.onSurfaceVariant)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rules.length,
          itemBuilder: (context, index) {
            final rule = rules[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              elevation: 0,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: Text(rule.platformName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Class: ${rule.assetClass?.name ?? 'Unknown'}\nKeywords: ${rule.keywords}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: cs.error,
                  onPressed: () async {
                    ref.read(investmentRuleProvider.notifier).deleteRule(rule.id);
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _UnmappedInboxTab extends ConsumerStatefulWidget {
  const _UnmappedInboxTab();

  @override
  ConsumerState<_UnmappedInboxTab> createState() => _UnmappedInboxTabState();
}

class _UnmappedInboxTabState extends ConsumerState<_UnmappedInboxTab> {
  final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    final inboxState = ref.watch(unmappedInvestmentsProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return inboxState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (transactions) {
        if (transactions.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: cs.primary.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text('Inbox Zero!', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('All your investments are perfectly mapped.', style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final tx = transactions[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: cs.errorContainer,
                          child: Icon(Icons.help_outline, color: cs.onErrorContainer),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${(tx.merchantName?.isNotEmpty == true ? tx.merchantName : tx.description) ?? 'Unknown'}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(tx.date ?? '', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                            ],
                          ),
                        ),
                        Text(
                          _currencyFormat.format(tx.amount),
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _showMappingDialog(context, ref, tx),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Map this Investment'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMappingDialog(BuildContext context, WidgetRef ref, UnifiedTransaction tx) async {
    final assetClasses = ref.read(assetClassesProvider).value ?? [];
    if (assetClasses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please create an Asset Class first.')));
      return;
    }

    final platformCtrl = TextEditingController(text: tx.merchantName ?? '');
    final keywordCtrl = TextEditingController(text: tx.merchantName ?? '');
    int selectedAssetClassId = assetClasses.first.id;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Smart Mapping'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Platform Name'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: platformCtrl,
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'e.g. Zerodha, Groww'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Asset Class'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: selectedAssetClassId,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: assetClasses.map((ac) => DropdownMenuItem(
                      value: ac.id,
                      child: Text(ac.name),
                    )).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => selectedAssetClassId = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Matching Keyword'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: keywordCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(), 
                      hintText: 'e.g. ZERODHA',
                      helperText: 'Any transaction matching this keyword will be mapped automatically.',
                      helperMaxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  if (platformCtrl.text.isNotEmpty && keywordCtrl.text.isNotEmpty) {
                    try {
                      await ref.read(investmentRuleProvider.notifier).addRule(
                        platformCtrl.text,
                        selectedAssetClassId,
                        keywordCtrl.text,
                      );
                      if (tx.id != null) {
                        ref.read(unmappedInvestmentsProvider.notifier).removeMappedTransaction(tx.id!);
                      }
                      if (context.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  }
                },
                child: const Text('Save Rule'),
              ),
            ],
          );
        }
      ),
    );
  }
}
