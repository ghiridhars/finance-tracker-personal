/// Credit Card models.
import 'enums.dart';

class CreditCardTransaction {
  final int? id;
  final String? date;
  final String? description;
  final double? amount;
  final TransactionType? type;
  final String? referenceNumber;

  CreditCardTransaction({
    this.id,
    this.date,
    this.description,
    this.amount,
    this.type,
    this.referenceNumber,
  });

  factory CreditCardTransaction.fromJson(Map<String, dynamic> json) {
    return CreditCardTransaction(
      id: json['id'],
      date: json['date'],
      description: json['description'],
      amount: _toDouble(json['amount']),
      type: json['type'] != null
          ? TransactionType.fromString(json['type'])
          : null,
      referenceNumber: json['reference_number'],
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  @override
  String toString() => '$date | $description | \$${amount?.toStringAsFixed(2) ?? "0.00"} (${type?.value ?? "?"})';  
}

class CreditCardStatement {
  final int? id;
  final String? statementDate;
  final String? dueDate;
  final String? cardNumber;
  final String? cardHolderName;
  final double? creditLimit;
  final double? availableCredit;
  final double? totalDues;
  final double? minimumAmountDue;
  final List<CreditCardTransaction> transactions;

  CreditCardStatement({
    this.id,
    this.statementDate,
    this.dueDate,
    this.cardNumber,
    this.cardHolderName,
    this.creditLimit,
    this.availableCredit,
    this.totalDues,
    this.minimumAmountDue,
    this.transactions = const [],
  });

  factory CreditCardStatement.fromJson(Map<String, dynamic> json) {
    return CreditCardStatement(
      id: json['id'],
      statementDate: json['statement_date'],
      dueDate: json['due_date'],
      cardNumber: json['card_number'],
      cardHolderName: json['card_holder_name'],
      creditLimit: CreditCardTransaction._toDouble(json['credit_limit']),
      availableCredit:
          CreditCardTransaction._toDouble(json['available_credit']),
      totalDues: CreditCardTransaction._toDouble(json['total_dues']),
      minimumAmountDue:
          CreditCardTransaction._toDouble(json['minimum_amount_due']),
      transactions: (json['transactions'] as List<dynamic>?)
              ?.map((t) => CreditCardTransaction.fromJson(t))
              .toList() ??
          [],
    );
  }

  @override
  String toString() =>
      'Card: ${cardNumber ?? "?"} | Date: $statementDate | ${transactions.length} transactions';
}
