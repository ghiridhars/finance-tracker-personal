/// Transaction type enum matching the Python backend.
/// Replaces: TransactionType in React's Transaction interface
enum TransactionType {
  credit('CREDIT'),
  debit('DEBIT');

  final String value;
  const TransactionType(this.value);

  static TransactionType fromString(String s) {
    return TransactionType.values.firstWhere(
      (e) => e.value == s.toUpperCase(),
      orElse: () => TransactionType.credit,
    );
  }
}
