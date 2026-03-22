/// UPI ID API module — manages UPI handle ↔ account/category mappings.
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/upi_models.dart';
import 'api_client.dart';

class UpiApi {
  /// List all UPI IDs, optionally filtered.
  static Future<List<UpiId>> getUpiIds({
    bool? isOwn,
    String? accountIdentifier,
  }) async {
    final params = <String, String>{};
    if (isOwn != null) params['is_own'] = isOwn.toString();
    if (accountIdentifier != null) {
      params['account_identifier'] = accountIdentifier;
    }
    final uri = Uri.parse('${ApiClient.baseUrl}/api/v2/upi-ids')
        .replace(queryParameters: params.isNotEmpty ? params : null);

    final response = await http.get(uri, headers: ApiClient.headers);
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to fetch UPI IDs: ${ApiClient.extractErrorDetail(response.body)}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((d) => UpiId.fromJson(d)).toList();
  }

  /// Create a new UPI ID mapping.
  static Future<UpiId> createUpiId({
    required String upiHandle,
    String? label,
    String? accountType,
    String? accountIdentifier,
    int? categoryId,
    bool isOwn = false,
  }) async {
    final body = <String, dynamic>{
      'upi_handle': upiHandle,
      'is_own': isOwn,
    };
    if (label != null) body['label'] = label;
    if (accountType != null) body['account_type'] = accountType;
    if (accountIdentifier != null) {
      body['account_identifier'] = accountIdentifier;
    }
    if (categoryId != null) body['category_id'] = categoryId;

    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/upi-ids'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode(body),
    );
    if (response.statusCode != 201) {
      throw Exception(
          'Failed to create UPI ID: ${ApiClient.extractErrorDetail(response.body)}');
    }
    return UpiId.fromJson(jsonDecode(response.body));
  }

  /// Update an existing UPI ID mapping.
  static Future<UpiId> updateUpiId(
    int upiId, {
    String? label,
    String? accountType,
    String? accountIdentifier,
    int? categoryId,
    bool? isOwn,
  }) async {
    final body = <String, dynamic>{};
    if (label != null) body['label'] = label;
    if (accountType != null) body['account_type'] = accountType;
    if (accountIdentifier != null) {
      body['account_identifier'] = accountIdentifier;
    }
    if (categoryId != null) body['category_id'] = categoryId;
    if (isOwn != null) body['is_own'] = isOwn;

    final response = await http.put(
      Uri.parse('${ApiClient.baseUrl}/api/v2/upi-ids/$upiId'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to update UPI ID: ${ApiClient.extractErrorDetail(response.body)}');
    }
    return UpiId.fromJson(jsonDecode(response.body));
  }

  /// Delete a UPI ID mapping.
  static Future<void> deleteUpiId(int upiId) async {
    final response = await http.delete(
      Uri.parse('${ApiClient.baseUrl}/api/v2/upi-ids/$upiId'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to delete UPI ID: ${ApiClient.extractErrorDetail(response.body)}');
    }
  }

  /// Re-scan all transactions against current UPI-based rules.
  static Future<UpiRescanResult> rescanTransactions() async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/upi-ids/rescan'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to rescan: ${ApiClient.extractErrorDetail(response.body)}');
    }
    return UpiRescanResult.fromJson(jsonDecode(response.body));
  }
}
