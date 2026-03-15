/// Budget, goals, reminders, and recurring transaction API calls.
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/budget_models.dart';
import 'api_client.dart';

class BudgetApi {
  // ── Budgets ────────────────────────────────────────────────

  /// Get budget progress (budget vs actual spending) for a month.
  static Future<List<BudgetProgress>> getBudgetProgress({
    int? year,
    int? month,
  }) async {
    final params = <String, String>{};
    if (year != null) params['year'] = year.toString();
    if (month != null) params['month'] = month.toString();
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/budgets/progress')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: ApiClient.headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch budget progress: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((b) => BudgetProgress.fromJson(b)).toList();
  }

  /// Get overall budget summary for a month.
  static Future<BudgetSummary> getBudgetSummary({
    int? year,
    int? month,
  }) async {
    final params = <String, String>{};
    if (year != null) params['year'] = year.toString();
    if (month != null) params['month'] = month.toString();
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/budgets/summary')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: ApiClient.headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch budget summary: ${response.body}');
    }
    return BudgetSummary.fromJson(jsonDecode(response.body));
  }

  /// Create a new budget.
  static Future<Budget> createBudget({
    required int categoryId,
    required int year,
    required int month,
    required double amount,
    bool rollover = false,
    String? notes,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/budgets'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode({
        'category_id': categoryId,
        'year': year,
        'month': month,
        'amount': amount,
        'rollover': rollover,
        'notes': notes,
      }),
    );
    if (response.statusCode != 201) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to create budget: $detail');
    }
    return Budget.fromJson(jsonDecode(response.body));
  }

  /// Copy budgets from one month to another.
  static Future<List<Budget>> copyBudgets({
    required int fromYear,
    required int fromMonth,
    required int toYear,
    required int toMonth,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/budgets/copy'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode({
        'from_year': fromYear,
        'from_month': fromMonth,
        'to_year': toYear,
        'to_month': toMonth,
      }),
    );
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to copy budgets: $detail');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((b) => Budget.fromJson(b)).toList();
  }

  /// Update a budget.
  static Future<Budget> updateBudget(
    int budgetId, {
    double? amount,
    bool? rollover,
    String? notes,
  }) async {
    final body = <String, dynamic>{};
    if (amount != null) body['amount'] = amount;
    if (rollover != null) body['rollover'] = rollover;
    if (notes != null) body['notes'] = notes;
    final response = await http.patch(
      Uri.parse('${ApiClient.baseUrl}/api/v2/budgets/$budgetId'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to update budget: $detail');
    }
    return Budget.fromJson(jsonDecode(response.body));
  }

  /// Delete a budget.
  static Future<void> deleteBudget(int budgetId) async {
    final response = await http.delete(
      Uri.parse('${ApiClient.baseUrl}/api/v2/budgets/$budgetId'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete budget: ${response.body}');
    }
  }

  // ── Savings Goals ──────────────────────────────────────────

  /// List savings goals.
  static Future<List<SavingsGoal>> getGoals({
    bool includeCompleted = false,
  }) async {
    final params = <String, String>{};
    if (includeCompleted) params['include_completed'] = 'true';
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/goals')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: ApiClient.headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch goals: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((g) => SavingsGoal.fromJson(g)).toList();
  }

  /// Create a savings goal.
  static Future<SavingsGoal> createGoal({
    required String name,
    required double targetAmount,
    double currentAmount = 0,
    String? deadline,
    String? icon,
    String? color,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'target_amount': targetAmount,
      'current_amount': currentAmount,
    };
    if (deadline != null) body['deadline'] = deadline;
    if (icon != null) body['icon'] = icon;
    if (color != null) body['color'] = color;
    if (notes != null) body['notes'] = notes;

    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/goals'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode(body),
    );
    if (response.statusCode != 201) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to create goal: $detail');
    }
    return SavingsGoal.fromJson(jsonDecode(response.body));
  }

  /// Contribute to a savings goal.
  static Future<SavingsGoal> contributeToGoal(int goalId, double amount) async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/goals/$goalId/contribute'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode({'amount': amount}),
    );
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to contribute to goal: $detail');
    }
    return SavingsGoal.fromJson(jsonDecode(response.body));
  }

  /// Delete a savings goal.
  static Future<void> deleteGoal(int goalId) async {
    final response = await http.delete(
      Uri.parse('${ApiClient.baseUrl}/api/v2/goals/$goalId'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete goal: ${response.body}');
    }
  }

  // ── Bill Reminders ─────────────────────────────────────────

  /// List bill reminders.
  static Future<List<BillReminder>> getReminders({
    bool includePaid = false,
    int? upcomingDays,
  }) async {
    final params = <String, String>{};
    if (includePaid) params['include_paid'] = 'true';
    if (upcomingDays != null) {
      params['upcoming_days'] = upcomingDays.toString();
    }
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/reminders')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: ApiClient.headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch reminders: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((r) => BillReminder.fromJson(r)).toList();
  }

  /// Create a bill reminder.
  static Future<BillReminder> createReminder({
    required String name,
    double? amount,
    int? categoryId,
    bool isRecurring = true,
    String? frequency,
    int? dayOfMonth,
    String? nextDueDate,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'is_recurring': isRecurring,
    };
    if (amount != null) body['amount'] = amount;
    if (categoryId != null) body['category_id'] = categoryId;
    if (frequency != null) body['frequency'] = frequency;
    if (dayOfMonth != null) body['day_of_month'] = dayOfMonth;
    if (nextDueDate != null) body['next_due_date'] = nextDueDate;
    if (notes != null) body['notes'] = notes;

    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/reminders'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode(body),
    );
    if (response.statusCode != 201) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to create reminder: $detail');
    }
    return BillReminder.fromJson(jsonDecode(response.body));
  }

  /// Mark a bill reminder as paid.
  static Future<BillReminder> markReminderPaid(int reminderId) async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/reminders/$reminderId/paid'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to mark paid: $detail');
    }
    return BillReminder.fromJson(jsonDecode(response.body));
  }

  /// Delete a bill reminder.
  static Future<void> deleteReminder(int reminderId) async {
    final response = await http.delete(
      Uri.parse('${ApiClient.baseUrl}/api/v2/reminders/$reminderId'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete reminder: ${response.body}');
    }
  }

  /// Auto-detect CC dues as bill reminders.
  static Future<List<BillReminder>> autoDetectReminders() async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/reminders/auto-detect'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to auto-detect reminders: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((r) => BillReminder.fromJson(r)).toList();
  }

  // ── Recurring Transactions ─────────────────────────────────

  /// List detected recurring transactions.
  static Future<List<RecurringTransaction>> getRecurring({
    bool activeOnly = true,
  }) async {
    final params = <String, String>{};
    if (activeOnly) params['active_only'] = 'true';
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/recurring')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: ApiClient.headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch recurring: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((r) => RecurringTransaction.fromJson(r)).toList();
  }

  /// Trigger recurring transaction detection.
  static Future<List<RecurringTransaction>> detectRecurring() async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/recurring/detect'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to detect recurring: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((r) => RecurringTransaction.fromJson(r)).toList();
  }

  /// Toggle subscription flag on a recurring transaction.
  static Future<RecurringTransaction> toggleSubscription(
    int recurringId,
    bool isSubscription,
  ) async {
    final response = await http.patch(
      Uri.parse('${ApiClient.baseUrl}/api/v2/recurring/$recurringId/subscription'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode({'is_subscription': isSubscription}),
    );
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to toggle subscription: $detail');
    }
    return RecurringTransaction.fromJson(jsonDecode(response.body));
  }

  /// Delete a recurring transaction record.
  static Future<void> deleteRecurring(int recurringId) async {
    final response = await http.delete(
      Uri.parse('${ApiClient.baseUrl}/api/v2/recurring/$recurringId'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete recurring: ${response.body}');
    }
  }
}
