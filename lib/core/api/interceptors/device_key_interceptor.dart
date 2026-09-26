import 'package:dio/dio.dart';

import '../api_paths.dart';

/// Adds the shared `X-Device-Key` header to every outgoing request, except
/// one that opts out with `extra[DioRequestExtras.omitDeviceKey]` (the
/// biometric attempt-status call).
///
/// The key is a per-installation build value (`--dart-define=DEVICE_KEY=…`,
/// never a source default). It is never displayed and never logged — the
/// logging interceptor redacts it.
class DeviceKeyInterceptor extends Interceptor {
  DeviceKeyInterceptor(this._deviceKey);

  final String _deviceKey;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra[DioRequestExtras.omitDeviceKey] == true) {
      options.headers.remove(ApiHeaders.deviceKey);
    } else if (_deviceKey.isNotEmpty) {
      options.headers[ApiHeaders.deviceKey] = _deviceKey;
    }
    handler.next(options);
  }
}
