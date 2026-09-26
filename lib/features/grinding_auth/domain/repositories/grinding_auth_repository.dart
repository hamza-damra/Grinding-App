import 'package:dio/dio.dart' show CancelToken;

import '../entities/biometric_attempt.dart';
import '../entities/grinding_worker.dart';

/// `GrindingAppApi` session endpoints (contract §7). Every method throws an
/// `AppFailure` on error.
abstract class GrindingAuthRepository {
  /// `POST /auth/pin` — the only call without `X-Session-Token`. The PIN is
  /// used for this one request and never stored or logged. A `BIOMETRIC_*`
  /// 403 throws `BiometricDeniedFailure` (biometric handoff §4.2).
  Future<PinLoginResult> loginWithPin(String pin);

  /// `GET /sessions/me`.
  Future<GrindingSession> getSession();

  /// `POST /auth/logout`. Returns `ended` (`false` = the token was already
  /// unusable — still logged out).
  Future<bool> logout();

  /// `GET {statusPath}` — biometric attempt status, long-polled (the server
  /// holds it up to 25 s). Sends only [attemptToken]. A 410 throws
  /// `BiometricAttemptExpiredFailure`; [cancelToken] aborts a held poll.
  Future<BiometricAttemptStatusResponse> getBiometricAttemptStatus({
    required String? statusPath,
    required String attemptToken,
    CancelToken? cancelToken,
  });
}
