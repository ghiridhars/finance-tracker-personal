/// Analytics / Dashboard API calls.
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/analytics_models.dart';
import 'api_client.dart';

class AnalyticsApi {
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
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/analytics/summary')
        .replace(queryParameters: _dateParams(from: from, to: to));
    final response = await http.get(uri, headers: ApiClient.headers);
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
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/analytics/spending-by-category')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: ApiClient.headers);
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
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/analytics/spending-trends')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: ApiClient.headers);
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
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/analytics/income-vs-expense')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: ApiClient.headers);
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
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/analytics/month-over-month')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: ApiClient.headers);
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
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/analytics/top-merchants')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: ApiClient.headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch top merchants: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((m) => MerchantSpending.fromJson(m)).toList();
  }

  /// Get daily spending data for a specific month (for calendar heatmap).
  static Future<List<SpendingTrend>> getDailySpending({
    required int year,
    required int month,
  }) async {
    final from = '$year-${month.toString().padLeft(2, '0')}-01';
    final lastDay = DateTime(year, month + 1, 0).day;
    final to = '$year-${month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';
    return getSpendingTrends(from: from, to: to, granularity: 'daily');
  }
}
