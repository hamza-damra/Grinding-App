import 'package:dio/dio.dart' show CancelToken;

import '../entities/check_result.dart';
import '../entities/execution_result.dart';
import '../entities/grinding_order.dart';
import '../value_objects/grinding_command.dart';
import '../value_objects/grinding_source.dart';
import '../value_objects/grinding_status.dart';

/// `GrindingAppApi` order endpoints (contract §7). Every method throws an
/// `AppFailure` on error.
abstract class GrindingOrdersRepository {
  /// `POST /check`. [sourceType] only after a `GRINDING_IDENTIFIER_AMBIGUOUS`
  /// answer, and only as the worker's own choice.
  Future<CheckResult> check(
    String identifier, {
    GrindingSourceType? sourceType,
  });

  /// `GET /orders?status=…` — oldest first, at most 100.
  Future<List<GrindingOrder>> getQueue(GrindingQueueStatus status);

  /// `POST /orders/{orderId}/start|complete` with a persisted
  /// [clientRequestId]. Never retried here: the command controller owns
  /// retries (same id, auth-generation fenced). [cancelToken] aborts the
  /// request when the session ends.
  Future<ExecutionResult> execute(
    GrindingCommand command, {
    required int orderId,
    required String clientRequestId,
    CancelToken? cancelToken,
  });
}
