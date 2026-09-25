import 'package:dio/dio.dart';

import '../api_paths.dart';

/// Adds the shared `X-Device-Key` header to every outgoing request.
///
/// The key is a per-installation build value (`--dart-define=DEVICE_KEY=…`,
/// never a source default). It is never displayed and never logged — the
/// logging interceptor redacts it.
class DeviceKeyInterceptor extends Interceptor {
  DeviceKeyInterceptor(this._deviceKey);

  final String _deviceKey;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_deviceKey.isNotEmpty) {
      options.headers[ApiHeaders.deviceKey] = _deviceKey;
    }
    handler.next(options);
  }
}
