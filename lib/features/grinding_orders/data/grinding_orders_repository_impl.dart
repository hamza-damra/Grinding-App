import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bootstrap/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/entities/check_result.dart';
import '../domain/entities/execution_result.dart';
import '../domain/entities/grinding_order.dart';
import '../domain/repositories/grinding_orders_repository.dart';
import '../domain/value_objects/grinding_command.dart';
import '../domain/value_objects/grinding_source.dart';
import '../domain/value_objects/grinding_status.dart';
import 'grinding_orders_remote_data_source.dart';

class GrindingOrdersRepositoryImpl implements GrindingOrdersRepository {
  GrindingOrdersRepositoryImpl(this._remote);

  final GrindingOrdersRemoteDataSource _remote;

  @override
  Future<CheckResult> check(
    String identifier, {
    GrindingSourceType? sourceType,
  }) => _guard(() => _remote.check(identifier, sourceType: sourceType));

  @override
  Future<List<GrindingOrder>> getQueue(GrindingQueueStatus status) =>
      _guard(() => _remote.getQueue(status));

  @override
  Future<ExecutionResult> execute(
    GrindingCommand command, {
    required int orderId,
    required String clientRequestId,
    CancelToken? cancelToken,
  }) => _guard(
    () => _remote.execute(
      command,
      orderId: orderId,
      clientRequestId: clientRequestId,
      cancelToken: cancelToken,
    ),
  );

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on AppFailure {
      rethrow;
    } on DioException catch (e) {
      throw ErrorMapper.fromException(e);
    } catch (e, st) {
      throw ErrorMapper.fromException(e, st);
    }
  }
}

final grindingOrdersRemoteDataSourceProvider =
    Provider<GrindingOrdersRemoteDataSource>(
      (ref) => GrindingOrdersRemoteDataSource(ref.watch(dioProvider)),
    );

final grindingOrdersRepositoryProvider = Provider<GrindingOrdersRepository>((
  ref,
) {
  return GrindingOrdersRepositoryImpl(
    ref.watch(grindingOrdersRemoteDataSourceProvider),
  );
});
