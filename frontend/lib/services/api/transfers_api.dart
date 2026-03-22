/// Transfer API module — manages transfer detection, linking, and listing.
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/unified_transaction_models.dart';
import 'api_client.dart';

/// Response from the detect endpoint.
class TransferDetectResult {
  final int linkedCount;
  final List<TransferPair> details;

  TransferDetectResult({required this.linkedCount, this.details = const []});

  factory TransferDetectResult.fromJson(Map<String, dynamic> json) {
    return TransferDetectResult(
      linkedCount: json['linked_count'] ?? 0,
      details: (json['details'] as List<dynamic>?)
              ?.map((d) => TransferPair.fromJson(d))
              .toList() ??
          [],
    );
  }
}

/// A linked transfer pair.
class TransferPair {
  final String transferGroupId;
  final String? transferType;
  final List<UnifiedTransaction> transactions;

  TransferPair({
    required this.transferGroupId,
    this.transferType,
    this.transactions = const [],
  });

  factory TransferPair.fromJson(Map<String, dynamic> json) {
    return TransferPair(
      transferGroupId: json['transfer_group_id'] ?? '',
      transferType: json['transfer_type'],
      transactions: (json['transactions'] as List<dynamic>?)
              ?.map((t) => UnifiedTransaction.fromJson(t))
              .toList() ??
          [],
    );
  }
}

class TransfersApi {
  /// Run auto-detection on all unlinked transactions.
  static Future<TransferDetectResult> detectTransfers() async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/transfers/detect'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to detect transfers: ${response.body}');
    }
    return TransferDetectResult.fromJson(jsonDecode(response.body));
  }

  /// Manually link two transactions as a transfer pair.
  static Future<TransferPair> linkTransfer({
    required int transactionId1,
    required int transactionId2,
    String transferType = 'INTERNAL_TRANSFER',
  }) async {
    final response = await http.post(
      Uri.parse('${ApiClient.baseUrl}/api/v2/transfers/link'),
      headers: ApiClient.jsonHeaders,
      body: jsonEncode({
        'transaction_id_1': transactionId1,
        'transaction_id_2': transactionId2,
        'transfer_type': transferType,
      }),
    );
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to link transfer: $detail');
    }
    return TransferPair.fromJson(jsonDecode(response.body));
  }

  /// Unlink a transfer pair.
  static Future<void> unlinkTransfer(String transferGroupId) async {
    final response = await http.delete(
      Uri.parse('${ApiClient.baseUrl}/api/v2/transfers/$transferGroupId'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to unlink transfer: ${response.body}');
    }
  }

  /// List all linked transfer pairs.
  static Future<List<TransferPair>> listTransfers() async {
    final response = await http.get(
      Uri.parse('${ApiClient.baseUrl}/api/v2/transfers'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch transfers: ${response.body}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.map((d) => TransferPair.fromJson(d)).toList();
  }

  /// Update the transfer type for a linked pair.
  static Future<TransferPair> updateTransferType(
    String transferGroupId,
    String transferType,
  ) async {
    final response = await http.patch(
      Uri.parse(
          '${ApiClient.baseUrl}/api/v2/transfers/$transferGroupId?transfer_type=$transferType'),
      headers: ApiClient.headers,
    );
    if (response.statusCode != 200) {
      final detail = ApiClient.extractErrorDetail(response.body);
      throw Exception('Failed to update transfer type: $detail');
    }
    return TransferPair.fromJson(jsonDecode(response.body));
  }
}
