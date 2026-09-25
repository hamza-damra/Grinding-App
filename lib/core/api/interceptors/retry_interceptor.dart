import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';
import '../api_paths.dart';

/// Automatic retry for **read-only** requests that fail with a transient
/// transport error (stale socket / cold TLS after a resume, server warm-up).
/// Ported from the Operator App's `RetryInterceptor`.
///
/// Safety boundary — only ever retries requests that are safe to repeat:
///   * `GET` (queues, `/sessions/me`), unless `extra[disableAutoRetry]`;
///   * a `POST` that explicitly opts in via `extra[readOnlyRetry] == true`
///     (`/check` only — the contract says it never changes anything).
///
/// START / COMPLETE never opt in. Their retries are owned by the command
/// controller, which reuses the persisted `clientRequestId` and re-checks
/// the auth generation before every resend — a generic interceptor retry
/// could resend worker A's command after worker B logged in.
///
/// Retried failure types: connect/send/receive timeouts, connection errors
/// and 502/503/504. A 4xx (including session errors) is never retried.
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required this._dio,
    int? maxRetries,
    List<Duration>? backoff,
    Random? random,
  }) : _maxRetries = maxRetries ?? AppConfig.idempotentRetryCount,
       _backoff = backoff ?? AppConfig.idempotentRetryBackoff,
       _random = random ?? Random();

  final Dio _dio;
  final int _maxRetries;
  final List<Duration> _backoff;
  final Random _random;

  static const String _kAttempt = '__retryAttempt';

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final attempt = (options.extra[_kAttempt] as int?) ?? 0;

    if (!isRetriable(err) || attempt >= _maxRetries) {
      handler.next(err);
      return;
    }

    final nextAttempt = attempt + 1;
    if (kDebugMode) {
      debugPrint(
        '[RetryInterceptor] RETRY ${options.method} ${options.path} '
        'type=${err.type.name} status=${err.response?.statusCode} '
        'attempt=$nextAttempt',
      );
    }

    final delay = _delayFor(nextAttempt);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (options.cancelToken?.isCancelled ?? false) {
      handler.next(err);
      return;
    }

    final retryOptions = options.copyWith(
      extra: <String, dynamic>{...options.extra, _kAttempt: nextAttempt},
    );

    try {
      final response = await _dio.fetch<dynamic>(retryOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      // `e` already traversed the full chain (its own pass through this
      // interceptor stopped once the budget was spent). Forward as-is.
      handler.next(e);
    } catch (_) {
      handler.next(err);
    }
  }

  /// Public for tests.
  static bool isRetriable(DioException err) {
    final options = err.requestOptions;
    final method = options.method.toUpperCase();
    final optedIn = options.extra[DioRequestExtras.readOnlyRetry] == true;
    if (method == 'GET') {
      if (options.extra[DioRequestExtras.disableAutoRetry] == true) {
        return false;
      }
    } else if (!(method == 'POST' && optedIn)) {
      return false;
    }
    if (options.responseType == ResponseType.stream) return false;
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final status = err.response?.statusCode;
        return status == 502 || status == 503 || status == 504;
      case DioExceptionType.transformTimeout:
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return false;
    }
  }

  Duration _delayFor(int attempt) {
    if (_backoff.isEmpty) return Duration.zero;
    final base = _backoff[(attempt - 1).clamp(0, _backoff.length - 1)];
    if (base <= Duration.zero) return Duration.zero;
    // Up to +50% jitter so a fan-out of resume refreshes does not retry in
    // lock-step.
    final jitterMs = (base.inMilliseconds * 0.5 * _random.nextDouble()).round();
    return base + Duration(milliseconds: jitterMs);
  }
}
