import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../auth/auth_session.dart';
import '../config/app_config.dart';
import 'api_paths.dart';
import 'interceptors/device_key_interceptor.dart';
import 'interceptors/error_envelope_interceptor.dart';
import 'interceptors/logging_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import 'interceptors/session_invalidated_interceptor.dart';
import 'interceptors/session_token_interceptor.dart';
import 'interceptors/transport_guard_interceptor.dart';
import 'session_invalidation_signal.dart';

class ApiClient {
  ApiClient._();

  static Dio buildDio({
    required AuthSession session,
    SessionInvalidationSignal? sessionInvalidationSignal,
    String? baseUrl,
    String deviceKey = AppConfig.deviceKey,
    bool Function(Uri uri)? isTransportAllowed,
    List<Duration>? readRetryBackoff,
    Logger? logger,
  }) {
    baseUrl ??= AppConfig.baseUrl;
    if (kDebugMode) {
      // Safe diagnostic: only the base URL. The device key is never logged.
      debugPrint(
        '[ApiClient] APP_ENV=${AppConfig.environment.name} baseUrl=$baseUrl',
      );
    }

    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: AppConfig.connectTimeout,
        sendTimeout: AppConfig.sendTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        contentType: ApiHeaders.contentTypeJson,
        responseType: ResponseType.json,
        // Never follow redirects: a redirect could forward the device key /
        // session token to another host or downgrade to HTTP.
        followRedirects: false,
      ),
    );

    dio.interceptors.addAll(<Interceptor>[
      // Refuses non-HTTPS URLs before any credential is attached.
      TransportGuardInterceptor(isAllowed: isTransportAllowed),
      RedactingLoggingInterceptor(logger: logger),
      // Read-only retries only (GET + opted-in `/check`). Placed before the
      // token/envelope interceptors so a recovered retry never reaches the
      // session-invalidation path. START / COMPLETE are never retried here.
      RetryInterceptor(dio: dio, backoff: readRetryBackoff),
      DeviceKeyInterceptor(deviceKey),
      SessionTokenInterceptor(session),
      const ErrorEnvelopeInterceptor(),
      // Must be AFTER ErrorEnvelopeInterceptor so it sees the typed failure.
      if (sessionInvalidationSignal != null)
        SessionInvalidatedInterceptor(sessionInvalidationSignal),
    ]);

    return dio;
  }
}

final dioProvider = Provider<Dio>((ref) {
  // Both dependencies are leaf providers, so there is no cycle with the auth
  // controller (which depends on dioProvider through its repository).
  final session = ref.watch(authSessionProvider);
  final signal = ref.watch(sessionInvalidationSignalProvider);
  return ApiClient.buildDio(
    session: session,
    sessionInvalidationSignal: signal,
  );
});
