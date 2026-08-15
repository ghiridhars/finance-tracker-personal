import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/classification_rule_models.dart';

import '../providers/classification_rules_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/transactions_provider.dart';
import '../services/api/classification_rules_api.dart';

class ClassificationRulesScreen extends ConsumerStatefulWidget {
  const ClassificationRulesScreen({super.key});

  @override
  ConsumerState<ClassificationRulesScreen> createState() => _ClassificationRulesScreenState();
}

class _ClassificationRulesScreenState extends ConsumerState<ClassificationRulesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(classificationRulesProvider.notifier).loadRules();
      ref.read(categoriesProvider.notifier).loadCategories();
    });
  }

  void _showRuleDialog([ClassificationRule? rule]) {
    showDialog(
      context: context,
      builder: (context) => ClassificationRuleDialog(rule: rule),
    );
  }

  Future<void> _deleteRule(ClassificationRule rule) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Rule'),
        content: Text('Are you sure you want to delete "${rule.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && rule.id != null) {
      try {
        await ref.read(classificationRulesProvider.notifier).deleteRule(rule.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rule deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete rule: $e')),
          );
        }
      }
    }
  }

  Future<void> _applyRule(ClassificationRule rule) async {
    if (rule.id == null) return;
    try {
      final res = await ClassificationRulesApi.applyRule(rule.id!);
      ref.invalidate(needsReviewCountProvider);
      ref.read(reviewRefreshTriggerProvider.notifier).increment();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rule applied! Updated ${res["updated_count"] ?? 0} transactions.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to apply rule: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rulesAsync = ref.watch(classificationRulesProvider);
    final categoriesState = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Classification Rules'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRuleDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Create Rule'),
      ),
      body: rulesAsync.when(
        data: (rules) {
          if (rules.isEmpty) {
            return const Center(child: Text('No classification rules found.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: rules.length,
            itemBuilder: (context, index) {
              final rule = rules[index];
              final categoryName = categoriesState.categories
                  .where((c) => c.id == rule.targetCategoryId)
                  .map((c) => c.name)
                  .firstOrNull ?? 'None';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(rule.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (rule.pattern != null) Text('Pattern: ${rule.pattern} ${rule.patternIsRegex ? "(Regex)" : ""}'),
                      Text('Target Category: $categoryName'),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.play_arrow_outlined),
                        tooltip: 'Apply Retroactively',
                        onPressed: () => _applyRule(rule),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit Rule',
                        onPressed: () => _showRuleDialog(rule),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        color: Theme.of(context).colorScheme.error,
                        tooltip: 'Delete Rule',
                        onPressed: () => _deleteRule(rule),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }
}

class ClassificationRuleDialog extends ConsumerStatefulWidget {
  final ClassificationRule? rule;
  const ClassificationRuleDialog({super.key, this.rule});

  @override
  ConsumerState<ClassificationRuleDialog> createState() => _ClassificationRuleDialogState();
}

class _ClassificationRuleDialogState extends ConsumerState<ClassificationRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _patternController;
  late bool _isRegex;
  int? _selectedCategoryId;
  bool _isSaving = false;
  String? _dryRunResult;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.rule?.name ?? '');
    _patternController = TextEditingController(text: widget.rule?.pattern ?? '');
    _isRegex = widget.rule?.patternIsRegex ?? false;
    _selectedCategoryId = widget.rule?.targetCategoryId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _patternController.dispose();
    super.dispose();
  }

  Future<void> _dryRun() async {
    if (widget.rule?.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save the rule first before dry running.')),
      );
      return;
    }
    try {
      final res = await ClassificationRulesApi.dryRunRule(widget.rule!.id!);
      setState(() {
        _dryRunResult = 'Matches ${res.matchedCount} transactions';
      });
    } catch (e) {
      setState(() {
        _dryRunResult = 'Failed: $e';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final rule = ClassificationRule(
      id: widget.rule?.id,
      name: _nameController.text.trim(),
      pattern: _patternController.text.trim().isEmpty ? null : _patternController.text.trim(),
      patternIsRegex: _isRegex,
      targetCategoryId: _selectedCategoryId,
    );

    try {
      int? returnedRuleId;
      if (rule.id == null) {
        final newRule = await ref.read(classificationRulesProvider.notifier).addRule(rule);
        returnedRuleId = newRule.id;
      } else {
        await ref.read(classificationRulesProvider.notifier).updateRule(rule.id!, rule);
        returnedRuleId = rule.id;
      }
      if (mounted) Navigator.pop(context, returnedRuleId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save rule: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesState = ref.watch(categoriesProvider);

    return AlertDialog(
      title: Text(widget.rule == null ? 'Create Rule' : 'Edit Rule'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                validator: (val) => val == null || val.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _patternController,
                decoration: const InputDecoration(labelText: 'Pattern', border: OutlineInputBorder()),
              ),
              SwitchListTile(
                title: const Text('Pattern is Regex'),
                value: _isRegex,
                onChanged: (val) => setState(() => _isRegex = val),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _selectedCategoryId,
                decoration: const InputDecoration(labelText: 'Target Category', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  ...categoriesState.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                ],
                onChanged: (val) => setState(() => _selectedCategoryId = val),
              ),
              if (widget.rule?.id != null) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.science),
                      label: const Text('Dry Run'),
                      onPressed: _dryRun,
                    ),
                    if (_dryRunResult != null)
                      Flexible(child: Text(_dryRunResult!, style: const TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
        ),
      ],
    );
  }
}
