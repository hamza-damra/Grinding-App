import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_codes.dart';

/// What a START / COMPLETE failure means for its pending record
/// (contract §4.4: clear only after a 2xx or a definitive 4xx business error).
enum CommandFailureClass {
  /// 4xx business answer (not a session code): the server did not apply the
  /// command and never will under this id → clear the record, show the
  /// Arabic message, re-check.
  definitive,

  /// `GRINDING_WORKER_SESSION_*` / `GRINDING_WORKER_NOT_ALLOWED`: the session
  /// ended → keep the record; the worker returns to PIN.
  sessionEnded,

  /// The request may or may not have reached the server (timeout, lost
  /// connection, 408/429/5xx) → keep the record, resend the SAME id.
  retryable,

  /// Anything else (device rejected, captive portal, old backend, unknown)
  /// → keep the record, show the Arabic message, no automatic resend.
  keep,

  /// Aborted locally (session changed) → keep the record, stay silent.
  cancelled,
}

CommandFailureClass classifyCommandFailure(AppFailure failure) {
  return switch (failure) {
    CancelledFailure() => CommandFailureClass.cancelled,
    ApiFailure(:final code, :final status) =>
      ErrorCodes.isSessionTerminal(code)
          ? CommandFailureClass.sessionEnded
          : _apiStatusClass(status),
    SessionExpiredFailure() => CommandFailureClass.sessionEnded,
    NetworkFailure() => CommandFailureClass.retryable,
    TimeoutFailure() => CommandFailureClass.retryable,
    ServerFailure(:final status) =>
      (status == null || status == 408 || status == 429 || status >= 500)
          ? CommandFailureClass.retryable
          : CommandFailureClass.keep,
    DeviceNotAuthorizedFailure() => CommandFailureClass.keep,
    AppNotConfiguredFailure() => CommandFailureClass.keep,
    // Login-only answers; never expected on a command.
    BiometricDeniedFailure() => CommandFailureClass.keep,
    BiometricAttemptExpiredFailure() => CommandFailureClass.keep,
    UnknownFailure() => CommandFailureClass.keep,
  };
}

CommandFailureClass _apiStatusClass(int? status) {
  if (status == null) return CommandFailureClass.keep;
  if (status == 408 || status == 429 || status >= 500) {
    return CommandFailureClass.retryable;
  }
  if (status >= 400 && status < 500) return CommandFailureClass.definitive;
  return CommandFailureClass.keep;
}
