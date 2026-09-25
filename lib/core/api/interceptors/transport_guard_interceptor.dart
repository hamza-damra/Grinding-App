import 'package:dio/dio.dart';

import '../../config/app_config.dart';
import '../../errors/app_failure.dart';

/// First interceptor in the chain: refuses to send any request whose URL is
/// not HTTPS (plain HTTP is tolerated only to the device loopback in a
/// non-release build, or to the opt-in lab host — see
/// [AppConfig.isSecureTransport]).
///
/// Runs before `DeviceKeyInterceptor` / `SessionTokenInterceptor`, so a
/// rejected request never even has credentials attached. Defence in depth on
/// top of the config-missing screen and Android's network security config:
/// the PIN, device key and session token must never travel in cleartext.
class TransportGuardInterceptor extends Interceptor {
  TransportGuardInterceptor({bool Function(Uri uri)? isAllowed})
    : _isAllowed = isAllowed ?? AppConfig.isSecureTransport;

  final bool Function(Uri uri) _isAllowed;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_isAllowed(options.uri)) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: const AppFailure.appNotConfigured(),
          message: 'Refused: credentials may only be sent over HTTPS',
        ),
      );
      return;
    }
    handler.next(options);
  }
}
