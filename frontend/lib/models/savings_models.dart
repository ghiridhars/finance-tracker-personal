/// Savings Account Transaction model.
/// Replaces: Transaction interface in React's TransactionList.tsx
import 'converters.dart';
import 'enums.dart';

class SavingsTransaction {
  final int? id;
  final String? date;
  final String? description;
  final String? referenceNumber;
  final double? withdrawalAmount;
  final double? depositAmount;
  final double? closingBalance;
  final TransactionType? type;

  SavingsTransaction({
    this.id,
    this.date,
    this.description,
    this.referenceNumber,
    this.withdrawalAmount,
    this.depositAmount,
    this.closingBalance,
    this.type,
  });

  /// Computed amount: withdrawal or deposit, whichever is non-zero.
  double get effectiveAmount => withdrawalAmount ?? depositAmount ?? 0;

  factory SavingsTransaction.fromJson(Map<String, dynamic> json) {
    return SavingsTransaction(
      id: json['id'],
      date: json['date'],
      description: json['description'],
      referenceNumber: json['reference_number'],
      withdrawalAmount: toDouble(json['withdrawal_amount']),
      depositAmount: toDouble(json['deposit_amount']),
      closingBalance: toDouble(json['closing_balance']),
      type: json['type'] != null
          ? TransactionType.fromString(json['type'])
          : null,
    );
  }

  @override
  String toString() => '$date | $description | \$${effectiveAmount.toStringAsFixed(2)} (${type?.value ?? "?"})';
}

/// Savings Account Statement model.
class SavingsStatement {
  final int? id;
  final String? accountNumber;
  final String? accountHolderName;
  final String? ifscCode;
  final String? branchName;
  final String? fromDate;
  final String? toDate;
  final double? openingBalance;
  final double? closingBalance;
  final List<SavingsTransaction> transactions;

  SavingsStatement({
    this.id,
    this.accountNumber,
    this.accountHolderName,
    this.ifscCode,
    this.branchName,
    this.fromDate,
    this.toDate,
    this.openingBalance,
    this.closingBalance,
    this.transactions = const [],
  });

  factory SavingsStatement.fromJson(Map<String, dynamic> json) {
    return SavingsStatement(
      id: json['id'],
      accountNumber: json['account_number'],
      accountHolderName: json['account_holder_name'],
      ifscCode: json['ifsc_code'],
      branchName: json['branch_name'],
      fromDate: json['from_date'],
      toDate: json['to_date'],
      openingBalance: toDouble(json['opening_balance']),
      closingBalance: toDouble(json['closing_balance']),
      transactions: (json['transactions'] as List<dynamic>?)
              ?.map((t) => SavingsTransaction.fromJson(t))
              .toList() ??
          [],
    );
  }

  @override
  String toString() =>
      'Account: ${accountNumber ?? "?"} | $fromDate - $toDate | ${transactions.length} transactions';
}
