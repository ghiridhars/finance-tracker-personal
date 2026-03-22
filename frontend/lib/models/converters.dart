/// Safely converts a dynamic value to double (handles num, String, null).
double? toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
