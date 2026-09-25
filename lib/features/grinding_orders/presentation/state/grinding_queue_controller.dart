import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/grinding_orders_repository_impl.dart';
import '../../domain/entities/grinding_order.dart';
import '../../domain/value_objects/grinding_status.dart';

/// One queue (`GET /orders?status=…`). Display-only: tapping a row runs the
/// same `/check` flow as a scan. Fetched when Home opens, on pull-to-refresh,
/// after a successful command and on resume (via `ref.invalidate`). No
/// polling. Bounded by the server (max 100).
class GrindingQueueController
    extends
        AutoDisposeFamilyAsyncNotifier<
          List<GrindingOrder>,
          GrindingQueueStatus
        > {
  @override
  Future<List<GrindingOrder>> build(GrindingQueueStatus arg) {
    return ref.watch(grindingOrdersRepositoryProvider).getQueue(arg);
  }

  /// Pull-to-refresh. Keeps the current rows visible while loading and after
  /// a failure (the error is shown on top of them).
  Future<void> refresh() async {
    final previous = state;
    state = const AsyncLoading<List<GrindingOrder>>().copyWithPrevious(
      previous,
    );
    final next = await AsyncValue.guard(
      () => ref.read(grindingOrdersRepositoryProvider).getQueue(arg),
    );
    state = next.hasError
        ? AsyncError<List<GrindingOrder>>(
            next.error!,
            next.stackTrace ?? StackTrace.current,
          ).copyWithPrevious(previous)
        : next;
  }
}

final grindingQueueProvider = AsyncNotifierProvider.autoDispose
    .family<GrindingQueueController, List<GrindingOrder>, GrindingQueueStatus>(
      GrindingQueueController.new,
    );
