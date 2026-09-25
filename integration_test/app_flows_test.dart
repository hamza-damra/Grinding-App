import 'package:flutter_grinding_app/core/errors/arabic_messages.dart';
import 'package:flutter_grinding_app/core/storage/secure_token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_grinding_backend.dart';
import '../test/support/finders.dart';
import '../test/support/test_harness.dart';
import 'support/device_harness.dart';

/// Scenarios A–E on a real Android device / emulator with the real secure
/// storage, SharedPreferences and durable pending-command files. The backend
/// is the in-process fake (no credentials leave the device). Manual entry
/// only — no camera permission dialog.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(silenceNetworkLogs);
  setUp(resetDeviceState);

  final uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  Future<FakeGrindingBackend> loggedIn(WidgetTester tester) async {
    final backend = seededBackend()..seedSharedNumbers();
    await pumpDeviceApp(tester, backend);
    await loginWithPin(tester, Fx.pinA);
    await pumpUntilFound(tester, byKey('worker-name'));
    return backend;
  }

  Future<void> confirm(WidgetTester tester, String label) async {
    await pumpUntilFound(tester, inConfirmDialog(label));
    await tester.tap(inConfirmDialog(label));
    await tester.pumpAndSettle();
  }

  testWidgets('A: READY → «بدء الجرش» → IN_GRINDING → COMPLETE → COMPLETED', (
    tester,
  ) async {
    final backend = await loggedIn(tester);
    // The token went to the real secure storage.
    expect(await FlutterSecureTokenStore().readSessionToken(), isNotNull);

    await checkManually(tester, Fx.readyNumber);
    await pumpUntilFound(tester, byKey('command-start'));
    await tester.tap(byKey('command-start'));
    await confirm(tester, ArabicMessages.startConfirmAction);
    await pumpUntilFound(tester, find.text(ArabicMessages.startSuccess));
    await pumpUntilFound(tester, byKey('command-complete'));

    await tester.tap(byKey('command-complete'));
    await confirm(tester, ArabicMessages.completeConfirmAction);
    await pumpUntilFound(tester, find.text(ArabicMessages.completeSuccess));
    expect(byKey('command-start'), findsNothing);
    expect(byKey('command-complete'), findsNothing);

    expect(backend.orders[Fx.readyId]!.status, 'COMPLETED');
    final ids = backend.commandRequests.map((r) => r.clientRequestId!).toList();
    expect(ids, hasLength(2));
    expect(ids[0], matches(uuidV4));
    expect(ids[1], matches(uuidV4));
    expect(ids[0], isNot(ids[1]));
    expect(await (await realPendingStore()).loadAll(), isEmpty);
  });

  testWidgets(
    'B: response lost after commit → same id → replayed:true, one transition',
    (tester) async {
      final backend = await loggedIn(tester);
      await checkManually(tester, Fx.readyNumber);
      await pumpUntilFound(tester, byKey('command-start'));
      backend.faults.add(
        FakeFault(FaultKind.lostResponseAfterCommit, pathEndsWith: '/start'),
      );
      await tester.tap(byKey('command-start'));
      await confirm(tester, ArabicMessages.startConfirmAction);
      await pumpUntilFound(tester, find.text(ArabicMessages.startSuccess));

      final sent = backend.commandRequests;
      expect(sent, hasLength(2));
      expect(sent[0].clientRequestId, sent[1].clientRequestId);
      expect(backend.transitionsFor(Fx.readyId), 1);
      expect(await (await realPendingStore()).loadAll(), isEmpty);
    },
  );

  testWidgets(
    'C: roll and pallet both actionable → worker picks → /check carries '
    'sourceType',
    (tester) async {
      final backend = await loggedIn(tester);
      await tester.enterText(
        byKey('manual-identifier'),
        Fx.bothActionableNumber,
      );
      await tester.pump();
      await tester.tap(byKey('manual-check'));
      await pumpUntilFound(tester, find.text(ArabicMessages.selectionTitle));
      expect(find.text(ArabicMessages.selectionText), findsOneWidget);

      await tester.tap(byKey('selection-pallet'));
      await pumpUntilFound(tester, byKey('command-start'));
      final bodies = backend.requestsTo('/check').map((r) => r.body).toList();
      expect(bodies.first, <String, dynamic>{
        'identifier': Fx.bothActionableNumber,
      });
      expect(bodies.last, <String, dynamic>{
        'identifier': Fx.bothActionableNumber,
        'sourceType': 'PALLET',
      });
    },
  );

  testWidgets(
    'C2: shared number with one actionable item opens without a question',
    (tester) async {
      final backend = await loggedIn(tester);
      await checkManually(tester, Fx.sharedNumber);
      await pumpUntilFound(tester, byKey('shared-number-notice'));
      expect(find.text(ArabicMessages.selectionTitle), findsNothing);
      expect(byKey('command-start'), findsOneWidget);
      expect(backend.requestsTo('/check'), hasLength(1));
    },
  );

  testWidgets('D: PENDING_APPROVAL can never be started', (tester) async {
    final backend = await loggedIn(tester);
    await checkManually(tester, Fx.pendingApprovalNumber);
    await pumpUntilFound(
      tester,
      find.text(ArabicMessages.pendingApprovalMessage),
    );
    expect(byKey('command-start'), findsNothing);
    expect(byKey('command-complete'), findsNothing);
    expect(backend.commandRequests, isEmpty);
  });

  for (final sameWorker in <bool>[true, false]) {
    final who = sameWorker ? 'the same worker' : 'another worker';
    testWidgets('E: session expires with a START pending → re-login ($who) → '
        'banner, nothing auto-sent → explicit confirm → SAME id', (
      tester,
    ) async {
      final backend = await loggedIn(tester);
      await checkManually(tester, Fx.readyNumber);
      await pumpUntilFound(tester, byKey('command-start'));

      // The session ends (12 h passed) right before the tap.
      backend.expireSession(backend.activeTokenFor(Fx.workerA)!);
      await tester.tap(byKey('command-start'));
      await confirm(tester, ArabicMessages.startConfirmAction);
      await pumpUntilFound(tester, find.text(ArabicMessages.sessionExpired));
      expect(find.text(ArabicMessages.pinScreenTitle), findsOneWidget);

      final firstId = backend.commandRequests.single.clientRequestId!;
      final onDisk = await (await realPendingStore()).loadAll();
      expect(onDisk.single.clientRequestId, firstId);

      // App restarted in between (provider graph rebuilt from storage).
      await restartInProcess(tester, backend);
      await loginWithPin(tester, sameWorker ? Fx.pinA : Fx.pinB);
      await pumpUntilFound(tester, byKey('pending-banner-pending_1042_start'));
      expect(
        find.text(ArabicMessages.pendingOtherWorker(Fx.workerAName)),
        sameWorker ? findsNothing : findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(backend.commandRequests, hasLength(1), reason: 'never auto-sent');

      await tester.tap(find.text(ArabicMessages.pendingOpenOrder));
      await pumpUntilFound(tester, byKey('command-start'));
      await tester.tap(byKey('command-start'));
      await confirm(tester, ArabicMessages.startConfirmAction);
      await pumpUntilFound(tester, find.text(ArabicMessages.startSuccess));

      expect(backend.commandRequests, hasLength(2));
      expect(backend.commandRequests.last.clientRequestId, firstId);
      expect(backend.transitionsFor(Fx.readyId), 1);
      expect(
        backend.orders[Fx.readyId]!.startedByName,
        sameWorker ? Fx.workerAName : Fx.workerBName,
      );
      expect(await (await realPendingStore()).loadAll(), isEmpty);
    });
  }
}
