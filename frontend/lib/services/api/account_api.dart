/// Account management API calls (CRUD, merge, delete, summary).
library;
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

  static Future<Map<String, dynamic>> createAccount({
    required String bankName,
    required String accountType,
    required String name,
    String? accountNumber,
    String? holderName,
    String? ifscCode,
    String? accountSubtype,
    String? notes,
    double? loanPrincipal,
    double? loanInterestRate,
    double? loanEmiAmount,
    String? loanStartDate,
    String? loanEndDate,
    double? creditLimit,
    int? billingCycleDay,
    double? investedAmount,
    double? currentValue,
  }) async {
    final body = {
      'bank_name': bankName,
      'account_type': accountType,
      'name': name,
      if (accountNumber != null) 'account_number': accountNumber,
      if (holderName != null) 'holder_name': holderName,
      if (ifscCode != null) 'ifsc_code': ifscCode,
      if (accountSubtype != null) 'account_subtype': accountSubtype,
      if (notes != null) 'notes': notes,
      if (loanPrincipal != null) 'loan_principal': loanPrincipal,
      if (loanInterestRate != null) 'loan_interest_rate': loanInterestRate,
      if (loanEmiAmount != null) 'loan_emi_amount': loanEmiAmount,
      if (loanStartDate != null) 'loan_start_date': loanStartDate,
      if (loanEndDate != null) 'loan_end_date': loanEndDate,
      if (creditLimit != null) 'credit_limit': creditLimit,
      if (billingCycleDay != null) 'billing_cycle_day': billingCycleDay,
      if (investedAmount != null) 'invested_amount': investedAmount,
      if (currentValue != null) 'current_value': currentValue,
    };
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/accounts'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to create account: ${ApiClient.extractErrorDetail(response.body)}');
    }
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> updateAccount(int accountId, Map<String, dynamic> updates) async {
    final response = await http.put(
      Uri.parse('${ApiClient.baseUrl}/api/v2/accounts/$accountId'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode(updates),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update account: ${ApiClient.extractErrorDetail(response.body)}');
    }
    return jsonDecode(response.body);
  }

  static Future<void> mergeAccounts(int sourceId, int targetId) async {
    final body = {
      'source_account_id': sourceId,
      'target_account_id': targetId,
    };
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/accounts/merge'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to merge accounts: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }

  static Future<void> deleteAccount(int accountId) async {
    final response = await http.delete(
      Uri.parse('${ApiClient.baseUrl}/api/v2/accounts/$accountId'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete account: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }

  static Future<Map<String, dynamic>> getAccountSummary(int accountId) async {
    final response = await http.get(
      Uri.parse('${ApiClient.baseUrl}/api/v2/accounts/$accountId/summary'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to get account summary: ${ApiClient.extractErrorDetail(response.body)}');
    }
    return jsonDecode(response.body);
  }
}
