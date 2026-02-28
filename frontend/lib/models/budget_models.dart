/// Phase 5 models — Budget, SavingsGoal, BillReminder, RecurringTransaction.
import 'category_models.dart';

// ── Helper ──────────────────────────────────────────────────

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

// ── Budget ──────────────────────────────────────────────────

class Budget {
  final int id;
  final int categoryId;
  final int year;
  final int month;
  final double amount;
  final bool rollover;
  final String? notes;
  final String? createdAt;
  final Category? category;

  Budget({
    required this.id,
    required this.categoryId,
    required this.year,
    required this.month,
    required this.amount,
    this.rollover = false,
    this.notes,
    this.createdAt,
    this.category,
  });

  factory Budget.fromJson(Map<String, dynamic> json) {
    return Budget(
      id: json['id'],
      categoryId: json['category_id'],
      year: json['year'],
      month: json['month'],
      amount: _toDouble(json['amount']) ?? 0,
      rollover: json['rollover'] ?? false,
      notes: json['notes'],
      createdAt: json['created_at'],
      category:
          json['category'] != null ? Category.fromJson(json['category']) : null,
    );
  }
}

class BudgetProgress {
  final int id;
  final int categoryId;
  final String categoryName;
  final String? categoryColor;
  final String? categoryIcon;
  final int year;
  final int month;
  final double budgetAmount;
  final double spentAmount;
  final double remaining;
  final double percentageUsed;
  final double rolloverAmount;
  final bool isOverBudget;

  BudgetProgress({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    this.categoryColor,
    this.categoryIcon,
    required this.year,
    required this.month,
    required this.budgetAmount,
    required this.spentAmount,
    required this.remaining,
    required this.percentageUsed,
    this.rolloverAmount = 0,
    this.isOverBudget = false,
  });

  factory BudgetProgress.fromJson(Map<String, dynamic> json) {
    return BudgetProgress(
      id: json['id'],
      categoryId: json['category_id'],
      categoryName: json['category_name'] ?? '',
      categoryColor: json['category_color'],
      categoryIcon: json['category_icon'],
      year: json['year'],
      month: json['month'],
      budgetAmount: _toDouble(json['budget_amount']) ?? 0,
      spentAmount: _toDouble(json['spent_amount']) ?? 0,
      remaining: _toDouble(json['remaining']) ?? 0,
      percentageUsed: _toDouble(json['percentage_used']) ?? 0,
      rolloverAmount: _toDouble(json['rollover_amount']) ?? 0,
      isOverBudget: json['is_over_budget'] ?? false,
    );
  }
}

class BudgetSummary {
  final int year;
  final int month;
  final double totalBudgeted;
  final double totalSpent;
  final double overallPercentage;
  final int overBudgetCount;
  final List<BudgetProgress> categories;

  BudgetSummary({
    required this.year,
    required this.month,
    required this.totalBudgeted,
    required this.totalSpent,
    required this.overallPercentage,
    this.overBudgetCount = 0,
    this.categories = const [],
  });

  factory BudgetSummary.fromJson(Map<String, dynamic> json) {
    return BudgetSummary(
      year: json['year'],
      month: json['month'],
      totalBudgeted: _toDouble(json['total_budgeted']) ?? 0,
      totalSpent: _toDouble(json['total_spent']) ?? 0,
      overallPercentage: _toDouble(json['overall_percentage']) ?? 0,
      overBudgetCount: json['over_budget_count'] ?? 0,
      categories: (json['categories'] as List<dynamic>?)
              ?.map((c) => BudgetProgress.fromJson(c))
              .toList() ??
          [],
    );
  }
}

// ── SavingsGoal ─────────────────────────────────────────────

class SavingsGoal {
  final int id;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final String? deadline;
  final String? icon;
  final String? color;
  final String? notes;
  final bool isCompleted;
  final String? createdAt;
  final double percentage;
  final int? daysRemaining;

  SavingsGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    this.currentAmount = 0,
    this.deadline,
    this.icon,
    this.color,
    this.notes,
    this.isCompleted = false,
    this.createdAt,
    this.percentage = 0,
    this.daysRemaining,
  });

  factory SavingsGoal.fromJson(Map<String, dynamic> json) {
    return SavingsGoal(
      id: json['id'],
      name: json['name'] ?? '',
      targetAmount: _toDouble(json['target_amount']) ?? 0,
      currentAmount: _toDouble(json['current_amount']) ?? 0,
      deadline: json['deadline'],
      icon: json['icon'],
      color: json['color'],
      notes: json['notes'],
      isCompleted: json['is_completed'] ?? false,
      createdAt: json['created_at'],
      percentage: _toDouble(json['percentage']) ?? 0,
      daysRemaining: json['days_remaining'],
    );
  }
}

// ── BillReminder ────────────────────────────────────────────

class BillReminder {
  final int id;
  final String name;
  final double? amount;
  final int? categoryId;
  final bool isRecurring;
  final String? frequency;
  final int? dayOfMonth;
  final String? nextDueDate;
  final bool isAutoDetected;
  final bool isPaid;
  final String? notes;
  final String? createdAt;
  final Category? category;
  final int? daysUntilDue;
  final bool isOverdue;

  BillReminder({
    required this.id,
    required this.name,
    this.amount,
    this.categoryId,
    this.isRecurring = true,
    this.frequency,
    this.dayOfMonth,
    this.nextDueDate,
    this.isAutoDetected = false,
    this.isPaid = false,
    this.notes,
    this.createdAt,
    this.category,
    this.daysUntilDue,
    this.isOverdue = false,
  });

  factory BillReminder.fromJson(Map<String, dynamic> json) {
    return BillReminder(
      id: json['id'],
      name: json['name'] ?? '',
      amount: _toDouble(json['amount']),
      categoryId: json['category_id'],
      isRecurring: json['is_recurring'] ?? true,
      frequency: json['frequency'],
      dayOfMonth: json['day_of_month'],
      nextDueDate: json['next_due_date'],
      isAutoDetected: json['is_auto_detected'] ?? false,
      isPaid: json['is_paid'] ?? false,
      notes: json['notes'],
      createdAt: json['created_at'],
      category:
          json['category'] != null ? Category.fromJson(json['category']) : null,
      daysUntilDue: json['days_until_due'],
      isOverdue: json['is_overdue'] ?? false,
    );
  }
}

// ── RecurringTransaction ────────────────────────────────────

class RecurringTransaction {
  final int id;
  final String merchantName;
  final String? descriptionPattern;
  final double averageAmount;
  final String frequency;
  final int? categoryId;
  final Category? category;
  final String? lastDate;
  final String? nextExpectedDate;
  final int occurrenceCount;
  final bool isActive;
  final bool isSubscription;
  final String? createdAt;

  RecurringTransaction({
    required this.id,
    required this.merchantName,
    this.descriptionPattern,
    required this.averageAmount,
    required this.frequency,
    this.categoryId,
    this.category,
    this.lastDate,
    this.nextExpectedDate,
    this.occurrenceCount = 0,
    this.isActive = true,
    this.isSubscription = false,
    this.createdAt,
  });

  factory RecurringTransaction.fromJson(Map<String, dynamic> json) {
    return RecurringTransaction(
      id: json['id'],
      merchantName: json['merchant_name'] ?? '',
      descriptionPattern: json['description_pattern'],
      averageAmount: _toDouble(json['average_amount']) ?? 0,
      frequency: json['frequency'] ?? '',
      categoryId: json['category_id'],
      category:
          json['category'] != null ? Category.fromJson(json['category']) : null,
      lastDate: json['last_date'],
      nextExpectedDate: json['next_expected_date'],
      occurrenceCount: json['occurrence_count'] ?? 0,
      isActive: json['is_active'] ?? true,
      isSubscription: json['is_subscription'] ?? false,
      createdAt: json['created_at'],
    );
  }
}
