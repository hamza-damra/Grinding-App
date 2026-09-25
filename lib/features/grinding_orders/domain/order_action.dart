import 'entities/check_result.dart';
import 'entities/pending_command.dart';
import 'value_objects/grinding_command.dart';
import 'value_objects/grinding_source.dart';
import 'value_objects/grinding_status.dart';

/// What the order card offers. Produced only by [resolveOrderAction].
sealed class OrderAction {
  const OrderAction();
}

/// No button — just the `message`.
final class NoOrderAction extends OrderAction {
  const NoOrderAction();
}

/// The command's own button («بدء الجرش» / «تأكيد انتهاء الجرش»).
final class CommandOrderAction extends OrderAction {
  const CommandOrderAction({
    required this.command,
    required this.enabled,
    required this.busy,
    this.pending,
  });

  final GrindingCommand command;

  /// A persisted record whose id the tap will reuse (never a new id).
  final PendingCommand? pending;

  /// `false` while the check is refreshing or a command is in flight.
  final bool enabled;

  /// A request for this order is in flight (spinner).
  final bool busy;
}

/// «تحقق من الطلب السابق»: a persisted record that no longer matches the
/// order's current state. Tapping (after confirmation) sends the SAME id
/// once; the backend can then only answer `replayed:true` (it had succeeded)
/// or a definitive 4xx (it had not and can no longer apply) — either clears
/// the record. This is the one bounded exception to "the allowed* booleans
/// are the final gate": it exists because the contract only lets a record be
/// cleared by a server answer, and it is offered only when a fresh `/check`
/// shows the record can NOT be applied as a new action.
final class ReconcileOrderAction extends OrderAction {
  const ReconcileOrderAction({
    required this.pending,
    required this.enabled,
    required this.busy,
  });

  final PendingCommand pending;
  final bool enabled;
  final bool busy;
}

/// Pure action gate for the order card.
///
/// * START only if `allowedToStartGrinding && status == READY_FOR_GRINDING &&
///   !allowedToCompleteGrinding`.
/// * COMPLETE only if `allowedToCompleteGrinding && status == IN_GRINDING &&
///   !allowedToStartGrinding`.
/// * Both flags true, an unknown status, no order, or no successful check →
///   no action.
/// * A [pending] record (see [selectPendingForCheck]) wins: its own command
///   with the same id if the fresh check still allows exactly that command
///   for exactly that order; otherwise [ReconcileOrderAction]. A COMPLETE is
///   never offered while a START is pending.
/// * [checkRejected]: the `/check` itself was definitively rejected (e.g. the
///   number no longer resolves) — only a pending record can be reconciled.
/// * While [locked] (check refreshing, pending records still loading) or a
///   command is [inFlight], the button stays visible but disabled.
OrderAction resolveOrderAction({
  required CheckResult? check,
  required PendingCommand? pending,
  required GrindingCommand? inFlight,
  required bool locked,
  bool checkRejected = false,
}) {
  final busy = inFlight != null;
  final enabled = !busy && !locked;

  if (check == null) {
    if (checkRejected && pending != null) {
      return ReconcileOrderAction(
        pending: pending,
        enabled: enabled,
        busy: busy,
      );
    }
    return const NoOrderAction();
  }

  final order = check.order;
  final startAllowed =
      order != null &&
      check.allowedToStartGrinding &&
      check.status == GrindingStatus.readyForGrinding &&
      !check.allowedToCompleteGrinding;
  final completeAllowed =
      order != null &&
      check.allowedToCompleteGrinding &&
      check.status == GrindingStatus.inGrinding &&
      !check.allowedToStartGrinding;

  if (pending != null) {
    final sameOrder = order != null && pending.orderId == order.id;
    final stillAllowed =
        sameOrder &&
        switch (pending.command) {
          GrindingCommand.start => startAllowed,
          GrindingCommand.complete => completeAllowed,
        };
    if (stillAllowed) {
      return CommandOrderAction(
        command: pending.command,
        pending: pending,
        enabled: enabled,
        busy: busy,
      );
    }
    return ReconcileOrderAction(pending: pending, enabled: enabled, busy: busy);
  }

  if (startAllowed) {
    return CommandOrderAction(
      command: GrindingCommand.start,
      enabled: enabled,
      busy: busy,
    );
  }
  if (completeAllowed) {
    return CommandOrderAction(
      command: GrindingCommand.complete,
      enabled: enabled,
      busy: busy,
    );
  }
  return const NoOrderAction();
}

/// The pending record relevant to the order on screen:
///
/// 1. the record for the checked order's id (at most one per order); else
/// 2. an "orphan" record opened through the same number and the same
///    ROLL/PALLET answer whose order the number no longer resolves to (order
///    cancelled / replaced / not found). One grinding order exists per roll
///    or pallet, so such an order can no longer be in the state its command
///    needs — reconciling it can only replay or be rejected.
PendingCommand? selectPendingForCheck({
  required Iterable<PendingCommand> records,
  required String? identifier,
  required GrindingSourceType? chosenSourceType,
  required int? checkedOrderId,
}) {
  if (checkedOrderId != null) {
    for (final record in records) {
      if (record.orderId == checkedOrderId) return record;
    }
  }
  if (identifier == null) return null;
  for (final record in records) {
    if (record.identifier == identifier &&
        record.sourceType == chosenSourceType &&
        record.orderId != checkedOrderId) {
      return record;
    }
  }
  return null;
}
