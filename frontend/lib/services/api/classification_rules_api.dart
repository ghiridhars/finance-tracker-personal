import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import '../../models/classification_rule_models.dart';

class ClassificationRulesApi {
  static Future<List<ClassificationRule>> getRules() async {
    final response = await http.get(
      Uri.parse('${ApiClient.baseUrl}/api/v2/classification-rules'),
      headers: ApiClient.headers,
    ).timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((json) => ClassificationRule.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load classification rules: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }

  static Future<ClassificationRule> createRule(ClassificationRule rule) async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/classification-rules'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode(rule.toJson()),
    ).timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);

    if (response.statusCode == 201 || response.statusCode == 200) {
      return ClassificationRule.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create classification rule: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }

  static Future<ClassificationRule> updateRule(int id, ClassificationRule rule) async {
    final response = await http.patch(
      Uri.parse('${ApiClient.baseUrl}/api/v2/classification-rules/$id'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode(rule.toJson()),
    ).timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);

    if (response.statusCode == 200) {
      return ClassificationRule.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to update classification rule: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }

  static Future<void> deleteRule(int id) async {
    final response = await http.delete(
      Uri.parse('${ApiClient.baseUrl}/api/v2/classification-rules/$id'),
      headers: ApiClient.headers,
    ).timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to delete classification rule: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }

  static Future<ClassificationRuleDryRunResult> dryRunRule(int id) async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/classification-rules/$id/dry-run'),
      headers: ApiClient.headers,
    ).timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);

    if (response.statusCode == 200) {
      return ClassificationRuleDryRunResult.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to dry run classification rule: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }

  static Future<Map<String, dynamic>> applyRule(int id) async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/classification-rules/$id/apply'),
      headers: ApiClient.headers,
    ).timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to apply classification rule: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }
}
