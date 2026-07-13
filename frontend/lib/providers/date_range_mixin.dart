/// Shared date-range utilities for transaction notifiers.
/// Eliminates duplicated applyPreset / formatDate logic across providers.
library;
import 'transactions_provider.dart' show DateRangePreset;

mixin DateRangeMixin {
  /// Format a DateTime as 'YYYY-MM-DD' for API calls.
  String formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  /// Resolve a DateRangePreset to concrete from/to dates.
  /// Returns (from, to) — either or both may be null for "all time".
  ({DateTime? from, DateTime? to}) resolveDateRange(DateRangePreset preset) {
    final now = DateTime.now();
    return switch (preset) {
      DateRangePreset.last7Days => (
          from: now.subtract(const Duration(days: 7)),
          to: now,
        ),
      DateRangePreset.last30Days => (
          from: now.subtract(const Duration(days: 30)),
          to: now,
        ),
      DateRangePreset.last3Months => (
          from: DateTime(now.year, now.month - 3, now.day),
          to: now,
        ),
      DateRangePreset.thisYear => (
          from: DateTime(now.year, 1, 1),
          to: now,
        ),
      DateRangePreset.all => (from: null, to: null),
      DateRangePreset.custom => (from: null, to: null), // no-op, set via setDateRange
    };
  }
}
