import 'package:dio/dio.dart';

import 'app_failure.dart';

/// Translates lower-level transport errors into [AppFailure]s.
///
/// Structured HTTP envelopes are mapped in `ErrorEnvelopeInterceptor`, which
/// puts the typed failure on `DioException.error`; this mapper is the
/// second-line catcher for raw [DioException]s and other thrown objects.
class ErrorMapper {
  ErrorMapper._();

  static AppFailure fromException(Object error, [StackTrace? _]) {
    if (error is AppFailure) return error;
    if (error is DioException) return _fromDio(error);
    return AppFailure.unknown(cause: error);
  }

  static AppFailure _fromDio(DioException e) {
    final wrapped = e.error;
    if (wrapped is AppFailure) return wrapped;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const AppFailure.timeout();
      case DioExceptionType.cancel:
        return const AppFailure.cancelled();
      case DioExceptionType.connectionError:
        return const AppFailure.network();
      case DioExceptionType.badCertificate:
        return AppFailure.server(status: e.response?.statusCode);
      case DioExceptionType.badResponse:
        return AppFailure.server(status: e.response?.statusCode);
      case DioExceptionType.unknown:
        // A socket-level failure surfaces as `unknown` with a SocketException
        // / HttpException cause on some platforms; it is still a lost
        // connection from the worker's point of view.
        final cause = e.error;
        if (cause != null && _isSocketLevel(cause)) {
          return const AppFailure.network();
        }
        return AppFailure.unknown(cause: e.error ?? e);
    }
  }

  static bool _isSocketLevel(Object cause) {
    final name = cause.runtimeType.toString();
    return name == 'SocketException' ||
        name == 'HttpException' ||
        name == 'HandshakeException' ||
        name == 'TlsException';
  }
}
