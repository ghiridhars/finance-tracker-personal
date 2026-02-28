/// Account & Statement management models for Phase 4.

class Account {
  final String type; // SAVINGS or CREDIT_CARD
  final String identifier; // account_number or card_number
  final String? holderName;
  final String? bank;
  final int statementCount;
  final int transactionCount;
  final String? lastStatementDate;
  final double? balance;
  final double? creditLimit;
  final double? availableCredit;

  Account({
    required this.type,
    required this.identifier,
    this.holderName,
    this.bank,
    this.statementCount = 0,
    this.transactionCount = 0,
    this.lastStatementDate,
    this.balance,
    this.creditLimit,
    this.availableCredit,
  });

  bool get isSavings => type == 'SAVINGS';
  bool get isCreditCard => type == 'CREDIT_CARD';

  String get maskedIdentifier {
    if (identifier.length <= 4) return identifier;
    return '****${identifier.substring(identifier.length - 4)}';
  }

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      type: json['type'] ?? '',
      identifier: json['identifier'] ?? '',
      holderName: json['holder_name'],
      bank: json['bank'],
      statementCount: json['statement_count'] ?? 0,
      transactionCount: json['transaction_count'] ?? 0,
      lastStatementDate: json['last_statement_date'],
      balance: _toDouble(json['balance']),
      creditLimit: _toDouble(json['credit_limit']),
      availableCredit: _toDouble(json['available_credit']),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

/// Lightweight summary of a savings statement (without embedded transactions).
class SavingsStatementSummary {
  final int id;
  final String? accountNumber;
  final String? accountHolderName;
  final String? fromDate;
  final String? toDate;
  final double? openingBalance;
  final double? closingBalance;
  final int transactionCount;

  SavingsStatementSummary({
    required this.id,
    this.accountNumber,
    this.accountHolderName,
    this.fromDate,
    this.toDate,
    this.openingBalance,
    this.closingBalance,
    this.transactionCount = 0,
  });

  factory SavingsStatementSummary.fromJson(Map<String, dynamic> json) {
    return SavingsStatementSummary(
      id: json['id'],
      accountNumber: json['account_number'],
      accountHolderName: json['account_holder_name'],
      fromDate: json['from_date'],
      toDate: json['to_date'],
      openingBalance: _toDouble(json['opening_balance']),
      closingBalance: _toDouble(json['closing_balance']),
      transactionCount: (json['transactions'] as List?)?.length ?? 0,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

/// Lightweight summary of a credit card statement.
class CreditCardStatementSummary {
  final int id;
  final String? cardNumber;
  final String? cardHolderName;
  final String? statementDate;
  final String? dueDate;
  final double? totalDues;
  final double? creditLimit;
  final double? minimumAmountDue;
  final int transactionCount;

  CreditCardStatementSummary({
    required this.id,
    this.cardNumber,
    this.cardHolderName,
    this.statementDate,
    this.dueDate,
    this.totalDues,
    this.creditLimit,
    this.minimumAmountDue,
    this.transactionCount = 0,
  });

  factory CreditCardStatementSummary.fromJson(Map<String, dynamic> json) {
    return CreditCardStatementSummary(
      id: json['id'],
      cardNumber: json['card_number'],
      cardHolderName: json['card_holder_name'],
      statementDate: json['statement_date'],
      dueDate: json['due_date'],
      totalDues: _toDouble(json['total_dues']),
      creditLimit: _toDouble(json['credit_limit']),
      minimumAmountDue: _toDouble(json['minimum_amount_due']),
      transactionCount: (json['transactions'] as List?)?.length ?? 0,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

/// Paginated list response wrapper.
class PaginatedResponse<T> {
  final List<T> items;
  final int total;
  final int limit;
  final int offset;

  PaginatedResponse({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  bool get hasMore => offset + items.length < total;
  int get currentPage => (offset ~/ limit) + 1;
  int get totalPages => (total / limit).ceil();
}
