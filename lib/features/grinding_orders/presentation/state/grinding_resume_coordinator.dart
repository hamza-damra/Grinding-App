import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/lifecycle/lifecycle_resume_notifier.dart';
import '../../../grinding_auth/presentation/state/grinding_auth_controller.dart';
import '../../../grinding_auth/presentation/state/grinding_auth_state.dart';
import 'current_order_controller.dart';
import 'grinding_queue_controller.dart';
import 'order_command_controller.dart';

/// Contract §11 "App resumed": `GET /sessions/me`, then re-check the order on
/// screen, then refresh the lists. Driven by the debounced
/// [lifecycleResumeProvider] tick; single-flight (a burst of resumes never
/// stacks refreshes). The open order is not re-checked while one of its
/// commands is in flight — the command's own result refreshes it. Nothing
/// here ever sends a START / COMPLETE. Mounted in `app.dart`.
class GrindingResumeCoordinator extends Notifier<void> {
  bool _running = false;

  @override
  void build() {
    ref.listen<int>(lifecycleResumeProvider, (previous, next) {
      if (previous == null || next == previous) return;
      unawaited(onResume());
    });
  }

  Future<void> onResume() async {
    if (_running) return;
    _running = true;
    try {
      await ref.read(grindingAuthControllerProvider.notifier).verifySession();
      final auth = ref.read(grindingAuthControllerProvider).valueOrNull;
      if (auth is! GrindingAuthAuthenticated) return;

      final order = ref.read(currentOrderControllerProvider);
      final orderId = order.displayOrder?.id;
      final commands = ref.read(orderCommandControllerProvider).valueOrNull;
      final busy =
          orderId != null && commands?.inFlightForOrder(orderId) != null;
      if (order.isOpen && !order.ambiguity && !busy) {
        await ref.read(currentOrderControllerProvider.notifier).refresh();
      }
      ref.invalidate(grindingQueueProvider);
    } finally {
      _running = false;
    }
  }
}

final grindingResumeCoordinatorProvider =
    NotifierProvider<GrindingResumeCoordinator, void>(
      GrindingResumeCoordinator.new,
    );
