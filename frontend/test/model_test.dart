/// Unit tests for data models: SavingsTransaction, CreditCardTransaction,
/// SavingsStatement, CreditCardStatement, and TransactionType.
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker_frontend/models/savings_models.dart';
import 'package:finance_tracker_frontend/models/credit_card_models.dart';
import 'package:finance_tracker_frontend/models/enums.dart';

void main() {
  group('TransactionType', () {
    test('fromString parses CREDIT', () {
      expect(TransactionType.fromString('CREDIT'), TransactionType.credit);
    });

    test('fromString parses DEBIT', () {
      expect(TransactionType.fromString('DEBIT'), TransactionType.debit);
    });

    test('fromString is case-insensitive', () {
      expect(TransactionType.fromString('credit'), TransactionType.credit);
      expect(TransactionType.fromString('Debit'), TransactionType.debit);
    });

    test('fromString defaults to credit for unknown values', () {
      expect(TransactionType.fromString('UNKNOWN'), TransactionType.credit);
      expect(TransactionType.fromString(''), TransactionType.credit);
    });

    test('value returns correct string', () {
      expect(TransactionType.credit.value, 'CREDIT');
      expect(TransactionType.debit.value, 'DEBIT');
    });
  });

  group('SavingsTransaction', () {
    test('fromJson parses complete JSON', () {
      final json = {
        'id': 1,
        'date': '2025-12-01',
        'description': 'UPI Payment',
        'reference_number': 'REF123',
        'withdrawal_amount': 500.0,
        'deposit_amount': null,
        'closing_balance': 10000.0,
        'type': 'DEBIT',
      };

      final txn = SavingsTransaction.fromJson(json);
      expect(txn.id, 1);
      expect(txn.date, '2025-12-01');
      expect(txn.description, 'UPI Payment');
      expect(txn.referenceNumber, 'REF123');
      expect(txn.withdrawalAmount, 500.0);
      expect(txn.depositAmount, isNull);
      expect(txn.closingBalance, 10000.0);
      expect(txn.type, TransactionType.debit);
    });

    test('fromJson handles null fields', () {
      final txn = SavingsTransaction.fromJson({});
      expect(txn.id, isNull);
      expect(txn.date, isNull);
      expect(txn.description, isNull);
      expect(txn.withdrawalAmount, isNull);
      expect(txn.depositAmount, isNull);
      expect(txn.closingBalance, isNull);
      expect(txn.type, isNull);
    });

    test('effectiveAmount uses withdrawal when present', () {
      final txn = SavingsTransaction.fromJson({
        'withdrawal_amount': 200.0,
        'deposit_amount': null,
      });
      expect(txn.effectiveAmount, 200.0);
    });

    test('effectiveAmount uses deposit when withdrawal is null', () {
      final txn = SavingsTransaction.fromJson({
        'withdrawal_amount': null,
        'deposit_amount': 1500.0,
      });
      expect(txn.effectiveAmount, 1500.0);
    });

    test('effectiveAmount returns 0 when both null', () {
      final txn = SavingsTransaction.fromJson({});
      expect(txn.effectiveAmount, 0.0);
    });

    test('_toDouble handles int values', () {
      final txn = SavingsTransaction.fromJson({
        'closing_balance': 5000,
      });
      expect(txn.closingBalance, 5000.0);
    });

    test('_toDouble handles string values', () {
      final txn = SavingsTransaction.fromJson({
        'closing_balance': '7500.50',
      });
      expect(txn.closingBalance, 7500.50);
    });

    test('_toDouble handles invalid string', () {
      final txn = SavingsTransaction.fromJson({
        'closing_balance': 'not-a-number',
      });
      expect(txn.closingBalance, isNull);
    });

    test('toString produces readable output', () {
      final txn = SavingsTransaction.fromJson({
        'date': '2025-12-01',
        'description': 'Test',
        'withdrawal_amount': 100.0,
        'type': 'DEBIT',
      });
      expect(txn.toString(), contains('2025-12-01'));
      expect(txn.toString(), contains('Test'));
      expect(txn.toString(), contains('DEBIT'));
    });
  });

  group('SavingsStatement', () {
    test('fromJson parses complete JSON with transactions', () {
      final json = {
        'id': 1,
        'account_number': '1234567890',
        'account_holder_name': 'John',
        'ifsc_code': 'HDFC0001234',
        'branch_name': 'Main Branch',
        'from_date': '2025-11-01',
        'to_date': '2025-11-30',
        'opening_balance': 5000.0,
        'closing_balance': 8000.0,
        'transactions': [
          {
            'id': 1,
            'date': '2025-11-15',
            'description': 'Salary',
            'deposit_amount': 50000.0,
            'type': 'CREDIT',
          },
        ],
      };

      final stmt = SavingsStatement.fromJson(json);
      expect(stmt.accountNumber, '1234567890');
      expect(stmt.accountHolderName, 'John');
      expect(stmt.openingBalance, 5000.0);
      expect(stmt.closingBalance, 8000.0);
      expect(stmt.transactions.length, 1);
      expect(stmt.transactions.first.description, 'Salary');
    });

    test('fromJson handles null transactions list', () {
      final stmt = SavingsStatement.fromJson({'transactions': null});
      expect(stmt.transactions, isEmpty);
    });

    test('fromJson handles missing transactions key', () {
      final stmt = SavingsStatement.fromJson({});
      expect(stmt.transactions, isEmpty);
    });
  });

  group('CreditCardTransaction', () {
    test('fromJson parses complete JSON', () {
      final json = {
        'id': 10,
        'date': '2025-12-05',
        'description': 'Amazon Purchase',
        'amount': 1469.0,
        'type': 'DEBIT',
        'reference_number': 'CC-REF-001',
      };

      final txn = CreditCardTransaction.fromJson(json);
      expect(txn.id, 10);
      expect(txn.date, '2025-12-05');
      expect(txn.description, 'Amazon Purchase');
      expect(txn.amount, 1469.0);
      expect(txn.type, TransactionType.debit);
      expect(txn.referenceNumber, 'CC-REF-001');
    });

    test('fromJson handles null fields', () {
      final txn = CreditCardTransaction.fromJson({});
      expect(txn.id, isNull);
      expect(txn.amount, isNull);
      expect(txn.type, isNull);
    });

    test('_toDouble handles int, double, string, null', () {
      expect(
        CreditCardTransaction.fromJson({'amount': 100}).amount,
        100.0,
      );
      expect(
        CreditCardTransaction.fromJson({'amount': 99.99}).amount,
        99.99,
      );
      expect(
        CreditCardTransaction.fromJson({'amount': '250.75'}).amount,
        250.75,
      );
      expect(
        CreditCardTransaction.fromJson({'amount': null}).amount,
        isNull,
      );
      expect(
        CreditCardTransaction.fromJson({'amount': 'invalid'}).amount,
        isNull,
      );
    });
  });

  group('CreditCardStatement', () {
    test('fromJson parses complete JSON', () {
      final json = {
        'id': 1,
        'statement_date': '2025-12-01',
        'due_date': '2025-12-20',
        'card_number': '**** 1234',
        'card_holder_name': 'Jane',
        'credit_limit': 200000.0,
        'available_credit': 150000.0,
        'total_dues': 508.0,
        'minimum_amount_due': 7.0,
        'transactions': [
          {
            'id': 1,
            'date': '2025-11-10',
            'description': 'Swiggy Order',
            'amount': 282.0,
            'type': 'DEBIT',
          },
        ],
      };

      final stmt = CreditCardStatement.fromJson(json);
      expect(stmt.cardNumber, '**** 1234');
      expect(stmt.creditLimit, 200000.0);
      expect(stmt.totalDues, 508.0);
      expect(stmt.minimumAmountDue, 7.0);
      expect(stmt.transactions.length, 1);
    });

    test('fromJson handles empty transactions', () {
      final stmt = CreditCardStatement.fromJson({});
      expect(stmt.transactions, isEmpty);
    });
  });
}
