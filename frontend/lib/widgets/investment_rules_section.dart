import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/investment_rule.dart';
import '../providers/investment_rule_provider.dart';
import '../providers/dashboard_provider.dart';

class InvestmentRulesSection extends ConsumerWidget {
  const InvestmentRulesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ruleState = ref.watch(investmentRuleProvider);
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ExpansionTile(
        title: const Text('Config: Platform Classification Rules', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Map vendors/platforms to Asset Classes', style: TextStyle(fontSize: 12)),
        leading: Icon(Icons.rule_folder_outlined, color: theme.colorScheme.primary),
        childrenPadding: const EdgeInsets.all(8.0),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _showRuleDialog(context, ref, null),
              icon: const Icon(Icons.add),
              label: const Text('Add Rule'),
            ),
          ),
          ruleState.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
            error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('Error loading rules: $e')),
            data: (rules) {
              if (rules.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No rules found. Add one above.'),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rules.length,
                itemBuilder: (context, index) {
                  final rule = rules[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                    title: Row(
                      children: [
                        Text(rule.assetClass, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_ios, size: 10, color: theme.colorScheme.outline),
                        const SizedBox(width: 8),
                        Text(rule.platformName, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13)),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: rule.keywords.split(',').where((k) => k.trim().isNotEmpty).map((k) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(k.trim(), style: const TextStyle(fontSize: 10)),
                          );
                        }).toList(),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _showRuleDialog(context, ref, rule),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          onPressed: () => _deleteRule(context, ref, rule),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showRuleDialog(BuildContext context, WidgetRef ref, InvestmentRule? rule) async {
    final platformController = TextEditingController(text: rule?.platformName);
    final keywordsController = TextEditingController(text: rule?.keywords);
    
    final assetClasses = [
      'Mutual Funds',
      'Stocks',
      'Fixed Deposits',
      'Recurring Deposits',
      'Insurance',
      'Commodities (Gold/Silver)',
      'Provident Funds',
      'Bonds',
      'Real Estate',
      'Other'
    ];
    String selectedAssetClass = rule?.assetClass ?? assetClasses.first;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(rule == null ? 'New Classification Rule' : 'Edit Rule'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: assetClasses.contains(selectedAssetClass) ? selectedAssetClass : 'Other',
                      decoration: const InputDecoration(
                        labelText: 'Asset Class',
                        border: OutlineInputBorder(),
                      ),
                      items: assetClasses.map((ac) {
                        return DropdownMenuItem(value: ac, child: Text(ac));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => selectedAssetClass = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: platformController,
                      decoration: const InputDecoration(
                        labelText: 'Platform / Bank',
                        hintText: 'e.g. Groww, SBI, LIC',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: keywordsController,
                      decoration: const InputDecoration(
                        labelText: 'Match Keywords',
                        hintText: 'e.g. groww, iccl, sgb',
                        border: OutlineInputBorder(),
                        helperText: 'Comma separated snippets found in bank statements.',
                        helperMaxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final platform = platformController.text.trim();
                    final keywords = keywordsController.text.trim();
                    if (platform.isNotEmpty) {
                      final notifier = ref.read(investmentRuleProvider.notifier);
                      try {
                        if (rule == null) {
                          await notifier.addRule(platform, selectedAssetClass, keywords);
                        } else {
                          await notifier.updateRule(rule.id, platform, selectedAssetClass, keywords);
                        }
                        if (context.mounted) Navigator.pop(context);
                        ref.read(dashboardProvider.notifier).loadDashboard();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error saving rule: $e')),
                          );
                        }
                      }
                    }
                  },
                  child: const Text('Save Rule'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _deleteRule(BuildContext context, WidgetRef ref, InvestmentRule rule) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Rule?'),
        content: Text('Delete classification rule for ${rule.platformName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(investmentRuleProvider.notifier).deleteRule(rule.id);
        ref.read(dashboardProvider.notifier).loadDashboard();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting rule: $e')),
          );
        }
      }
    }
  }
}
