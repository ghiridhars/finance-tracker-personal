/// Dashboard state management — loads all analytics data.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/analytics_models.dart';
import '../services/api_service.dart';

// ── Date range helper ───────────────────────────────────────

enum DashboardRange { last7d, last30d, last90d, last6m, last1y, allTime }

extension DashboardRangeLabel on DashboardRange {
  String get label => switch (this) {
        DashboardRange.last7d => '7 Days',
        DashboardRange.last30d => '30 Days',
        DashboardRange.last90d => '90 Days',
        DashboardRange.last6m => '6 Months',
        DashboardRange.last1y => '1 Year',
        DashboardRange.allTime => 'All Time',
      };

  /// Returns (from, to) ISO date strings. null = no bound.
  (String?, String?) get dates {
    final now = DateTime.now();
    String to = _iso(now);
    switch (this) {
      case DashboardRange.last7d:
        return (_iso(now.subtract(const Duration(days: 7))), to);
      case DashboardRange.last30d:
        return (_iso(now.subtract(const Duration(days: 30))), to);
      case DashboardRange.last90d:
        return (_iso(now.subtract(const Duration(days: 90))), to);
      case DashboardRange.last6m:
        return (_iso(now.subtract(const Duration(days: 180))), to);
      case DashboardRange.last1y:
        return (_iso(now.subtract(const Duration(days: 365))), to);
      case DashboardRange.allTime:
        return (null, null);
    }
  }

  static String _iso(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

// ── State ───────────────────────────────────────────────────

class DashboardState {
  final bool isLoading;
  final String? error;
  final DashboardRange range;
  final DashboardSummary? summary;
  final List<CategorySpending> categorySpending;
  final List<SpendingTrend> spendingTrends;
  final List<IncomeVsExpense> incomeVsExpense;
  final MonthOverMonth? monthOverMonth;
  final List<MerchantSpending> topMerchants;

  const DashboardState({
    this.isLoading = false,
    this.error,
    this.range = DashboardRange.last30d,
    this.summary,
    this.categorySpending = const [],
    this.spendingTrends = const [],
    this.incomeVsExpense = const [],
    this.monthOverMonth,
    this.topMerchants = const [],
  });

  DashboardState copyWith({
    bool? isLoading,
    String? error,
    DashboardRange? range,
    DashboardSummary? summary,
    List<CategorySpending>? categorySpending,
    List<SpendingTrend>? spendingTrends,
    List<IncomeVsExpense>? incomeVsExpense,
    MonthOverMonth? monthOverMonth,
    List<MerchantSpending>? topMerchants,
  }) {
    return DashboardState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      range: range ?? this.range,
      summary: summary ?? this.summary,
      categorySpending: categorySpending ?? this.categorySpending,
      spendingTrends: spendingTrends ?? this.spendingTrends,
      incomeVsExpense: incomeVsExpense ?? this.incomeVsExpense,
      monthOverMonth: monthOverMonth ?? this.monthOverMonth,
      topMerchants: topMerchants ?? this.topMerchants,
    );
  }
}

// ── Notifier ────────────────────────────────────────────────

class DashboardNotifier extends Notifier<DashboardState> {
  @override
  DashboardState build() {
    // Auto-load on first access
    Future.microtask(() => loadDashboard());
    return const DashboardState(isLoading: true);
  }

  Future<void> loadDashboard({DashboardRange? range}) async {
    final r = range ?? state.range;
    state = state.copyWith(isLoading: true, error: null, range: r);

    try {
      final (from, to) = r.dates;

      // Determine granularity based on range
      String granularity;
      switch (r) {
        case DashboardRange.last7d:
          granularity = 'daily';
        case DashboardRange.last30d:
          granularity = 'daily';
        case DashboardRange.last90d:
          granularity = 'weekly';
        case DashboardRange.last6m:
          granularity = 'monthly';
        case DashboardRange.last1y:
          granularity = 'monthly';
        case DashboardRange.allTime:
          granularity = 'monthly';
      }

      // Fire all requests concurrently
      final results = await Future.wait([
        ApiService.getDashboardSummary(from: from, to: to),
        ApiService.getSpendingByCategory(from: from, to: to),
        ApiService.getSpendingTrends(from: from, to: to, granularity: granularity),
        ApiService.getIncomeVsExpense(from: from, to: to),
        ApiService.getMonthOverMonth(),
        ApiService.getTopMerchants(from: from, to: to),
      ]);

      state = state.copyWith(
        isLoading: false,
        summary: results[0] as DashboardSummary,
        categorySpending: results[1] as List<CategorySpending>,
        spendingTrends: results[2] as List<SpendingTrend>,
        incomeVsExpense: results[3] as List<IncomeVsExpense>,
        monthOverMonth: results[4] as MonthOverMonth,
        topMerchants: results[5] as List<MerchantSpending>,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setRange(DashboardRange range) => loadDashboard(range: range);
}

// ── Provider ────────────────────────────────────────────────

final dashboardProvider =
    NotifierProvider<DashboardNotifier, DashboardState>(DashboardNotifier.new);
