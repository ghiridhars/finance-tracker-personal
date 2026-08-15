import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/unified_transaction_models.dart';
import '../models/enums.dart';
import '../models/category_models.dart';
import '../providers/categories_provider.dart';
import '../providers/accounts_provider.dart';
import '../providers/transactions_provider.dart';
import '../services/api_service.dart';
import '../services/api/classification_rules_api.dart';
import '../models/classification_rule_models.dart';
import '../widgets/ui_system/ui_system.dart';
import 'classification_rules_screen.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  static const int _kPageSize = 50;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  int _totalCount = 0;
  String? _error;

  final List<UnifiedTransaction> _transactions = [];
  final Set<int> _approvedIds = {};
  UnifiedTransaction? _selectedTransaction;
  
  int? _selectedCategoryId;
  int? _selectedTransferAccountId;
  bool _isSubmitting = false;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(accountsProvider.notifier).loadAccounts();
      ref.read(categoriesProvider.notifier).loadCategories();
    });
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoadingInitial = true;
      _error = null;
      _transactions.clear();
      _approvedIds.clear();
      _offset = 0;
      _hasMore = true;
      _selectedTransaction = null;
    });

    try {
      final count = await ApiService.countTransactions(reviewStatus: 'NEEDS_REVIEW');
      final txns = await ApiService.getUnifiedTransactions(
        reviewStatus: 'NEEDS_REVIEW',
        limit: _kPageSize,
        offset: 0,
      );

      if (!mounted) return;
      setState(() {
        _totalCount = count;
        _transactions.addAll(txns);
        _offset = txns.length;
        _hasMore = txns.length >= _kPageSize && _offset < count;
        if (_transactions.isNotEmpty) {
          _selectTransaction(_transactions.first);
        }
        _isLoadingInitial = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoadingInitial = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final txns = await ApiService.getUnifiedTransactions(
        reviewStatus: 'NEEDS_REVIEW',
        limit: _kPageSize,
        offset: _offset,
      );

      if (!mounted) return;
      setState(() {
        _transactions.addAll(txns);
        _offset += txns.length;
        _hasMore = txns.length >= _kPageSize && _offset < _totalCount;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading more: $e')));
      });
    }
  }

  void _selectTransaction(UnifiedTransaction txn) {
    setState(() {
      _selectedTransaction = txn;
      _selectedCategoryId = txn.categoryId;
      _selectedTransferAccountId = (txn.type == TransactionType.credit) ? txn.fromAccountId : txn.toAccountId;
    });
  }

  Future<void> _approveCurrentTransaction() async {
    if (_selectedTransaction == null) return;
    final txn = _selectedTransaction!;
    final isDebit = txn.type == TransactionType.debit;

    setState(() => _isSubmitting = true);
    try {
      final payload = <String, dynamic>{
        'id': txn.id,
        'category_id': _selectedCategoryId,
        'review_status': 'REVIEWED',
      };
      if (isDebit) {
        payload['to_account_id'] = _selectedTransferAccountId;
      } else {
        payload['from_account_id'] = _selectedTransferAccountId;
      }

      await ApiService.bulkUpdateTransactions([payload]);
      setState(() {
        _approvedIds.add(txn.id!);
        _isSubmitting = false;
      });
      ref.invalidate(needsReviewCountProvider);
      _moveToNext();
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _approveAndCreateRule() async {
    if (_selectedTransaction == null) return;
    final txn = _selectedTransaction!;
    final isDebit = txn.type == TransactionType.debit;

    setState(() => _isSubmitting = true);
    try {
      final payload = <String, dynamic>{
        'id': txn.id,
        'category_id': _selectedCategoryId,
        'review_status': 'REVIEWED',
      };
      if (isDebit) {
        payload['to_account_id'] = _selectedTransferAccountId;
      } else {
        payload['from_account_id'] = _selectedTransferAccountId;
      }

      await ApiService.bulkUpdateTransactions([payload]);
      setState(() {
        _approvedIds.add(txn.id!);
        _isSubmitting = false;
      });
      ref.invalidate(needsReviewCountProvider);

      if (mounted) {
        final merchantName = txn.merchantName ?? txn.description ?? '';
        final rule = ClassificationRule(
          name: 'Rule for $merchantName',
          pattern: merchantName,
          targetCategoryId: _selectedCategoryId,
        );
        final returnedRuleId = await showDialog<int>(
          context: context,
          builder: (context) => ClassificationRuleDialog(rule: rule),
        );
        
        // If a rule was successfully created (or updated) from the dialog, apply it immediately
        if (returnedRuleId != null && mounted) {
          try {
            await ClassificationRulesApi.applyRule(returnedRuleId);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Rule created and applied successfully')),
            );
            // Refresh the review list so applied transactions disappear
            _loadInitial();
            return; // Exit here so we don't call _moveToNext() on stale data
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Rule created, but failed to apply: $e')),
            );
          }
        }
      }
      _moveToNext();
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  void _moveToNext() {
    final remaining = _transactions.where((t) => !_approvedIds.contains(t.id)).toList();
    if (remaining.isNotEmpty) {
      final currentIndex = remaining.indexWhere((t) => t.id == _selectedTransaction?.id);
      if (currentIndex != -1 && currentIndex + 1 < remaining.length) {
        _selectTransaction(remaining[currentIndex + 1]);
      } else {
        _selectTransaction(remaining.first);
      }
    } else {
      setState(() => _selectedTransaction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInitial) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Error: $_error', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _loadInitial, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final queue = _transactions.where((t) => !_approvedIds.contains(t.id)).toList();
    final theme = Theme.of(context);

    if (queue.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('All caught up! No transactions need review.', style: TextStyle(fontSize: 18))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Review Queue (${queue.length} pending)'),
      ),
      body: Row(
        children: [
          // Left Panel: Queue
          Expanded(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant)),
              ),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: queue.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == queue.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final txn = queue[index];
                  final isSelected = _selectedTransaction?.id == txn.id;
                  final formatter = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
                  final isExpense = txn.type?.name.toUpperCase() == 'DEBIT';

                  DateTime? dateObj;
                  if (txn.date != null) {
                    dateObj = DateTime.tryParse(txn.date!);
                  }

                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                    title: Text(
                      txn.merchantName ?? txn.description ?? 'Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(dateObj != null ? DateFormat('MMM dd, yyyy').format(dateObj) : (txn.date ?? '')),
                    trailing: Text(
                      formatter.format(txn.amount ?? 0),
                      style: TextStyle(
                        color: isExpense ? Colors.red : Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => _selectTransaction(txn),
                  );
                },
              ),
            ),
          ),
          // Right Panel: Context
          Expanded(
            flex: 2,
            child: _selectedTransaction == null
                ? const Center(child: Text('Select a transaction to review'))
                : _buildContextPanel(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildContextPanel(ThemeData theme) {
    final txn = _selectedTransaction!;
    final categoriesState = ref.watch(categoriesProvider);
    final formatter = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

    final selectedCategory = categoriesState.categories.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => Category(id: -1, name: '', isSystem: false),
    );
    final isSelfTransfer = txn.isTransfer || selectedCategory.name == 'Self Transfer';
    final allAccounts = ref.watch(accountsProvider).accounts;
    final isDebit = txn.type == TransactionType.debit;

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Review Transaction',
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (txn.classificationSource != null || txn.classificationConfidence != null)
                BadgePill.info(
                  label: '${txn.classificationSource ?? "Auto Match"} • ${((txn.classificationConfidence ?? 0.85) * 100).toInt()}%',
                ),
            ],
          ),
          const SizedBox(height: 24),
          
          ModernCard(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(label: 'Amount', value: formatter.format(txn.amount ?? 0), isAmount: true, isExpense: txn.type?.name.toUpperCase() == 'DEBIT'),
                const Divider(height: 32),
                _DetailRow(
                  label: 'Date', 
                  value: txn.date != null 
                      ? DateFormat('MMMM dd, yyyy - hh:mm a').format(DateTime.parse(txn.date!))
                      : 'Unknown'
                ),
                const Divider(height: 32),
                _DetailRow(label: 'Raw Description', value: txn.description ?? ''),
                const Divider(height: 32),
                _DetailRow(label: 'Cleaned Merchant', value: txn.merchantName ?? 'N/A'),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          Text('Category', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: ValueKey(_selectedTransaction?.id),
            value: _selectedCategoryId,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            hint: const Text('Select a category'),
            items: categoriesState.categories.map((c) {
              return DropdownMenuItem(
                value: c.id,
                child: Text(c.name),
              );
            }).toList(),
            onChanged: (val) => setState(() => _selectedCategoryId = val),
          ),
          if (isSelfTransfer && allAccounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(isDebit ? 'Transfer Destination' : 'Transfer Origin', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: ValueKey('transfer_${_selectedTransaction?.id}'),
              value: _selectedTransferAccountId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              hint: Text(isDebit ? 'Select destination account' : 'Select origin account'),
              items: allAccounts
                  .where((a) => a.id != txn.bankAccountId)
                  .map((a) => DropdownMenuItem<int>(
                        value: a.id,
                        child: Text('${a.bank ?? 'Account'} ${a.maskedIdentifier} (${a.type})'),
                      ))
                  .toList(),
              onChanged: (val) => setState(() => _selectedTransferAccountId = val),
            ),
          ],
          
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.rule),
                label: const Text('Approve & Create Rule'),
                onPressed: _isSubmitting ? null : _approveAndCreateRule,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Approve'),
                onPressed: _isSubmitting ? null : _approveCurrentTransaction,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isAmount;
  final bool isExpense;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isAmount = false,
    this.isExpense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: isAmount ? FontWeight.bold : FontWeight.normal,
              color: isAmount
                  ? (isExpense ? Colors.red : Colors.green)
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
