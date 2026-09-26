import 'app_failure.dart';

/// Whether [failure] is a *technical connection* failure — the class of
/// errors that should surface the reusable connection dialog / recovery
/// banner rather than an inline business message.
///
/// Business failures carry their own canonical Arabic copy and belong inline
/// or in a dialog, not in a "connection" treatment.
bool isConnectionFailure(AppFailure failure) {
  return switch (failure) {
    NetworkFailure() => true,
    TimeoutFailure() => true,
    ServerFailure() => true,
    UnknownFailure() => true,
    ApiFailure() => false,
    SessionExpiredFailure() => false,
    CancelledFailure() => false,
    AppNotConfiguredFailure() => false,
    DeviceNotAuthorizedFailure() => false,
    BiometricDeniedFailure() => false,
    BiometricAttemptExpiredFailure() => false,
  };
}

/// Whether a START / COMPLETE that failed this way may be retried with the
/// same `clientRequestId` without the worker's involvement: the request may
/// or may not have reached the server, so only the idempotent resend can
/// tell. HTTP 408 / 429 / 5xx are included — the server did not accept it
/// definitively.
bool isRetryableCommandFailure(AppFailure failure) {
  return switch (failure) {
    NetworkFailure() => true,
    TimeoutFailure() => true,
    ServerFailure(:final status) =>
      status == null || status == 408 || status == 429 || status >= 500,
    _ => false,
  };
}
