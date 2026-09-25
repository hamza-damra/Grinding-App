import '../../../../core/formatting/digits.dart';

/// The 12-digit roll / pallet number (contract §4.2: "exactly 12 digits").
///
/// Normalization: trim, convert Arabic-Indic digits to ASCII, keep leading
/// zeros. Anything that is not then exactly 12 ASCII digits is invalid and is
/// rejected BEFORE any network call.
class GrindingIdentifier {
  GrindingIdentifier._();

  static final RegExp _twelveDigits = RegExp(r'^[0-9]{12}$');

  /// The canonical identifier, or `null` when [raw] is not exactly 12 digits.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final candidate = toAsciiDigits(raw.trim());
    return _twelveDigits.hasMatch(candidate) ? candidate : null;
  }

  static bool isValid(String? raw) => normalize(raw) != null;
}
