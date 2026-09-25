import 'package:dio/dio.dart';

import '../../errors/app_failure.dart';
import '../../errors/error_codes.dart';

/// Parses the backend error envelope
/// (`{success:false, error:{code, message, details}}`) on error responses and
/// puts a typed [AppFailure] on `DioException.error`:
///
/// * a 401/403 without a `GRINDING_*` code (or without an envelope) →
///   [DeviceNotAuthorizedFailure] (contract §4.1: the device key was
///   rejected before business logic);
/// * any other envelope with a `code` → [ApiFailure];
/// * no envelope (5xx, HTML error pages, gateways) → [ServerFailure].
class ErrorEnvelopeInterceptor extends Interceptor {
  const ErrorEnvelopeInterceptor();

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Already wrapped by an upstream interceptor — let it through.
    if (err.error is AppFailure) {
      handler.next(err);
      return;
    }

    final response = err.response;
    if (response == null) {
      handler.next(err);
      return;
    }

    final status = response.statusCode;
    String? code;
    String? message;
    Map<String, dynamic>? details;
    final body = response.data;
    if (body is Map) {
      final errorObj = body['error'];
      if (errorObj is Map) {
        final rawCode = errorObj['code'];
        if (rawCode is String && rawCode.isNotEmpty) code = rawCode;
        final rawMessage = errorObj['message'];
        if (rawMessage is String) message = rawMessage;
        final rawDetails = errorObj['details'];
        if (rawDetails is Map) {
          details = Map<String, dynamic>.from(rawDetails);
        }
      }
    }

    final AppFailure wrapped;
    if (ErrorCodes.isDeviceRejection(status: status, code: code)) {
      wrapped = AppFailure.deviceNotAuthorized(status: status);
    } else if (code != null) {
      wrapped = AppFailure.api(
        code: code,
        backendMessage: message,
        status: status,
        details: details,
      );
    } else {
      wrapped = AppFailure.server(status: status);
    }

    handler.next(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: wrapped,
        stackTrace: err.stackTrace,
        message: err.message,
      ),
    );
  }
}
