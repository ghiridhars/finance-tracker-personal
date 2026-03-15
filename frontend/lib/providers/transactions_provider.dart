/// TransactionsNotifier — manages transaction data, loading state, and date filters.
/// Cross-tab reactive: uploading a statement triggers auto-refresh here.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/unified_transaction_models.dart';
import '../services/api_service.dart';
import 'date_range_mixin.dart';

/// Date range filter preset.
enum DateRangePreset {
  last7Days('Last 7 days'),
  last30Days('Last 30 days'),
  last3Months('Last 3 months'),
  thisYear('This year'),
  all('All time'),
  custom('Custom');

  final String label;
  const DateRangePreset(this.label);
}

/// State for transactions of a specific type.
class TransactionsState {
  final List<dynamic> transactions;
  final bool isLoading;
  final String? error;
  final DateTime? fromDate;
  final DateTime? toDate;
  final DateRangePreset preset;

  const TransactionsState({
    this.transactions = const [],
    this.isLoading = false,
    this.error,
    this.fromDate,
    this.toDate,
    this.preset = DateRangePreset.last30Days,
  });

  TransactionsState copyWith({
    List<dynamic>? transactions,
    bool? isLoading,
    String? error,
    DateTime? fromDate,
    DateTime? toDate,
    DateRangePreset? preset,
    bool clearError = false,
    bool clearFromDate = false,
    bool clearToDate = false,
  }) {
    return TransactionsState(
      transactions: transactions ?? this.transactions,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
      preset: preset ?? this.preset,
    );
  }
}

/// Notifier for savings transactions.
class SavingsTransactionsNotifier extends Notifier<TransactionsState>
    with DateRangeMixin {
  @override
  TransactionsState build() {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));
    return TransactionsState(
      fromDate: from,
      toDate: now,
      preset: DateRangePreset.last30Days,
    );
  }

  Future<void> loadTransactions() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final txns = await ApiService.getSavingsTransactions(
        from: state.fromDate != null
            ? formatDate(state.fromDate!)
            : null,
        to: state.toDate != null
            ? formatDate(state.toDate!)
            : null,
      );
      state = state.copyWith(transactions: txns, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  void setDateRange(DateTime? from, DateTime? to, DateRangePreset preset) {
    state = TransactionsState(
      transactions: state.transactions,
      fromDate: from,
      toDate: to,
      preset: preset,
    );
    loadTransactions();
  }

  void applyPreset(DateRangePreset preset) {
    if (preset == DateRangePreset.custom) return;
    final range = resolveDateRange(preset);
    setDateRange(range.from, range.to, preset);
  }
}

/// Notifier for credit card transactions.
class CreditCardTransactionsNotifier extends Notifier<TransactionsState>
    with DateRangeMixin {
  @override
  TransactionsState build() {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));
    return TransactionsState(
      fromDate: from,
      toDate: now,
      preset: DateRangePreset.last30Days,
    );
  }

  Future<void> loadTransactions() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final txns = await ApiService.getCreditCardTransactions(
        from: state.fromDate != null
            ? formatDate(state.fromDate!)
            : null,
        to: state.toDate != null
            ? formatDate(state.toDate!)
            : null,
      );
      state = state.copyWith(transactions: txns, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        error: e.toString(),
        isLoading: false,
      );
    }
  }

  void setDateRange(DateTime? from, DateTime? to, DateRangePreset preset) {
    state = TransactionsState(
      transactions: state.transactions,
      fromDate: from,
      toDate: to,
      preset: preset,
    );
    loadTransactions();
  }

  void applyPreset(DateRangePreset preset) {
    if (preset == DateRangePreset.custom) return;
    final range = resolveDateRange(preset);
    setDateRange(range.from, range.to, preset);
  }
}

/// Providers
final savingsTransactionsProvider =
    NotifierProvider<SavingsTransactionsNotifier, TransactionsState>(
        SavingsTransactionsNotifier.new);

final creditCardTransactionsProvider =
    NotifierProvider<CreditCardTransactionsNotifier, TransactionsState>(
        CreditCardTransactionsNotifier.new);

// ── Unified Transactions ────────────────────────────────────

/// State for the unified (all-source) transactions tab.
class UnifiedTransactionsState {
  final List<UnifiedTransaction> transactions;
  final bool isLoading;
  final String? error;
  final DateTime? fromDate;
  final DateTime? toDate;
  final DateRangePreset preset;
  final int? categoryFilter;
  final String? bankFilter;
  final String? accountIdentifierFilter;
  final String? sourceTypeFilter;
  final String? typeFilter;
  final String? searchQuery;

  const UnifiedTransactionsState({
    this.transactions = const [],
    this.isLoading = false,
    this.error,
    this.fromDate,
    this.toDate,
    this.preset = DateRangePreset.last3Months,
    this.categoryFilter,
    this.bankFilter,
    this.accountIdentifierFilter,
    this.sourceTypeFilter,
    this.typeFilter,
    this.searchQuery,
  });

  UnifiedTransactionsState copyWith({
    List<UnifiedTransaction>? transactions,
    bool? isLoading,
    String? error,
    DateTime? fromDate,
    DateTime? toDate,
    DateRangePreset? preset,
    int? categoryFilter,
    String? bankFilter,
    String? accountIdentifierFilter,
    String? sourceTypeFilter,
    String? typeFilter,
    String? searchQuery,
    bool clearError = false,
    bool clearCategoryFilter = false,
    bool clearBankFilter = false,
    bool clearAccountIdentifierFilter = false,
    bool clearSourceTypeFilter = false,
    bool clearTypeFilter = false,
    bool clearSearch = false,
  }) {
    return UnifiedTransactionsState(
      transactions: transactions ?? this.transactions,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      preset: preset ?? this.preset,
      categoryFilter:
          clearCategoryFilter ? null : (categoryFilter ?? this.categoryFilter),
      bankFilter: clearBankFilter ? null : (bankFilter ?? this.bankFilter),
      accountIdentifierFilter: clearAccountIdentifierFilter
          ? null
          : (accountIdentifierFilter ?? this.accountIdentifierFilter),
      sourceTypeFilter: clearSourceTypeFilter
          ? null
          : (sourceTypeFilter ?? this.sourceTypeFilter),
      typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
      searchQuery: clearSearch ? null : (searchQuery ?? this.searchQuery),
    );
  }
}

class UnifiedTransactionsNotifier extends Notifier<UnifiedTransactionsState>
    with DateRangeMixin {
  @override
  UnifiedTransactionsState build() {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - 3, now.day);
    return UnifiedTransactionsState(
      fromDate: from,
      toDate: now,
      preset: DateRangePreset.last3Months,
    );
  }

  Future<void> loadTransactions() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final txns = await ApiService.getUnifiedTransactions(
        from: state.fromDate != null ? formatDate(state.fromDate!) : null,
        to: state.toDate != null ? formatDate(state.toDate!) : null,
        categoryId: state.categoryFilter,
        bank: state.bankFilter,
        accountIdentifier: state.accountIdentifierFilter,
        sourceType: state.sourceTypeFilter,
        type: state.typeFilter,
        search: state.searchQuery,
      );
      state = state.copyWith(transactions: txns, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  void setFilters({
    int? categoryId,
    String? bank,
    String? accountIdentifier,
    String? sourceType,
    String? type,
    String? search,
    bool clearCategory = false,
    bool clearBank = false,
    bool clearAccountIdentifier = false,
    bool clearSourceType = false,
    bool clearType = false,
    bool clearSearch = false,
  }) {
    state = state.copyWith(
      categoryFilter: categoryId,
      bankFilter: bank,
      accountIdentifierFilter: accountIdentifier,
      sourceTypeFilter: sourceType,
      typeFilter: type,
      searchQuery: search,
      clearCategoryFilter: clearCategory,
      clearBankFilter: clearBank,
      clearAccountIdentifierFilter: clearAccountIdentifier,
      clearSourceTypeFilter: clearSourceType,
      clearTypeFilter: clearType,
      clearSearch: clearSearch,
    );
    loadTransactions();
  }

  void applyPreset(DateRangePreset preset) {
    if (preset == DateRangePreset.custom) return;
    final range = resolveDateRange(preset);
    state = UnifiedTransactionsState(
      transactions: state.transactions,
      fromDate: range.from,
      toDate: range.to,
      preset: preset,
      categoryFilter: state.categoryFilter,
      bankFilter: state.bankFilter,
      accountIdentifierFilter: state.accountIdentifierFilter,
      sourceTypeFilter: state.sourceTypeFilter,
      typeFilter: state.typeFilter,
      searchQuery: state.searchQuery,
    );
    loadTransactions();
  }

  Future<void> recategorizeAll() async {
    try {
      await ApiService.recategorizeAll();
      await loadTransactions();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

final unifiedTransactionsProvider =
    NotifierProvider<UnifiedTransactionsNotifier, UnifiedTransactionsState>(
        UnifiedTransactionsNotifier.new);
