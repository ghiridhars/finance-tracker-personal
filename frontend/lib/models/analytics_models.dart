/// Models for analytics/dashboard data from the backend.

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
      totalIncome: _d(json['total_income']),
      totalSpending: _d(json['total_spending']),
      netSavings: _d(json['net_savings']),
      transactionCount: json['transaction_count'] ?? 0,
      avgTransaction: _d(json['avg_transaction']),
      topSpendingCategory: json['top_spending_category'],
      topSpendingAmount: _d(json['top_spending_amount']),
      activeBanks: json['active_banks'] ?? 0,
    );
  }

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
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
      amount: _d(json['amount']),
      percentage: _d(json['percentage']),
      count: json['count'] ?? 0,
    );
  }

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
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
      spending: _d(json['spending']),
      count: json['count'] ?? 0,
    );
  }

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
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
      spending: _d(json['spending']),
      income: _d(json['income']),
      count: json['count'] ?? 0,
      byAccount:
          accountList.map((a) => AccountSpending.fromJson(a)).toList(),
    );
  }

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
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
      income: _d(json['income']),
      expense: _d(json['expense']),
      net: _d(json['net']),
    );
  }

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
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
      current: _d(json['current']),
      previous: _d(json['previous']),
      changePct: json['change_pct'] != null ? _d(json['change_pct']) : null,
    );
  }

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
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
      currentTotal: _d(json['current_total']),
      previousTotal: _d(json['previous_total']),
      totalChangePct: json['total_change_pct'] != null
          ? _d(json['total_change_pct'])
          : null,
      comparison: (json['comparison'] as List<dynamic>?)
              ?.map((c) => MonthComparison.fromJson(c))
              .toList() ??
          [],
    );
  }

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
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
      amount: _d(json['amount']),
      count: json['count'] ?? 0,
      percentage: _d(json['percentage']),
    );
  }

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
