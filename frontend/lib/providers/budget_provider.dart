/// Budget & Goals state management (Phase 5).
/// Manages budgets, savings goals, bill reminders, and recurring transactions.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/budget_models.dart';
import '../models/category_models.dart';
import '../services/api_service.dart';

// ── State ───────────────────────────────────────────────────

class BudgetState {
  final bool isLoading;
  final String? error;
  final int year;
  final int month;

  // Budget data
  final List<BudgetProgress> budgetProgress;
  final BudgetSummary? summary;

  // Savings goals
  final List<SavingsGoal> goals;
  final bool showCompletedGoals;

  // Bill reminders
  final List<BillReminder> reminders;
  final bool showPaidReminders;

  // Recurring transactions
  final List<RecurringTransaction> recurring;

  // Categories (for creating budgets)
  final List<Category> categories;

  const BudgetState({
    this.isLoading = false,
    this.error,
    required this.year,
    required this.month,
    this.budgetProgress = const [],
    this.summary,
    this.goals = const [],
    this.showCompletedGoals = false,
    this.reminders = const [],
    this.showPaidReminders = false,
    this.recurring = const [],
    this.categories = const [],
  });

  BudgetState copyWith({
    bool? isLoading,
    String? error,
    int? year,
    int? month,
    List<BudgetProgress>? budgetProgress,
    BudgetSummary? summary,
    List<SavingsGoal>? goals,
    bool? showCompletedGoals,
    List<BillReminder>? reminders,
    bool? showPaidReminders,
    List<RecurringTransaction>? recurring,
    List<Category>? categories,
    bool clearError = false,
  }) {
    return BudgetState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      year: year ?? this.year,
      month: month ?? this.month,
      budgetProgress: budgetProgress ?? this.budgetProgress,
      summary: summary ?? this.summary,
      goals: goals ?? this.goals,
      showCompletedGoals: showCompletedGoals ?? this.showCompletedGoals,
      reminders: reminders ?? this.reminders,
      showPaidReminders: showPaidReminders ?? this.showPaidReminders,
      recurring: recurring ?? this.recurring,
      categories: categories ?? this.categories,
    );
  }
}

// ── Notifier ────────────────────────────────────────────────

class BudgetNotifier extends Notifier<BudgetState> {
  @override
  BudgetState build() {
    final now = DateTime.now();
    Future.microtask(() => loadAll());
    return BudgetState(
      isLoading: true,
      year: now.year,
      month: now.month,
    );
  }

  /// Load all Phase 5 data concurrently.
  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        ApiService.getBudgetSummary(year: state.year, month: state.month),
        ApiService.getBudgetProgress(year: state.year, month: state.month),
        ApiService.getGoals(includeCompleted: state.showCompletedGoals),
        ApiService.getReminders(includePaid: state.showPaidReminders),
        ApiService.getRecurring(),
        ApiService.getCategories(),
      ]);
      state = state.copyWith(
        isLoading: false,
        summary: results[0] as BudgetSummary,
        budgetProgress: results[1] as List<BudgetProgress>,
        goals: results[2] as List<SavingsGoal>,
        reminders: results[3] as List<BillReminder>,
        recurring: results[4] as List<RecurringTransaction>,
        categories: results[5] as List<Category>,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // ── Month navigation ─────────────────────────────────────

  void previousMonth() {
    int y = state.year;
    int m = state.month - 1;
    if (m < 1) {
      m = 12;
      y--;
    }
    state = state.copyWith(year: y, month: m);
    _reloadBudgets();
  }

  void nextMonth() {
    int y = state.year;
    int m = state.month + 1;
    if (m > 12) {
      m = 1;
      y++;
    }
    state = state.copyWith(year: y, month: m);
    _reloadBudgets();
  }

  Future<void> _reloadBudgets() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        ApiService.getBudgetSummary(year: state.year, month: state.month),
        ApiService.getBudgetProgress(year: state.year, month: state.month),
      ]);
      state = state.copyWith(
        isLoading: false,
        summary: results[0] as BudgetSummary,
        budgetProgress: results[1] as List<BudgetProgress>,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // ── Budget CRUD ───────────────────────────────────────────

  Future<void> createBudget({
    required int categoryId,
    required double amount,
    bool rollover = false,
    String? notes,
  }) async {
    try {
      await ApiService.createBudget(
        categoryId: categoryId,
        year: state.year,
        month: state.month,
        amount: amount,
        rollover: rollover,
        notes: notes,
      );
      await _reloadBudgets();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> updateBudget(
    int budgetId, {
    double? amount,
    bool? rollover,
    String? notes,
  }) async {
    try {
      await ApiService.updateBudget(
        budgetId,
        amount: amount,
        rollover: rollover,
        notes: notes,
      );
      await _reloadBudgets();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteBudget(int budgetId) async {
    try {
      await ApiService.deleteBudget(budgetId);
      await _reloadBudgets();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> copyFromPreviousMonth() async {
    int prevYear = state.year;
    int prevMonth = state.month - 1;
    if (prevMonth < 1) {
      prevMonth = 12;
      prevYear--;
    }
    try {
      await ApiService.copyBudgets(
        fromYear: prevYear,
        fromMonth: prevMonth,
        toYear: state.year,
        toMonth: state.month,
      );
      await _reloadBudgets();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // ── Goals ─────────────────────────────────────────────────

  Future<void> createGoal({
    required String name,
    required double targetAmount,
    double currentAmount = 0,
    String? deadline,
    String? icon,
    String? color,
    String? notes,
  }) async {
    try {
      await ApiService.createGoal(
        name: name,
        targetAmount: targetAmount,
        currentAmount: currentAmount,
        deadline: deadline,
        icon: icon,
        color: color,
        notes: notes,
      );
      await _reloadGoals();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> contributeToGoal(int goalId, double amount) async {
    try {
      await ApiService.contributeToGoal(goalId, amount);
      await _reloadGoals();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteGoal(int goalId) async {
    try {
      await ApiService.deleteGoal(goalId);
      await _reloadGoals();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void toggleShowCompletedGoals() {
    state = state.copyWith(
        showCompletedGoals: !state.showCompletedGoals);
    _reloadGoals();
  }

  Future<void> _reloadGoals() async {
    try {
      final goals = await ApiService.getGoals(
          includeCompleted: state.showCompletedGoals);
      state = state.copyWith(goals: goals);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // ── Bill Reminders ────────────────────────────────────────

  Future<void> createReminder({
    required String name,
    double? amount,
    int? categoryId,
    bool isRecurring = true,
    String? frequency,
    int? dayOfMonth,
    String? nextDueDate,
    String? notes,
  }) async {
    try {
      await ApiService.createReminder(
        name: name,
        amount: amount,
        categoryId: categoryId,
        isRecurring: isRecurring,
        frequency: frequency,
        dayOfMonth: dayOfMonth,
        nextDueDate: nextDueDate,
        notes: notes,
      );
      await _reloadReminders();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> markReminderPaid(int reminderId) async {
    try {
      await ApiService.markReminderPaid(reminderId);
      await _reloadReminders();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteReminder(int reminderId) async {
    try {
      await ApiService.deleteReminder(reminderId);
      await _reloadReminders();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> autoDetectReminders() async {
    try {
      await ApiService.autoDetectReminders();
      await _reloadReminders();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void toggleShowPaidReminders() {
    state = state.copyWith(
        showPaidReminders: !state.showPaidReminders);
    _reloadReminders();
  }

  Future<void> _reloadReminders() async {
    try {
      final reminders = await ApiService.getReminders(
          includePaid: state.showPaidReminders);
      state = state.copyWith(reminders: reminders);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // ── Recurring Transactions ────────────────────────────────

  Future<void> detectRecurring() async {
    try {
      await ApiService.detectRecurring();
      await _reloadRecurring();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> toggleSubscription(int id, bool isSubscription) async {
    try {
      await ApiService.toggleSubscription(id, isSubscription);
      await _reloadRecurring();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteRecurring(int id) async {
    try {
      await ApiService.deleteRecurring(id);
      await _reloadRecurring();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> _reloadRecurring() async {
    try {
      final recurring = await ApiService.getRecurring();
      state = state.copyWith(recurring: recurring);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

// ── Provider ────────────────────────────────────────────────

final budgetProvider =
    NotifierProvider<BudgetNotifier, BudgetState>(BudgetNotifier.new);
