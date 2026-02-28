/// API service for communicating with the FastAPI backend.
/// Replaces: statementService.ts (Axios-based) from React frontend.
///
/// Key differences from React version:
/// - Uses dart:http instead of Axios
/// - Typed model deserialization instead of raw JSON
/// - File upload via http.MultipartRequest instead of FormData
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/savings_models.dart';
import '../models/credit_card_models.dart';
import '../models/category_models.dart';
import '../models/unified_transaction_models.dart';
import '../models/analytics_models.dart';
import '../models/account_models.dart';
import '../models/budget_models.dart';

class ApiService {
  // Base URL — configurable for dev/prod
  static const String baseUrl = 'http://127.0.0.1:8080';

  /// Get savings transactions (default: last 30 days).
  /// Replaces: statementService.getTransactions(from?, to?) in React
  static Future<List<SavingsTransaction>> getSavingsTransactions({
    String? from,
    String? to,
  }) async {
    final params = <String, String>{};
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;

    final uri = Uri.parse('$baseUrl/api/transactions/savings')
        .replace(queryParameters: params.isNotEmpty ? params : null);

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch transactions: ${response.body}');
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data.map((t) => SavingsTransaction.fromJson(t)).toList();
  }

  /// Get credit card transactions.
  /// FIX: This endpoint was missing in the Java version.
  static Future<List<CreditCardTransaction>> getCreditCardTransactions({
    String? from,
    String? to,
  }) async {
    final params = <String, String>{};
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;

    final uri = Uri.parse('$baseUrl/api/transactions/credit-card')
        .replace(queryParameters: params.isNotEmpty ? params : null);

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch transactions: ${response.body}');
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data.map((t) => CreditCardTransaction.fromJson(t)).toList();
  }

  /// Health check — verifies backend is reachable.
  static Future<Map<String, dynamic>> healthCheck() async {
    final response = await http.get(Uri.parse('$baseUrl/health'));
    return jsonDecode(response.body);
  }

  /// Extract error detail from FastAPI error response JSON.
  static String _extractErrorDetail(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json.containsKey('detail')) {
        return json['detail'].toString();
      }
    } catch (_) {}
    return body;
  }

  // ── V2 Unified Endpoints ──────────────────────────────────

  /// Upload a PDF statement via the unified v2 endpoint.
  /// Works for any bank + statement type combination.
  static Future<Map<String, dynamic>> uploadStatementV2({
    required List<int> fileBytes,
    required String fileName,
    required String bank,
    required String statementType,
    bool save = true,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/v2/statements/upload'
      '?bank=$bank&type=$statementType&save=$save',
    );
    final request = http.MultipartRequest('POST', uri);
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: fileName,
      contentType: MediaType('application', 'pdf'),
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      final detail = _extractErrorDetail(response.body);
      throw Exception('Upload failed (${response.statusCode}): $detail');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Upload a CSV statement via the unified v2 endpoint.
  static Future<Map<String, dynamic>> uploadCsvStatementV2({
    required List<int> fileBytes,
    required String fileName,
    required String bank,
    required String statementType,
    bool save = true,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/v2/statements/upload-csv'
      '?bank=$bank&type=$statementType&save=$save',
    );
    final request = http.MultipartRequest('POST', uri);
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: fileName,
      contentType: MediaType('text', 'csv'),
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      final detail = _extractErrorDetail(response.body);
      throw Exception('Upload failed (${response.statusCode}): $detail');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ── V2 Categories ─────────────────────────────────────────

  /// Get all categories.
  static Future<List<Category>> getCategories() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v2/categories'));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch categories: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((c) => Category.fromJson(c)).toList();
  }

  /// Create a new category.
  static Future<Category> createCategory({
    required String name,
    String? icon,
    String? color,
    List<String> keywords = const [],
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v2/categories'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'icon': icon,
        'color': color,
        'keywords': keywords,
      }),
    );
    if (response.statusCode != 201) {
      final detail = _extractErrorDetail(response.body);
      throw Exception('Failed to create category: $detail');
    }
    return Category.fromJson(jsonDecode(response.body));
  }

  /// Add keywords to a category.
  static Future<Category> addCategoryKeywords(
      int categoryId, List<String> keywords) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v2/categories/$categoryId/keywords'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'keywords': keywords}),
    );
    if (response.statusCode != 200) {
      final detail = _extractErrorDetail(response.body);
      throw Exception('Failed to add keywords: $detail');
    }
    return Category.fromJson(jsonDecode(response.body));
  }

  /// Delete a category.
  static Future<void> deleteCategory(int categoryId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v2/categories/$categoryId'),
    );
    if (response.statusCode != 200) {
      final detail = _extractErrorDetail(response.body);
      throw Exception('Failed to delete category: $detail');
    }
  }

  // ── V2 Unified Transactions ───────────────────────────────

  /// Get unified transactions with optional filters.
  static Future<List<UnifiedTransaction>> getUnifiedTransactions({
    String? from,
    String? to,
    int? categoryId,
    String? bank,
    String? sourceType,
    String? type,
    String? search,
    double? minAmount,
    double? maxAmount,
    int limit = 100,
    int offset = 0,
  }) async {
    final params = <String, String>{};
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;
    if (categoryId != null) params['category_id'] = categoryId.toString();
    if (bank != null) params['bank'] = bank;
    if (sourceType != null) params['source_type'] = sourceType;
    if (type != null) params['type'] = type;
    if (search != null) params['search'] = search;
    if (minAmount != null) params['min_amount'] = minAmount.toString();
    if (maxAmount != null) params['max_amount'] = maxAmount.toString();
    params['limit'] = limit.toString();
    params['offset'] = offset.toString();

    final uri = Uri.parse('$baseUrl/api/v2/transactions')
        .replace(queryParameters: params);

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch transactions: ${response.body}');
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data.map((t) => UnifiedTransaction.fromJson(t)).toList();
  }

  /// Update a unified transaction (re-categorize, add notes, etc.)
  static Future<UnifiedTransaction> updateTransaction(
    int transactionId, {
    int? categoryId,
    String? merchantName,
    String? notes,
    List<int>? tagIds,
  }) async {
    final body = <String, dynamic>{};
    if (categoryId != null) body['category_id'] = categoryId;
    if (merchantName != null) body['merchant_name'] = merchantName;
    if (notes != null) body['notes'] = notes;
    if (tagIds != null) body['tag_ids'] = tagIds;

    final response = await http.patch(
      Uri.parse('$baseUrl/api/v2/transactions/$transactionId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      final detail = _extractErrorDetail(response.body);
      throw Exception('Failed to update transaction: $detail');
    }
    return UnifiedTransaction.fromJson(jsonDecode(response.body));
  }

  /// Trigger bulk re-categorization of all transactions.
  static Future<int> recategorizeAll() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v2/transactions/recategorize'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to recategorize: ${response.body}');
    }
    final data = jsonDecode(response.body);
    return data['updated'] as int;
  }

  // ── V2 Analytics / Dashboard ──────────────────────────────

  static Map<String, String> _dateParams({String? from, String? to}) {
    final p = <String, String>{};
    if (from != null) p['from'] = from;
    if (to != null) p['to'] = to;
    return p;
  }

  /// Dashboard summary (income, spending, net, top category, etc.)
  static Future<DashboardSummary> getDashboardSummary({
    String? from,
    String? to,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v2/analytics/summary')
        .replace(queryParameters: _dateParams(from: from, to: to));
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch summary: ${response.body}');
    }
    return DashboardSummary.fromJson(jsonDecode(response.body));
  }

  /// Spending by category (pie chart).
  static Future<List<CategorySpending>> getSpendingByCategory({
    String? from,
    String? to,
  }) async {
    final params = _dateParams(from: from, to: to);
    final uri = Uri.parse('$baseUrl/api/v2/analytics/spending-by-category')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch category spending: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((c) => CategorySpending.fromJson(c)).toList();
  }

  /// Spending trends over time (line chart).
  static Future<List<SpendingTrend>> getSpendingTrends({
    String? from,
    String? to,
    String granularity = 'daily',
  }) async {
    final params = _dateParams(from: from, to: to);
    params['granularity'] = granularity;
    final uri = Uri.parse('$baseUrl/api/v2/analytics/spending-trends')
        .replace(queryParameters: params);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch trends: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((t) => SpendingTrend.fromJson(t)).toList();
  }

  /// Income vs expense by month (bar chart).
  static Future<List<IncomeVsExpense>> getIncomeVsExpense({
    String? from,
    String? to,
  }) async {
    final params = _dateParams(from: from, to: to);
    final uri = Uri.parse('$baseUrl/api/v2/analytics/income-vs-expense')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch income vs expense: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((d) => IncomeVsExpense.fromJson(d)).toList();
  }

  /// Month-over-month comparison.
  static Future<MonthOverMonth> getMonthOverMonth({String? month}) async {
    final params = <String, String>{};
    if (month != null) params['month'] = month;
    final uri = Uri.parse('$baseUrl/api/v2/analytics/month-over-month')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch MoM data: ${response.body}');
    }
    return MonthOverMonth.fromJson(jsonDecode(response.body));
  }

  /// Top merchants by spending.
  static Future<List<MerchantSpending>> getTopMerchants({
    String? from,
    String? to,
    int limit = 15,
  }) async {
    final params = _dateParams(from: from, to: to);
    params['limit'] = limit.toString();
    final uri = Uri.parse('$baseUrl/api/v2/analytics/top-merchants')
        .replace(queryParameters: params);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch top merchants: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((m) => MerchantSpending.fromJson(m)).toList();
  }

  // ────────────────────────────────────────────────────────────
  // Accounts & Statement Management (Phase 4)
  // ────────────────────────────────────────────────────────────

  /// List all linked accounts and credit cards.
  static Future<List<Account>> getAccounts() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v2/accounts'));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch accounts: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((a) => Account.fromJson(a)).toList();
  }

  /// List savings statements (paginated).
  static Future<PaginatedResponse<SavingsStatementSummary>>
      getSavingsStatements({
    String? accountNumber,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (accountNumber != null) params['account_number'] = accountNumber;
    final uri =
        Uri.parse('$baseUrl/api/v2/accounts/statements/savings')
            .replace(queryParameters: params);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch savings statements: ${response.body}');
    }
    final body = jsonDecode(response.body);
    final items = (body['items'] as List)
        .map((s) => SavingsStatementSummary.fromJson(s))
        .toList();
    return PaginatedResponse(
      items: items,
      total: body['total'],
      limit: body['limit'],
      offset: body['offset'],
    );
  }

  /// List credit card statements (paginated).
  static Future<PaginatedResponse<CreditCardStatementSummary>>
      getCreditCardStatements({
    String? cardNumber,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (cardNumber != null) params['card_number'] = cardNumber;
    final uri =
        Uri.parse('$baseUrl/api/v2/accounts/statements/credit-card')
            .replace(queryParameters: params);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch CC statements: ${response.body}');
    }
    final body = jsonDecode(response.body);
    final items = (body['items'] as List)
        .map((s) => CreditCardStatementSummary.fromJson(s))
        .toList();
    return PaginatedResponse(
      items: items,
      total: body['total'],
      limit: body['limit'],
      offset: body['offset'],
    );
  }

  /// Delete a savings statement (and its cascaded transactions).
  static Future<void> deleteSavingsStatement(int statementId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v2/accounts/statements/savings/$statementId'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete savings statement: ${response.body}');
    }
  }

  /// Delete a credit card statement (and its cascaded transactions).
  static Future<void> deleteCreditCardStatement(int statementId) async {
    final response = await http.delete(
      Uri.parse(
          '$baseUrl/api/v2/accounts/statements/credit-card/$statementId'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete CC statement: ${response.body}');
    }
  }

  /// Delete a single unified transaction.
  static Future<void> deleteTransaction(int transactionId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v2/transactions/$transactionId'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete transaction: ${response.body}');
    }
  }

  // ────────────────────────────────────────────────────────────
  // Budgets (Phase 5)
  // ────────────────────────────────────────────────────────────

  /// Get budget progress (budget vs actual spending) for a month.
  static Future<List<BudgetProgress>> getBudgetProgress({
    int? year,
    int? month,
  }) async {
    final params = <String, String>{};
    if (year != null) params['year'] = year.toString();
    if (month != null) params['month'] = month.toString();
    final uri = Uri.parse('$baseUrl/api/v2/budgets/progress')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri);
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
    final uri = Uri.parse('$baseUrl/api/v2/budgets/summary')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri);
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
      Uri.parse('$baseUrl/api/v2/budgets'),
      headers: {'Content-Type': 'application/json'},
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
      final detail = _extractErrorDetail(response.body);
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
      Uri.parse('$baseUrl/api/v2/budgets/copy'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'from_year': fromYear,
        'from_month': fromMonth,
        'to_year': toYear,
        'to_month': toMonth,
      }),
    );
    if (response.statusCode != 200) {
      final detail = _extractErrorDetail(response.body);
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
      Uri.parse('$baseUrl/api/v2/budgets/$budgetId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      final detail = _extractErrorDetail(response.body);
      throw Exception('Failed to update budget: $detail');
    }
    return Budget.fromJson(jsonDecode(response.body));
  }

  /// Delete a budget.
  static Future<void> deleteBudget(int budgetId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v2/budgets/$budgetId'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete budget: ${response.body}');
    }
  }

  // ────────────────────────────────────────────────────────────
  // Savings Goals (Phase 5)
  // ────────────────────────────────────────────────────────────

  /// List savings goals.
  static Future<List<SavingsGoal>> getGoals({
    bool includeCompleted = false,
  }) async {
    final params = <String, String>{};
    if (includeCompleted) params['include_completed'] = 'true';
    final uri = Uri.parse('$baseUrl/api/v2/goals')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri);
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
      Uri.parse('$baseUrl/api/v2/goals'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 201) {
      final detail = _extractErrorDetail(response.body);
      throw Exception('Failed to create goal: $detail');
    }
    return SavingsGoal.fromJson(jsonDecode(response.body));
  }

  /// Contribute to a savings goal.
  static Future<SavingsGoal> contributeToGoal(
      int goalId, double amount) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v2/goals/$goalId/contribute'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'amount': amount}),
    );
    if (response.statusCode != 200) {
      final detail = _extractErrorDetail(response.body);
      throw Exception('Failed to contribute to goal: $detail');
    }
    return SavingsGoal.fromJson(jsonDecode(response.body));
  }

  /// Delete a savings goal.
  static Future<void> deleteGoal(int goalId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v2/goals/$goalId'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete goal: ${response.body}');
    }
  }

  // ────────────────────────────────────────────────────────────
  // Bill Reminders (Phase 5)
  // ────────────────────────────────────────────────────────────

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
    final uri = Uri.parse('$baseUrl/api/v2/reminders')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri);
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
      Uri.parse('$baseUrl/api/v2/reminders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 201) {
      final detail = _extractErrorDetail(response.body);
      throw Exception('Failed to create reminder: $detail');
    }
    return BillReminder.fromJson(jsonDecode(response.body));
  }

  /// Mark a bill reminder as paid.
  static Future<BillReminder> markReminderPaid(int reminderId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v2/reminders/$reminderId/paid'),
    );
    if (response.statusCode != 200) {
      final detail = _extractErrorDetail(response.body);
      throw Exception('Failed to mark paid: $detail');
    }
    return BillReminder.fromJson(jsonDecode(response.body));
  }

  /// Delete a bill reminder.
  static Future<void> deleteReminder(int reminderId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v2/reminders/$reminderId'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete reminder: ${response.body}');
    }
  }

  /// Auto-detect CC dues as bill reminders.
  static Future<List<BillReminder>> autoDetectReminders() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v2/reminders/auto-detect'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to auto-detect reminders: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((r) => BillReminder.fromJson(r)).toList();
  }

  // ────────────────────────────────────────────────────────────
  // Recurring Transactions (Phase 5)
  // ────────────────────────────────────────────────────────────

  /// List detected recurring transactions.
  static Future<List<RecurringTransaction>> getRecurring({
    bool activeOnly = true,
  }) async {
    final params = <String, String>{};
    if (activeOnly) params['active_only'] = 'true';
    final uri = Uri.parse('$baseUrl/api/v2/recurring')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch recurring: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((r) => RecurringTransaction.fromJson(r)).toList();
  }

  /// Trigger recurring transaction detection.
  static Future<List<RecurringTransaction>> detectRecurring() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v2/recurring/detect'),
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
      Uri.parse('$baseUrl/api/v2/recurring/$recurringId/subscription'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'is_subscription': isSubscription}),
    );
    if (response.statusCode != 200) {
      final detail = _extractErrorDetail(response.body);
      throw Exception('Failed to toggle subscription: $detail');
    }
    return RecurringTransaction.fromJson(jsonDecode(response.body));
  }

  /// Delete a recurring transaction record.
  static Future<void> deleteRecurring(int recurringId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/v2/recurring/$recurringId'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete recurring: ${response.body}');
    }
  }

  // ── Export & Data Management ──────────────────────────────

  /// Get the URL for exporting transactions as CSV.
  /// Use this to trigger a download in the browser.
  static String getExportUrl({
    String format = 'csv',
    String? from,
    String? to,
    int? categoryId,
    String? bank,
    String? sourceType,
    String? type,
    String? search,
  }) {
    final params = <String, String>{'format': format};
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;
    if (categoryId != null) params['category_id'] = categoryId.toString();
    if (bank != null) params['bank'] = bank;
    if (sourceType != null) params['source_type'] = sourceType;
    if (type != null) params['type'] = type;
    if (search != null) params['search'] = search;

    final uri = Uri.parse('$baseUrl/api/v2/export/transactions')
        .replace(queryParameters: params);
    return uri.toString();
  }

  /// Clear all data from the database.
  static Future<Map<String, dynamic>> clearAllData() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/v2/data/clear-all'),
    );
    if (response.statusCode != 200) {
      final detail = _extractErrorDetail(response.body);
      throw Exception('Failed to clear data: $detail');
    }
    return jsonDecode(response.body);
  }
}
