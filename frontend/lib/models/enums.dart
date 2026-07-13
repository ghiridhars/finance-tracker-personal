/// Transaction type enum matching the Python backend.
/// Replaces: TransactionType in React's Transaction interface
enum TransactionType {
  credit('CREDIT'),
  debit('DEBIT');

  final String value;
  const TransactionType(this.value);

  static TransactionType fromString(String s) {
    final match = TransactionType.values.where(
      (e) => e.value == s.toUpperCase(),
    );
    if (match.isEmpty) {
      return TransactionType.credit;
    }
    return match.first;
  }
}
