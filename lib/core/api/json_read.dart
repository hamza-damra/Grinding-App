/// Lenient JSON field readers shared by the hand-written DTOs. Wrong types
/// read as `null` (or `false`) instead of throwing; required fields are
/// enforced by each DTO.
class JsonRead {
  JsonRead._();

  static Map<String, dynamic>? map(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  static String? string(Object? raw) => raw is String ? raw : null;

  static String? nonEmptyString(Object? raw) =>
      raw is String && raw.trim().isNotEmpty ? raw : null;

  /// Accepts `42` and `42.0` (some serializers emit integral doubles).
  static int? integer(Object? raw) {
    if (raw is int) return raw;
    if (raw is double && raw.isFinite && raw == raw.truncateToDouble()) {
      return raw.toInt();
    }
    return null;
  }

  /// Only an explicit JSON `true` is true — an action gate must never be
  /// opened by a missing or malformed field.
  static bool flag(Object? raw) => raw == true;
}
