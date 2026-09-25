import '../../../../core/formatting/digits.dart';

/// PIN rule (contract §4.2: `pin` is exactly 4 digits). Validated before any
/// call; the PIN itself is never stored, logged or echoed.
class PinRule {
  PinRule._();

  static const int length = 4;
  static final RegExp _fourDigits = RegExp(r'^[0-9]{4}$');

  /// The canonical PIN, or `null` when [raw] is not exactly 4 digits.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final candidate = toAsciiDigits(raw.trim());
    return _fourDigits.hasMatch(candidate) ? candidate : null;
  }
}
