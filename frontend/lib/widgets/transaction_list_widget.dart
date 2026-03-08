/// TransactionListWidget — Displays transactions with Riverpod state,
/// date range filter with presets, sortable columns, and semantic theme colors.
///
/// Supports both savings and credit card transactions.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/savings_models.dart';
import '../models/credit_card_models.dart';
import '../models/enums.dart';
import '../providers/transactions_provider.dart';

enum TransactionViewType { savings, creditCard }

class TransactionListWidget extends ConsumerStatefulWidget {
  final TransactionViewType type;

  const TransactionListWidget({super.key, required this.type});

  @override
  ConsumerState<TransactionListWidget> createState() =>
      _TransactionListWidgetState();
}

class _TransactionListWidgetState
    extends ConsumerState<TransactionListWidget> {
  int _sortColumnIndex = 0;
  bool _sortAscending = false; // newest first by default

  final _currencyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  final _dateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    // Load transactions on first build
    Future.microtask(() => _notifier.loadTransactions());
  }

  /// Returns the correct notifier based on transaction type.
  dynamic get _notifier => widget.type == TransactionViewType.savings
      ? ref.read(savingsTransactionsProvider.notifier)
      : ref.read(creditCardTransactionsProvider.notifier);

  void _sort<T>(
      Comparable<T> Function(dynamic txn) getField, int columnIndex,
      bool ascending, List<dynamic> transactions) {
    transactions.sort((a, b) {
      final aValue = getField(a);
      final bValue = getField(b);
      return ascending
          ? Comparable.compare(aValue, bValue)
          : Comparable.compare(bValue, aValue);
    });
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  Future<void> _pickDate(BuildContext context, bool isFrom) async {
    final txnState = widget.type == TransactionViewType.savings
        ? ref.read(savingsTransactionsProvider)
        : ref.read(creditCardTransactionsProvider);

    final initialDate = isFrom
        ? (txnState.fromDate ?? DateTime.now().subtract(const Duration(days: 30)))
        : (txnState.toDate ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );

    if (picked != null) {
      final from = isFrom ? picked : txnState.fromDate;
      final to = isFrom ? txnState.toDate : picked;
      _notifier.setDateRange(from, to, DateRangePreset.custom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final txnState = widget.type == TransactionViewType.savings
        ? ref.watch(savingsTransactionsProvider)
        : ref.watch(creditCardTransactionsProvider);

    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Date filter bar
        _buildFilterBar(context, txnState, colorScheme),
        const Divider(height: 1),

        // Main content
        Expanded(child: _buildContent(context, txnState, colorScheme)),
      ],
    );
  }

  Widget _buildFilterBar(
      BuildContext context, TransactionsState txnState, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick preset chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: DateRangePreset.values
                  .where((p) => p != DateRangePreset.custom)
                  .map((preset) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(preset.label),
                          selected: txnState.preset == preset,
                          onSelected: (_) => _notifier.applyPreset(preset),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),

          // Custom date pickers + count
          Row(
            children: [
              // From date
              _buildDateChip(
                context,
                label: txnState.fromDate != null
                    ? 'From: ${_dateFormat.format(txnState.fromDate!)}'
                    : 'From: —',
                onTap: () => _pickDate(context, true),
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 8),
              // To date
              _buildDateChip(
                context,
                label: txnState.toDate != null
                    ? 'To: ${_dateFormat.format(txnState.toDate!)}'
                    : 'To: —',
                onTap: () => _pickDate(context, false),
                colorScheme: colorScheme,
              ),
              const Spacer(),
              // Transaction count + refresh
              if (!txnState.isLoading)
                Text(
                  '${txnState.transactions.length} transaction(s)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: () => _notifier.loadTransactions(),
              ),
            ],
          ),

          // Active custom filter indicator
          if (txnState.preset == DateRangePreset.custom &&
              (txnState.fromDate != null || txnState.toDate != null))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Chip(
                label: const Text('Custom date range'),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () =>
                    _notifier.applyPreset(DateRangePreset.last30Days),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDateChip(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return ActionChip(
      avatar: Icon(Icons.calendar_today, size: 16, color: colorScheme.primary),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildContent(
      BuildContext context, TransactionsState txnState, ColorScheme colorScheme) {
    if (txnState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (txnState.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48,
                color: colorScheme.error),
            const SizedBox(height: 16),
            Text('Failed to load transactions',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(txnState.error!,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _notifier.loadTransactions(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (txnState.transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48,
                color: colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'No transactions found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.type == TransactionViewType.savings
                  ? 'Upload a savings statement to see transactions here'
                  : 'Upload a credit card statement to see transactions here',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _notifier.loadTransactions(),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: widget.type == TransactionViewType.savings
            ? _buildSavingsTable(txnState, colorScheme)
            : _buildCreditCardTable(txnState, colorScheme),
      ),
    );
  }

  DataTable _buildSavingsTable(
      TransactionsState txnState, ColorScheme colorScheme) {
    final txns = txnState.transactions.cast<SavingsTransaction>();
    return DataTable(
      sortColumnIndex: _sortColumnIndex,
      sortAscending: _sortAscending,
      columns: [
        DataColumn(
          label: const Text('Date'),
          onSort: (i, asc) => _sort<String>(
              (t) => (t as SavingsTransaction).date ?? '', i, asc,
              txnState.transactions),
        ),
        DataColumn(
          label: const Text('Description'),
          onSort: (i, asc) => _sort<String>(
              (t) => (t as SavingsTransaction).description ?? '', i, asc,
              txnState.transactions),
        ),
        DataColumn(
          label: const Text('Reference'),
          onSort: (i, asc) => _sort<String>(
              (t) => (t as SavingsTransaction).referenceNumber ?? '', i, asc,
              txnState.transactions),
        ),
        DataColumn(
          label: const Text('Amount'),
          numeric: true,
          onSort: (i, asc) => _sort<num>(
              (t) => (t as SavingsTransaction).effectiveAmount, i, asc,
              txnState.transactions),
        ),
        const DataColumn(label: Text('Type')),
        DataColumn(
          label: const Text('Balance'),
          numeric: true,
          onSort: (i, asc) => _sort<num>(
              (t) => (t as SavingsTransaction).closingBalance ?? 0, i, asc,
              txnState.transactions),
        ),
      ],
      rows: txns
          .map((t) => DataRow(cells: [
                DataCell(Text(_formatDate(t.date ?? ''))),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Text(t.description ?? '',
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataCell(Text(t.referenceNumber ?? '')),
                DataCell(Text(_currencyFormat.format(t.effectiveAmount))),
                DataCell(_buildTypeBadge(t.type, colorScheme)),
                DataCell(
                    Text(_currencyFormat.format(t.closingBalance ?? 0))),
              ]))
          .toList(),
    );
  }

  DataTable _buildCreditCardTable(
      TransactionsState txnState, ColorScheme colorScheme) {
    final txns = txnState.transactions.cast<CreditCardTransaction>();
    return DataTable(
      sortColumnIndex: _sortColumnIndex,
      sortAscending: _sortAscending,
      columns: [
        DataColumn(
          label: const Text('Date'),
          onSort: (i, asc) => _sort<String>(
              (t) => (t as CreditCardTransaction).date ?? '', i, asc,
              txnState.transactions),
        ),
        DataColumn(
          label: const Text('Description'),
          onSort: (i, asc) => _sort<String>(
              (t) => (t as CreditCardTransaction).description ?? '', i, asc,
              txnState.transactions),
        ),
        DataColumn(
          label: const Text('Amount'),
          numeric: true,
          onSort: (i, asc) => _sort<num>(
              (t) => (t as CreditCardTransaction).amount ?? 0, i, asc,
              txnState.transactions),
        ),
        const DataColumn(label: Text('Type')),
      ],
      rows: txns
          .map((t) => DataRow(cells: [
                DataCell(Text(_formatDate(t.date ?? ''))),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Text(t.description ?? '',
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataCell(Text(_currencyFormat.format(t.amount ?? 0))),
                DataCell(_buildTypeBadge(t.type, colorScheme)),
              ]))
          .toList(),
    );
  }

  Widget _buildTypeBadge(TransactionType? type, ColorScheme colorScheme) {
    final typeStr = type?.value ?? 'UNKNOWN';
    final isCredit = type == TransactionType.credit;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isCredit
            ? colorScheme.primaryContainer
            : colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        typeStr,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isCredit
              ? colorScheme.onPrimaryContainer
              : colorScheme.onErrorContainer,
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return _dateFormat.format(date);
    } catch (_) {
      return dateStr;
    }
  }
}
