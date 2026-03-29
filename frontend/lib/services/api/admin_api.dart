/// Admin / Database Manager API calls.
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/admin_models.dart';
import 'api_client.dart';

class AdminApi {
  static String get _base => '${ApiClient.baseUrl}/api/v2/admin';

  /// List all allowed tables with row counts.
  static Future<List<TableInfo>> getTables() async {
    final response = await http.get(
      Uri.parse('$_base/tables'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch tables: ${ApiClient.extractErrorDetail(response.body)}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((t) => TableInfo.fromJson(t)).toList();
  }

  /// Get column metadata for a table.
  static Future<TableSchemaModel> getTableSchema(String tableName) async {
    final response = await http.get(
      Uri.parse('$_base/tables/$tableName/schema'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch schema: ${ApiClient.extractErrorDetail(response.body)}');
    }
    return TableSchemaModel.fromJson(jsonDecode(response.body));
  }

  /// Get paginated rows from a table.
  static Future<RowsResponse> getRows(
    String tableName, {
    int limit = 50,
    int offset = 0,
    String? sort,
    String order = 'asc',
    String? search,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      'order': order,
    };
    if (sort != null) params['sort'] = sort;
    if (search != null && search.isNotEmpty) params['search'] = search;

    final uri = Uri.parse('$_base/tables/$tableName/rows')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: ApiClient.headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch rows: ${ApiClient.extractErrorDetail(response.body)}');
    }
    return RowsResponse.fromJson(jsonDecode(response.body));
  }

  /// Create a new row.
  static Future<Map<String, dynamic>> createRow(
    String tableName,
    Map<String, dynamic> data,
  ) async {
    final response = await http.post(
      Uri.parse('$_base/tables/$tableName/rows'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode(data),
    );
    if (response.statusCode != 201) {
      throw Exception(ApiClient.extractErrorDetail(response.body));
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  /// Update an existing row.
  static Future<Map<String, dynamic>> updateRow(
    String tableName,
    int rowId,
    Map<String, dynamic> data,
  ) async {
    final response = await http.put(
      Uri.parse('$_base/tables/$tableName/rows/$rowId'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode(data),
    );
    if (response.statusCode != 200) {
      throw Exception(ApiClient.extractErrorDetail(response.body));
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  /// Delete a row.
  static Future<void> deleteRow(String tableName, int rowId) async {
    final response = await http.delete(
      Uri.parse('$_base/tables/$tableName/rows/$rowId'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception(ApiClient.extractErrorDetail(response.body));
    }
  }

  /// Get FK dropdown options for a column.
  static Future<List<FKOption>> getFKOptions(
    String tableName,
    String columnName,
  ) async {
    final response = await http.get(
      Uri.parse('$_base/tables/$tableName/fk-options/$columnName'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch FK options: ${ApiClient.extractErrorDetail(response.body)}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((o) => FKOption.fromJson(o)).toList();
  }
}
