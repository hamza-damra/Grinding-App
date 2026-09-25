import 'package:dio/dio.dart';

import '../../../core/api/api_envelope.dart';
import '../../../core/api/api_paths.dart';
import '../../../core/api/json_read.dart';
import '../domain/entities/grinding_worker.dart';
import 'dtos/auth_dtos.dart';

/// Thin Dio wrapper for the session endpoints.
class GrindingAuthRemoteDataSource {
  GrindingAuthRemoteDataSource(this._dio);

  final Dio _dio;

  /// No `X-Session-Token` (the only such call). Never retried.
  Future<PinLoginResult> loginWithPin(String pin) async {
    final response = await _dio.post<dynamic>(
      ApiPaths.authPin,
      data: PinLoginRequest(pin).toJson(),
    );
    return ApiEnvelope.unwrap<PinLoginResult>(response, (data) {
      final json = JsonRead.map(data);
      if (json == null) throw const FormatException('login: data not a map');
      return PinLoginResponseDto.fromJson(json);
    });
  }

  Future<GrindingSession> getSession() async {
    final response = await _dio.get<dynamic>(
      ApiPaths.sessionsMe,
      options: Options(
        extra: const <String, dynamic>{DioRequestExtras.useSessionToken: true},
      ),
    );
    return ApiEnvelope.unwrap<GrindingSession>(response, (data) {
      final json = JsonRead.map(data);
      if (json == null) throw const FormatException('session: data not a map');
      return SessionViewDto.fromJson(json);
    });
  }

  Future<bool> logout() async {
    final response = await _dio.post<dynamic>(
      ApiPaths.authLogout,
      options: Options(
        extra: const <String, dynamic>{DioRequestExtras.useSessionToken: true},
      ),
    );
    return ApiEnvelope.unwrap<bool>(response, LogoutResponseDto.endedFrom);
  }
}
