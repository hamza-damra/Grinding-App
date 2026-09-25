import 'package:dio/dio.dart';

import '../../../core/api/api_envelope.dart';
import '../../../core/api/api_paths.dart';
import '../../../core/api/json_read.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/entities/check_result.dart';
import '../domain/entities/execution_result.dart';
import '../domain/entities/grinding_order.dart';
import '../domain/value_objects/grinding_command.dart';
import '../domain/value_objects/grinding_source.dart';
import '../domain/value_objects/grinding_status.dart';
import 'dtos/check_dtos.dart';

/// Thin Dio wrapper for the order endpoints. All carry `X-Session-Token`.
class GrindingOrdersRemoteDataSource {
  GrindingOrdersRemoteDataSource(this._dio);

  final Dio _dio;

  Future<CheckResult> check(
    String identifier, {
    GrindingSourceType? sourceType,
  }) async {
    final response = await _dio.post<dynamic>(
      ApiPaths.check,
      data: CheckRequestDto(
        identifier: identifier,
        sourceType: sourceType,
      ).toJson(),
      options: Options(
        extra: const <String, dynamic>{
          DioRequestExtras.useSessionToken: true,
          // `/check` "never changes anything" (contract §4.2), so a transport
          // failure may be retried transparently.
          DioRequestExtras.readOnlyRetry: true,
        },
      ),
    );
    return ApiEnvelope.unwrap<CheckResult>(response, (data) {
      final json = JsonRead.map(data);
      if (json == null) throw const FormatException('check: data not a map');
      return CheckResponseDto.fromJson(json);
    });
  }

  Future<List<GrindingOrder>> getQueue(GrindingQueueStatus status) async {
    final response = await _dio.get<dynamic>(
      ApiPaths.orders,
      queryParameters: <String, dynamic>{'status': status.wire},
      options: Options(
        extra: const <String, dynamic>{DioRequestExtras.useSessionToken: true},
      ),
    );
    return ApiEnvelope.unwrap<List<GrindingOrder>>(response, (data) {
      final json = JsonRead.map(data);
      if (json == null) throw const FormatException('queue: data not a map');
      return QueueResponseDto.fromJson(json);
    });
  }

  /// Sends ONE attempt. Retries (same id) belong to the command controller.
  Future<ExecutionResult> execute(
    GrindingCommand command, {
    required int orderId,
    required String clientRequestId,
    CancelToken? cancelToken,
  }) async {
    final path = switch (command) {
      GrindingCommand.start => ApiPaths.orderStart(orderId),
      GrindingCommand.complete => ApiPaths.orderComplete(orderId),
    };
    final response = await _dio.post<dynamic>(
      path,
      data: ExecutionRequestDto(clientRequestId).toJson(),
      cancelToken: cancelToken,
      options: Options(
        extra: const <String, dynamic>{DioRequestExtras.useSessionToken: true},
      ),
    );
    if (!ApiEnvelope.isSuccess(response)) {
      // 2xx without `success:true` (captive portal, proxy page): the server
      // did not acknowledge the command — keep the pending record.
      throw AppFailure.server(status: response.statusCode);
    }
    final body = response.data as Map<String, dynamic>;
    return ExecutionResponseDto.fromData(body['data']);
  }
}
