/// Unified Transaction List — shows all transactions from all sources
/// with category badges, search, filters, and CSV export.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/unified_transaction_models.dart';
import '../models/category_models.dart';
import '../providers/transactions_provider.dart';
import '../providers/categories_provider.dart';
import '../services/api_service.dart';
import 'skeleton_widgets.dart';

class UnifiedTransactionListWidget extends ConsumerStatefulWidget {
  const UnifiedTransactionListWidget({super.key});

  @override
  ConsumerState<UnifiedTransactionListWidget> createState() =>
      _UnifiedTransactionListWidgetState();
}

class _UnifiedTransactionListWidgetState
    extends ConsumerState<UnifiedTransactionListWidget> {
  final TextEditingController _searchController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txState = ref.watch(unifiedTransactionsProvider);
    final catState = ref.watch(categoriesProvider);

    // Load data on first build
    if (!_initialized) {
      _initialized = true;
      Future.microtask(() {
        ref.read(unifiedTransactionsProvider.notifier).loadTransactions();
        ref.read(categoriesProvider.notifier).loadCategories();
      });
    }

    return Column(
      children: [
        // ── Search + filters bar ──────────────────────────
        _buildFilterBar(context, txState, catState),

        // ── Date range presets ────────────────────────────
        _buildPresetChips(txState),

        // ── Transaction list ─────────────────────────────
        Expanded(
          child: _buildTransactionList(context, txState),
        ),
      ],
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    UnifiedTransactionsState txState,
    CategoriesState catState,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          // Search field
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search transactions…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(unifiedTransactionsProvider.notifier)
                              .setFilters(clearSearch: true);
                        },
                      )
                    : null,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onSubmitted: (value) {
                if (value.trim().isEmpty) {
                  ref
                      .read(unifiedTransactionsProvider.notifier)
                      .setFilters(clearSearch: true);
                } else {
                  ref
                      .read(unifiedTransactionsProvider.notifier)
                      .setFilters(search: value.trim());
                }
              },
            ),
          ),

          const SizedBox(width: 8),

          // Category filter dropdown
          if (catState.categories.isNotEmpty)
            PopupMenuButton<int?>(
              icon: Badge(
                isLabelVisible: txState.categoryFilter != null,
                child: const Icon(Icons.category),
              ),
              tooltip: 'Filter by category',
              onSelected: (catId) {
                if (catId == null) {
                  ref
                      .read(unifiedTransactionsProvider.notifier)
                      .setFilters(clearCategory: true);
                } else {
                  ref
                      .read(unifiedTransactionsProvider.notifier)
                      .setFilters(categoryId: catId);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<int?>(
                  value: null,
                  child: Text('All Categories'),
                ),
                const PopupMenuDivider(),
                ...catState.categories.map((c) => PopupMenuItem<int?>(
                      value: c.id,
                      child: Row(
                        children: [
                          _categoryDot(c),
                          const SizedBox(width: 8),
                          Text(c.name),
                        ],
                      ),
                    )),
              ],
            ),

          // Source type filter
          PopupMenuButton<String?>(
            icon: Badge(
              isLabelVisible: txState.sourceTypeFilter != null,
              child: const Icon(Icons.account_balance),
            ),
            tooltip: 'Filter by source',
            onSelected: (value) {
              if (value == null) {
                ref
                    .read(unifiedTransactionsProvider.notifier)
                    .setFilters(clearSourceType: true);
              } else {
                ref
                    .read(unifiedTransactionsProvider.notifier)
                    .setFilters(sourceType: value);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String?>(
                  value: null, child: Text('All Sources')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'SAVINGS', child: Text('Savings')),
              const PopupMenuItem(
                  value: 'CREDIT_CARD', child: Text('Credit Card')),
            ],
          ),

          // Export button
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export as CSV',
            onPressed: () => _exportTransactions(txState),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChips(UnifiedTransactionsState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: DateRangePreset.values
              .where((p) => p != DateRangePreset.custom)
              .map((preset) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(preset.label, style: const TextStyle(fontSize: 12)),
                      selected: state.preset == preset,
                      onSelected: (_) {
                        ref
                            .read(unifiedTransactionsProvider.notifier)
                            .applyPreset(preset);
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildTransactionList(
      BuildContext context, UnifiedTransactionsState state) {
    if (state.isLoading) {
      return const SkeletonTransactionList();
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8),
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(unifiedTransactionsProvider.notifier).loadTransactions(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long,
                size: 64, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            Text(
              'No transactions found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Upload a statement to see transactions here',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(unifiedTransactionsProvider.notifier).loadTransactions(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: state.transactions.length,
        itemBuilder: (context, index) {
          final tx = state.transactions[index];
          return Dismissible(
            key: ValueKey(tx.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade400,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) => showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete Transaction'),
                content: const Text(
                    'Are you sure you want to delete this transaction?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ),
            onDismissed: (_) async {
              try {
                await ApiService.deleteTransaction(tx.id!);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Transaction deleted')),
                  );
                }
                ref
                    .read(unifiedTransactionsProvider.notifier)
                    .loadTransactions();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Delete failed: $e')),
                  );
                }
              }
            },
            child: _TransactionTile(
              transaction: tx,
              onCategoryTap: () => _showCategoryDialog(context, tx),
            ),
          );
        },
      ),
    );
  }

  void _exportTransactions(UnifiedTransactionsState state) async {
    String? from;
    String? to;
    if (state.fromDate != null) {
      from = '${state.fromDate!.year}-${state.fromDate!.month.toString().padLeft(2, '0')}-${state.fromDate!.day.toString().padLeft(2, '0')}';
    }
    if (state.toDate != null) {
      to = '${state.toDate!.year}-${state.toDate!.month.toString().padLeft(2, '0')}-${state.toDate!.day.toString().padLeft(2, '0')}';
    }

    final url = ApiService.getExportUrl(
      format: 'csv',
      from: from,
      to: to,
      categoryId: state.categoryFilter,
      sourceType: state.sourceTypeFilter,
      search: state.searchQuery,
    );

    // Trigger download (browser on web, default app on desktop)
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _showCategoryDialog(BuildContext context, UnifiedTransaction tx) async {
    final catState = ref.read(categoriesProvider);
    if (catState.categories.isEmpty) {
      await ref.read(categoriesProvider.notifier).loadCategories();
    }
    final categories = ref.read(categoriesProvider).categories;

    if (!context.mounted) return;

    final selected = await showDialog<int?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Set Category'),
        children: categories
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c.id),
                  child: Row(
                    children: [
                      _categoryDot(c),
                      const SizedBox(width: 10),
                      Text(c.name),
                      if (tx.categoryId == c.id) ...[
                        const Spacer(),
                        const Icon(Icons.check, size: 18),
                      ],
                    ],
                  ),
                ))
            .toList(),
      ),
    );

    if (selected != null && tx.id != null) {
      await ApiService.updateTransaction(tx.id!, categoryId: selected);
      ref.read(unifiedTransactionsProvider.notifier).loadTransactions();
    }
  }

  Widget _categoryDot(Category c) {
    final color =
        c.color != null ? _parseHexColor(c.color!) : Colors.grey;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  Color _parseHexColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}

/// Individual transaction row with category badge.
class _TransactionTile extends StatelessWidget {
  final UnifiedTransaction transaction;
  final VoidCallback onCategoryTap;

  const _TransactionTile({
    required this.transaction,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDebit = transaction.type?.value == 'DEBIT';
    final amountColor = isDebit
        ? Theme.of(context).colorScheme.error
        : Colors.green.shade700;
    final amountPrefix = isDebit ? '−' : '+';
    final amount = transaction.amount?.toStringAsFixed(2) ?? '0.00';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: _sourceIcon(transaction.sourceType),
        title: Text(
          transaction.merchantName ?? transaction.description ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (transaction.merchantName != null &&
                transaction.description != null &&
                transaction.merchantName != transaction.description)
              Text(
                transaction.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  transaction.date ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
                if (transaction.bank != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      transaction.bank!,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ],
                if (transaction.category != null) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onCategoryTap,
                    child: _categoryChip(context, transaction.category!),
                  ),
                ] else ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onCategoryTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).disabledColor,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '+ Category',
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).disabledColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Text(
          '$amountPrefix₹$amount',
          style: TextStyle(
            color: amountColor,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _sourceIcon(String? sourceType) {
    if (sourceType == 'CREDIT_CARD') {
      return const CircleAvatar(
        radius: 16,
        backgroundColor: Color(0xFFE3F2FD),
        child: Icon(Icons.credit_card, size: 18, color: Color(0xFF1976D2)),
      );
    }
    return const CircleAvatar(
      radius: 16,
      backgroundColor: Color(0xFFE8F5E9),
      child: Icon(Icons.account_balance, size: 18, color: Color(0xFF388E3C)),
    );
  }

  Widget _categoryChip(BuildContext context, Category category) {
    final color = category.color != null
        ? _parseHexColor(category.color!)
        : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        category.name,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }

  Color _parseHexColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}
