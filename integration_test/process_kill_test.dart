import 'dart:async';
import 'dart:io';

import 'package:flutter_grinding_app/core/errors/arabic_messages.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/finders.dart';
import '../test/support/test_harness.dart';
import 'support/device_harness.dart';

/// REAL Android process-kill test for the idempotency invariant (owner
/// correction #1): the `clientRequestId` is durably persisted before the
/// first request, so a process death right before / right after the server
/// commits can never make the next launch mint a second id.
///
/// Driven by `tool/process_kill_test.ps1` (two separate app processes):
///
/// * phase 1 (`KILL_PHASE=1`): fresh state → PIN → READY order → «بدء الجرش»
///   → confirm. The fake network kills the app process with SIGKILL
///   * `KILL_MODE=before_commit`: when the request reaches the "server",
///     before the server applies it;
///   * `KILL_MODE=after_commit`: after the server committed it, before the
///     response returns.
///   The host then reads the record straight from the app sandbox
///   (`adb shell run-as … cat`) — independent evidence of what was on disk.
/// * phase 2 (`KILL_PHASE=2`, `EXPECTED_ID=<id read by the host>`): a new
///   process. Asserts the record on disk has exactly that id, the id
///   generator is NEVER called, nothing is sent before an explicit confirm,
///   and the resend carries the same id (after_commit → `replayed:true`,
///   no second transition).
///
/// Skipped unless `KILL_PHASE` is defined.
const String _phase = String.fromEnvironment('KILL_PHASE');
const String _mode = String.fromEnvironment('KILL_MODE');
const String _expectedId = String.fromEnvironment('EXPECTED_ID');

Future<Never> _killThisProcess(String reason) {
  // ignore: avoid_print
  print('KILL_TEST_KILLING pid=$pid reason=$reason');
  Process.killPid(pid, ProcessSignal.sigkill);
  // SIGKILL cannot be caught: nothing after this line ever runs.
  return Completer<Never>().future;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(silenceNetworkLogs);

  testWidgets('phase 1: persist, then die around the START request', (
    tester,
  ) async {
    expect(_mode, anyOf('before_commit', 'after_commit'));
    await resetDeviceState();
    final backend = seededBackend();
    backend.onRequest = (r) async {
      if (!r.path.endsWith('/start')) return;
      // What is on disk at the moment the request is on the wire.
      final records = await (await realPendingStore()).loadAll();
      // ignore: avoid_print
      print(
        'KILL_TEST_ON_DISK_AT_SEND=${records.map((e) => e.clientRequestId).join(',')} '
        'SENT=${r.clientRequestId}',
      );
      if (_mode == 'before_commit') await _killThisProcess('before commit');
    };
    backend.onCommitted = (r) async {
      if (_mode == 'after_commit') await _killThisProcess('after commit');
    };

    await pumpDeviceApp(tester, backend);
    await loginWithPin(tester, Fx.pinA);
    await pumpUntilFound(tester, byKey('worker-name'));
    await checkManually(tester, Fx.readyNumber);
    await pumpUntilFound(tester, byKey('command-start'));
    await tester.tap(byKey('command-start'));
    await pumpUntilFound(
      tester,
      inConfirmDialog(ArabicMessages.startConfirmAction),
    );
    await tester.tap(inConfirmDialog(ArabicMessages.startConfirmAction));
    // The process dies inside the fake network; this never returns.
    await pumpUntilFound(tester, find.text('unreachable'));
    fail('the process should have been killed');
  }, skip: _phase != '1');

  testWidgets('phase 2: relaunch recovers the SAME id and never mints', (
    tester,
  ) async {
    expect(_expectedId, isNotEmpty, reason: 'pass EXPECTED_ID');
    final restored = await (await realPendingStore()).loadAll();
    expect(restored, hasLength(1));
    expect(restored.single.clientRequestId, _expectedId);
    expect(restored.single.command, GrindingCommand.start);
    expect(restored.single.orderId, Fx.readyId);

    final backend = seededBackend();
    if (_mode == 'after_commit') {
      // The server of phase 1 committed the START before the process died.
      backend.orders[Fx.readyId]!
        ..status = 'IN_GRINDING'
        ..startedByName = Fx.workerAName
        ..startedAt = backend.now;
      backend.seedIdempotency(_expectedId, Fx.readyId, 'START');
    }
    var minted = 0;
    await pumpDeviceApp(
      tester,
      backend,
      ids: () {
        minted++;
        return 'MUST-NOT-BE-MINTED-$minted';
      },
    );
    await pumpUntilFound(tester, byKey('pin-input'));
    await loginWithPin(tester, Fx.pinA);
    await pumpUntilFound(tester, byKey('pending-banner-pending_1042_start'));
    await tester.pump(const Duration(seconds: 1));
    expect(backend.commandRequests, isEmpty, reason: 'never auto-sent');

    await tester.tap(find.text(ArabicMessages.pendingOpenOrder));
    if (_mode == 'before_commit') {
      await pumpUntilFound(tester, byKey('command-start'));
      await tester.tap(byKey('command-start'));
      await pumpUntilFound(
        tester,
        inConfirmDialog(ArabicMessages.startConfirmAction),
      );
      await tester.tap(inConfirmDialog(ArabicMessages.startConfirmAction));
    } else {
      // START already applied: the record no longer matches the order →
      // «تحقق من الطلب السابق», confirmed explicitly.
      await pumpUntilFound(tester, byKey('command-reconcile'));
      expect(byKey('command-complete'), findsNothing);
      await tester.tap(byKey('command-reconcile'));
      await pumpUntilFound(tester, inConfirmDialog(ArabicMessages.checkButton));
      await tester.tap(inConfirmDialog(ArabicMessages.checkButton));
    }
    await pumpUntilFound(tester, find.text(ArabicMessages.startSuccess));

    expect(minted, 0, reason: 'no new clientRequestId after the restart');
    final sent = backend.commandRequests.single;
    expect(sent.clientRequestId, _expectedId);
    expect(
      backend.transitionsFor(Fx.readyId),
      _mode == 'before_commit' ? 1 : 0,
      reason: 'after_commit must be a replay, never a second transition',
    );
    expect(await (await realPendingStore()).loadAll(), isEmpty);
    // ignore: avoid_print
    print('KILL_TEST_RESULT=PASS mode=$_mode id=$_expectedId minted=$minted');
  }, skip: _phase != '2');
}
