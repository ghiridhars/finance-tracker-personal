/// Account & Statement management models for Phase 4.
import 'converters.dart';

class Account {
  final int? id;
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
    this.id,
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
      id: json['id'],
      type: json['type'] ?? '',
      identifier: json['identifier'] ?? '',
      holderName: json['holder_name'],
      bank: json['bank'],
      statementCount: json['statement_count'] ?? 0,
      transactionCount: json['transaction_count'] ?? 0,
      lastStatementDate: json['last_statement_date'],
      balance: toDouble(json['balance']),
      creditLimit: toDouble(json['credit_limit']),
      availableCredit: toDouble(json['available_credit']),
    );
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
      openingBalance: toDouble(json['opening_balance']),
      closingBalance: toDouble(json['closing_balance']),
      transactionCount: (json['transactions'] as List?)?.length ?? 0,
    );
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
      totalDues: toDouble(json['total_dues']),
      creditLimit: toDouble(json['credit_limit']),
      minimumAmountDue: toDouble(json['minimum_amount_due']),
      transactionCount: (json['transactions'] as List?)?.length ?? 0,
    );
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
