import '../entities/grinding_worker.dart';

/// `GrindingAppApi` session endpoints (contract §7). Every method throws an
/// `AppFailure` on error.
abstract class GrindingAuthRepository {
  /// `POST /auth/pin` — the only call without `X-Session-Token`. The PIN is
  /// used for this one request and never stored or logged.
  Future<PinLoginResult> loginWithPin(String pin);

  /// `GET /sessions/me`.
  Future<GrindingSession> getSession();

  /// `POST /auth/logout`. Returns `ended` (`false` = the token was already
  /// unusable — still logged out).
  Future<bool> logout();
}
