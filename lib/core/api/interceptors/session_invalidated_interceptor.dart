import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../errors/app_failure.dart';
import '../../errors/error_codes.dart';
import '../api_paths.dart';
import '../session_invalidation_signal.dart';

/// Global response handler for the session-terminal codes of contract §4.3
/// (`GRINDING_WORKER_SESSION_REQUIRED/INVALID/EXPIRED`,
/// `GRINDING_WORKER_NOT_ALLOWED`) on session-scoped calls.
///
/// Emits to [SessionInvalidationSignal] with the request's auth generation
/// and never reads a provider itself (that would create a Riverpod cycle —
/// see the signal's doc). `SessionInvalidationListener` does the cleanup.
///
/// `POST /auth/pin` does not opt into the session token, so a
/// `GRINDING_WORKER_NOT_ALLOWED` login rejection is NOT a session
/// invalidation — the PIN screen shows it inline.
///
/// Wired AFTER `ErrorEnvelopeInterceptor` so the typed [ApiFailure] is on
/// `err.error`.
class SessionInvalidatedInterceptor extends Interceptor {
  SessionInvalidatedInterceptor(this._signal);

  final SessionInvalidationSignal _signal;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final wrapped = err.error;
    final options = err.requestOptions;
    if (wrapped is ApiFailure &&
        options.extra[DioRequestExtras.useSessionToken] == true &&
        ErrorCodes.isSessionTerminal(wrapped.code)) {
      final generation = options.extra[DioRequestExtras.authGeneration];
      if (kDebugMode) {
        debugPrint(
          '[SessionInvalidation] ${wrapped.code} on '
          '${options.method} ${options.path} generation=$generation',
        );
      }
      _signal.emit(
        SessionInvalidation(
          failure: wrapped,
          generation: generation is int ? generation : null,
        ),
      );
    }
    handler.next(err);
  }
}
