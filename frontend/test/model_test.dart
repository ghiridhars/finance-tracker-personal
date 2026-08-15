/// Unit tests for data models: SavingsTransaction, CreditCardTransaction,
/// SavingsStatement, CreditCardStatement, and TransactionType.
library;
import 'package:flutter_test/flutter_test.dart';
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
}
