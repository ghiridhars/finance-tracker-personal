import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/unified_transaction_models.dart';
import '../providers/categories_provider.dart';
import '../providers/transactions_provider.dart';
import '../services/api_service.dart';

/// Page size for paginated review loading.
const int _kPageSize = 25;

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  // ── Pagination state ──────────────────────────────────────
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  int _totalCount = 0;
  String? _error;

  final List<UnifiedTransaction> _transactions = [];
  final Map<int, Map<String, dynamic>> _edits = {};
  final Set<int> _approvedIds = {}; // Tracks individually approved items
  bool _isSubmitting = false;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────

  Future<void> _loadInitial() async {
    setState(() {
      _isLoadingInitial = true;
      _error = null;
      _transactions.clear();
      _edits.clear();
      _approvedIds.clear();
      _offset = 0;
      _hasMore = true;
    });

    try {
      final count =
          await ApiService.countTransactions(reviewStatus: 'NEEDS_REVIEW');
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
        _isLoadingInitial = false;
        _initEdits(txns);
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
        _initEdits(txns);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _initEdits(List<UnifiedTransaction> txns) {
    for (var tx in txns) {
      _edits[tx.id!] = {
        'id': tx.id,
        'category_id': tx.category?.id,
        'merchant_name': tx.merchantName ?? '',
        'notes': tx.notes ?? '',
        'review_status': 'REVIEWED',
      };
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  // ── Individual approve ────────────────────────────────────

  Future<void> _approveOne(int txId) async {
    final edit = _edits[txId];
    if (edit == null) return;

    setState(() => _approvedIds.add(txId));

    try {
      await ApiService.bulkUpdateTransactions([edit]);
      ref.invalidate(needsReviewCountProvider);

      if (mounted) {
        // Remove from list after a brief delay for the animation
        await Future.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        setState(() {
          _transactions.removeWhere((t) => t.id == txId);
          _edits.remove(txId);
          _approvedIds.remove(txId);
          _totalCount = _totalCount > 0 ? _totalCount - 1 : 0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _approvedIds.remove(txId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to approve: $e')),
        );
      }
    }
  }

  // ── Bulk submit ───────────────────────────────────────────

  Future<void> _submitAll() async {
    if (_edits.isEmpty) return;
    setState(() => _isSubmitting = true);

    try {
      final updates = _edits.values.toList();
      await ApiService.bulkUpdateTransactions(updates);

      ref.invalidate(needsReviewCountProvider);
      ref.read(unifiedTransactionsProvider.notifier).loadTransactions();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Successfully reviewed ${updates.length} transactions')),
        );
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to submit: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  void _updateEdit(int id, String key, dynamic value) {
    // Don't call setState for every keystroke — just update the map.
    _edits[id]?[key] = value;
  }

  void _dismissTransaction(int index) {
    final tx = _transactions[index];
    setState(() {
      _transactions.removeAt(index);
      _edits.remove(tx.id);
      _totalCount = _totalCount > 0 ? _totalCount - 1 : 0;
    });
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final categoriesState = ref.watch(categoriesProvider);
    final categories = categoriesState.categories;
    final validCategoryIds = categories.map((c) => c.id).toSet();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoadingInitial) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Loading transactions for review...',
                  style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('Something went wrong', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                onPressed: _loadInitial,
              ),
            ],
          ),
        ),
      );
    }

    if (_transactions.isEmpty && !_hasMore) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle_outline,
                    size: 64, color: Colors.green.shade600),
              ),
              const SizedBox(height: 24),
              Text('All caught up!',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('No transactions need review.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to Dashboard'),
                onPressed: () => context.go('/'),
              ),
            ],
          ),
        ),
      );
    }

    final pendingCount =
        _transactions.where((t) => !_approvedIds.contains(t.id)).length;
    final itemCount = _transactions.length + (_hasMore ? 1 : 0);

    return Scaffold(
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────
          _ReviewHeader(
            totalCount: _totalCount,
            pendingCount: pendingCount,
            loadedCount: _transactions.length,
            hasMore: _hasMore,
            isSubmitting: _isSubmitting,
            onSubmitAll: pendingCount > 0 ? _submitAll : null,
            theme: theme,
          ),

          // ── Paginated list ──────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (index >= _transactions.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                final tx = _transactions[index];
                final editData = _edits[tx.id!];
                final isApproved = _approvedIds.contains(tx.id);

                final rawCatId = editData?['category_id'] as int?;
                final safeCatId =
                    (rawCatId != null && validCategoryIds.contains(rawCatId))
                        ? rawCatId
                        : null;

                return AnimatedOpacity(
                  opacity: isApproved ? 0.4 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: AnimatedScale(
                    scale: isApproved ? 0.95 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ReviewCard(
                        tx: tx,
                        editData: editData ?? {},
                        safeCatId: safeCatId,
                        categories: categories,
                        isApproved: isApproved,
                        isDark: isDark,
                        theme: theme,
                        onUpdateEdit: (key, value) =>
                            _updateEdit(tx.id!, key, value),
                        onApprove: () => _approveOne(tx.id!),
                        onDismiss: () => _dismissTransaction(index),
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

// ═══════════════════════════════════════════════════════════════
// Header widget
// ═══════════════════════════════════════════════════════════════

class _ReviewHeader extends StatelessWidget {
  final int totalCount;
  final int pendingCount;
  final int loadedCount;
  final bool hasMore;
  final bool isSubmitting;
  final VoidCallback? onSubmitAll;
  final ThemeData theme;

  const _ReviewHeader({
    required this.totalCount,
    required this.pendingCount,
    required this.loadedCount,
    required this.hasMore,
    required this.isSubmitting,
    required this.onSubmitAll,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.rate_review_outlined,
                    size: 22, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Review Transactions',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                        _subtitle(),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.done_all, size: 18),
                label: Text('Submit All ($pendingCount)'),
                onPressed: isSubmitting ? null : onSubmitAll,
              ),
            ],
          ),
          if (totalCount > 0 && hasMore) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: loadedCount / totalCount,
                      minHeight: 4,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('$loadedCount / $totalCount loaded',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle() {
    if (totalCount == 0) return 'No transactions need review';
    if (loadedCount >= totalCount) {
      return '$totalCount transaction${totalCount == 1 ? '' : 's'} need your attention';
    }
    return 'Showing $loadedCount of $totalCount — scroll for more';
  }
}

// ═══════════════════════════════════════════════════════════════
// Individual review card
// ═══════════════════════════════════════════════════════════════

class _ReviewCard extends StatelessWidget {
  final UnifiedTransaction tx;
  final Map<String, dynamic> editData;
  final int? safeCatId;
  final List categories;
  final bool isApproved;
  final bool isDark;
  final ThemeData theme;
  final void Function(String key, dynamic value) onUpdateEdit;
  final VoidCallback onApprove;
  final VoidCallback onDismiss;

  const _ReviewCard({
    required this.tx,
    required this.editData,
    required this.safeCatId,
    required this.categories,
    required this.isApproved,
    required this.isDark,
    required this.theme,
    required this.onUpdateEdit,
    required this.onApprove,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withAlpha(isApproved ? 8 : 18)
            : Colors.white.withAlpha(isApproved ? 140 : 230),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isApproved
              ? Colors.green.withAlpha(80)
              : (isDark
                  ? Colors.white.withAlpha(25)
                  : Colors.black.withAlpha(15)),
          width: isApproved ? 1.5 : 1,
        ),
        boxShadow: [
          if (!isApproved)
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Review reason banner ──────────────────────
              if (tx.reviewReason != null && tx.reviewReason!.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(isDark ? 40 : 30),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.amber.withAlpha(isDark ? 60 : 50),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tx.reviewReason!,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: isDark
                                ? Colors.amber.shade300
                                : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Row 1: description + amount ──────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tx.description ?? 'No description',
                                style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (tx.date != null)
                                    _MetadataChip(
                                        icon: Icons.calendar_today,
                                        label: tx.date!),
                                  if (tx.bank != null)
                                    _MetadataChip(
                                        icon: Icons.account_balance,
                                        label: tx.bank!),
                                  _MetadataChip(
                                      icon: Icons.credit_card,
                                      label: tx.sourceLabel),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (tx.type?.value == 'CREDIT'
                                        ? Colors.green
                                        : Colors.red)
                                    .withAlpha(isDark ? 40 : 25),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '₹${tx.amount?.toStringAsFixed(2) ?? '0.00'}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: tx.type?.value == 'CREDIT'
                                      ? Colors.green.shade600
                                      : Colors.red.shade600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tx.type?.value ?? '',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // ── Row 2: editable fields ──────────────
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<int?>(
                            decoration: InputDecoration(
                              labelText: 'Category',
                              isDense: true,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            initialValue: safeCatId,
                            items: [
                              const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('Uncategorized')),
                              ...categories.map((c) =>
                                  DropdownMenuItem<int?>(
                                    value: c.id,
                                    child: Text(c.name),
                                  )),
                            ],
                            onChanged: (val) =>
                                onUpdateEdit('category_id', val),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            key: ValueKey('merchant_${tx.id}'),
                            initialValue:
                                editData['merchant_name'] as String? ?? '',
                            decoration: InputDecoration(
                              labelText: 'Merchant',
                              isDense: true,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            onChanged: (val) =>
                                onUpdateEdit('merchant_name', val),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            key: ValueKey('notes_${tx.id}'),
                            initialValue:
                                editData['notes'] as String? ?? '',
                            decoration: InputDecoration(
                              labelText: 'Notes',
                              isDense: true,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            onChanged: (val) =>
                                onUpdateEdit('notes', val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Row 3: action buttons ───────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: Icon(Icons.close, size: 16,
                              color: theme.colorScheme.onSurfaceVariant),
                          label: Text('Dismiss',
                              style: TextStyle(
                                  color:
                                      theme.colorScheme.onSurfaceVariant)),
                          onPressed: isApproved ? null : onDismiss,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          icon: isApproved
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.check, size: 18),
                          label: Text(
                              isApproved ? 'Approving...' : 'Approve'),
                          onPressed: isApproved ? null : onApprove,
                          style: FilledButton.styleFrom(
                            backgroundColor: isApproved
                                ? Colors.green.withAlpha(40)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Metadata chip
// ═══════════════════════════════════════════════════════════════

class _MetadataChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetadataChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
