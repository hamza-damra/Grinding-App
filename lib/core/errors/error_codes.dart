/// Backend error codes of the Grinding App contract
/// (`docs/GRINDING_APP_BACKEND_CONTRACT.md` §4.2, §4.3, §10).
class ErrorCodes {
  ErrorCodes._();

  // Login (`POST /auth/pin`).
  static const String operatorPinInvalid = 'OPERATOR_PIN_INVALID';
  static const String operatorBackingUserInvalid =
      'OPERATOR_BACKING_USER_INVALID';
  static const String validationError = 'VALIDATION_ERROR';

  // Session (§4.3) — any endpoint with a session.
  static const String sessionRequired = 'GRINDING_WORKER_SESSION_REQUIRED';
  static const String sessionInvalid = 'GRINDING_WORKER_SESSION_INVALID';
  static const String sessionExpired = 'GRINDING_WORKER_SESSION_EXPIRED';

  /// 403 on login (not a grinding worker) AND on any session call (access
  /// withdrawn — the session was ended).
  static const String workerNotAllowed = 'GRINDING_WORKER_NOT_ALLOWED';

  // `/check`.
  static const String identifierInvalid = 'GRINDING_IDENTIFIER_INVALID';
  static const String sourceNotFound = 'GRINDING_SOURCE_NOT_FOUND';
  static const String identifierAmbiguous = 'GRINDING_IDENTIFIER_AMBIGUOUS';

  // START / COMPLETE.
  static const String approvalRequired = 'GRINDING_APPROVAL_REQUIRED';
  static const String orderNotReady = 'GRINDING_ORDER_NOT_READY';
  static const String orderNotInProgress = 'GRINDING_ORDER_NOT_IN_PROGRESS';
  static const String orderAlreadyCompleted =
      'GRINDING_ORDER_ALREADY_COMPLETED';
  static const String sourceStateChanged = 'GRINDING_SOURCE_STATE_CHANGED';
  static const String orderNotFound = 'GRINDING_ORDER_NOT_FOUND';
  static const String idempotencyKeyReused = 'GRINDING_IDEMPOTENCY_KEY_REUSED';

  // Biometric login gate
  // (`docs/FRONTEND_HANDOFF_GRINDING_APP_BIOMETRIC_LOGIN_GATE.md` §4.4).
  // 403 on `POST /auth/pin`; the first three may carry an attempt token.
  static const String biometricVerificationRequired =
      'BIOMETRIC_VERIFICATION_REQUIRED';
  static const String biometricVerificationExpired =
      'BIOMETRIC_VERIFICATION_EXPIRED';
  static const String biometricDeviceUnavailable =
      'BIOMETRIC_DEVICE_UNAVAILABLE';

  /// Only a SYSTEM_ADMIN can fix these: never polled, never retried.
  static const String biometricMappingMissing = 'BIOMETRIC_MAPPING_MISSING';
  static const String biometricMappingDisabled = 'BIOMETRIC_MAPPING_DISABLED';

  /// 410 on the attempt-status endpoint: unknown or expired attempt.
  static const String biometricLoginAttemptExpired =
      'BIOMETRIC_LOGIN_ATTEMPT_EXPIRED';

  /// A biometric-gate code. Branch on this, never on the HTTP status alone:
  /// other 403s keep their own handling.
  static bool isBiometric(String? code) =>
      code != null && code.startsWith('BIOMETRIC_');

  static bool isBiometricMapping(String? code) =>
      code == biometricMappingMissing || code == biometricMappingDisabled;

  /// Codes that end the worker's session: clear the token and go to PIN.
  static const Set<String> sessionTerminalCodes = <String>{
    sessionRequired,
    sessionInvalid,
    sessionExpired,
    workerNotAllowed,
  };

  static bool isSessionTerminal(String? code) =>
      code != null && sessionTerminalCodes.contains(code);

  /// Contract §4.1: a 401/403 whose code is not a `GRINDING_*` code (or that
  /// has no envelope at all) means the device itself was rejected.
  /// `OPERATOR_PIN_INVALID` is the one documented non-`GRINDING_*` 401; the
  /// `BIOMETRIC_*` login refusals are not device rejections either.
  static bool isDeviceRejection({required int? status, required String? code}) {
    if (status != 401 && status != 403) return false;
    if (code == null || code.isEmpty) return true;
    if (code == operatorPinInvalid || isBiometric(code)) return false;
    return !code.startsWith('GRINDING_');
  }
}
