import 'package:dio/dio.dart';

import '../errors/app_failure.dart';

/// Helpers for unwrapping the standard backend response envelope:
///
/// ```json
/// { "success": true, "data": <T> }
/// ```
///
/// Error envelopes are translated into [ApiFailure] by
/// `ErrorEnvelopeInterceptor`, so this helper only handles successful
/// responses. A 2xx response without `success:true` (captive portal, proxy
/// page, wrong server) is a malformed server response ([ServerFailure]).
class ApiEnvelope {
  ApiEnvelope._();

  static T unwrap<T>(
    Response<dynamic> response,
    T Function(Object? data) fromData,
  ) {
    if (!isSuccess(response)) {
      throw AppFailure.server(status: response.statusCode);
    }
    final body = response.data as Map<String, dynamic>;
    return fromData(body['data']);
  }

  /// `true` when the body is a JSON object with `success == true`, i.e. the
  /// server positively acknowledged the request.
  static bool isSuccess(Response<dynamic> response) {
    final body = response.data;
    return body is Map<String, dynamic> && body['success'] == true;
  }
}
