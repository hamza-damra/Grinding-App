/// Display of backend decimals (contract §6: `expectedWeightKg` is a decimal
/// with 3 places — "parse as decimal/string, display as-is, never round").
///
/// JSON has no decimal type, so the value arrives as an `int`, a `double` or
/// (defensively) a `String`. All three are rendered as text without ever
/// rounding:
///
/// * `int` → `40` → `40.000`;
/// * `double` → the shortest round-trip representation (`40.0`, `12.345`),
///   then padded to 3 decimals as TEXT. A `DECIMAL(12,3)` value has at most 12
///   significant digits, well inside a double's exact round-trip range, so the
///   shortest representation IS the value the server sent;
/// * `String` → validated and padded as text, never passed through a double.
///
/// More than 3 decimals (outside the contract) is shown exactly as received —
/// truncating or rounding would misstate the weight.
class DecimalWeight {
  DecimalWeight._();

  static final RegExp _decimal = RegExp(r'^(-?)(\d+)(?:\.(\d+))?$');

  /// Canonical text (`40.000`) or `null` for null / unparseable input.
  static String? canonical(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return '$raw.000';
    if (raw is double) {
      if (!raw.isFinite) return null;
      final shortest = raw.toString();
      if (shortest.contains('e') || shortest.contains('E')) {
        // Only reachable far outside DECIMAL(12,3) (|x| ≥ 1e21 or < 1e-6).
        return raw.toStringAsFixed(3);
      }
      return _fromDecimalText(shortest);
    }
    if (raw is String) return _fromDecimalText(raw.trim());
    return null;
  }

  static String? _fromDecimalText(String text) {
    final match = _decimal.firstMatch(text);
    if (match == null) return null;
    final sign = match.group(1)!;
    final whole = match.group(2)!;
    final fraction = match.group(3) ?? '';
    if (fraction.length > 3) return '$sign$whole.$fraction';
    return '$sign$whole.${fraction.padRight(3, '0')}';
  }

  /// `40.000 كغ`, or `null` when [raw] is absent/invalid.
  static String? displayKg(Object? raw) {
    final text = canonical(raw);
    return text == null ? null : '$text كغ';
  }

  /// A quantity (pallet piece count) shown as received: `1200`, `12.5`.
  static String? displayQuantity(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return '$raw';
    if (raw is double) {
      if (!raw.isFinite) return null;
      if (raw == raw.truncateToDouble() && raw.abs() < 1e15) {
        return raw.toInt().toString();
      }
      return raw.toString();
    }
    if (raw is String) {
      final t = raw.trim();
      return _decimal.hasMatch(t) ? t : null;
    }
    return null;
  }
}
