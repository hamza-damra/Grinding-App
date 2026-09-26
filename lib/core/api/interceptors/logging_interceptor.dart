import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../api_paths.dart';

/// Logs every outgoing request and its result with **all sensitive values
/// redacted**. The following are never logged in the clear:
///
/// * the PIN (request body field `pin`);
/// * the shared device key (`X-Device-Key` header);
/// * the session token (`X-Session-Token` header and the `sessionToken`
///   field of the login response);
/// * the biometric attempt token (`X-Biometric-Attempt-Token` header and the
///   `attemptToken` field of a `BIOMETRIC_*` login refusal).
///
/// The default [Logger] uses [DevelopmentFilter], which only prints in debug
/// builds (asserts enabled): profile and release builds log nothing.
class RedactingLoggingInterceptor extends Interceptor {
  RedactingLoggingInterceptor({Logger? logger})
    : _logger =
          logger ??
          Logger(
            filter: DevelopmentFilter(),
            printer: SimplePrinter(colors: false),
          );

  final Logger _logger;

  static const String _redacted = '***';
  static const Set<String> _redactedHeaders = <String>{
    ApiHeaders.deviceKey,
    ApiHeaders.sessionToken,
    ApiHeaders.biometricAttemptToken,
  };
  static const Set<String> _redactedBodyFields = <String>{
    'pin',
    'sessionToken',
    'attemptToken',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logger.i(
      '→ ${options.method} ${options.uri} '
      'headers=${redactHeaders(options.headers)} '
      'body=${redactBody(options.data)}',
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _logger.i(
      '← ${response.statusCode} ${response.requestOptions.uri} '
      'body=${redactBody(response.data)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Diagnostic detail for transport-level failures without leaking request
    // bodies or headers.
    _logger.w(
      '× ${err.requestOptions.method} ${err.requestOptions.uri} '
      'type=${err.type} status=${err.response?.statusCode} '
      'cause=${err.error?.runtimeType} '
      'body=${redactBody(err.response?.data)}',
    );
    handler.next(err);
  }

  /// Public for tests.
  static Map<String, dynamic> redactHeaders(Map<String, dynamic> headers) {
    return <String, dynamic>{
      for (final entry in headers.entries)
        entry.key:
            _redactedHeaders.any(
              (h) => h.toLowerCase() == entry.key.toLowerCase(),
            )
            ? _redacted
            : entry.value,
    };
  }

  /// Public for tests — recursive redaction of any sensitive field anywhere
  /// in the body, regardless of nesting.
  static Object? redactBody(Object? body) {
    if (body == null) return null;
    if (body is Map) {
      return <String, dynamic>{
        for (final entry in body.entries)
          if (entry.key is String)
            (entry.key as String): _redactedBodyFields.contains(entry.key)
                ? _redacted
                : redactBody(entry.value),
      };
    }
    if (body is List) {
      return body.map(redactBody).toList(growable: false);
    }
    return body;
  }
}
