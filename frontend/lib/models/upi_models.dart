/// UPI ID model for managing UPI handle ↔ account/category mappings.
class UpiId {
  final int? id;
  final String upiHandle;
  final String? label;
  final String? accountType;
  final String? accountIdentifier;
  final int? categoryId;
  final bool isOwn;
  final String? createdAt;

  UpiId({
    this.id,
    required this.upiHandle,
    this.label,
    this.accountType,
    this.accountIdentifier,
    this.categoryId,
    this.isOwn = false,
    this.createdAt,
  });

  factory UpiId.fromJson(Map<String, dynamic> json) {
    return UpiId(
      id: json['id'],
      upiHandle: json['upi_handle'] ?? '',
      label: json['label'],
      accountType: json['account_type'],
      accountIdentifier: json['account_identifier'],
      categoryId: json['category_id'],
      isOwn: json['is_own'] ?? false,
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'upi_handle': upiHandle,
      if (label != null) 'label': label,
      if (accountType != null) 'account_type': accountType,
      if (accountIdentifier != null) 'account_identifier': accountIdentifier,
      if (categoryId != null) 'category_id': categoryId,
      'is_own': isOwn,
    };
  }

  UpiId copyWith({
    int? id,
    String? upiHandle,
    String? label,
    String? accountType,
    String? accountIdentifier,
    int? categoryId,
    bool? isOwn,
    String? createdAt,
  }) {
    return UpiId(
      id: id ?? this.id,
      upiHandle: upiHandle ?? this.upiHandle,
      label: label ?? this.label,
      accountType: accountType ?? this.accountType,
      accountIdentifier: accountIdentifier ?? this.accountIdentifier,
      categoryId: categoryId ?? this.categoryId,
      isOwn: isOwn ?? this.isOwn,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => '$upiHandle${label != null ? " ($label)" : ""}';
}

/// Result from the UPI rescan endpoint.
class UpiRescanResult {
  final int transactionsScanned;
  final int categoriesUpdated;
  final int transfersFlagged;

  UpiRescanResult({
    required this.transactionsScanned,
    required this.categoriesUpdated,
    required this.transfersFlagged,
  });

  factory UpiRescanResult.fromJson(Map<String, dynamic> json) {
    return UpiRescanResult(
      transactionsScanned: json['transactions_scanned'] ?? 0,
      categoriesUpdated: json['categories_updated'] ?? 0,
      transfersFlagged: json['transfers_flagged'] ?? 0,
    );
  }
}
