/// Unified transaction model — single representation for all transaction types.
import 'category_models.dart';
import 'enums.dart';

class UnifiedTransaction {
  final int? id;
  final String? date;
  final String? description;
  final double? amount;
  final TransactionType? type;
  final String? sourceType;
  final int? sourceTransactionId;
  final String? bank;
  final String? accountIdentifier;
  final int? categoryId;
  final Category? category;
  final String? merchantName;
  final String? notes;
  final String? referenceNumber;
  final List<Tag> tags;
  final String? createdAt;

  UnifiedTransaction({
    this.id,
    this.date,
    this.description,
    this.amount,
    this.type,
    this.sourceType,
    this.sourceTransactionId,
    this.bank,
    this.accountIdentifier,
    this.categoryId,
    this.category,
    this.merchantName,
    this.notes,
    this.referenceNumber,
    this.tags = const [],
    this.createdAt,
  });

  factory UnifiedTransaction.fromJson(Map<String, dynamic> json) {
    return UnifiedTransaction(
      id: json['id'],
      date: json['date'],
      description: json['description'],
      amount: _toDouble(json['amount']),
      type: json['type'] != null
          ? TransactionType.fromString(json['type'])
          : null,
      sourceType: json['source_type'],
      sourceTransactionId: json['source_transaction_id'],
      bank: json['bank'],
      accountIdentifier: json['account_identifier'],
      categoryId: json['category_id'],
      category: json['category'] != null
          ? Category.fromJson(json['category'])
          : null,
      merchantName: json['merchant_name'],
      notes: json['notes'],
      referenceNumber: json['reference_number'],
      tags: (json['tags'] as List<dynamic>?)
              ?.map((t) => Tag.fromJson(t))
              .toList() ??
          [],
      createdAt: json['created_at'],
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Display-friendly source label
  String get sourceLabel {
    if (sourceType == 'CREDIT_CARD') return 'Credit Card';
    if (sourceType == 'SAVINGS') return 'Savings';
    return sourceType ?? 'Unknown';
  }

  @override
  String toString() =>
      '$date | $description | ₹${amount?.toStringAsFixed(2) ?? "0.00"} (${type?.value ?? "?"})';
}
