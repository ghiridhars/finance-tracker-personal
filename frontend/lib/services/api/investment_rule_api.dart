import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import '../../models/investment_rule.dart';

class InvestmentRuleApi {
  static Future<List<InvestmentRule>> getInvestmentRules() async {
    final response = await http
        .get(Uri.parse('${ApiClient.baseUrl}/api/v2/investment-rules'), headers: ApiClient.headers)
        .timeout(ApiClient.timeout);
    
    ApiClient.checkAuth(response);

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((j) => InvestmentRule.fromJson(j)).toList();
    } else {
      throw Exception('Failed to load rules: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }

  static Future<InvestmentRule> createInvestmentRule(String platformName, String assetClass, String keywords) async {
    final response = await http
        .post(
          Uri.parse('${ApiClient.baseUrl}/api/v2/investment-rules'),
          headers: ApiClient.jsonHeaders,
          body: jsonEncode({
            'platform_name': platformName,
            'asset_class': assetClass,
            'keywords': keywords,
          }),
        )
        .timeout(ApiClient.timeout);
        
    ApiClient.checkAuth(response);

    if (response.statusCode == 201 || response.statusCode == 200) {
      return InvestmentRule.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create rule: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }

  static Future<InvestmentRule> updateInvestmentRule(int id, {String? platformName, String? assetClass, String? keywords}) async {
    final body = <String, dynamic>{};
    if (platformName != null) body['platform_name'] = platformName;
    if (assetClass != null) body['asset_class'] = assetClass;
    if (keywords != null) body['keywords'] = keywords;

    final response = await http
        .put(
          Uri.parse('${ApiClient.baseUrl}/api/v2/investment-rules/$id'),
          headers: ApiClient.jsonHeaders,
          body: jsonEncode(body),
        )
        .timeout(ApiClient.timeout);
        
    ApiClient.checkAuth(response);

    if (response.statusCode == 200) {
      return InvestmentRule.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to update rule: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }

  static Future<void> deleteInvestmentRule(int id) async {
    final response = await http
        .delete(
          Uri.parse('${ApiClient.baseUrl}/api/v2/investment-rules/$id'),
          headers: ApiClient.headers,
        )
        .timeout(ApiClient.timeout);
        
    ApiClient.checkAuth(response);

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete rule: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }
}
