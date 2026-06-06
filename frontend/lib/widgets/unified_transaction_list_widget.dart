/// Unified Transaction List — shows all transactions from all sources
/// with category badges, search, filters, and CSV export.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/unified_transaction_models.dart';
import '../models/category_models.dart';
import '../providers/transactions_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/app_settings_provider.dart';
import '../services/api_service.dart';
import '../utils/color_utils.dart';
import 'skeleton_widgets.dart';

class UnifiedTransactionListWidget extends ConsumerStatefulWidget {
  const UnifiedTransactionListWidget({super.key});

  @override
  ConsumerState<UnifiedTransactionListWidget> createState() =>
      _UnifiedTransactionListWidgetState();
}

class _UnifiedTransactionListWidgetState
    extends ConsumerState<UnifiedTransactionListWidget> {
  static const int _allCategoriesMenuValue = -1;
  static const String _allSourcesMenuValue = '__ALL_SOURCES__';
  static const String _transfersOnlyMenuValue = '__TRANSFERS_ONLY__';
  static const String _allReviewStatusesMenuValue = '__ALL_REVIEW_STATUSES__';

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _initialized = false;

  bool _isTransfersCategory(Category category) {
    final name = category.name.trim().toLowerCase();
    return name == 'transfers' || name.contains('transfer');
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
              onChanged: (value) {
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  if (value.trim().isEmpty) {
                    ref
                        .read(unifiedTransactionsProvider.notifier)
                        .setFilters(clearSearch: true);
                  } else {
                    ref
                        .read(unifiedTransactionsProvider.notifier)
                        .setFilters(search: value.trim());
                  }
                });
              },
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
            PopupMenuButton<int>(
              icon: Badge(
                isLabelVisible: txState.categoryFilter != null,
                child: const Icon(Icons.category),
              ),
              tooltip: 'Filter by category',
              onSelected: (catId) {
                if (catId == _allCategoriesMenuValue) {
                  ref
                      .read(unifiedTransactionsProvider.notifier)
                      .setFilters(clearCategory: true, clearIsTransfer: true);
                } else {
                  final selectedCategory = catState.categories
                      .where((c) => c.id == catId)
                      .cast<Category?>()
                      .firstWhere((c) => c != null, orElse: () => null);
                  if (selectedCategory != null &&
                      _isTransfersCategory(selectedCategory)) {
                    ref
                        .read(unifiedTransactionsProvider.notifier)
                        .setFilters(isTransfer: true, clearCategory: true);
                    return;
                  }
                  ref
                      .read(unifiedTransactionsProvider.notifier)
                      .setFilters(categoryId: catId, clearIsTransfer: true);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<int>(
                  value: _allCategoriesMenuValue,
                  child: Text('All Categories'),
                ),
                const PopupMenuDivider(),
                ...catState.categories
                    .where((c) => c.id != null)
                    .map((c) => PopupMenuItem<int>(
                      value: c.id!,
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
          PopupMenuButton<String>(
            icon: Badge(
              isLabelVisible:
                  txState.sourceTypeFilter != null || txState.isTransferFilter == true,
              child: const Icon(Icons.account_balance),
            ),
            tooltip: 'Filter by source',
            onSelected: (value) {
              if (value == _allSourcesMenuValue) {
                ref
                    .read(unifiedTransactionsProvider.notifier)
                    .setFilters(clearSourceType: true, clearIsTransfer: true);
              } else if (value == _transfersOnlyMenuValue) {
                ref
                    .read(unifiedTransactionsProvider.notifier)
                    .setFilters(isTransfer: true, clearSourceType: true);
              } else {
                ref
                    .read(unifiedTransactionsProvider.notifier)
                    .setFilters(sourceType: value, clearIsTransfer: true);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: _allSourcesMenuValue,
                child: Text('All Sources'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: _transfersOnlyMenuValue, child: Text('Transfers')),
              const PopupMenuItem(
                  value: 'SAVINGS', child: Text('Savings')),
              const PopupMenuItem(
                  value: 'CREDIT_CARD', child: Text('Credit Card')),
            ],
          ),

          PopupMenuButton<String>(
            icon: Badge(
              isLabelVisible: txState.reviewStatusFilter != null,
              child: const Icon(Icons.flag_outlined),
            ),
            tooltip: 'Filter by review status',
            onSelected: (value) {
              if (value == _allReviewStatusesMenuValue) {
                ref
                    .read(unifiedTransactionsProvider.notifier)
                    .setFilters(clearReviewStatus: true);
              } else {
                ref
                    .read(unifiedTransactionsProvider.notifier)
                    .setFilters(reviewStatus: value);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: _allReviewStatusesMenuValue,
                child: Text('All Statuses'),
              ),
              PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'NEEDS_REVIEW',
                child: Text('Needs Review'),
              ),
              PopupMenuItem<String>(
                value: 'AUTO_PARSED',
                child: Text('Auto-detected'),
              ),
              PopupMenuItem<String>(
                value: 'LLM_PARSED',
                child: Text('AI-parsed'),
              ),
              PopupMenuItem<String>(
                value: 'REVIEWED',
                child: Text('Reviewed'),
              ),
            ],
          ),

          // Clear filters button
          if (txState.categoryFilter != null ||
              txState.sourceTypeFilter != null ||
              txState.isTransferFilter == true ||
              txState.reviewStatusFilter != null)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              tooltip: 'Clear filters',
              onPressed: () {
                ref.read(unifiedTransactionsProvider.notifier).setFilters(
                      clearCategory: true,
                      clearSourceType: true,
                      clearIsTransfer: true,
                      clearReviewStatus: true,
                    );
              },
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (state.preset != DateRangePreset.all)
                  OutlinedButton(
                    onPressed: () => ref
                        .read(unifiedTransactionsProvider.notifier)
                        .applyPreset(DateRangePreset.all),
                    child: const Text('Try All time'),
                  ),
                if (state.accountIdentifierFilter != null ||
                    state.bankAccountIdFilter != null)
                  OutlinedButton(
                    onPressed: () => ref
                        .read(unifiedTransactionsProvider.notifier)
                        .setFilters(
                          clearAccountIdentifier: true,
                          clearBankAccountId: true,
                        ),
                    child: const Text('Show all accounts'),
                  ),
                if (state.categoryFilter != null || state.isTransferFilter == true)
                  OutlinedButton(
                    onPressed: () => ref
                        .read(unifiedTransactionsProvider.notifier)
                        .setFilters(clearCategory: true, clearIsTransfer: true),
                    child: const Text('Clear category filter'),
                  ),
                if (state.reviewStatusFilter != null)
                  OutlinedButton(
                    onPressed: () => ref
                        .read(unifiedTransactionsProvider.notifier)
                        .setFilters(clearReviewStatus: true),
                    child: const Text('Clear status filter'),
                  ),
              ],
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
            confirmDismiss: (_) async => true,
            onDismissed: (_) async {
              bool undone = false;
              
              // Optimistically remove from local state
              ref
                  .read(unifiedTransactionsProvider.notifier)
                  .removeTransactionLocal(tx.id!);

              final snackBar = SnackBar(
                content: const Text('Transaction deleted'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () {
                    undone = true;
                    // Reload to restore the transaction
                    ref
                        .read(unifiedTransactionsProvider.notifier)
                        .loadTransactions();
                  },
                ),
                duration: const Duration(seconds: 5),
              );

              final snackBarController = ScaffoldMessenger.of(context).showSnackBar(snackBar);
              await snackBarController.closed.then((reason) async {
                if (!undone) {
                  try {
                    await ApiService.deleteTransaction(tx.id!);
                    // Reload to ensure final server state matches local
                    ref
                        .read(unifiedTransactionsProvider.notifier)
                        .loadTransactions();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Delete failed: $e')),
                      );
                      // Reload to restore state if deletion failed on server
                      ref
                          .read(unifiedTransactionsProvider.notifier)
                          .loadTransactions();
                    }
                  }
                }
              });
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
        c.color != null ? parseHexColor(c.color!) : Colors.grey;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Individual transaction row with category badge.
class _TransactionTile extends ConsumerWidget {
  final UnifiedTransaction transaction;
  final VoidCallback onCategoryTap;

  const _TransactionTile({
    required this.transaction,
    required this.onCategoryTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencySymbol = ref.watch(appSettingsProvider).currency;
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
                if (transaction.needsReview) ...[
                  const SizedBox(width: 6),
                  _reviewChip(),
                ],
                if (transaction.isTransfer) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz,
                            size: 10, color: Colors.orange.shade700),
                        const SizedBox(width: 2),
                        Text(
                          transaction.transferType == 'CC_BILL_PAYMENT'
                              ? 'CC Payment'
                              : 'Transfer',
                          style: TextStyle(
                              fontSize: 10, color: Colors.orange.shade700),
                        ),
                      ],
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
          '$amountPrefix$currencySymbol$amount',
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
        ? parseHexColor(category.color!)
        : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        category.name,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }

  Widget _reviewChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.amber.shade400),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 10, color: Colors.amber.shade800),
          const SizedBox(width: 2),
          Text(
            'Needs review',
            style: TextStyle(fontSize: 10, color: Colors.amber.shade800),
          ),
        ],
      ),
    );
  }
}
