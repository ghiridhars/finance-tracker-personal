/// Account and statement management API calls.
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/account_models.dart';
import 'api_client.dart';

class AccountApi {
  /// List all linked accounts and credit cards.
  static Future<List<Account>> getAccounts() async {
    final response = await http.get(
      Uri.parse('${ApiClient.baseUrl}/api/v2/accounts'),
      headers: ApiClient.headers,
    );
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
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/accounts/statements/savings')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: ApiClient.headers);
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
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/accounts/statements/credit-card')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: ApiClient.headers);
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
      Uri.parse('${ApiClient.baseUrl}/api/v2/accounts/statements/savings/$statementId'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete savings statement: ${response.body}');
    }
  }

  /// Delete a credit card statement (and its cascaded transactions).
  static Future<void> deleteCreditCardStatement(int statementId) async {
    final response = await http.delete(
      Uri.parse('${ApiClient.baseUrl}/api/v2/accounts/statements/credit-card/$statementId'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete CC statement: ${response.body}');
    }
  }

  /// Rename an account (update holder name).
  static Future<void> renameAccount({
    required String accountType,
    required String identifier,
    required String name,
  }) async {
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/accounts/rename').replace(
      queryParameters: {
        'account_type': accountType,
        'identifier': identifier,
        'name': name,
      },
    );
    final response = await http.patch(uri, headers: ApiClient.headers);
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to rename account: $detail');
    }
  }
}
