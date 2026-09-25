/// Grinding App endpoints (`docs/GRINDING_APP_BACKEND_CONTRACT.md` §4.2).
class ApiPaths {
  ApiPaths._();

  static const String _base = '/api/v1/grinding-app';

  /// `POST` — PIN login. The ONLY call without `X-Session-Token`.
  static const String authPin = '$_base/auth/pin';

  /// `GET` — current session / worker (used on launch and on resume).
  static const String sessionsMe = '$_base/sessions/me';

  /// `POST` — end the session; idempotent (`ended:false` = already unusable).
  static const String authLogout = '$_base/auth/logout';

  /// `POST` — resolve a scanned number. Read-only.
  static const String check = '$_base/check';

  /// `GET ?status=READY_FOR_GRINDING|IN_GRINDING` — queue, oldest first.
  static const String orders = '$_base/orders';

  /// `POST {clientRequestId}` — start grinding (idempotent).
  static String orderStart(int orderId) => '$_base/orders/$orderId/start';

  /// `POST {clientRequestId}` — confirm physical grinding (idempotent).
  static String orderComplete(int orderId) => '$_base/orders/$orderId/complete';
}

class ApiHeaders {
  ApiHeaders._();

  static const String deviceKey = 'X-Device-Key';
  static const String sessionToken = 'X-Session-Token';
  static const String contentType = 'Content-Type';
  static const String contentTypeJson = 'application/json';
}

class DioRequestExtras {
  DioRequestExtras._();

  /// Opt-in: attach `X-Session-Token` (every call except `POST /auth/pin`).
  static const String useSessionToken = 'useSessionToken';

  /// Stamped by `SessionTokenInterceptor`: the auth generation whose token
  /// this request carried. Lets a late session error from a previous worker
  /// be told apart from one for the current worker.
  static const String authGeneration = 'authGeneration';

  /// Opt-in for the transport auto-retry on a read-only POST (`/check`).
  /// GETs are retried by default; START / COMPLETE never set this — their
  /// retries are owned by the command controller, which re-checks the auth
  /// generation before every resend.
  static const String readOnlyRetry = 'readOnlyRetry';

  /// Opt a GET out of the transport auto-retry.
  static const String disableAutoRetry = 'disableAutoRetry';
}
