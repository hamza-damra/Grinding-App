import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_grinding_app/core/errors/arabic_messages.dart';
import 'package:flutter_grinding_app/core/widgets/confirm_dialog.dart';
import 'package:flutter_grinding_app/core/widgets/primary_button.dart';
import 'package:flutter_grinding_app/features/grinding_orders/presentation/order_copy.dart';
import 'package:flutter_grinding_app/features/grinding_orders/presentation/widgets/source_selection_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_grinding_backend.dart';
import '../../../support/finders.dart';
import '../../../support/test_harness.dart';

Future<GrindingTestHarness> _openOrder(
  WidgetTester tester,
  String number, {
  GrindingTestHarness? harness,
}) async {
  final h = harness ?? GrindingTestHarness();
  await h.signedIn(Fx.workerA);
  await pumpGrindingApp(tester, h);
  await checkManually(tester, number);
  return h;
}

GrindingTestHarness _sharedHarness() =>
    GrindingTestHarness(backend: seededBackend()..seedSharedNumbers());

/// Opens a number whose both items are actionable. The shimmer behind the
/// selection dialog never "settles": pump frames.
Future<GrindingTestHarness> _openBothActionable(WidgetTester tester) async {
  final h = _sharedHarness();
  await h.signedIn(Fx.workerA);
  await pumpGrindingApp(tester, h);
  await tester.enterText(byKey('manual-identifier'), Fx.bothActionableNumber);
  await tester.pump();
  await tester.tap(byKey('manual-check'));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  return h;
}

Finder _inSelection(String key, Finder matching) =>
    find.descendant(of: byKey(key), matching: matching);

Finder _chip(String label) =>
    find.descendant(of: byKey('order-status-chip'), matching: find.text(label));

void _expectNoCommandButton() {
  expect(byKey('command-start'), findsNothing);
  expect(byKey('command-complete'), findsNothing);
  expect(byKey('command-reconcile'), findsNothing);
}

VoidCallback? _onPressed(WidgetTester tester, String key) =>
    tester.widget<PrimaryButton>(byKey(key)).onPressed;

void main() {
  setUpAll(silenceNetworkLogs);

  group('order card per status (contract §4.2 / §5.4)', () {
    testWidgets('READY_FOR_GRINDING: fields, «جرش مباشر», «بدء الجرش»', (
      tester,
    ) async {
      await _openOrder(tester, Fx.readyNumber);
      expect(textIgnoringIsolates('GR-001042'), findsWidgets);
      expect(_chip(ArabicMessages.readyList), findsOneWidget);
      expect(byKey('direct-scrap-tag'), findsOneWidget);
      expect(find.text(ArabicMessages.sourceRoll), findsOneWidget);
      expect(textIgnoringIsolates(Fx.readyNumber), findsWidgets);
      expect(find.text('رول أبيض 0.8'), findsOneWidget);
      expect(
        find.descendant(
          of: byKey('order-weight'),
          matching: textIgnoringIsolates('40.000 كغ'),
        ),
        findsOneWidget,
      );
      expect(byKey('command-start'), findsOneWidget);
      expect(find.text(ArabicMessages.startButton), findsOneWidget);
      expect(byKey('command-complete'), findsNothing);
    });

    testWidgets(
      'IN_GRINDING: started by / at (Asia/Hebron), «تأكيد انتهاء الجرش»',
      (tester) async {
        await _openOrder(tester, Fx.inGrindingNumber);
        expect(_chip(ArabicMessages.inGrindingList), findsOneWidget);
        expect(find.text(OrderCopy.startedBy), findsOneWidget);
        expect(find.text('سامي خليل'), findsOneWidget);
        // 07:05Z on 2026-09-22 is 10:05 in Hebron (summer, UTC+3).
        expect(textIgnoringIsolates('2026-09-22 10:05'), findsOneWidget);
        expect(textIgnoringIsolates('12.345 كغ'), findsOneWidget);
        expect(byKey('command-complete'), findsOneWidget);
        expect(byKey('command-start'), findsNothing);
      },
    );

    testWidgets('PENDING_APPROVAL: message, no button', (tester) async {
      await _openOrder(tester, Fx.pendingApprovalNumber);
      expect(_chip(ArabicMessages.pendingApprovalLabel), findsOneWidget);
      expect(find.text(ArabicMessages.pendingApprovalMessage), findsOneWidget);
      expect(byKey('direct-scrap-tag'), findsNothing);
      _expectNoCommandButton();
    });

    testWidgets('long status label fits a 360 px phone at 1.2× text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final h = GrindingTestHarness();
      await h.signedIn(Fx.workerA);
      await pumpGrindingApp(tester, h);
      await tester.binding.setSurfaceSize(const Size(360, 640));
      await tester.pumpAndSettle();
      await checkManually(tester, Fx.pendingApprovalNumber);
      // Any RenderFlex overflow fails the test by itself.
      expect(_chip(ArabicMessages.pendingApprovalLabel), findsOneWidget);
    });

    testWidgets('COMPLETED legacy: legacy note, never a worker name', (
      tester,
    ) async {
      await _openOrder(tester, Fx.legacyNumber);
      expect(_chip(ArabicMessages.completedLabel), findsOneWidget);
      expect(byKey('legacy-note'), findsOneWidget);
      expect(find.text(ArabicMessages.legacyCompleted), findsOneWidget);
      expect(find.text(OrderCopy.completedBy), findsNothing);
      _expectNoCommandButton();
    });

    testWidgets('NOT_ELIGIBLE: server message + product/quantity, no button', (
      tester,
    ) async {
      await _openOrder(tester, Fx.notEligibleNumber);
      expect(_chip(ArabicMessages.notEligibleLabel), findsOneWidget);
      expect(find.text('لا يوجد أمر جرش لهذه الطبلية.'), findsOneWidget);
      expect(find.text('كاسة 250'), findsOneWidget);
      expect(textIgnoringIsolates('1200'), findsOneWidget);
      _expectNoCommandButton();
    });

    testWidgets('pallet: quantity instead of weight', (tester) async {
      await _openOrder(tester, Fx.palletNumber);
      expect(find.text(ArabicMessages.sourcePallet), findsOneWidget);
      expect(byKey('order-quantity'), findsOneWidget);
      expect(byKey('order-weight'), findsNothing);
      expect(byKey('direct-scrap-tag'), findsNothing);
    });

    testWidgets('unknown number → Arabic error, no button', (tester) async {
      await _openOrder(tester, Fx.unknownNumber);
      expect(find.text(ArabicMessages.sourceNotFound), findsOneWidget);
      _expectNoCommandButton();
    });

    testWidgets(
      'device key rejected → «هذا الجهاز غير مخوّل»; stays logged in',
      (tester) async {
        final h = GrindingTestHarness();
        h.backend.faults.add(
          FakeFault(FaultKind.deviceUnauthorized, pathEndsWith: '/check'),
        );
        await _openOrder(tester, Fx.readyNumber, harness: h);
        expect(find.text(ArabicMessages.deviceNotAuthorized), findsOneWidget);
        expect(find.text(ArabicMessages.pinScreenTitle), findsNothing);
        _expectNoCommandButton();
      },
    );
  });

  group('happy path (contract §9)', () {
    testWidgets(
      'START → «بدأ الجرش.» → COMPLETE → «تم الجرش فعليًا» → no button',
      (tester) async {
        final h = await _openOrder(tester, Fx.readyNumber);

        // Cancel sends nothing and mints nothing.
        await tester.tap(byKey('command-start'));
        await tester.pumpAndSettle();
        expect(
          textIgnoringIsolates(ArabicMessages.startConfirmTitle('GR-001042')),
          findsOneWidget,
        );
        await tester.tap(inConfirmDialog(ArabicMessages.cancel));
        await tester.pumpAndSettle();
        expect(h.backend.commandRequests, isEmpty);
        expect(h.ids.calls, 0);

        await tester.tap(byKey('command-start'));
        await tester.pumpAndSettle();
        await tester.tap(inConfirmDialog(ArabicMessages.startConfirmAction));
        await tester.pumpAndSettle();
        expect(byKey('success-banner'), findsOneWidget);
        expect(find.text(ArabicMessages.startSuccess), findsOneWidget);
        expect(_chip(ArabicMessages.inGrindingList), findsOneWidget);
        expect(find.text(Fx.workerAName), findsOneWidget);
        expect(byKey('command-complete'), findsOneWidget);

        await tester.tap(byKey('command-complete'));
        await tester.pumpAndSettle();
        expect(find.text(ArabicMessages.completeConfirmTitle), findsOneWidget);
        await tester.tap(inConfirmDialog(ArabicMessages.completeConfirmAction));
        await tester.pumpAndSettle();
        expect(find.text(ArabicMessages.completeSuccess), findsOneWidget);
        expect(_chip(ArabicMessages.completedLabel), findsOneWidget);
        expect(find.text(OrderCopy.completedBy), findsOneWidget);
        _expectNoCommandButton();

        expect(h.backend.orders[Fx.readyId]!.status, 'COMPLETED');
        expect(
          h.backend.commandRequests.map((r) => r.clientRequestId),
          <String>['cid-1', 'cid-2'],
        );
      },
    );

    testWidgets(
      'while in flight: disabled + spinner, back blocked, one request',
      (tester) async {
        final h = await _openOrder(tester, Fx.readyNumber);
        final release = Completer<void>();
        h.backend.faults.add(
          FakeFault(
            FaultKind.hang,
            pathEndsWith: '/start',
            release: release,
            thenCommit: true,
          ),
        );
        await tester.tap(byKey('command-start'));
        await tester.pumpAndSettle();
        await tester.tap(inConfirmDialog(ArabicMessages.startConfirmAction));
        await tester.pump();
        // Let the confirm dialog finish its exit animation (the spinner never
        // settles, so no pumpAndSettle here).
        await tester.pump(const Duration(milliseconds: 500));

        expect(_onPressed(tester, 'command-start'), isNull);
        expect(
          find.descendant(
            of: byKey('command-start'),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        // Double tap does nothing.
        await tester.tap(byKey('command-start'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(Dialog), findsNothing);
        // Android back is blocked while the outcome is unknown.
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(byKey('order-card'), findsOneWidget);

        release.complete();
        await tester.pumpAndSettle();
        expect(find.text(ArabicMessages.startSuccess), findsOneWidget);
        expect(h.backend.commandRequests, hasLength(1));
        expect(h.ids.calls, 1);
      },
    );
  });

  group('failures', () {
    testWidgets('business error → Arabic dialog → re-check shows the truth', (
      tester,
    ) async {
      final h = await _openOrder(tester, Fx.readyNumber);
      // Another worker started it meanwhile.
      h.backend.orders[Fx.readyId]!
        ..status = 'IN_GRINDING'
        ..startedByName = Fx.workerBName
        ..startedAt = '2026-09-22T09:00:00.000Z';

      await tester.tap(byKey('command-start'));
      await tester.pumpAndSettle();
      await tester.tap(inConfirmDialog(ArabicMessages.startConfirmAction));
      await tester.pumpAndSettle();
      expect(find.text(ArabicMessages.orderNotReady), findsOneWidget);
      expect(find.textContaining('READY'), findsNothing);
      await tester.tap(find.text(ArabicMessages.ok));
      await tester.pumpAndSettle();

      expect(_chip(ArabicMessages.inGrindingList), findsOneWidget);
      expect(find.text(Fx.workerBName), findsOneWidget);
      expect(byKey('command-complete'), findsOneWidget);
      expect(h.memoryPending.records, isEmpty);
    });

    testWidgets(
      'network lost → «انقطع الاتصال — أعد المحاولة» → retry reuses the id',
      (tester) async {
        final h = await _openOrder(tester, Fx.readyNumber);
        h.backend.faults.add(
          FakeFault(
            FaultKind.connectionError,
            pathEndsWith: '/start',
            times: 4,
          ),
        );
        await tester.tap(byKey('command-start'));
        await tester.pumpAndSettle();
        await tester.tap(inConfirmDialog(ArabicMessages.startConfirmAction));
        await tester.pumpAndSettle();

        expect(byKey('network-lost'), findsOneWidget);
        expect(find.text(ArabicMessages.networkLost), findsOneWidget);
        expect(h.backend.commandRequests, hasLength(4));

        await tester.tap(byKey('command-retry'));
        await tester.pumpAndSettle();
        expect(
          find.byType(Dialog),
          findsNothing,
          reason: 'same in-session action',
        );
        expect(find.text(ArabicMessages.startSuccess), findsOneWidget);
        expect(
          h.backend.commandRequests.map((r) => r.clientRequestId).toSet(),
          <String>{'cid-1'},
        );
        expect(h.backend.transitionsFor(Fx.readyId), 1);
      },
    );

    testWidgets(
      'lost response after commit → replayed:true → same success UI',
      (tester) async {
        final h = await _openOrder(tester, Fx.readyNumber);
        h.backend.faults.add(
          FakeFault(FaultKind.lostResponseAfterCommit, pathEndsWith: '/start'),
        );
        await tester.tap(byKey('command-start'));
        await tester.pumpAndSettle();
        await tester.tap(inConfirmDialog(ArabicMessages.startConfirmAction));
        await tester.pumpAndSettle();
        expect(find.text(ArabicMessages.startSuccess), findsOneWidget);
        expect(h.backend.transitionsFor(Fx.readyId), 1);
      },
    );
  });

  group('smart Roll/Pallet resolution (contract §4.2 / §5.3)', () {
    testWidgets(
      'one actionable item opens directly — no question, the card names the '
      'other item and the confirmation says which one is ground',
      (tester) async {
        final h = await _openOrder(tester, Fx.sharedNumber);
        expect(find.byType(SourceSelectionDialog), findsNothing);
        expect(textIgnoringIsolates('GR-001047'), findsWidgets);
        expect(find.text(ArabicMessages.sourceRoll), findsWidgets);
        expect(
          find.text(
            ArabicMessages.sharedNumberNotice(
              ArabicMessages.sourcePallet,
              ArabicMessages.notEligibleLabel,
            ),
          ),
          findsOneWidget,
        );
        expect(h.backend.requestsTo('/check').single.body, <String, dynamic>{
          'identifier': Fx.sharedNumber,
        });

        await tester.tap(byKey('command-start'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(ConfirmDialog),
            matching: find.text(
              ArabicMessages.sharedNumberConfirmWarning(
                ArabicMessages.sourceRollDefinite,
              ),
            ),
          ),
          findsOneWidget,
        );
        await tester.tap(inConfirmDialog(ArabicMessages.startConfirmAction));
        await tester.pumpAndSettle();
        expect(find.text(ArabicMessages.startSuccess), findsOneWidget);
        expect(h.backend.transitionsFor(Fx.sharedRollId), 1);
        // The follow-up re-check stays on the item the server picked.
        expect(h.backend.requestsTo('/check').last.body, <String, dynamic>{
          'identifier': Fx.sharedNumber,
          'sourceType': 'ROLL',
        });
      },
    );

    testWidgets('only the pallet actionable → the pallet opens directly', (
      tester,
    ) async {
      await _openOrder(
        tester,
        Fx.palletActionableNumber,
        harness: _sharedHarness(),
      );
      expect(find.byType(SourceSelectionDialog), findsNothing);
      expect(textIgnoringIsolates('GR-001050'), findsWidgets);
      expect(find.text(ArabicMessages.sourcePallet), findsWidgets);
      expect(byKey('shared-number-notice'), findsOneWidget);
      expect(byKey('command-start'), findsOneWidget);
    });

    testWidgets(
      'both actionable → selection with each item\'s status and action',
      (tester) async {
        await _openBothActionable(tester);
        expect(find.byType(SourceSelectionDialog), findsOneWidget);
        expect(find.text(ArabicMessages.selectionTitle), findsOneWidget);
        expect(find.text(ArabicMessages.selectionText), findsOneWidget);
        expect(byKey('selection-cancel'), findsOneWidget);
        // Roll: IN_GRINDING → «تأكيد انتهاء الجرش»; pallet: READY → «بدء».
        expect(
          _inSelection('selection-roll', find.text(ArabicMessages.sourceRoll)),
          findsOneWidget,
        );
        expect(
          _inSelection(
            'selection-roll',
            find.text(ArabicMessages.inGrindingList),
          ),
          findsOneWidget,
        );
        expect(
          _inSelection(
            'selection-roll',
            find.text(ArabicMessages.completeButton),
          ),
          findsOneWidget,
        );
        expect(
          _inSelection(
            'selection-pallet',
            find.text(ArabicMessages.sourcePallet),
          ),
          findsOneWidget,
        );
        expect(
          _inSelection('selection-pallet', find.text(ArabicMessages.readyList)),
          findsOneWidget,
        );
        expect(
          _inSelection(
            'selection-pallet',
            find.text(ArabicMessages.startButton),
          ),
          findsOneWidget,
        );
        expect(
          _inSelection('selection-pallet', find.text('كاسة 250')),
          findsOneWidget,
        );
        _expectNoCommandButton();
      },
    );

    testWidgets('«طبلية» → re-check with sourceType PALLET → «بدء الجرش»', (
      tester,
    ) async {
      final h = await _openBothActionable(tester);
      await tester.tap(byKey('selection-pallet'));
      await tester.pumpAndSettle();
      expect(find.byType(SourceSelectionDialog), findsNothing);
      expect(textIgnoringIsolates('GR-001049'), findsWidgets);
      expect(byKey('command-start'), findsOneWidget);
      expect(byKey('command-complete'), findsNothing);
      expect(h.backend.requestsTo('/check').last.body, <String, dynamic>{
        'identifier': Fx.bothActionableNumber,
        'sourceType': 'PALLET',
      });
    });

    testWidgets('«رول» → re-check with sourceType ROLL → «تأكيد الانتهاء»', (
      tester,
    ) async {
      final h = await _openBothActionable(tester);
      await tester.tap(byKey('selection-roll'));
      await tester.pumpAndSettle();
      expect(textIgnoringIsolates('GR-001048'), findsWidgets);
      expect(byKey('command-complete'), findsOneWidget);
      expect(byKey('command-start'), findsNothing);
      expect(h.backend.requestsTo('/check').last.body, <String, dynamic>{
        'identifier': Fx.bothActionableNumber,
        'sourceType': 'ROLL',
      });
    });

    testWidgets('«إلغاء» → back to Home, nothing inferred', (tester) async {
      final h = await _openBothActionable(tester);
      await tester.tap(byKey('selection-cancel'));
      await tester.pumpAndSettle();
      expect(byKey('scan-button'), findsOneWidget);
      expect(h.backend.requestsTo('/check'), hasLength(1));
    });

    testWidgets(
      'neither actionable → «غير مؤهل للجرش», both states, no button',
      (tester) async {
        await _openOrder(
          tester,
          Fx.noneActionableNumber,
          harness: _sharedHarness(),
        );
        expect(find.byType(SourceSelectionDialog), findsNothing);
        expect(_chip(ArabicMessages.notEligibleLabel), findsOneWidget);
        expect(
          find.descendant(
            of: byKey('candidate-row-roll'),
            matching: find.textContaining(ArabicMessages.pendingApprovalLabel),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: byKey('candidate-row-pallet'),
            matching: find.textContaining(ArabicMessages.completedLabel),
          ),
          findsOneWidget,
        );
        expect(
          find.text('الرقم موجود لرول وطبلية، ولا يمكن جرش أيٍّ منهما الآن.'),
          findsOneWidget,
        );
        _expectNoCommandButton();
      },
    );

    testWidgets('a rejected roll next to a READY pallet → the pallet', (
      tester,
    ) async {
      await _openOrder(
        tester,
        Fx.rejectedRollNumber,
        harness: _sharedHarness(),
      );
      expect(find.byType(SourceSelectionDialog), findsNothing);
      expect(textIgnoringIsolates('GR-001054'), findsWidgets);
      expect(byKey('command-start'), findsOneWidget);
    });
  });
}
