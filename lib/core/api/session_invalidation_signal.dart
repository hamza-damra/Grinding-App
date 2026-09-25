import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/app_failure.dart';

/// One session-terminal response (`GRINDING_WORKER_SESSION_*` /
/// `GRINDING_WORKER_NOT_ALLOWED`) together with the auth generation whose
/// token the failed request carried.
class SessionInvalidation {
  const SessionInvalidation({required this.failure, required this.generation});

  final ApiFailure failure;

  /// `null` when the request was not stamped (should not happen for
  /// session-scoped calls; treated as stale).
  final int? generation;
}

/// Stream-backed decoupling shim between `SessionInvalidatedInterceptor`
/// (inside Dio, owned by `dioProvider`) and the auth controller cleanup
/// (which transitively depends on `dioProvider`). Mirrors the Operator App's
/// `AppTokenInvalidationSignal`: reading the auth controller from inside the
/// Dio chain would create a Riverpod `CircularDependencyError`.
class SessionInvalidationSignal {
  final StreamController<SessionInvalidation> _controller =
      StreamController<SessionInvalidation>.broadcast();

  Stream<SessionInvalidation> get stream => _controller.stream;

  void emit(SessionInvalidation event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  void dispose() {
    _controller.close();
  }
}

final sessionInvalidationSignalProvider = Provider<SessionInvalidationSignal>((
  ref,
) {
  final signal = SessionInvalidationSignal();
  ref.onDispose(signal.dispose);
  return signal;
});
