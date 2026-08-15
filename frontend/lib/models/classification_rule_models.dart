class ClassificationRule {
  final int? id;
  final String name;
  final String? pattern;
  final bool patternIsRegex;
  final String? upiHandle;
  final double? amountMin;
  final double? amountMax;
  final String? bankFilter;
  final String? transactionTypeFilter;
  final int? targetCategoryId;
  final String? targetMerchant;
  final bool markAsTransfer;
  final bool markAsExcluded;
  final int priority;
  final bool isActive;
  final int appliedCount;
  final DateTime? createdAt;

  ClassificationRule({
    this.id,
    required this.name,
    this.pattern,
    this.patternIsRegex = false,
    this.upiHandle,
    this.amountMin,
    this.amountMax,
    this.bankFilter,
    this.transactionTypeFilter,
    this.targetCategoryId,
    this.targetMerchant,
    this.markAsTransfer = false,
    this.markAsExcluded = false,
    this.priority = 100,
    this.isActive = true,
    this.appliedCount = 0,
    this.createdAt,
  });

  factory ClassificationRule.fromJson(Map<String, dynamic> json) {
    return ClassificationRule(
      id: json['id'],
      name: json['name'] ?? '',
      pattern: json['pattern'],
      patternIsRegex: json['pattern_is_regex'] ?? false,
      upiHandle: json['upi_handle'],
      amountMin: json['amount_min'] != null ? double.parse(json['amount_min'].toString()) : null,
      amountMax: json['amount_max'] != null ? double.parse(json['amount_max'].toString()) : null,
      bankFilter: json['bank_filter'],
      transactionTypeFilter: json['transaction_type_filter'],
      targetCategoryId: json['target_category_id'],
      targetMerchant: json['target_merchant'],
      markAsTransfer: json['mark_as_transfer'] ?? false,
      markAsExcluded: json['mark_as_excluded'] ?? false,
      priority: json['priority'] ?? 100,
      isActive: json['is_active'] ?? true,
      appliedCount: json['applied_count'] ?? 0,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (pattern != null) 'pattern': pattern,
      'pattern_is_regex': patternIsRegex,
      if (upiHandle != null) 'upi_handle': upiHandle,
      if (amountMin != null) 'amount_min': amountMin,
      if (amountMax != null) 'amount_max': amountMax,
      if (bankFilter != null) 'bank_filter': bankFilter,
      if (transactionTypeFilter != null) 'transaction_type_filter': transactionTypeFilter,
      if (targetCategoryId != null) 'target_category_id': targetCategoryId,
      if (targetMerchant != null) 'target_merchant': targetMerchant,
      'mark_as_transfer': markAsTransfer,
      'mark_as_excluded': markAsExcluded,
      'priority': priority,
      'is_active': isActive,
    };
  }
}

class ClassificationRuleDryRunResult {
  final int matchedCount;

  ClassificationRuleDryRunResult({
    required this.matchedCount,
  });

  factory ClassificationRuleDryRunResult.fromJson(Map<String, dynamic> json) {
    return ClassificationRuleDryRunResult(
      matchedCount: json['matched_count'] ?? 0,
    );
  }
}
