/// Unified transaction model — single representation for all transaction types.
library;
import 'category_models.dart';
import 'converters.dart';
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
  final int? bankAccountId;
  final String? accountIdentifier;
  final int? categoryId;
  final Category? category;
  final String? merchantName;
  final String? notes;
  final String? referenceNumber;
  final bool isTransfer;
  final String? transferGroupId;
  final String? transferType;
  final int? fromAccountId;
  final int? toAccountId;
  final String? fromAccountName;
  final String? toAccountName;
  final String? reviewStatus;
  final String? reviewReason;

  final String? classificationSource;
  final int? suggestedCategoryId;
  final String? suggestedCategoryName;
  final double? classificationConfidence;
  final bool isExcluded;
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
    this.bankAccountId,
    this.accountIdentifier,
    this.categoryId,
    this.category,
    this.merchantName,
    this.notes,
    this.referenceNumber,
    this.isTransfer = false,
    this.transferGroupId,
    this.transferType,
    this.fromAccountId,
    this.toAccountId,
    this.fromAccountName,
    this.toAccountName,
    this.reviewStatus,
    this.reviewReason,
    this.classificationSource,
    this.suggestedCategoryId,
    this.suggestedCategoryName,
    this.classificationConfidence,
    this.isExcluded = false,
    this.createdAt,
  });

  factory UnifiedTransaction.fromJson(Map<String, dynamic> json) {
    return UnifiedTransaction(
      id: json['id'],
      date: json['date'],
      description: json['description'],
      amount: toDouble(json['amount']),
      type: json['type'] != null
          ? TransactionType.fromString(json['type'])
          : null,
      sourceType: json['source_type'],
      sourceTransactionId: json['source_transaction_id'],
      bank: json['bank'],
      bankAccountId: json['bank_account_id'],
      accountIdentifier: json['account_identifier'],
      categoryId: json['category_id'],
      category: json['category'] != null
          ? Category.fromJson(json['category'])
          : null,
      merchantName: json['merchant_name'],
      notes: json['notes'],
      referenceNumber: json['reference_number'],
      isTransfer: json['is_transfer'] ?? false,
      transferGroupId: json['transfer_group_id'],
      transferType: json['transfer_type'],
      fromAccountId: json['from_account_id'],
      toAccountId: json['to_account_id'],
      fromAccountName: json['from_account_name'],
      toAccountName: json['to_account_name'],
      reviewStatus: json['review_status'],
      reviewReason: json['review_reason'],
      classificationSource: json['classification_source'],
      suggestedCategoryId: json['suggested_category_id'],
      suggestedCategoryName: json['suggested_category'] != null 
          ? json['suggested_category']['name'] 
          : null,
      classificationConfidence: toDouble(json['classification_confidence']),
      isExcluded: json['is_excluded'] ?? false,
      createdAt: json['created_at'],
    );
  }

  bool get needsReview => reviewStatus == 'NEEDS_REVIEW';

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
