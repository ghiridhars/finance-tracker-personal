/// UPI ID management widget — used in account detail view and settings.
///
/// Shows UPI IDs linked to the current context (account or all),
/// with add/edit/delete capabilities and a rescan trigger.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/upi_models.dart';
import '../models/category_models.dart';
import '../providers/upi_provider.dart';
import '../providers/categories_provider.dart';

// ──────────────────────────────────────────────────────────────
// UPI IDs section for an account card (compact inline view)
// ──────────────────────────────────────────────────────────────

class AccountUpiSection extends ConsumerWidget {
  final String accountType;
  final String accountIdentifier;

  const AccountUpiSection({
    super.key,
    required this.accountType,
    required this.accountIdentifier,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upiState = ref.watch(upiProvider);
    final accountUpis = upiState.forAccount(accountIdentifier);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.qr_code, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              'UPI IDs',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            SizedBox(
              height: 28,
              child: TextButton.icon(
                onPressed: () => _showAddUpiDialog(
                  context,
                  ref,
                  accountType: accountType,
                  accountIdentifier: accountIdentifier,
                ),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ],
        ),
        if (accountUpis.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              'No UPI IDs linked',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.outline),
            ),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: accountUpis.map((upi) {
              return Chip(
                avatar: Icon(Icons.alternate_email, size: 14, color: cs.primary),
                label: Text(
                  upi.upiHandle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () async {
                  final confirm = await _confirmDelete(context, upi.upiHandle);
                  if (confirm && context.mounted) {
                    ref.read(upiProvider.notifier).deleteUpiId(upi.id!);
                  }
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Full UPI Management Panel (for Settings / dedicated screen)
// ──────────────────────────────────────────────────────────────

class UpiManagementPanel extends ConsumerWidget {
  const UpiManagementPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upiState = ref.watch(upiProvider);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Icon(Icons.qr_code_2, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'UPI ID Mappings',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: upiState.isLoading
                  ? null
                  : () => _showAddUpiDialog(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add UPI'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Link UPI IDs to your accounts (for transfer detection) or to categories '
          '(for auto-categorization).',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline),
        ),
        const SizedBox(height: 12),

        // Rescan button
        OutlinedButton.icon(
          onPressed: upiState.isLoading ? null : () => _rescan(context, ref),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Re-scan transactions with UPI rules'),
        ),
        const SizedBox(height: 16),

        if (upiState.isLoading && upiState.upiIds.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (upiState.error != null && upiState.upiIds.isEmpty)
          Center(
            child: Text('Error: ${upiState.error}',
                style: TextStyle(color: cs.error)),
          )
        else if (upiState.upiIds.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.qr_code, size: 48, color: cs.outline),
                  const SizedBox(height: 8),
                  Text('No UPI IDs configured',
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          )
        else ...[
          // Own UPIs section
          if (upiState.ownUpiIds.isNotEmpty) ...[
            _UpiSectionHeader(
              title: 'My UPI IDs',
              subtitle: 'Linked to your accounts — transactions matching these are flagged as transfers',
              count: upiState.ownUpiIds.length,
            ),
            const SizedBox(height: 8),
            ...upiState.ownUpiIds.map((upi) => _UpiListTile(upi: upi)),
            const SizedBox(height: 16),
          ],
          // Third-party UPIs section
          if (upiState.thirdPartyUpiIds.isNotEmpty) ...[
            _UpiSectionHeader(
              title: 'Third-party UPI IDs',
              subtitle: 'Mapped to categories for auto-categorization',
              count: upiState.thirdPartyUpiIds.length,
            ),
            const SizedBox(height: 8),
            ...upiState.thirdPartyUpiIds.map((upi) => _UpiListTile(upi: upi)),
          ],
        ],
      ],
    );
  }

  Future<void> _rescan(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(upiProvider.notifier).rescan();
    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Scanned ${result.transactionsScanned} transactions: '
            '${result.categoriesUpdated} categories updated, '
            '${result.transfersFlagged} transfers flagged',
          ),
        ),
      );
    }
  }
}

// ──────────────────────────────────────────────────────────────
// Section header
// ──────────────────────────────────────────────────────────────

class _UpiSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;

  const _UpiSectionHeader({
    required this.title,
    required this.subtitle,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('$count',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onPrimaryContainer)),
            ),
          ],
        ),
        Text(subtitle,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.outline)),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
// UPI list tile
// ──────────────────────────────────────────────────────────────

class _UpiListTile extends ConsumerWidget {
  final UpiId upi;
  const _UpiListTile({required this.upi});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final categoriesState = ref.watch(categoriesProvider);

    String? categoryName;
    if (upi.categoryId != null) {
      final cat = categoriesState.categories.cast<Category?>().firstWhere(
            (c) => c?.id == upi.categoryId,
            orElse: () => null,
          );
      categoryName = cat?.name;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: upi.isOwn ? cs.primaryContainer : cs.tertiaryContainer,
          child: Icon(
            upi.isOwn ? Icons.account_balance : Icons.alternate_email,
            size: 18,
            color: upi.isOwn ? cs.onPrimaryContainer : cs.onTertiaryContainer,
          ),
        ),
        title: Text(upi.upiHandle,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        subtitle: Text(
          [
            if (upi.label != null) upi.label!,
            if (upi.accountIdentifier != null)
              'Account: ****${upi.accountIdentifier!.length > 4 ? upi.accountIdentifier!.substring(upi.accountIdentifier!.length - 4) : upi.accountIdentifier}',
            if (categoryName != null) 'Category: $categoryName',
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
          tooltip: 'Remove UPI ID',
          onPressed: () async {
            final confirm = await _confirmDelete(context, upi.upiHandle);
            if (confirm && context.mounted) {
              ref.read(upiProvider.notifier).deleteUpiId(upi.id!);
            }
          },
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Shared dialogs
// ──────────────────────────────────────────────────────────────

Future<bool> _confirmDelete(BuildContext context, String handle) async {
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove UPI ID?'),
          content: Text('Remove "$handle" from your UPI mappings?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Remove'),
            ),
          ],
        ),
      ) ??
      false;
}

void _showAddUpiDialog(
  BuildContext context,
  WidgetRef ref, {
  String? accountType,
  String? accountIdentifier,
}) {
  final handleController = TextEditingController();
  final labelController = TextEditingController();
  bool isOwn = accountIdentifier != null;
  int? selectedCategoryId;

  showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final categoriesState = ref.read(categoriesProvider);
          List<Category> categoryList = categoriesState.categories;

          return AlertDialog(
            title: Text(
                isOwn ? 'Add Your UPI ID' : 'Add Third-party UPI ID'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: handleController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'UPI Handle',
                      hintText: 'e.g. username@hdfcbank',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: labelController,
                    decoration: const InputDecoration(
                      labelText: 'Label (optional)',
                      hintText: 'e.g. My HDFC UPI, Swiggy',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                  ),
                  if (accountIdentifier == null) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('This is my own UPI'),
                      subtitle: Text(
                        isOwn
                            ? 'Transactions will be flagged as transfers'
                            : 'Transactions will be auto-categorized',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      value: isOwn,
                      onChanged: (v) => setDialogState(() => isOwn = v),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                  if (!isOwn && categoryList.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'Auto-assign category',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: categoryList
                          .map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedCategoryId = v),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final handle = handleController.text.trim();
                  if (handle.isEmpty || !handle.contains('@')) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Enter a valid UPI handle (e.g. user@bank)')),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop();
                  final success =
                      await ref.read(upiProvider.notifier).addUpiId(
                            upiHandle: handle,
                            label: labelController.text.trim().isNotEmpty
                                ? labelController.text.trim()
                                : null,
                            accountType: accountType,
                            accountIdentifier: accountIdentifier,
                            categoryId: selectedCategoryId,
                            isOwn: isOwn,
                          );
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(success
                            ? 'UPI ID added'
                            : 'Failed to add UPI ID'),
                      ),
                    );
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      );
    },
  );
}
