/// Budget & Goals screen (Phase 5).
///
/// Sections:
///   1. Budget overview — month selector + progress bars per category
///   2. Savings goals — progress rings + contribute
///   3. Bill reminders — upcoming bills with overdue indicators
///   4. Recurring transactions — auto-detected patterns
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/budget_models.dart';
import '../models/category_models.dart';
import '../providers/budget_provider.dart';
import 'skeleton_widgets.dart';

final _currency =
    NumberFormat.currency(symbol: '\u20B9', decimalDigits: 2);

const _monthNames = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

// ─────────────────────────────────────────────────────────────
// Root widget
// ─────────────────────────────────────────────────────────────

class BudgetGoalsWidget extends ConsumerWidget {
  const BudgetGoalsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(budgetProvider);

    if (s.isLoading && s.budgetProgress.isEmpty && s.goals.isEmpty) {
      return const SkeletonBudgetGoals();
    }

    if (s.error != null &&
        s.budgetProgress.isEmpty &&
        s.goals.isEmpty &&
        s.reminders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text('Error loading data',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(s.error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref.read(budgetProvider.notifier).loadAll(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(budgetProvider.notifier).loadAll(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Budget Section ──
          _BudgetSection(state: s, ref: ref),
          const SizedBox(height: 24),
          // ── Savings Goals Section ──
          _GoalsSection(state: s, ref: ref),
          const SizedBox(height: 24),
          // ── Bill Reminders Section ──
          _RemindersSection(state: s, ref: ref),
          const SizedBox(height: 24),
          // ── Recurring Transactions Section ──
          _RecurringSection(state: s, ref: ref),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 1. Budget Section
// ─────────────────────────────────────────────────────────────

class _BudgetSection extends StatelessWidget {
  final BudgetState state;
  final WidgetRef ref;

  const _BudgetSection({required this.state, required this.ref});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + month selector
        Row(
          children: [
            Icon(Icons.pie_chart, color: cs.primary),
            const SizedBox(width: 8),
            Text('Budgets',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () =>
                  ref.read(budgetProvider.notifier).previousMonth(),
              tooltip: 'Previous month',
            ),
            Text(
              '${_monthNames[state.month]} ${state.year}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () =>
                  ref.read(budgetProvider.notifier).nextMonth(),
              tooltip: 'Next month',
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Summary card
        if (state.summary != null) _BudgetSummaryCard(summary: state.summary!),
        const SizedBox(height: 8),

        // Action buttons
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _showAddBudgetDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Budget'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(budgetProvider.notifier).copyFromPreviousMonth(),
              icon: const Icon(Icons.content_copy, size: 18),
              label: const Text('Copy Last Month'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Budget progress cards
        if (state.budgetProgress.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('No budgets set for this month',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6))),
              ),
            ),
          )
        else
          ...state.budgetProgress
              .map((bp) => _BudgetProgressCard(
                    progress: bp,
                    onDelete: () =>
                        ref.read(budgetProvider.notifier).deleteBudget(bp.id),
                    onEdit: () => _showEditBudgetDialog(context, bp),
                  )),
      ],
    );
  }

  void _showAddBudgetDialog(BuildContext context) {
    // Filter out categories that already have budgets this month
    final existingCategoryIds =
        state.budgetProgress.map((b) => b.categoryId).toSet();
    final availableCategories = state.categories
        .where((c) => !existingCategoryIds.contains(c.id))
        .toList();

    if (availableCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('All categories already have budgets this month')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => _AddBudgetDialog(
        categories: availableCategories,
        onSave: (categoryId, amount, rollover) {
          ref.read(budgetProvider.notifier).createBudget(
                categoryId: categoryId,
                amount: amount,
                rollover: rollover,
              );
        },
      ),
    );
  }

  void _showEditBudgetDialog(BuildContext context, BudgetProgress bp) {
    showDialog(
      context: context,
      builder: (_) => _EditBudgetDialog(
        progress: bp,
        onSave: (amount, rollover) {
          ref.read(budgetProvider.notifier).updateBudget(
                bp.id,
                amount: amount,
                rollover: rollover,
              );
        },
      ),
    );
  }
}

class _BudgetSummaryCard extends StatelessWidget {
  final BudgetSummary summary;
  const _BudgetSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = summary.overallPercentage.clamp(0.0, 100.0);
    final color = pct > 90
        ? Colors.red
        : pct > 70
            ? Colors.orange
            : Colors.green;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SummaryStat(
                  label: 'Budgeted',
                  value: _currency.format(summary.totalBudgeted),
                  color: cs.primary,
                ),
                _SummaryStat(
                  label: 'Spent',
                  value: _currency.format(summary.totalSpent),
                  color: color,
                ),
                _SummaryStat(
                  label: 'Over Budget',
                  value: '${summary.overBudgetCount}',
                  color: summary.overBudgetCount > 0
                      ? Colors.red
                      : Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: cs.surfaceContainerHighest,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text('${pct.toStringAsFixed(1)}% of total budget used',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold, color: color)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _BudgetProgressCard extends StatelessWidget {
  final BudgetProgress progress;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _BudgetProgressCard({
    required this.progress,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = progress.percentageUsed.clamp(0.0, 100.0);
    final color = progress.isOverBudget
        ? Colors.red
        : pct > 70
            ? Colors.orange
            : Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (progress.categoryIcon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(progress.categoryIcon!,
                        style: const TextStyle(fontSize: 20)),
                  ),
                Expanded(
                  child: Text(progress.categoryName,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: onEdit,
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(Icons.delete, size: 18, color: cs.error),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Spent: ${_currency.format(progress.spentAmount)}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w500),
                ),
                Text(
                  'of ${_currency.format(progress.budgetAmount)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${pct.toStringAsFixed(1)}%',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: color)),
                if (progress.rolloverAmount > 0)
                  Text(
                    'Rollover: ${_currency.format(progress.rolloverAmount)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                Text(
                  'Remaining: ${_currency.format(progress.remaining)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: progress.remaining < 0 ? Colors.red : null),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Budget Dialogs ──────────────────────────────────────────

class _AddBudgetDialog extends StatefulWidget {
  final List<Category> categories;
  final void Function(int categoryId, double amount, bool rollover) onSave;

  const _AddBudgetDialog({required this.categories, required this.onSave});

  @override
  State<_AddBudgetDialog> createState() => _AddBudgetDialogState();
}

class _AddBudgetDialogState extends State<_AddBudgetDialog> {
  int? _selectedCategoryId;
  final _amountCtrl = TextEditingController();
  bool _rollover = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Budget'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            value: _selectedCategoryId,
            items: widget.categories
                .map((c) => DropdownMenuItem(
                    value: c.id,
                    child: Text(
                        '${c.icon ?? ""} ${c.name}'.trim())))
                .toList(),
            onChanged: (v) => setState(() => _selectedCategoryId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            decoration: const InputDecoration(
              labelText: 'Monthly Limit',
              prefixText: '\u20B9 ',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Rollover unused'),
            subtitle: const Text('Carry unspent budget to next month'),
            value: _rollover,
            onChanged: (v) => setState(() => _rollover = v),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amountCtrl.text);
            if (_selectedCategoryId != null && amount != null && amount > 0) {
              widget.onSave(_selectedCategoryId!, amount, _rollover);
              Navigator.pop(context);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _EditBudgetDialog extends StatefulWidget {
  final BudgetProgress progress;
  final void Function(double amount, bool rollover) onSave;

  const _EditBudgetDialog({required this.progress, required this.onSave});

  @override
  State<_EditBudgetDialog> createState() => _EditBudgetDialogState();
}

class _EditBudgetDialogState extends State<_EditBudgetDialog> {
  late final TextEditingController _amountCtrl;
  late bool _rollover;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
        text: widget.progress.budgetAmount.toStringAsFixed(2));
    _rollover = widget.progress.rolloverAmount > 0;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.progress.categoryName} Budget'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amountCtrl,
            decoration: const InputDecoration(
              labelText: 'Monthly Limit',
              prefixText: '\u20B9 ',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Rollover unused'),
            value: _rollover,
            onChanged: (v) => setState(() => _rollover = v),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amountCtrl.text);
            if (amount != null && amount > 0) {
              widget.onSave(amount, _rollover);
              Navigator.pop(context);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 2. Savings Goals Section
// ─────────────────────────────────────────────────────────────

class _GoalsSection extends StatelessWidget {
  final BudgetState state;
  final WidgetRef ref;
  const _GoalsSection({required this.state, required this.ref});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.flag, color: cs.primary),
            const SizedBox(width: 8),
            Text('Savings Goals',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: () =>
                  ref.read(budgetProvider.notifier).toggleShowCompletedGoals(),
              icon: Icon(state.showCompletedGoals
                  ? Icons.visibility_off
                  : Icons.visibility,
                  size: 18),
              label: Text(state.showCompletedGoals ? 'Hide done' : 'Show done'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => _showAddGoalDialog(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New Goal'),
        ),
        const SizedBox(height: 12),
        if (state.goals.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('No savings goals yet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6))),
              ),
            ),
          )
        else
          ...state.goals.map((g) => _GoalCard(
                goal: g,
                onContribute: () => _showContributeDialog(context, g),
                onDelete: () =>
                    ref.read(budgetProvider.notifier).deleteGoal(g.id),
              )),
      ],
    );
  }

  void _showAddGoalDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _AddGoalDialog(
        onSave: (name, target, current, deadline) {
          ref.read(budgetProvider.notifier).createGoal(
                name: name,
                targetAmount: target,
                currentAmount: current,
                deadline: deadline,
              );
        },
      ),
    );
  }

  void _showContributeDialog(BuildContext context, SavingsGoal goal) {
    showDialog(
      context: context,
      builder: (_) => _ContributeDialog(
        goal: goal,
        onContribute: (amount) {
          ref.read(budgetProvider.notifier).contributeToGoal(goal.id, amount);
        },
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final SavingsGoal goal;
  final VoidCallback onContribute;
  final VoidCallback onDelete;
  const _GoalCard(
      {required this.goal, required this.onContribute, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = goal.percentage.clamp(0.0, 100.0);
    final color = goal.isCompleted
        ? Colors.green
        : pct > 70
            ? Colors.blue
            : cs.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (goal.icon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child:
                        Text(goal.icon!, style: const TextStyle(fontSize: 22)),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(goal.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (goal.daysRemaining != null)
                        Text(
                          goal.isCompleted
                              ? 'Completed!'
                              : '${goal.daysRemaining} days left',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: goal.isCompleted
                                  ? Colors.green
                                  : (goal.daysRemaining! < 30
                                      ? Colors.orange
                                      : null)),
                        ),
                    ],
                  ),
                ),
                if (!goal.isCompleted)
                  IconButton(
                    icon: const Icon(Icons.add_circle, size: 20),
                    onPressed: onContribute,
                    tooltip: 'Contribute',
                    color: cs.primary,
                  ),
                IconButton(
                  icon: Icon(Icons.delete, size: 18, color: cs.error),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_currency.format(goal.currentAmount),
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: color)),
                Text('of ${_currency.format(goal.targetAmount)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: cs.surfaceContainerHighest,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text('${pct.toStringAsFixed(1)}%',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _AddGoalDialog extends StatefulWidget {
  final void Function(
      String name, double target, double current, String? deadline) onSave;
  const _AddGoalDialog({required this.onSave});

  @override
  State<_AddGoalDialog> createState() => _AddGoalDialogState();
}

class _AddGoalDialogState extends State<_AddGoalDialog> {
  final _nameCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _currentCtrl = TextEditingController(text: '0');
  DateTime? _deadline;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    _currentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Savings Goal'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Goal Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetCtrl,
              decoration: const InputDecoration(
                labelText: 'Target Amount',
                prefixText: '\u20B9 ',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _currentCtrl,
              decoration: const InputDecoration(
                labelText: 'Saved So Far',
                prefixText: '\u20B9 ',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_deadline == null
                  ? 'Set Deadline (optional)'
                  : 'Deadline: ${DateFormat.yMMMd().format(_deadline!)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate:
                      _deadline ?? DateTime.now().add(const Duration(days: 90)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2035),
                );
                if (d != null) setState(() => _deadline = d);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            final target = double.tryParse(_targetCtrl.text);
            final current = double.tryParse(_currentCtrl.text) ?? 0;
            if (name.isNotEmpty && target != null && target > 0) {
              widget.onSave(
                name,
                target,
                current,
                _deadline != null
                    ? DateFormat('yyyy-MM-dd').format(_deadline!)
                    : null,
              );
              Navigator.pop(context);
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _ContributeDialog extends StatefulWidget {
  final SavingsGoal goal;
  final void Function(double amount) onContribute;
  const _ContributeDialog({required this.goal, required this.onContribute});

  @override
  State<_ContributeDialog> createState() => _ContributeDialogState();
}

class _ContributeDialogState extends State<_ContributeDialog> {
  final _amountCtrl = TextEditingController();

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.goal.targetAmount - widget.goal.currentAmount;
    return AlertDialog(
      title: Text('Contribute to "${widget.goal.name}"'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Remaining: ${_currency.format(remaining > 0 ? remaining : 0)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: '\u20B9 ',
              border: OutlineInputBorder(),
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amountCtrl.text);
            if (amount != null && amount > 0) {
              widget.onContribute(amount);
              Navigator.pop(context);
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 3. Bill Reminders Section
// ─────────────────────────────────────────────────────────────

class _RemindersSection extends StatelessWidget {
  final BudgetState state;
  final WidgetRef ref;
  const _RemindersSection({required this.state, required this.ref});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.notifications_active, color: cs.primary),
            const SizedBox(width: 8),
            Text('Bill Reminders',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: () =>
                  ref.read(budgetProvider.notifier).toggleShowPaidReminders(),
              icon: Icon(state.showPaidReminders
                  ? Icons.visibility_off
                  : Icons.visibility,
                  size: 18),
              label: Text(state.showPaidReminders ? 'Hide paid' : 'Show paid'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _showAddReminderDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Reminder'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(budgetProvider.notifier).autoDetectReminders(),
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Auto-Detect CC Dues'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (state.reminders.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('No bill reminders',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6))),
              ),
            ),
          )
        else
          ...state.reminders.map((r) => _ReminderCard(
                reminder: r,
                onMarkPaid: () =>
                    ref.read(budgetProvider.notifier).markReminderPaid(r.id),
                onDelete: () =>
                    ref.read(budgetProvider.notifier).deleteReminder(r.id),
              )),
      ],
    );
  }

  void _showAddReminderDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _AddReminderDialog(
        categories: state.categories,
        onSave: ({
          required String name,
          double? amount,
          int? categoryId,
          String? frequency,
          int? dayOfMonth,
          String? nextDueDate,
        }) {
          ref.read(budgetProvider.notifier).createReminder(
                name: name,
                amount: amount,
                categoryId: categoryId,
                frequency: frequency,
                dayOfMonth: dayOfMonth,
                nextDueDate: nextDueDate,
              );
        },
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final BillReminder reminder;
  final VoidCallback onMarkPaid;
  final VoidCallback onDelete;

  const _ReminderCard({
    required this.reminder,
    required this.onMarkPaid,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isOverdue = reminder.isOverdue;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isOverdue ? Colors.red.shade50 : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isOverdue
              ? Colors.red.shade100
              : reminder.isPaid
                  ? Colors.green.shade100
                  : cs.primaryContainer,
          child: Icon(
            reminder.isPaid
                ? Icons.check_circle
                : isOverdue
                    ? Icons.warning
                    : Icons.notifications,
            color: isOverdue
                ? Colors.red
                : reminder.isPaid
                    ? Colors.green
                    : cs.primary,
          ),
        ),
        title: Row(
          children: [
            Expanded(child: Text(reminder.name)),
            if (reminder.isAutoDetected)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Chip(
                  label: const Text('Auto',
                      style: TextStyle(fontSize: 10)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reminder.amount != null)
              Text(_currency.format(reminder.amount),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            if (reminder.nextDueDate != null)
              Text(
                isOverdue
                    ? 'OVERDUE — was due ${reminder.nextDueDate}'
                    : reminder.daysUntilDue != null
                        ? 'Due in ${reminder.daysUntilDue} days (${reminder.nextDueDate})'
                        : 'Due: ${reminder.nextDueDate}',
                style: TextStyle(
                  fontSize: 12,
                  color: isOverdue ? Colors.red : null,
                  fontWeight: isOverdue ? FontWeight.w600 : null,
                ),
              ),
            if (reminder.frequency != null)
              Text('${reminder.frequency}',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!reminder.isPaid)
              IconButton(
                icon: const Icon(Icons.check, size: 20),
                onPressed: onMarkPaid,
                tooltip: 'Mark Paid',
                color: Colors.green,
              ),
            IconButton(
              icon: Icon(Icons.delete, size: 18, color: cs.error),
              onPressed: onDelete,
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _AddReminderDialog extends StatefulWidget {
  final List<Category> categories;
  final void Function({
    required String name,
    double? amount,
    int? categoryId,
    String? frequency,
    int? dayOfMonth,
    String? nextDueDate,
  }) onSave;

  const _AddReminderDialog({required this.categories, required this.onSave});

  @override
  State<_AddReminderDialog> createState() => _AddReminderDialogState();
}

class _AddReminderDialogState extends State<_AddReminderDialog> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  int? _categoryId;
  String _frequency = 'MONTHLY';
  DateTime? _nextDue;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Bill Reminder'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Bill Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: 'Amount (optional)',
                prefixText: '\u20B9 ',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
                border: OutlineInputBorder(),
              ),
              value: _categoryId,
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                ...widget.categories.map((c) => DropdownMenuItem(
                    value: c.id,
                    child: Text('${c.icon ?? ""} ${c.name}'.trim()))),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Frequency',
                border: OutlineInputBorder(),
              ),
              value: _frequency,
              items: const [
                DropdownMenuItem(value: 'MONTHLY', child: Text('Monthly')),
                DropdownMenuItem(value: 'QUARTERLY', child: Text('Quarterly')),
                DropdownMenuItem(value: 'YEARLY', child: Text('Yearly')),
              ],
              onChanged: (v) => setState(() => _frequency = v ?? 'MONTHLY'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_nextDue == null
                  ? 'Set Next Due Date'
                  : 'Due: ${DateFormat.yMMMd().format(_nextDue!)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _nextDue ?? DateTime.now(),
                  firstDate:
                      DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime(2035),
                );
                if (d != null) setState(() => _nextDue = d);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            final amount = double.tryParse(_amountCtrl.text);
            widget.onSave(
              name: name,
              amount: amount,
              categoryId: _categoryId,
              frequency: _frequency,
              dayOfMonth: _nextDue?.day,
              nextDueDate: _nextDue != null
                  ? DateFormat('yyyy-MM-dd').format(_nextDue!)
                  : null,
            );
            Navigator.pop(context);
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 4. Recurring Transactions Section
// ─────────────────────────────────────────────────────────────

class _RecurringSection extends StatelessWidget {
  final BudgetState state;
  final WidgetRef ref;
  const _RecurringSection({required this.state, required this.ref});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.repeat, color: cs.primary),
            const SizedBox(width: 8),
            Text('Recurring Transactions',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => ref.read(budgetProvider.notifier).detectRecurring(),
          icon: const Icon(Icons.search, size: 18),
          label: const Text('Detect Patterns'),
        ),
        const SizedBox(height: 12),
        if (state.recurring.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('No recurring patterns detected yet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6))),
              ),
            ),
          )
        else
          ...state.recurring.map((r) => _RecurringCard(
                recurring: r,
                onToggleSub: (v) => ref
                    .read(budgetProvider.notifier)
                    .toggleSubscription(r.id, v),
                onDelete: () =>
                    ref.read(budgetProvider.notifier).deleteRecurring(r.id),
              )),
      ],
    );
  }
}

class _RecurringCard extends StatelessWidget {
  final RecurringTransaction recurring;
  final void Function(bool) onToggleSub;
  final VoidCallback onDelete;

  const _RecurringCard({
    required this.recurring,
    required this.onToggleSub,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: recurring.isSubscription
              ? Colors.purple.shade100
              : cs.primaryContainer,
          child: Icon(
            recurring.isSubscription ? Icons.subscriptions : Icons.repeat,
            color:
                recurring.isSubscription ? Colors.purple : cs.primary,
          ),
        ),
        title: Text(recurring.merchantName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_currency.format(recurring.averageAmount)} avg  •  ${recurring.frequency}  •  ${recurring.occurrenceCount}x',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (recurring.category != null)
              Text('Category: ${recurring.category!.name}',
                  style: Theme.of(context).textTheme.bodySmall),
            if (recurring.nextExpectedDate != null)
              Text('Next: ${recurring.nextExpectedDate}',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: recurring.isSubscription
                  ? 'Unmark subscription'
                  : 'Mark as subscription',
              child: IconButton(
                icon: Icon(
                  recurring.isSubscription
                      ? Icons.star
                      : Icons.star_border,
                  color: recurring.isSubscription ? Colors.purple : null,
                  size: 20,
                ),
                onPressed: () =>
                    onToggleSub(!recurring.isSubscription),
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete, size: 18, color: cs.error),
              onPressed: onDelete,
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
