/// Export, data management, categories, and Google Drive sync API calls.
library;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/category_models.dart';
import 'api_client.dart';

class ExportApi {
  // ── Categories ─────────────────────────────────────────────

  /// Get all categories.
  static Future<List<Category>> getCategories() async {
    final response = await http.get(
      Uri.parse('${ApiClient.baseUrl}/api/v2/categories'),
      headers: ApiClient.headers,
    );
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
      Uri.parse('${ApiClient.baseUrl}/api/v2/categories'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode({
        'name': name,
        'icon': icon,
        'color': color,
        'keywords': keywords,
      }),
    );
    if (response.statusCode != 201) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to create category: $detail');
    }
    return Category.fromJson(jsonDecode(response.body));
  }

  /// Add keywords to a category.
  static Future<Category> addCategoryKeywords(
      int categoryId, List<String> keywords) async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/categories/$categoryId/keywords'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode({'keywords': keywords}),
    );
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to add keywords: $detail');
    }
    return Category.fromJson(jsonDecode(response.body));
  }

  /// Delete a category.
  static Future<void> deleteCategory(int categoryId) async {
    final response = await http.delete(
      Uri.parse('${ApiClient.baseUrl}/api/v2/categories/$categoryId'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to delete category: $detail');
    }
  }

  // ── Health ─────────────────────────────────────────────────

  /// Health check — verifies backend is reachable.
  static Future<Map<String, dynamic>> healthCheck() async {
    final response = await http.get(
      Uri.parse('${ApiClient.baseUrl}/health'),
      headers: ApiClient.headers,
    );
    return jsonDecode(response.body);
  }

  // ── Export & Data Management ───────────────────────────────

  /// Get the URL for exporting transactions as CSV.
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

    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/export/transactions')
        .replace(queryParameters: params);
    return uri.toString();
  }

  /// Clear all data from the database.
  static Future<Map<String, dynamic>> clearAllData() async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/data/clear-all'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to clear data: $detail');
    }
    return jsonDecode(response.body);
  }

  // ── Google Drive Sync ─────────────────────────────────────

  /// Get Google Drive sync status.
  static Future<Map<String, dynamic>> getGDriveStatus() async {
    final response = await http.get(
      Uri.parse('${ApiClient.baseUrl}/api/v2/gdrive/status'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to get Drive status: ${response.body}');
    }
    return jsonDecode(response.body);
  }

  /// List files in the configured Google Drive folder.
  static Future<Map<String, dynamic>> getGDriveFiles() async {
    final response = await http.get(
      Uri.parse('${ApiClient.baseUrl}/api/v2/gdrive/files'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to list Drive files: $detail');
    }
    return jsonDecode(response.body);
  }

  /// Trigger a Google Drive sync.
  static Future<Map<String, dynamic>> syncFromGDrive({
    String? bank,
    String? statementType,
    List<String>? fileIds,
    bool force = false,
  }) async {
    final params = <String, String>{};
    if (bank != null) params['bank'] = bank;
    if (statementType != null) params['type'] = statementType;
    if (fileIds != null) params['file_ids'] = fileIds.join(',');
    if (force) params['force'] = 'true';

    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/gdrive/sync')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.post(uri, headers: ApiClient.headers);
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Drive sync failed: $detail');
    }
    return jsonDecode(response.body);
  }

  /// Reset sync state to allow re-processing.
  static Future<Map<String, dynamic>> resetGDriveSync({
    List<String>? fileIds,
  }) async {
    final params = <String, String>{};
    if (fileIds != null) params['file_ids'] = fileIds.join(',');

    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/gdrive/reset')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.post(uri, headers: ApiClient.headers);
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to reset sync: $detail');
    }
    return jsonDecode(response.body);
  }
}
