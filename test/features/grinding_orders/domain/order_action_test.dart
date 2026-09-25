import 'package:flutter_grinding_app/features/grinding_orders/domain/entities/check_result.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/entities/grinding_order.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/entities/pending_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/order_action.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_source.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_status.dart';
import 'package:flutter_test/flutter_test.dart';

GrindingOrder _order(GrindingStatus status, {int id = 1042}) => GrindingOrder(
  id: id,
  orderNumber: 'GR-001042',
  status: status,
  statusRaw: status.wire,
  sourceType: GrindingSourceType.roll,
  sourceOrigin: GrindingSourceOrigin.rollProductionScrap,
  sourceIdentifier: '001000000255',
  directScrap: true,
  legacy: false,
);

CheckResult _check(
  GrindingStatus status, {
  bool start = false,
  bool complete = false,
  bool withOrder = true,
  int orderId = 1042,
}) => CheckResult(
  identifier: '001000000255',
  sourceType: GrindingSourceType.roll,
  status: status,
  statusRaw: status.wire,
  allowedToStartGrinding: start,
  allowedToCompleteGrinding: complete,
  order: withOrder ? _order(status, id: orderId) : null,
);

PendingCommand _pending(
  GrindingCommand command, {
  int orderId = 1042,
  String identifier = '001000000255',
  GrindingSourceType? sourceType,
}) => PendingCommand(
  orderId: orderId,
  orderNumber: 'GR-001042',
  identifier: identifier,
  sourceType: sourceType,
  command: command,
  clientRequestId: 'cid-1',
  workerOperatorId: 57,
  workerName: 'محمد أحمد',
  createdAt: '2026-09-22T09:41:07.312Z',
);

OrderAction _resolve(
  CheckResult? check, {
  PendingCommand? pending,
  GrindingCommand? inFlight,
  bool locked = false,
  bool checkRejected = false,
}) => resolveOrderAction(
  check: check,
  pending: pending,
  inFlight: inFlight,
  locked: locked,
  checkRejected: checkRejected,
);

void main() {
  group('status → action (contract §4.2 table, all 5 statuses)', () {
    test('READY_FOR_GRINDING + allowedToStart → «بدء الجرش»', () {
      final action = _resolve(
        _check(GrindingStatus.readyForGrinding, start: true),
      );
      expect(action, isA<CommandOrderAction>());
      action as CommandOrderAction;
      expect(action.command, GrindingCommand.start);
      expect(action.enabled, isTrue);
      expect(action.pending, isNull);
    });

    test('IN_GRINDING + allowedToComplete → «تأكيد انتهاء الجرش»', () {
      final action = _resolve(
        _check(GrindingStatus.inGrinding, complete: true),
      );
      expect(action, isA<CommandOrderAction>());
      expect((action as CommandOrderAction).command, GrindingCommand.complete);
    });

    test('PENDING_APPROVAL → no action (even if a flag lied)', () {
      expect(
        _resolve(_check(GrindingStatus.pendingApproval)),
        isA<NoOrderAction>(),
      );
      expect(
        _resolve(_check(GrindingStatus.pendingApproval, start: true)),
        isA<NoOrderAction>(),
      );
    });

    test('COMPLETED → no action', () {
      expect(_resolve(_check(GrindingStatus.completed)), isA<NoOrderAction>());
    });

    test('NOT_ELIGIBLE (no order) → no action', () {
      expect(
        _resolve(_check(GrindingStatus.notEligible, withOrder: false)),
        isA<NoOrderAction>(),
      );
    });

    test('REJECTED / CANCELLED / unknown → no action', () {
      for (final status in <GrindingStatus>[
        GrindingStatus.rejected,
        GrindingStatus.cancelled,
        GrindingStatus.unknown,
      ]) {
        expect(
          _resolve(_check(status, start: true)),
          isA<NoOrderAction>(),
          reason: status.name,
        );
      }
    });
  });

  group('the booleans are the final gate', () {
    test('READY without allowedToStart → no action', () {
      expect(
        _resolve(_check(GrindingStatus.readyForGrinding)),
        isA<NoOrderAction>(),
      );
    });

    test('both flags true → no action (contradictory answer)', () {
      expect(
        _resolve(
          _check(GrindingStatus.readyForGrinding, start: true, complete: true),
        ),
        isA<NoOrderAction>(),
      );
      expect(
        _resolve(
          _check(GrindingStatus.inGrinding, start: true, complete: true),
        ),
        isA<NoOrderAction>(),
      );
    });

    test('flag for the other status → no action', () {
      expect(
        _resolve(_check(GrindingStatus.inGrinding, start: true)),
        isA<NoOrderAction>(),
      );
      expect(
        _resolve(_check(GrindingStatus.readyForGrinding, complete: true)),
        isA<NoOrderAction>(),
      );
    });

    test('no successful check → no action', () {
      expect(_resolve(null), isA<NoOrderAction>());
    });
  });

  group('busy / locked', () {
    test('in flight → visible, disabled, spinner', () {
      final action =
          _resolve(
                _check(GrindingStatus.readyForGrinding, start: true),
                inFlight: GrindingCommand.start,
              )
              as CommandOrderAction;
      expect(action.enabled, isFalse);
      expect(action.busy, isTrue);
    });

    test('locked (check refreshing / records loading) → disabled', () {
      final action =
          _resolve(
                _check(GrindingStatus.readyForGrinding, start: true),
                locked: true,
              )
              as CommandOrderAction;
      expect(action.enabled, isFalse);
      expect(action.busy, isFalse);
    });
  });

  group('pending record wins', () {
    test('START pending, order still READY → START with the same record', () {
      final pending = _pending(GrindingCommand.start);
      final action =
          _resolve(
                _check(GrindingStatus.readyForGrinding, start: true),
                pending: pending,
              )
              as CommandOrderAction;
      expect(action.command, GrindingCommand.start);
      expect(action.pending, same(pending));
    });

    test(
      'START pending, order now IN_GRINDING → reconcile, never COMPLETE',
      () {
        final action = _resolve(
          _check(GrindingStatus.inGrinding, complete: true),
          pending: _pending(GrindingCommand.start),
        );
        expect(action, isA<ReconcileOrderAction>());
        expect(
          (action as ReconcileOrderAction).pending.command,
          GrindingCommand.start,
        );
      },
    );

    test('COMPLETE pending, order still IN_GRINDING → COMPLETE, same id', () {
      final pending = _pending(GrindingCommand.complete);
      final action =
          _resolve(
                _check(GrindingStatus.inGrinding, complete: true),
                pending: pending,
              )
              as CommandOrderAction;
      expect(action.command, GrindingCommand.complete);
      expect(action.pending, same(pending));
    });

    test('COMPLETE pending, order now COMPLETED → reconcile', () {
      expect(
        _resolve(
          _check(GrindingStatus.completed),
          pending: _pending(GrindingCommand.complete),
        ),
        isA<ReconcileOrderAction>(),
      );
    });

    test(
      'pending for an order the number no longer resolves to → reconcile',
      () {
        expect(
          _resolve(
            _check(GrindingStatus.notEligible, withOrder: false),
            pending: _pending(GrindingCommand.start),
          ),
          isA<ReconcileOrderAction>(),
        );
      },
    );

    test('check rejected (4xx) with a pending record → reconcile only', () {
      expect(
        _resolve(
          null,
          pending: _pending(GrindingCommand.start),
          checkRejected: true,
        ),
        isA<ReconcileOrderAction>(),
      );
      expect(_resolve(null, checkRejected: true), isA<NoOrderAction>());
      expect(
        _resolve(null, pending: _pending(GrindingCommand.start)),
        isA<NoOrderAction>(),
        reason: 'a transient check failure never offers a send',
      );
    });

    test('reconcile is disabled while locked or in flight', () {
      final locked =
          _resolve(
                _check(GrindingStatus.completed),
                pending: _pending(GrindingCommand.complete),
                locked: true,
              )
              as ReconcileOrderAction;
      expect(locked.enabled, isFalse);
      final busy =
          _resolve(
                _check(GrindingStatus.completed),
                pending: _pending(GrindingCommand.complete),
                inFlight: GrindingCommand.complete,
              )
              as ReconcileOrderAction;
      expect(busy.enabled, isFalse);
      expect(busy.busy, isTrue);
    });
  });

  group('selectPendingForCheck', () {
    final forOrder = _pending(GrindingCommand.start);
    final orphanRoll = _pending(
      GrindingCommand.start,
      orderId: 900,
      identifier: '001000000293',
      sourceType: GrindingSourceType.roll,
    );

    test('matches by the checked order id first', () {
      expect(
        selectPendingForCheck(
          records: <PendingCommand>[orphanRoll, forOrder],
          identifier: '001000000255',
          chosenSourceType: null,
          checkedOrderId: 1042,
        ),
        same(forOrder),
      );
    });

    test('orphan: same number + same ROLL/PALLET answer', () {
      expect(
        selectPendingForCheck(
          records: <PendingCommand>[orphanRoll],
          identifier: '001000000293',
          chosenSourceType: GrindingSourceType.roll,
          checkedOrderId: null,
        ),
        same(orphanRoll),
      );
    });

    test('a different ROLL/PALLET answer never matches an orphan', () {
      expect(
        selectPendingForCheck(
          records: <PendingCommand>[orphanRoll],
          identifier: '001000000293',
          chosenSourceType: GrindingSourceType.pallet,
          checkedOrderId: null,
        ),
        isNull,
      );
    });

    test('nothing opened → nothing selected', () {
      expect(
        selectPendingForCheck(
          records: <PendingCommand>[forOrder],
          identifier: null,
          chosenSourceType: null,
          checkedOrderId: null,
        ),
        isNull,
      );
    });
  });
}
