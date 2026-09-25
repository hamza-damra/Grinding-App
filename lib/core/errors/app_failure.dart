/// Typed failure family surfaced by repositories and controllers. Mirrors the
/// Operator App's `AppFailure` (hand-written sealed classes instead of
/// freezed — see README "Code generation").
///
/// `toString` never includes backend messages or details: those can echo
/// request values, and failures end up in debug logs.
sealed class AppFailure implements Exception {
  const AppFailure();

  const factory AppFailure.network() = NetworkFailure;
  const factory AppFailure.timeout() = TimeoutFailure;
  const factory AppFailure.cancelled() = CancelledFailure;

  /// Server-side failure that did not return a parseable error envelope
  /// (5xx, 4xx without a `code`, HTML error pages, or a 2xx without
  /// `success:true`).
  const factory AppFailure.server({required int? status}) = ServerFailure;

  /// Backend returned `{success:false, error:{code, message, details}}`.
  const factory AppFailure.api({
    required String code,
    String? backendMessage,
    int? status,
    Map<String, dynamic>? details,
  }) = ApiFailure;

  /// Local-only: API_BASE_URL / DEVICE_KEY missing, or a non-HTTPS base URL.
  const factory AppFailure.appNotConfigured() = AppNotConfiguredFailure;

  /// Contract §4.1: any 401/403 without a `GRINDING_*` code means the device
  /// key was rejected before business logic ran. The worker's session is NOT
  /// touched — only an admin can fix the device key.
  const factory AppFailure.deviceNotAuthorized({int? status}) =
      DeviceNotAuthorizedFailure;

  /// No session token is held locally for a session-scoped call.
  const factory AppFailure.sessionExpired() = SessionExpiredFailure;

  const factory AppFailure.unknown({Object? cause}) = UnknownFailure;
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure();

  @override
  bool operator ==(Object other) => other is NetworkFailure;

  @override
  int get hashCode => (NetworkFailure).hashCode;

  @override
  String toString() => 'AppFailure.network()';
}

final class TimeoutFailure extends AppFailure {
  const TimeoutFailure();

  @override
  bool operator ==(Object other) => other is TimeoutFailure;

  @override
  int get hashCode => (TimeoutFailure).hashCode;

  @override
  String toString() => 'AppFailure.timeout()';
}

final class CancelledFailure extends AppFailure {
  const CancelledFailure();

  @override
  bool operator ==(Object other) => other is CancelledFailure;

  @override
  int get hashCode => (CancelledFailure).hashCode;

  @override
  String toString() => 'AppFailure.cancelled()';
}

final class ServerFailure extends AppFailure {
  const ServerFailure({required this.status});

  final int? status;

  @override
  bool operator ==(Object other) =>
      other is ServerFailure && other.status == status;

  @override
  int get hashCode => Object.hash(ServerFailure, status);

  @override
  String toString() => 'AppFailure.server(status: $status)';
}

final class ApiFailure extends AppFailure {
  const ApiFailure({
    required this.code,
    this.backendMessage,
    this.status,
    this.details,
  });

  final String code;

  /// English, technical — never shown to the worker (contract §4.1).
  final String? backendMessage;
  final int? status;
  final Map<String, dynamic>? details;

  @override
  bool operator ==(Object other) =>
      other is ApiFailure && other.code == code && other.status == status;

  @override
  int get hashCode => Object.hash(ApiFailure, code, status);

  @override
  String toString() => 'AppFailure.api(code: $code, status: $status)';
}

final class AppNotConfiguredFailure extends AppFailure {
  const AppNotConfiguredFailure();

  @override
  bool operator ==(Object other) => other is AppNotConfiguredFailure;

  @override
  int get hashCode => (AppNotConfiguredFailure).hashCode;

  @override
  String toString() => 'AppFailure.appNotConfigured()';
}

final class DeviceNotAuthorizedFailure extends AppFailure {
  const DeviceNotAuthorizedFailure({this.status});

  final int? status;

  @override
  bool operator ==(Object other) =>
      other is DeviceNotAuthorizedFailure && other.status == status;

  @override
  int get hashCode => Object.hash(DeviceNotAuthorizedFailure, status);

  @override
  String toString() => 'AppFailure.deviceNotAuthorized(status: $status)';
}

final class SessionExpiredFailure extends AppFailure {
  const SessionExpiredFailure();

  @override
  bool operator ==(Object other) => other is SessionExpiredFailure;

  @override
  int get hashCode => (SessionExpiredFailure).hashCode;

  @override
  String toString() => 'AppFailure.sessionExpired()';
}

final class UnknownFailure extends AppFailure {
  const UnknownFailure({this.cause});

  final Object? cause;

  @override
  bool operator ==(Object other) =>
      other is UnknownFailure && other.cause == cause;

  @override
  int get hashCode => Object.hash(UnknownFailure, cause);

  /// Only the cause's type — a cause's own `toString` could echo request
  /// data.
  @override
  String toString() => 'AppFailure.unknown(cause: ${cause?.runtimeType})';
}
