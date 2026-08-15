/// Account management models.
library;
import 'converters.dart';

class Account {
  final int? id;
  final String type; // SAVINGS or CREDIT_CARD
  final String identifier; // account_number or card_number
  final String? holderName;
  final String? bank;
  final int statementCount;
  final int transactionCount;
  final double? balance;
  final double? creditLimit;
  final double? availableCredit;
  final String? accountSubtype;

  Account({
    this.id,
    required this.type,
    required this.identifier,
    this.holderName,
    this.bank,
    this.statementCount = 0,
    this.transactionCount = 0,
    this.balance,
    this.creditLimit,
    this.availableCredit,
    this.accountSubtype,
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
      balance: toDouble(json['balance']),
      creditLimit: toDouble(json['credit_limit']),
      availableCredit: toDouble(json['available_credit']),
      accountSubtype: json['account_subtype'],
    );
  }
}
