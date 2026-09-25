import 'dart:async';
import 'dart:io';

import 'package:flutter_grinding_app/core/auth/auth_session.dart';
import 'package:flutter_grinding_app/core/errors/app_failure.dart';
import 'package:flutter_grinding_app/core/errors/error_codes.dart';
import 'package:flutter_grinding_app/core/storage/durable_file_store.dart';
import 'package:flutter_grinding_app/features/grinding_auth/presentation/state/grinding_auth_controller.dart';
import 'package:flutter_grinding_app/features/grinding_auth/presentation/state/grinding_auth_state.dart';
import 'package:flutter_grinding_app/features/grinding_auth/presentation/state/session_invalidation_listener.dart';
import 'package:flutter_grinding_app/features/grinding_orders/data/file_pending_command_store.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/entities/pending_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/order_action.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_status.dart';
import 'package:flutter_grinding_app/features/grinding_orders/presentation/state/current_order_controller.dart';
import 'package:flutter_grinding_app/features/grinding_orders/presentation/state/order_command_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_grinding_backend.dart';
import '../../support/test_harness.dart';

PendingCommand _record({
  required int orderId,
  required GrindingCommand command,
  required String id,
  String identifier = Fx.readyNumber,
  int worker = Fx.workerA,
  String workerName = Fx.workerAName,
}) => PendingCommand(
  orderId: orderId,
  orderNumber: 'GR-${orderId.toString().padLeft(6, '0')}',
  identifier: identifier,
  command: command,
  clientRequestId: id,
  workerOperatorId: worker,
  workerName: workerName,
  createdAt: '2026-09-22T09:00:00.000Z',
);

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Waits until the current order is no longer being re-checked.
Future<void> _checkIdle(ProviderContainer c) async {
  await _settle();
  for (var i = 0; i < 200; i++) {
    if (!c.read(currentOrderControllerProvider).isChecking) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('the re-check never completed');
}

/// Signed-in container with the command store loaded and [identifier] open.
Future<ProviderContainer> _ready(
  GrindingTestHarness h, {
  String identifier = Fx.readyNumber,
  int worker = Fx.workerA,
}) async {
  await h.signedIn(worker);
  final c = h.container();
  c.listen(sessionInvalidationListenerProvider, (_, _) {});
  c.listen(orderCommandControllerProvider, (_, _) {});
  await c.read(grindingAuthControllerProvider.future);
  await c.read(orderCommandControllerProvider.future);
  await c.read(currentOrderControllerProvider.notifier).open(identifier);
  return c;
}

Future<CommandOutcome> _run(
  ProviderContainer c,
  GrindingCommand command, {
  int orderId = Fx.readyId,
  bool reconcile = false,
}) {
  final order = c.read(currentOrderControllerProvider);
  return c
      .read(orderCommandControllerProvider.notifier)
      .run(
        command: command,
        orderId: orderId,
        orderNumber: 'GR-${orderId.toString().padLeft(6, '0')}',
        identifier: order.identifier!,
        reconcile: reconcile,
      );
}

OrderCommandState _commands(ProviderContainer c) =>
    c.read(orderCommandControllerProvider).requireValue;

void main() {
  setUpAll(silenceNetworkLogs);

  group('clientRequestId lifecycle (contract §4.4)', () {
    test(
      'minted on tap, persisted BEFORE the request, cleared on 2xx',
      () async {
        final h = GrindingTestHarness();
        final c = await _ready(h);
        String? persistedAtSend;
        h.backend.onRequest = (r) async {
          if (r.path.endsWith('/start')) {
            persistedAtSend = h
                .memoryPending
                .records[PendingCommand.keyFor(
                  Fx.readyId,
                  GrindingCommand.start,
                )]
                ?.clientRequestId;
          }
        };

        final outcome = await _run(c, GrindingCommand.start);

        expect(outcome.kind, CommandOutcomeKind.success);
        expect(h.ids.calls, 1);
        final sent = h.backend.commandRequests.single;
        expect(sent.clientRequestId, 'cid-1');
        expect(persistedAtSend, 'cid-1', reason: 'record on disk before send');
        expect(h.memoryPending.log, <String>[
          'save:pending_1042_start:cid-1',
          'remove:pending_1042_start',
        ]);
        expect(_commands(c).pending, isEmpty);
        expect(h.backend.orders[Fx.readyId]!.status, 'IN_GRINDING');
      },
    );

    test('a failed persist sends NOTHING', () async {
      final h = GrindingTestHarness();
      final c = await _ready(h);
      h.memoryPending.failSaves = true;
      final outcome = await _run(c, GrindingCommand.start);
      expect(outcome.kind, CommandOutcomeKind.notPersisted);
      expect(h.backend.commandRequests, isEmpty);
      expect(_commands(c).pending, isEmpty);
    });

    test(
      'network loss: 3 automatic retries with the SAME id, then manual retry',
      () async {
        final h = GrindingTestHarness();
        final c = await _ready(h);
        h.backend.faults.add(
          FakeFault(
            FaultKind.connectionError,
            pathEndsWith: '/start',
            times: 4,
          ),
        );

        final first = await _run(c, GrindingCommand.start);
        expect(first.kind, CommandOutcomeKind.networkLost);
        expect(
          h.backend.commandRequests,
          hasLength(4),
          reason: '1 + 3 retries',
        );
        expect(
          h.backend.commandRequests.map((r) => r.clientRequestId).toSet(),
          <String>{'cid-1'},
        );
        final key = PendingCommand.keyFor(Fx.readyId, GrindingCommand.start);
        expect(_commands(c).pending[key]?.clientRequestId, 'cid-1');
        expect(_commands(c).failures[key], isNotNull);

        // «إعادة المحاولة»: same id again, no new mint.
        final retry = await _run(c, GrindingCommand.start);
        expect(retry.kind, CommandOutcomeKind.success);
        expect(h.backend.commandRequests.last.clientRequestId, 'cid-1');
        expect(h.ids.calls, 1);
        expect(_commands(c).pending, isEmpty);
        expect(_commands(c).failures, isEmpty);
      },
    );

    test(
      'lost response after commit → retry → replayed:true → one transition',
      () async {
        final h = GrindingTestHarness();
        final c = await _ready(h);
        h.backend.faults.add(
          FakeFault(FaultKind.lostResponseAfterCommit, pathEndsWith: '/start'),
        );
        final outcome = await _run(c, GrindingCommand.start);
        expect(outcome.kind, CommandOutcomeKind.success);
        expect(outcome.result!.replayed, isTrue);
        expect(h.backend.commandRequests, hasLength(2));
        expect(
          h.backend.commandRequests.map((r) => r.clientRequestId).toSet(),
          <String>{'cid-1'},
        );
        expect(h.backend.transitionsFor(Fx.readyId), 1);
        expect(_commands(c).pending, isEmpty);
      },
    );

    test('timeouts and 5xx are retried with the same id too', () async {
      final h = GrindingTestHarness();
      final c = await _ready(h);
      h.backend.faults
        ..add(FakeFault(FaultKind.receiveTimeout, pathEndsWith: '/start'))
        ..add(FakeFault(FaultKind.serverError, pathEndsWith: '/start'));
      final outcome = await _run(c, GrindingCommand.start);
      expect(outcome.kind, CommandOutcomeKind.success);
      expect(h.backend.commandRequests, hasLength(3));
      expect(
        h.backend.commandRequests.map((r) => r.clientRequestId).toSet(),
        hasLength(1),
      );
    });

    test(
      'definitive 4xx (someone else started it) → cleared, business error',
      () async {
        final h = GrindingTestHarness();
        final c = await _ready(h);
        h.backend.orders[Fx.readyId]!.status = 'IN_GRINDING';
        final outcome = await _run(c, GrindingCommand.start);
        expect(outcome.kind, CommandOutcomeKind.businessError);
        expect(
          outcome.failure,
          isA<ApiFailure>().having(
            (f) => f.code,
            'code',
            ErrorCodes.orderNotReady,
          ),
        );
        expect(h.backend.commandRequests, hasLength(1));
        expect(_commands(c).pending, isEmpty);
        expect(h.memoryPending.records, isEmpty);
      },
    );

    test(
      'captive portal 200 / device rejection keep the record, no auto-resend',
      () async {
        for (final kind in <FaultKind>[
          FaultKind.captivePortal,
          FaultKind.deviceUnauthorized,
        ]) {
          final h = GrindingTestHarness();
          final c = await _ready(h);
          h.backend.faults.add(FakeFault(kind, pathEndsWith: '/start'));
          final outcome = await _run(c, GrindingCommand.start);
          expect(outcome.kind, CommandOutcomeKind.failed, reason: kind.name);
          expect(h.backend.commandRequests, hasLength(1), reason: kind.name);
          expect(_commands(c).pending, hasLength(1), reason: kind.name);
        }
      },
    );

    test('an existing record is reused — never a second id', () async {
      final h = GrindingTestHarness();
      h.memoryPending.records['pending_1042_start'] = _record(
        orderId: Fx.readyId,
        command: GrindingCommand.start,
        id: 'persisted-before-restart',
      );
      final c = await _ready(h);
      final outcome = await _run(c, GrindingCommand.start);
      expect(outcome.kind, CommandOutcomeKind.success);
      expect(h.ids.calls, 0);
      expect(
        h.backend.commandRequests.single.clientRequestId,
        'persisted-before-restart',
      );
    });

    test('the default generator mints UUID v4', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final next = c.read(clientRequestIdGeneratorProvider);
      final a = next();
      final b = next();
      final v4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(a, matches(v4));
      expect(b, matches(v4));
      expect(a, isNot(b));
      expect(a.length, lessThanOrEqualTo(64));
    });
  });

  group('double tap / stale gates', () {
    test(
      'a second tap while in flight mints nothing and sends nothing',
      () async {
        final h = GrindingTestHarness();
        final c = await _ready(h);
        final release = Completer<void>();
        h.backend.faults.add(
          FakeFault(
            FaultKind.hang,
            pathEndsWith: '/start',
            release: release,
            thenCommit: true,
          ),
        );
        final first = _run(c, GrindingCommand.start);
        await _settle();
        expect(
          _commands(c).inFlightForOrder(Fx.readyId),
          GrindingCommand.start,
        );
        final second = await _run(c, GrindingCommand.start);
        expect(second.kind, CommandOutcomeKind.ignored);
        release.complete();
        expect((await first).kind, CommandOutcomeKind.success);
        expect(h.ids.calls, 1);
        expect(h.backend.commandRequests, hasLength(1));
      },
    );

    test('a tap before pending records are loaded cannot mint', () async {
      final h = GrindingTestHarness();
      h.memoryPending.loadGate = Completer<void>();
      await h.signedIn(Fx.workerA);
      final c = h.container();
      c.listen(orderCommandControllerProvider, (_, _) {});
      await c.read(grindingAuthControllerProvider.future);
      await c
          .read(currentOrderControllerProvider.notifier)
          .open(Fx.readyNumber);
      expect(c.read(orderCommandControllerProvider).isLoading, isTrue);

      final outcome = await _run(c, GrindingCommand.start);
      expect(outcome.kind, CommandOutcomeKind.ignored);
      expect(h.ids.calls, 0);
      expect(h.backend.commandRequests, isEmpty);
      h.memoryPending.loadGate!.complete();
    });

    test(
      'COMPLETE on a READY order (stale dialog) is refused locally',
      () async {
        final h = GrindingTestHarness();
        final c = await _ready(h);
        final outcome = await _run(c, GrindingCommand.complete);
        expect(outcome.kind, CommandOutcomeKind.ignored);
        expect(h.ids.calls, 0);
        expect(h.backend.commandRequests, isEmpty);
      },
    );

    test('a tap for another order than the one on screen is refused', () async {
      final h = GrindingTestHarness();
      final c = await _ready(h);
      final outcome = await _run(
        c,
        GrindingCommand.start,
        orderId: Fx.palletId,
      );
      expect(outcome.kind, CommandOutcomeKind.ignored);
      expect(h.backend.commandRequests, isEmpty);
    });

    test('while the check is refreshing the gate is closed', () async {
      final h = GrindingTestHarness();
      final c = await _ready(h);
      final release = Completer<void>();
      h.backend.faults.add(
        FakeFault(
          FaultKind.hang,
          pathEndsWith: '/check',
          release: release,
          thenCommit: true,
        ),
      );
      final refresh = c.read(currentOrderControllerProvider.notifier).refresh();
      await _settle();
      final outcome = await _run(c, GrindingCommand.start);
      expect(outcome.kind, CommandOutcomeKind.ignored);
      release.complete();
      await refresh;
    });
  });

  group('session changes (cross-worker safety)', () {
    test(
      'session expired mid-command → record kept, PIN, nothing resent',
      () async {
        final h = GrindingTestHarness();
        final c = await _ready(h);
        h.backend.expireSession(h.backend.activeTokenFor(Fx.workerA)!);
        final outcome = await _run(c, GrindingCommand.start);
        expect(outcome.kind, CommandOutcomeKind.sessionEnded);
        await _settle();
        expect(
          c.read(grindingAuthControllerProvider).valueOrNull,
          isA<GrindingAuthUnauthenticated>(),
        );
        expect(h.memoryPending.records.keys, <String>['pending_1042_start']);
        expect(h.backend.commandRequests, hasLength(1));
      },
    );

    test(
      'logout during the retry backoff stops the loop; B never sends A’s id',
      () async {
        final h = GrindingTestHarness(
          backoff: const <Duration>[Duration(milliseconds: 200)],
        );
        final c = await _ready(h);
        final firstAttempt = Completer<void>();
        h.backend.onRequest = (r) async {
          if (r.path.endsWith('/start') && !firstAttempt.isCompleted) {
            firstAttempt.complete();
          }
        };
        h.backend.faults.add(
          FakeFault(
            FaultKind.connectionError,
            pathEndsWith: '/start',
            times: 9,
          ),
        );
        final running = _run(c, GrindingCommand.start);
        await firstAttempt.future;
        await _settle();

        final auth = c.read(grindingAuthControllerProvider.notifier);
        await auth.logout();
        await auth.login(Fx.pinB);

        expect((await running).kind, CommandOutcomeKind.aborted);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(h.backend.commandRequests, hasLength(1));
        final tokenA = h.backend.commandRequests.single.sessionToken;
        expect(tokenA, isNot(c.read(authSessionProvider).token));
        // Kept for an explicit, confirmed resend.
        expect(h.memoryPending.records.keys, <String>['pending_1042_start']);
        expect(_commands(c).failures, isEmpty);
      },
    );

    test(
      'a new worker sees the record but nothing is sent automatically',
      () async {
        final h = GrindingTestHarness();
        h.memoryPending.records['pending_1042_start'] = _record(
          orderId: Fx.readyId,
          command: GrindingCommand.start,
          id: 'id-of-worker-a',
        );
        final c = await _ready(h, worker: Fx.workerB);
        await _settle();
        expect(_commands(c).pending.keys, <String>['pending_1042_start']);
        expect(h.backend.commandRequests, isEmpty);

        // Worker B explicitly confirms → the SAME id is sent.
        final outcome = await _run(c, GrindingCommand.start);
        expect(outcome.kind, CommandOutcomeKind.success);
        expect(
          h.backend.commandRequests.single.clientRequestId,
          'id-of-worker-a',
        );
        expect(h.ids.calls, 0);
      },
    );
  });

  group('reconcile «تحقق من الطلب السابق»', () {
    test(
      'START committed before a kill → order IN_GRINDING → replayed, cleared',
      () async {
        final h = GrindingTestHarness();
        h.backend.orders[Fx.readyId]!.status = 'IN_GRINDING';
        h.backend.seedIdempotency('lost-id', Fx.readyId, 'START');
        h.memoryPending.records['pending_1042_start'] = _record(
          orderId: Fx.readyId,
          command: GrindingCommand.start,
          id: 'lost-id',
        );
        final c = await _ready(h);

        final order = c.read(currentOrderControllerProvider);
        final action = resolveOrderAction(
          check: order.usableCheck,
          pending: selectPendingForCheck(
            records: _commands(c).pending.values,
            identifier: order.identifier,
            chosenSourceType: order.chosenSourceType,
            checkedOrderId: order.usableCheck?.order?.id,
          ),
          inFlight: null,
          locked: false,
        );
        expect(action, isA<ReconcileOrderAction>());

        final outcome = await _run(c, GrindingCommand.start, reconcile: true);
        expect(outcome.kind, CommandOutcomeKind.success);
        expect(outcome.result!.replayed, isTrue);
        expect(h.backend.commandRequests.single.clientRequestId, 'lost-id');
        expect(h.backend.transitionsFor(Fx.readyId), 0);
        expect(_commands(c).pending, isEmpty);
      },
    );

    test(
      'never committed and no longer applicable → definitive 4xx clears it',
      () async {
        final h = GrindingTestHarness();
        h.backend.orders[Fx.readyId]!.status = 'IN_GRINDING';
        h.memoryPending.records['pending_1042_start'] = _record(
          orderId: Fx.readyId,
          command: GrindingCommand.start,
          id: 'never-arrived',
        );
        final c = await _ready(h);
        final outcome = await _run(c, GrindingCommand.start, reconcile: true);
        expect(outcome.kind, CommandOutcomeKind.businessError);
        expect(_commands(c).pending, isEmpty);
      },
    );

    test('reconcile never mints and is refused without a record', () async {
      final h = GrindingTestHarness();
      final c = await _ready(h);
      final outcome = await _run(c, GrindingCommand.start, reconcile: true);
      expect(outcome.kind, CommandOutcomeKind.ignored);
      expect(h.ids.calls, 0);
      expect(h.backend.commandRequests, isEmpty);
    });
  });

  group('durable store integration (restart = new container)', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('grinding_cmd_test');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    FilePendingCommandStore fileStore() =>
        FilePendingCommandStore(DurableFileStore(() async => dir));

    test(
      'network loss → restart → same id restored, nothing auto-sent',
      () async {
        final backend = seededBackend();
        final h1 = GrindingTestHarness(backend: backend, pending: fileStore());
        final c1 = await _ready(h1);
        backend.faults.add(
          FakeFault(
            FaultKind.connectionError,
            pathEndsWith: '/start',
            times: 4,
          ),
        );
        expect(
          (await _run(c1, GrindingCommand.start)).kind,
          CommandOutcomeKind.networkLost,
        );
        final mintedId = backend.commandRequests.first.clientRequestId;
        c1.dispose();
        final sentBefore = backend.commandRequests.length;

        // "Restart": fresh container, fresh id generator, same directory.
        final h2 = GrindingTestHarness(backend: backend, pending: fileStore());
        final c2 = await _ready(h2);
        await _settle();
        expect(backend.commandRequests, hasLength(sentBefore));
        final restored = _commands(c2).pending.values.single;
        expect(restored.clientRequestId, mintedId);
        // A restored record has no in-session failure → confirmation required.
        expect(_commands(c2).failures, isEmpty);

        final outcome = await _run(c2, GrindingCommand.start);
        expect(outcome.kind, CommandOutcomeKind.success);
        expect(backend.commandRequests.last.clientRequestId, mintedId);
        expect(h2.ids.calls, 0);
        expect(await fileStore().loadAll(), isEmpty);
        expect(backend.orders[Fx.readyId]!.status, 'IN_GRINDING');
      },
    );
  });

  group('success refreshes the truth', () {
    test('success shows the server order, then re-checks', () async {
      final h = GrindingTestHarness();
      final c = await _ready(h);
      final checksBefore = h.backend.requestsTo('/check').length;
      await _run(c, GrindingCommand.start);
      final order = c.read(currentOrderControllerProvider);
      expect(order.success, GrindingCommand.start);
      expect(order.displayOrder!.status, GrindingStatus.inGrinding);
      await _checkIdle(c);
      expect(h.backend.requestsTo('/check').length, checksBefore + 1);
      final after = c.read(currentOrderControllerProvider);
      expect(after.usableCheck!.status, GrindingStatus.inGrinding);
      expect(after.usableCheck!.allowedToCompleteGrinding, isTrue);
    });

    test(
      'START then COMPLETE reaches COMPLETED with two distinct ids',
      () async {
        final h = GrindingTestHarness();
        final c = await _ready(h);
        await _run(c, GrindingCommand.start);
        await _checkIdle(c);
        final outcome = await _run(c, GrindingCommand.complete);
        expect(outcome.kind, CommandOutcomeKind.success);
        expect(h.backend.orders[Fx.readyId]!.status, 'COMPLETED');
        expect(
          h.backend.commandRequests.map((r) => r.clientRequestId),
          <String>['cid-1', 'cid-2'],
        );
        await _checkIdle(c);
        final order = c.read(currentOrderControllerProvider);
        expect(order.usableCheck!.status, GrindingStatus.completed);
      },
    );
  });

  test(
    'unknown failure while persisting reports notPersisted with a mapped failure',
    () async {
      final h = GrindingTestHarness();
      final c = await _ready(h);
      h.memoryPending.failSaves = true;
      final outcome = await _run(c, GrindingCommand.start);
      expect(outcome.failure, isA<AppFailure>());
    },
  );
}
