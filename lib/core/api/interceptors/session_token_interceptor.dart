import 'package:dio/dio.dart';

import '../../auth/auth_session.dart';
import '../api_paths.dart';

/// Adds `X-Session-Token` **only** when the request opts in via
/// `options.extra[DioRequestExtras.useSessionToken] = true` (every call but
/// `POST /auth/pin`), and stamps the auth generation the token belongs to.
///
/// Reads the in-memory [AuthSession] synchronously, so the (token,
/// generation) pair is always consistent — see [AuthSession] for why that
/// matters.
class SessionTokenInterceptor extends Interceptor {
  SessionTokenInterceptor(this._session);

  final AuthSession _session;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra[DioRequestExtras.useSessionToken] == true) {
      final token = _session.token;
      options.extra[DioRequestExtras.authGeneration] = _session.generation;
      if (token != null && token.isNotEmpty) {
        options.headers[ApiHeaders.sessionToken] = token;
      } else {
        options.headers.remove(ApiHeaders.sessionToken);
      }
    }
    handler.next(options);
  }
}
