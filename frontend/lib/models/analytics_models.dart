/// Models for analytics/dashboard data from the backend.
import 'converters.dart';

class DashboardSummary {
  final String fromDate;
  final String toDate;
  final double totalIncome;
  final double totalSpending;
  final double netSavings;
  final int transactionCount;
  final double avgTransaction;
  final String? topSpendingCategory;
  final double topSpendingAmount;
  final int activeBanks;

  DashboardSummary({
    required this.fromDate,
    required this.toDate,
    required this.totalIncome,
    required this.totalSpending,
    required this.netSavings,
    required this.transactionCount,
    required this.avgTransaction,
    this.topSpendingCategory,
    required this.topSpendingAmount,
    required this.activeBanks,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      fromDate: json['from_date'] ?? '',
      toDate: json['to_date'] ?? '',
      totalIncome: toDouble(json['total_income']) ?? 0,
      totalSpending: toDouble(json['total_spending']) ?? 0,
      netSavings: toDouble(json['net_savings']) ?? 0,
      transactionCount: json['transaction_count'] ?? 0,
      avgTransaction: toDouble(json['avg_transaction']) ?? 0,
      topSpendingCategory: json['top_spending_category'],
      topSpendingAmount: toDouble(json['top_spending_amount']) ?? 0,
      activeBanks: json['active_banks'] ?? 0,
    );
  }
}

class CategorySpending {
  final int? categoryId;
  final String category;
  final String? color;
  final String? icon;
  final double amount;
  final double percentage;
  final int count;

  CategorySpending({
    this.categoryId,
    required this.category,
    this.color,
    this.icon,
    required this.amount,
    required this.percentage,
    required this.count,
  });

  factory CategorySpending.fromJson(Map<String, dynamic> json) {
    return CategorySpending(
      categoryId: json['category_id'],
      category: json['category'] ?? 'Unknown',
      color: json['color'],
      icon: json['icon'],
      amount: toDouble(json['amount']) ?? 0,
      percentage: toDouble(json['percentage']) ?? 0,
      count: json['count'] ?? 0,
    );
  }
}

class AccountSpending {
  final String bank;
  final double spending;
  final int count;

  AccountSpending({
    required this.bank,
    required this.spending,
    required this.count,
  });

  factory AccountSpending.fromJson(Map<String, dynamic> json) {
    return AccountSpending(
      bank: json['bank'] ?? 'OTHER',
      spending: toDouble(json['spending']) ?? 0,
      count: json['count'] ?? 0,
    );
  }
}

class SpendingTrend {
  final String period;
  final double spending;
  final double income;
  final int count;
  final List<AccountSpending> byAccount;

  SpendingTrend({
    required this.period,
    required this.spending,
    required this.income,
    required this.count,
    this.byAccount = const [],
  });

  factory SpendingTrend.fromJson(Map<String, dynamic> json) {
    final accountList = json['by_account'] as List<dynamic>? ?? [];
    return SpendingTrend(
      period: json['period'] ?? '',
      spending: toDouble(json['spending']) ?? 0,
      income: toDouble(json['income']) ?? 0,
      count: json['count'] ?? 0,
      byAccount:
          accountList.map((a) => AccountSpending.fromJson(a)).toList(),
    );
  }
}

class IncomeVsExpense {
  final String month;
  final double income;
  final double expense;
  final double net;

  IncomeVsExpense({
    required this.month,
    required this.income,
    required this.expense,
    required this.net,
  });

  factory IncomeVsExpense.fromJson(Map<String, dynamic> json) {
    return IncomeVsExpense(
      month: json['month'] ?? '',
      income: toDouble(json['income']) ?? 0,
      expense: toDouble(json['expense']) ?? 0,
      net: toDouble(json['net']) ?? 0,
    );
  }
}

class MonthComparison {
  final String category;
  final double current;
  final double previous;
  final double? changePct;

  MonthComparison({
    required this.category,
    required this.current,
    required this.previous,
    this.changePct,
  });

  factory MonthComparison.fromJson(Map<String, dynamic> json) {
    return MonthComparison(
      category: json['category'] ?? '',
      current: toDouble(json['current']) ?? 0,
      previous: toDouble(json['previous']) ?? 0,
      changePct: json['change_pct'] != null ? (toDouble(json['change_pct']) ?? 0) : null,
    );
  }
}

class MonthOverMonth {
  final String currentMonth;
  final String previousMonth;
  final double currentTotal;
  final double previousTotal;
  final double? totalChangePct;
  final List<MonthComparison> comparison;

  MonthOverMonth({
    required this.currentMonth,
    required this.previousMonth,
    required this.currentTotal,
    required this.previousTotal,
    this.totalChangePct,
    required this.comparison,
  });

  factory MonthOverMonth.fromJson(Map<String, dynamic> json) {
    return MonthOverMonth(
      currentMonth: json['current_month'] ?? '',
      previousMonth: json['previous_month'] ?? '',
      currentTotal: toDouble(json['current_total']) ?? 0,
      previousTotal: toDouble(json['previous_total']) ?? 0,
      totalChangePct: json['total_change_pct'] != null
          ? (toDouble(json['total_change_pct']) ?? 0)
          : null,
      comparison: (json['comparison'] as List<dynamic>?)
              ?.map((c) => MonthComparison.fromJson(c))
              .toList() ??
          [],
    );
  }
}

class MerchantSpending {
  final String merchant;
  final double amount;
  final int count;
  final double percentage;

  MerchantSpending({
    required this.merchant,
    required this.amount,
    required this.count,
    required this.percentage,
  });

  factory MerchantSpending.fromJson(Map<String, dynamic> json) {
    return MerchantSpending(
      merchant: json['merchant'] ?? 'Unknown',
      amount: toDouble(json['amount']) ?? 0,
      count: json['count'] ?? 0,
      percentage: toDouble(json['percentage']) ?? 0,
    );
  }
}
