/// Transaction-related API calls.
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/savings_models.dart';
import '../../models/credit_card_models.dart';
import '../../models/unified_transaction_models.dart';
import 'api_client.dart';

class TransactionApi {
  /// Get savings transactions (default: last 30 days).
  static Future<List<SavingsTransaction>> getSavingsTransactions({
    String? from,
    String? to,
  }) async {
    final params = <String, String>{};
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;

    final uri = Uri.parse('${ApiClient.baseUrl}/api/transactions/savings')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: ApiClient.headers).timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch transactions: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((t) => SavingsTransaction.fromJson(t)).toList();
  }

  /// Get credit card transactions.
  static Future<List<CreditCardTransaction>> getCreditCardTransactions({
    String? from,
    String? to,
  }) async {
    final params = <String, String>{};
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;

    final uri = Uri.parse('${ApiClient.baseUrl}/api/transactions/credit-card')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: ApiClient.headers).timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch transactions: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((t) => CreditCardTransaction.fromJson(t)).toList();
  }

  /// Get unified transactions with optional filters.
  static Future<List<UnifiedTransaction>> getUnifiedTransactions({
    String? from,
    String? to,
    int? categoryId,
    String? bank,
    int? bankAccountId,
    String? accountIdentifier,
    String? sourceType,
    bool? isTransfer,
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
    if (bankAccountId != null) params['bank_account_id'] = bankAccountId.toString();
    if (accountIdentifier != null) params['account_identifier'] = accountIdentifier;
    if (sourceType != null) params['source_type'] = sourceType;
    if (isTransfer != null) params['is_transfer'] = isTransfer.toString();
    if (type != null) params['type'] = type;
    if (search != null) params['search'] = search;
    if (minAmount != null) params['min_amount'] = minAmount.toString();
    if (maxAmount != null) params['max_amount'] = maxAmount.toString();
    params['limit'] = limit.toString();
    params['offset'] = offset.toString();

    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/transactions')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: ApiClient.headers).timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
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
      Uri.parse('${ApiClient.baseUrl}/api/v2/transactions/$transactionId'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode(body),
    ).timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to update transaction: $detail');
    }
    return UnifiedTransaction.fromJson(jsonDecode(response.body));
  }

  /// Trigger bulk re-categorization of all transactions.
  static Future<int> recategorizeAll() async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/transactions/recategorize'),
      headers: ApiClient.headers,
    ).timeout(const Duration(seconds: 120));
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to recategorize: ${response.body}');
    }
    final data = jsonDecode(response.body);
    return data['updated'] as int;
  }

  /// Delete a single unified transaction.
  static Future<void> deleteTransaction(int transactionId) async {
    final response = await http.delete(
      Uri.parse('${ApiClient.baseUrl}/api/v2/transactions/$transactionId'),
      headers: ApiClient.headers,
    ).timeout(ApiClient.timeout);
    ApiClient.checkAuth(response);
    if (response.statusCode != 200) {
      throw Exception('Failed to delete transaction: ${response.body}');
    }
  }
}
