import 'package:flutter/material.dart';
import 'package:flutter_grinding_app/core/errors/arabic_messages.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/entities/pending_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_command.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_grinding_backend.dart';
import '../support/finders.dart';
import '../support/test_harness.dart';

void main() {
  setUpAll(silenceNetworkLogs);

  group('PIN screen (contract §5.1)', () {
    testWidgets('title, «دخول» disabled until 4 digits', (tester) async {
      final h = GrindingTestHarness();
      await pumpGrindingApp(tester, h);
      expect(find.text(ArabicMessages.pinScreenTitle), findsOneWidget);
      final submit = byKey('pin-submit');
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.descendant(
                of: submit,
                matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(byKey('pin-input'), '482');
      await tester.pump();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(h.backend.requests, isEmpty);
    });

    testWidgets('wrong PIN → inline Arabic error, field cleared', (
      tester,
    ) async {
      final h = GrindingTestHarness();
      await pumpGrindingApp(tester, h);
      await loginWithPin(tester, '0000');
      expect(find.text(ArabicMessages.pinInvalid), findsOneWidget);
      expect(byKey('pin-error'), findsOneWidget);
      final field = tester.widget<EditableText>(
        find.descendant(
          of: byKey('pin-input'),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.controller.text, isEmpty);
    });

    testWidgets('non-grinding employee → «غير مخوّل…»', (tester) async {
      final h = GrindingTestHarness();
      await pumpGrindingApp(tester, h);
      await loginWithPin(tester, Fx.pinNotAllowed);
      expect(find.text(ArabicMessages.workerNotAllowed), findsOneWidget);
    });

    testWidgets('Arabic-Indic PIN works; login lands on Home', (tester) async {
      final h = GrindingTestHarness();
      await pumpGrindingApp(tester, h);
      await loginWithPin(tester, '٤٨٢١');
      expect(byKey('worker-name'), findsOneWidget);
      expect(find.text(Fx.workerAName), findsOneWidget);
      expect(h.backend.requestsTo('/auth/pin').single.body, <String, dynamic>{
        'pin': '4821',
      });
    });
  });

  group('Home (contract §5.2)', () {
    testWidgets('header, scan button, manual field, both lists', (
      tester,
    ) async {
      final h = GrindingTestHarness();
      await h.signedIn(Fx.workerA);
      await pumpGrindingApp(tester, h);

      expect(find.text(ArabicMessages.appTitle), findsOneWidget);
      expect(find.text(ArabicMessages.logout), findsOneWidget);
      expect(find.text(ArabicMessages.scanButton), findsOneWidget);
      expect(find.text(ArabicMessages.manualEntryLabel), findsOneWidget);
      expect(find.text(ArabicMessages.checkButton), findsOneWidget);
      expect(queueTab(ArabicMessages.readyList), findsOneWidget);
      expect(queueTab(ArabicMessages.inGrindingList), findsOneWidget);
      expect(
        textContainingIgnoringIsolates(ArabicMessages.sessionEndsAt),
        findsOneWidget,
      );

      for (final id in <int>[Fx.readyId, Fx.palletId, Fx.sharedRollId]) {
        expect(byKey('queue-row-$id'), findsOneWidget, reason: '$id');
      }
      await tester.tap(queueTab(ArabicMessages.inGrindingList));
      await tester.pumpAndSettle();
      expect(byKey('queue-row-${Fx.inGrindingId}'), findsOneWidget);
    });

    testWidgets('11 digits → inline validation, no network call', (
      tester,
    ) async {
      final h = GrindingTestHarness();
      await h.signedIn(Fx.workerA);
      await pumpGrindingApp(tester, h);
      await checkManually(tester, '00100000025');
      expect(find.text(ArabicMessages.identifierInvalid), findsOneWidget);
      expect(h.backend.requestsTo('/check'), isEmpty);
    });

    testWidgets('Arabic-Indic manual entry is converted and checked', (
      tester,
    ) async {
      final h = GrindingTestHarness();
      await h.signedIn(Fx.workerA);
      await pumpGrindingApp(tester, h);
      await checkManually(tester, '٠٠١٠٠٠٠٠٠٢٥٥');
      expect(byKey('order-card'), findsOneWidget);
      expect(h.backend.requestsTo('/check').single.body, <String, dynamic>{
        'identifier': Fx.readyNumber,
      });
    });

    testWidgets('a queue row opens the same /check flow (number only)', (
      tester,
    ) async {
      final h = GrindingTestHarness();
      await h.signedIn(Fx.workerA);
      await pumpGrindingApp(tester, h);
      await tester.tap(queueTab(ArabicMessages.inGrindingList));
      await tester.pumpAndSettle();
      await tester.tap(byKey('queue-row-${Fx.inGrindingId}'));
      await tester.pumpAndSettle();
      expect(byKey('command-complete'), findsOneWidget);
      expect(h.backend.requestsTo('/check').single.body, <String, dynamic>{
        'identifier': Fx.inGrindingNumber,
      });
    });

    testWidgets('empty lists → «لا توجد أوامر»', (tester) async {
      final backend = FakeGrindingBackend()
        ..addWorker(pin: Fx.pinA, operatorId: Fx.workerA, name: Fx.workerAName);
      final h = GrindingTestHarness(backend: backend);
      await h.signedIn(Fx.workerA);
      await pumpGrindingApp(tester, h);
      expect(find.text(ArabicMessages.emptyList), findsOneWidget);
    });

    testWidgets('logout: confirm → PIN screen, session ended server-side', (
      tester,
    ) async {
      final h = GrindingTestHarness();
      final token = await h.signedIn(Fx.workerA);
      await pumpGrindingApp(tester, h);
      await tester.tap(byKey('logout-button'));
      await tester.pumpAndSettle();
      expect(find.text(ArabicMessages.logoutConfirmTitle), findsOneWidget);

      // Cancel keeps the session.
      await tester.tap(inConfirmDialog(ArabicMessages.cancel));
      await tester.pumpAndSettle();
      expect(byKey('worker-name'), findsOneWidget);

      await tester.tap(byKey('logout-button'));
      await tester.pumpAndSettle();
      await tester.tap(inConfirmDialog(ArabicMessages.logout));
      await tester.pumpAndSettle();
      expect(find.text(ArabicMessages.pinScreenTitle), findsOneWidget);
      expect(h.backend.sessions[token]!.usable, isFalse);
      expect(await h.tokens.readSessionToken(), isNull);
    });

    testWidgets('session expired mid-shift → PIN with the reason', (
      tester,
    ) async {
      final h = GrindingTestHarness();
      final token = await h.signedIn(Fx.workerA);
      await pumpGrindingApp(tester, h);
      h.backend.expireSession(token);
      await checkManually(tester, Fx.readyNumber);
      await tester.pumpAndSettle();
      expect(find.text(ArabicMessages.pinScreenTitle), findsOneWidget);
      expect(find.text(ArabicMessages.sessionExpired), findsOneWidget);
    });

    testWidgets('pending banner names the other worker; open → same id', (
      tester,
    ) async {
      final h = GrindingTestHarness();
      h.memoryPending.records['pending_1042_start'] = const PendingCommand(
        orderId: Fx.readyId,
        orderNumber: 'GR-001042',
        identifier: Fx.readyNumber,
        command: GrindingCommand.start,
        clientRequestId: 'id-from-worker-b',
        workerOperatorId: Fx.workerB,
        workerName: Fx.workerBName,
        createdAt: '2026-09-22T08:00:00.000Z',
      );
      await h.signedIn(Fx.workerA);
      await pumpGrindingApp(tester, h);

      expect(byKey('pending-banner-pending_1042_start'), findsOneWidget);
      expect(
        find.text(ArabicMessages.pendingOtherWorker(Fx.workerBName)),
        findsOneWidget,
      );
      expect(h.backend.commandRequests, isEmpty, reason: 'never auto-sent');

      await tester.tap(find.text(ArabicMessages.pendingOpenOrder));
      await tester.pumpAndSettle();
      expect(byKey('command-start'), findsOneWidget);
      await tester.tap(byKey('command-start'));
      await tester.pumpAndSettle();
      // The confirmation repeats the other-worker warning.
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(
            ArabicMessages.pendingOtherWorker(Fx.workerBName),
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(inConfirmDialog(ArabicMessages.startConfirmAction));
      await tester.pumpAndSettle();

      expect(find.text(ArabicMessages.startSuccess), findsOneWidget);
      expect(
        h.backend.commandRequests.single.clientRequestId,
        'id-from-worker-b',
      );
      expect(h.ids.calls, 0);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(byKey('pending-banner-pending_1042_start'), findsNothing);
    });
  });
}
