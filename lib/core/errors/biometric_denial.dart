import '../api/json_read.dart';

/// A login refused by the biometric login gate
/// (`docs/FRONTEND_HANDOFF_GRINDING_APP_BIOMETRIC_LOGIN_GATE.md` §4.2): a
/// 403 whose `error.code` starts with `BIOMETRIC_`, parsed from
/// `error.details`.
///
/// [attemptToken] is a secret: it lives in memory for the fingerprint
/// dialog's lifetime only and is never logged, persisted, shown or put in a
/// URL. `toString` leaves it (and the message) out.
class BiometricDenial {
  const BiometricDenial({
    required this.code,
    this.message,
    this.validitySeconds,
    this.attemptAvailable = false,
    this.attemptToken,
    this.attemptExpiresAt,
    this.statusPath,
  });

  factory BiometricDenial.fromEnvelope({
    required String code,
    String? message,
    Map<String, dynamic>? details,
  }) {
    final expiresAt = JsonRead.nonEmptyString(details?['attemptExpiresAt']);
    return BiometricDenial(
      code: code,
      message: JsonRead.nonEmptyString(message),
      validitySeconds: JsonRead.integer(details?['validitySeconds']),
      attemptAvailable: JsonRead.flag(details?['attemptAvailable']),
      attemptToken: JsonRead.nonEmptyString(details?['attemptToken']),
      attemptExpiresAt: expiresAt == null
          ? null
          : DateTime.tryParse(expiresAt)?.toUtc(),
      statusPath: JsonRead.nonEmptyString(details?['statusPath']),
    );
  }

  /// `error.code` (`BIOMETRIC_VERIFICATION_REQUIRED`, …).
  final String code;

  /// `error.message` — Arabic by contract, displayed verbatim.
  final String? message;

  final int? validitySeconds;
  final bool attemptAvailable;
  final String? attemptToken;

  /// UTC instant. Display only (in `Asia/Hebron`); expiry is decided by the
  /// server's 410, never by the device clock.
  final DateTime? attemptExpiresAt;

  /// Relative path of the attempt-status endpoint, resolved against the
  /// login's base URL.
  final String? statusPath;

  /// Whether the dialog can wait for a scan by polling this attempt.
  bool get hasAttempt => attemptAvailable && attemptToken != null;

  @override
  bool operator ==(Object other) =>
      other is BiometricDenial &&
      other.code == code &&
      other.message == message &&
      other.validitySeconds == validitySeconds &&
      other.attemptAvailable == attemptAvailable &&
      other.attemptToken == attemptToken &&
      other.attemptExpiresAt == attemptExpiresAt &&
      other.statusPath == statusPath;

  @override
  int get hashCode => Object.hash(
    code,
    message,
    validitySeconds,
    attemptAvailable,
    attemptToken,
    attemptExpiresAt,
    statusPath,
  );

  @override
  String toString() =>
      'BiometricDenial(code: $code, attemptAvailable: $attemptAvailable)';
}
