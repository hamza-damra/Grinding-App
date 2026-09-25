import 'dart:async';

import 'package:flutter_grinding_app/core/errors/app_failure.dart';
import 'package:flutter_grinding_app/core/errors/error_codes.dart';
import 'package:flutter_grinding_app/features/grinding_auth/presentation/state/grinding_auth_controller.dart';
import 'package:flutter_grinding_app/features/grinding_orders/data/dtos/check_dtos.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/entities/execution_result.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/entities/grinding_order.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/entities/pending_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/order_action.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/check_resolution.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_source.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_status.dart';
import 'package:flutter_grinding_app/features/grinding_orders/presentation/state/current_order_controller.dart';
import 'package:flutter_grinding_app/features/grinding_orders/presentation/state/grinding_queue_controller.dart';
import 'package:flutter_grinding_app/features/grinding_orders/presentation/state/grinding_resume_coordinator.dart';
import 'package:flutter_grinding_app/features/grinding_orders/presentation/state/order_command_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_grinding_backend.dart';
import '../../support/test_harness.dart';

Future<ProviderContainer> _signedIn(GrindingTestHarness h) async {
  await h.signedIn(Fx.workerA);
  final c = h.container();
  c.listen(orderCommandControllerProvider, (_, _) {});
  await c.read(grindingAuthControllerProvider.future);
  await c.read(orderCommandControllerProvider.future);
  return c;
}

CurrentOrderController _orders(ProviderContainer c) =>
    c.read(currentOrderControllerProvider.notifier);

CurrentOrderState _order(ProviderContainer c) =>
    c.read(currentOrderControllerProvider);

/// Completes when the next request for [suffix] reaches the backend.
Future<void> _arrival(FakeGrindingBackend backend, String suffix) {
  final arrived = Completer<void>();
  final previous = backend.onRequest;
  backend.onRequest = (r) async {
    await previous?.call(r);
    if (r.path.endsWith(suffix) && !arrived.isCompleted) arrived.complete();
  };
  return arrived.future;
}

Future<void> _idle(ProviderContainer c) async {
  for (var i = 0; i < 300; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (!_order(c).isChecking) return;
  }
  fail('check never settled');
}

void main() {
  setUpAll(silenceNetworkLogs);

  group('CurrentOrderController', () {
    test('open → one /check with the identifier only', () async {
      final h = GrindingTestHarness();
      final c = await _signedIn(h);
      await _orders(c).open(Fx.readyNumber);
      final state = _order(c);
      expect(state.identifier, Fx.readyNumber);
      expect(state.usableCheck!.order!.id, Fx.readyId);
      expect(h.backend.requestsTo('/check').single.body, <String, dynamic>{
        'identifier': Fx.readyNumber,
      });
    });

    test('a duplicate scan while checking is ignored', () async {
      final h = GrindingTestHarness();
      final c = await _signedIn(h);
      final first = _orders(c).open(Fx.readyNumber);
      final second = _orders(c).open(Fx.readyNumber);
      await Future.wait(<Future<void>>[first, second]);
      expect(h.backend.requestsTo('/check'), hasLength(1));
    });

    test(
      'an older, slower /check response never overwrites a newer scan',
      () async {
        final h = GrindingTestHarness();
        final c = await _signedIn(h);
        final release = Completer<void>();
        h.backend.faults.add(
          FakeFault(
            FaultKind.hang,
            pathEndsWith: '/check',
            release: release,
            thenCommit: true,
          ),
        );
        final arrived = _arrival(h.backend, '/check');
        final slow = _orders(c).open(Fx.readyNumber);
        await arrived;
        await _orders(c).open(Fx.palletNumber);
        expect(_order(c).usableCheck!.order!.id, Fx.palletId);
        release.complete();
        await slow;
        expect(_order(c).identifier, Fx.palletNumber);
        expect(_order(c).usableCheck!.order!.id, Fx.palletId);
      },
    );

    test(
      'shared number, only the roll actionable → AUTO_RESOLVED, no question; '
      'the server\'s pick is pinned for every re-check',
      () async {
        final h = GrindingTestHarness();
        final c = await _signedIn(h);
        await _orders(c).open(Fx.sharedNumber);
        final state = _order(c);
        expect(state.ambiguity, isFalse);
        expect(state.usableCheck!.order!.id, Fx.sharedRollId);
        expect(state.usableCheck!.resolution, CheckResolution.autoResolved);
        expect(state.chosenSourceType, GrindingSourceType.roll);
        expect(state.sharedCandidates.map((c) => c.sourceType), <Object>[
          GrindingSourceType.roll,
          GrindingSourceType.pallet,
        ]);
        expect(
          resolveOrderAction(
            check: state.usableCheck,
            pending: null,
            inFlight: null,
            locked: false,
          ),
          isA<CommandOrderAction>().having(
            (a) => a.command,
            'command',
            GrindingCommand.start,
          ),
        );

        // The pallet becomes grindable too: a pinned refresh stays on the
        // roll the worker is looking at — no selection pops up mid-flow.
        h.backend.addOrder(
          id: 1099,
          identifier: Fx.sharedNumber,
          sourceType: 'PALLET',
          sourceOrigin: 'PALLETIZING_PALLET',
          directScrap: false,
        );
        await _orders(c).refresh();
        expect(_order(c).ambiguity, isFalse);
        expect(_order(c).usableCheck!.order!.id, Fx.sharedRollId);
        expect(_order(c).sharedCandidates, hasLength(2));
        expect(
          h.backend.requestsTo('/check').map((r) => r.body).toList(),
          <Map<String, dynamic>?>[
            <String, dynamic>{'identifier': Fx.sharedNumber},
            <String, dynamic>{
              'identifier': Fx.sharedNumber,
              'sourceType': 'ROLL',
            },
          ],
        );
      },
    );

    test('shared number, only the pallet actionable → the pallet', () async {
      final h = GrindingTestHarness(
        backend: seededBackend()..seedSharedNumbers(),
      );
      final c = await _signedIn(h);
      await _orders(c).open(Fx.palletActionableNumber);
      expect(_order(c).ambiguity, isFalse);
      expect(_order(c).usableCheck!.order!.id, Fx.palletActionableId);
      expect(_order(c).chosenSourceType, GrindingSourceType.pallet);
    });

    test('both actionable → ask with each item\'s action, never infer; the '
        'answer is reused for refresh', () async {
      final h = GrindingTestHarness(
        backend: seededBackend()..seedSharedNumbers(),
      );
      final c = await _signedIn(h);
      await _orders(c).open(Fx.bothActionableNumber);
      expect(_order(c).ambiguity, isTrue);
      expect(_order(c).check, isNull);
      expect(_order(c).usableCheck, isNull);
      final selection = _order(c).selection!;
      expect(selection.map((s) => s.sourceType), <Object>[
        GrindingSourceType.roll,
        GrindingSourceType.pallet,
      ]);
      // Different actions stay distinct.
      expect(selection[0].command, GrindingCommand.complete);
      expect(selection[1].command, GrindingCommand.start);
      expect(selection[1].orderNumber, 'GR-001049');

      await _orders(c).answerAmbiguity(GrindingSourceType.roll);
      expect(_order(c).ambiguity, isFalse);
      expect(_order(c).chosenSourceType, GrindingSourceType.roll);
      expect(_order(c).usableCheck!.order!.id, Fx.bothRollId);
      expect(_order(c).usableCheck!.allowedToCompleteGrinding, isTrue);

      await _orders(c).refresh();
      final bodies = h.backend.requestsTo('/check').map((r) => r.body).toList();
      expect(bodies, <Map<String, dynamic>?>[
        <String, dynamic>{'identifier': Fx.bothActionableNumber},
        <String, dynamic>{
          'identifier': Fx.bothActionableNumber,
          'sourceType': 'ROLL',
        },
        <String, dynamic>{
          'identifier': Fx.bothActionableNumber,
          'sourceType': 'ROLL',
        },
      ]);
    });

    test('answering PALLET opens the pallet\'s READY order', () async {
      final h = GrindingTestHarness(
        backend: seededBackend()..seedSharedNumbers(),
      );
      final c = await _signedIn(h);
      await _orders(c).open(Fx.bothActionableNumber);
      await _orders(c).answerAmbiguity(GrindingSourceType.pallet);
      expect(_order(c).usableCheck!.order!.id, Fx.bothPalletId);
      expect(_order(c).usableCheck!.allowedToStartGrinding, isTrue);
      expect(h.backend.requestsTo('/check').last.body, <String, dynamic>{
        'identifier': Fx.bothActionableNumber,
        'sourceType': 'PALLET',
      });
    });

    test('a 409 without readable candidates still asks (older backend)', () {
      final candidates = CheckCandidateDto.listFromJson(<Object?>[
        <String, dynamic>{'sourceType': 'ROLL', 'label': 'رول'},
        <String, dynamic>{'sourceType': 'PALLET', 'label': 'طبلية'},
        <String, dynamic>{'sourceType': 'SOMETHING_NEW'},
        'garbage',
      ]);
      expect(candidates.map((c) => c.sourceType), <Object>[
        GrindingSourceType.roll,
        GrindingSourceType.pallet,
      ]);
      expect(candidates.every((c) => c.command == null), isTrue);
      expect(candidates.every((c) => c.displayStatusLabel == null), isTrue);
    });

    test('neither actionable → NOT_ELIGIBLE for the number, both states, no '
        'action, nothing pinned', () async {
      final h = GrindingTestHarness(
        backend: seededBackend()..seedSharedNumbers(),
      );
      final c = await _signedIn(h);
      await _orders(c).open(Fx.noneActionableNumber);
      final state = _order(c);
      expect(state.ambiguity, isFalse);
      final check = state.usableCheck!;
      expect(check.status, GrindingStatus.notEligible);
      expect(check.resolution, CheckResolution.noneActionable);
      expect(check.sourceType, GrindingSourceType.unknown);
      expect(check.order, isNull);
      expect(check.candidates.map((c) => c.status), <Object>[
        GrindingStatus.pendingApproval,
        GrindingStatus.completed,
      ]);
      expect(state.chosenSourceType, isNull);
      expect(
        resolveOrderAction(
          check: check,
          pending: null,
          inFlight: null,
          locked: false,
        ),
        isA<NoOrderAction>(),
      );
    });

    test('both items without an order → NOT_ELIGIBLE, no question', () async {
      final h = GrindingTestHarness(
        backend: seededBackend()..seedSharedNumbers(),
      );
      final c = await _signedIn(h);
      await _orders(c).open(Fx.sharedNoOrderNumber);
      expect(_order(c).ambiguity, isFalse);
      expect(_order(c).usableCheck!.status, GrindingStatus.notEligible);
      expect(_order(c).usableCheck!.candidates, hasLength(2));
    });

    test('a REJECTED roll order never competes with a READY pallet', () async {
      final h = GrindingTestHarness(
        backend: seededBackend()..seedSharedNumbers(),
      );
      final c = await _signedIn(h);
      await _orders(c).open(Fx.rejectedRollNumber);
      expect(_order(c).ambiguity, isFalse);
      expect(_order(c).usableCheck!.order!.id, Fx.rejectedPalletReadyId);
      expect(_order(c).usableCheck!.allowedToStartGrinding, isTrue);
    });

    test(
      'a duplicate scan of a shared number while checking is ignored',
      () async {
        final h = GrindingTestHarness(
          backend: seededBackend()..seedSharedNumbers(),
        );
        final c = await _signedIn(h);
        await Future.wait(<Future<void>>[
          _orders(c).open(Fx.bothActionableNumber),
          _orders(c).open(Fx.bothActionableNumber),
        ]);
        expect(h.backend.requestsTo('/check'), hasLength(1));
        expect(_order(c).ambiguity, isTrue);
      },
    );

    test('unknown number → definitively rejected check', () async {
      final h = GrindingTestHarness();
      final c = await _signedIn(h);
      await _orders(c).open(Fx.unknownNumber);
      final state = _order(c);
      expect(
        state.check!.error,
        isA<ApiFailure>().having(
          (f) => f.code,
          'code',
          ErrorCodes.sourceNotFound,
        ),
      );
      expect(state.checkRejected, isTrue);
      expect(state.usableCheck, isNull);
    });

    test('a transient check failure is not a rejection', () async {
      final h = GrindingTestHarness();
      final c = await _signedIn(h);
      h.backend.faults.add(
        FakeFault(FaultKind.connectionError, pathEndsWith: '/check', times: 2),
      );
      await _orders(c).open(Fx.readyNumber);
      expect(_order(c).check!.error, const AppFailure.network());
      expect(_order(c).checkRejected, isFalse);
    });

    test('refresh keeps the card visible while the gate is locked', () async {
      final h = GrindingTestHarness();
      final c = await _signedIn(h);
      await _orders(c).open(Fx.readyNumber);
      final release = Completer<void>();
      h.backend.faults.add(
        FakeFault(
          FaultKind.hang,
          pathEndsWith: '/check',
          release: release,
          thenCommit: true,
        ),
      );
      final refreshing = _orders(c).refresh();
      expect(_order(c).isChecking, isTrue);
      expect(_order(c).displayOrder!.id, Fx.readyId);
      release.complete();
      await refreshing;
    });

    test('applyExecutionResult drops the old gates and re-checks', () async {
      final h = GrindingTestHarness();
      final c = await _signedIn(h);
      await _orders(c).open(Fx.readyNumber);
      final serverOrder = _order(c).usableCheck!.order!;
      _orders(c).applyExecutionResult(
        orderId: Fx.readyId,
        command: GrindingCommand.start,
        result: _executed(serverOrder),
      );
      final state = _order(c);
      expect(state.success, GrindingCommand.start);
      expect(state.usableCheck, isNull, reason: 'old gate must not be reused');
      expect(state.displayOrder, isNotNull);
      await _idle(c);
      expect(h.backend.requestsTo('/check'), hasLength(2));
    });

    test('a result for another order is ignored', () async {
      final h = GrindingTestHarness();
      final c = await _signedIn(h);
      await _orders(c).open(Fx.readyNumber);
      final other = _order(c).usableCheck!.order!;
      _orders(c).applyExecutionResult(
        orderId: 99,
        command: GrindingCommand.start,
        result: _executed(other),
      );
      expect(_order(c).success, isNull);
    });

    test('logout resets the opened order', () async {
      final h = GrindingTestHarness();
      final c = await _signedIn(h);
      c.listen(currentOrderControllerProvider, (_, _) {});
      await _orders(c).open(Fx.readyNumber);
      await c.read(grindingAuthControllerProvider.notifier).logout();
      expect(_order(c).isOpen, isFalse);
    });
  });

  group('queues', () {
    test('READY and IN_GRINDING lists, oldest first', () async {
      final h = GrindingTestHarness();
      final c = await _signedIn(h);
      final ready = await c.read(
        grindingQueueProvider(GrindingQueueStatus.ready).future,
      );
      final grinding = await c.read(
        grindingQueueProvider(GrindingQueueStatus.inGrinding).future,
      );
      expect(ready.map((o) => o.id), <int>[
        Fx.readyId,
        Fx.palletId,
        Fx.sharedRollId,
      ]);
      expect(grinding.map((o) => o.id), <int>[Fx.inGrindingId]);
    });

    test('pull-to-refresh failure keeps the rows on screen', () async {
      final h = GrindingTestHarness();
      final c = await _signedIn(h);
      final provider = grindingQueueProvider(GrindingQueueStatus.ready);
      c.listen(provider, (_, _) {});
      await c.read(provider.future);
      h.backend.faults.add(
        FakeFault(FaultKind.connectionError, pathEndsWith: '/orders', times: 2),
      );
      await c.read(provider.notifier).refresh();
      final value = c.read(provider);
      expect(value.hasError, isTrue);
      expect(value.valueOrNull, hasLength(3));
    });
  });

  group('resume coordinator (contract §11 "App resumed")', () {
    test(
      'verifies the session, re-checks the open order, refreshes queues',
      () async {
        final h = GrindingTestHarness();
        final c = await _signedIn(h);
        c.listen(grindingResumeCoordinatorProvider, (_, _) {});
        c.listen(currentOrderControllerProvider, (_, _) {});
        final queue = grindingQueueProvider(GrindingQueueStatus.ready);
        c.listen(queue, (_, _) {});
        await c.read(queue.future);
        await _orders(c).open(Fx.readyNumber);
        h.backend.requests.clear();

        await c.read(grindingResumeCoordinatorProvider.notifier).onResume();
        await _idle(c);
        await c.read(queue.future);

        final paths = h.backend.requests.map((r) => r.path).toList();
        expect(paths.first, endsWith('/sessions/me'));
        expect(paths.where((p) => p.endsWith('/check')), hasLength(1));
        expect(paths.where((p) => p.endsWith('/orders')), hasLength(1));
        expect(h.backend.commandRequests, isEmpty);
      },
    );

    test('never sends a pending command', () async {
      final h = GrindingTestHarness();
      h.memoryPending.records['pending_1042_start'] = const PendingCommand(
        orderId: Fx.readyId,
        orderNumber: 'GR-001042',
        identifier: Fx.readyNumber,
        command: GrindingCommand.start,
        clientRequestId: 'kept',
        workerOperatorId: Fx.workerA,
        workerName: Fx.workerAName,
        createdAt: '2026-09-22T09:00:00.000Z',
      );
      final c = await _signedIn(h);
      c.listen(grindingResumeCoordinatorProvider, (_, _) {});
      await _orders(c).open(Fx.readyNumber);
      await c.read(grindingResumeCoordinatorProvider.notifier).onResume();
      await _idle(c);
      expect(h.backend.commandRequests, isEmpty);
    });

    test('skips re-checking an order whose command is in flight', () async {
      final h = GrindingTestHarness();
      final c = await _signedIn(h);
      c.listen(grindingResumeCoordinatorProvider, (_, _) {});
      c.listen(currentOrderControllerProvider, (_, _) {});
      await _orders(c).open(Fx.readyNumber);
      final release = Completer<void>();
      h.backend.faults.add(
        FakeFault(
          FaultKind.hang,
          pathEndsWith: '/start',
          release: release,
          thenCommit: true,
        ),
      );
      final arrived = _arrival(h.backend, '/start');
      final command = c
          .read(orderCommandControllerProvider.notifier)
          .run(
            command: GrindingCommand.start,
            orderId: Fx.readyId,
            orderNumber: 'GR-001042',
            identifier: Fx.readyNumber,
          );
      await arrived;
      final checksBefore = h.backend.requestsTo('/check').length;
      await c.read(grindingResumeCoordinatorProvider.notifier).onResume();
      expect(h.backend.requestsTo('/check'), hasLength(checksBefore));
      release.complete();
      await command;
    });

    test('a burst of resumes is single-flight', () async {
      final h = GrindingTestHarness();
      final c = await _signedIn(h);
      c.listen(grindingResumeCoordinatorProvider, (_, _) {});
      h.backend.requests.clear();
      final coordinator = c.read(grindingResumeCoordinatorProvider.notifier);
      await Future.wait(<Future<void>>[
        coordinator.onResume(),
        coordinator.onResume(),
        coordinator.onResume(),
      ]);
      expect(h.backend.requestsTo('/sessions/me'), hasLength(1));
    });
  });
}

/// The server's answer to a START (display only; never fabricated in the app).
ExecutionResult _executed(GrindingOrder order) =>
    ExecutionResult(order: order, replayed: false);
