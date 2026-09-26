import 'package:flutter_grinding_app/app/app.dart';
import 'package:flutter_grinding_app/core/errors/arabic_messages.dart';
import 'package:flutter_grinding_app/core/lifecycle/lifecycle_resume_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_grinding_backend.dart';
import '../../support/finders.dart';
import '../../support/test_harness.dart';

/// The fingerprint dialog on the PIN screen (biometric handoff §5, §9, §11).
GrindingTestHarness _gated({
  List<Duration> backoff = const <Duration>[Duration.zero],
}) =>
    GrindingTestHarness(biometricBackoff: backoff)
      ..backend.setBiometricEnforced(true);

Finder get _dialog => byKey('biometric-dialog');

Finder _phase(String name) => byKey('biometric-phase-$name');

Finder _inDialog(String text) =>
    find.descendant(of: _dialog, matching: find.text(text));

int _logins(GrindingTestHarness h) => h.backend.requestsTo('/auth/pin').length;

void main() {
  setUpAll(silenceNetworkLogs);

  testWidgets('scanned before login → no dialog, straight to Home', (
    tester,
  ) async {
    final h = _gated()..backend.scanFingerprint(Fx.workerA);
    await pumpGrindingApp(tester, h);
    await loginWithPin(tester, Fx.pinA);
    expect(_dialog, findsNothing);
    expect(byKey('worker-name'), findsOneWidget);
    expect(h.backend.biometricStatusRequests, isEmpty);
  });

  testWidgets('login, then scan → the dialog completes the login by itself', (
    tester,
  ) async {
    final h = _gated();
    await pumpGrindingApp(tester, h);
    await loginWithPin(tester, Fx.pinA);

    expect(_dialog, findsOneWidget);
    expect(_phase('waiting'), findsOneWidget);
    expect(_inDialog(ArabicMessages.biometricTitle), findsOneWidget);
    expect(_inDialog(ArabicMessages.biometricWaiting), findsOneWidget);
    expect(_inDialog(ArabicMessages.biometricWaitingHint), findsOneWidget);
    expect(
      _inDialog(ArabicMessages.biometricVerificationRequired),
      findsOneWidget,
      reason: 'the server message, verbatim',
    );
    expect(byKey('biometric-cancel'), findsOneWidget);
    expect(byKey('biometric-retry'), findsNothing, reason: 'no bypass');

    h.backend.scanFingerprint(Fx.workerA);
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(byKey('worker-name'), findsOneWidget);
    expect(find.text(Fx.workerAName), findsOneWidget);
    expect(_logins(h), 2, reason: 'one re-submit, no re-typing');
  });

  testWidgets('barrier taps and the back button never dismiss it', (
    tester,
  ) async {
    final h = _gated();
    await pumpGrindingApp(tester, h);
    await loginWithPin(tester, Fx.pinA);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
  });

  testWidgets('terminal offline → device-offline state, keeps waiting', (
    tester,
  ) async {
    final h = _gated();
    await pumpGrindingApp(tester, h);
    await loginWithPin(tester, Fx.pinA);
    h.backend.setBiometricTerminalOnline(false);
    await tester.pumpAndSettle();
    expect(_phase('deviceOffline'), findsOneWidget);
    expect(_inDialog(ArabicMessages.biometricDeviceOffline), findsOneWidget);
    expect(byKey('biometric-cancel'), findsOneWidget);

    h.backend
      ..setBiometricTerminalOnline(true)
      ..scanFingerprint(Fx.workerA);
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(byKey('worker-name'), findsOneWidget);
  });

  testWidgets('a DEVICE_UNAVAILABLE refusal shows the server message', (
    tester,
  ) async {
    final h = _gated()..backend.setBiometricTerminalOnline(false);
    await pumpGrindingApp(tester, h);
    await loginWithPin(tester, Fx.pinA);
    expect(_phase('deviceOffline'), findsOneWidget);
    expect(
      _inDialog(ArabicMessages.biometricDeviceUnavailable),
      findsOneWidget,
    );
  });

  testWidgets('status call fails → network state with backoff, then recovers', (
    tester,
  ) async {
    final h = _gated(backoff: const <Duration>[Duration(seconds: 3)]);
    h.backend.faults.add(
      FakeFault(FaultKind.connectionError, pathEndsWith: '/status'),
    );
    await pumpGrindingApp(tester, h);
    await loginWithPin(tester, Fx.pinA);
    expect(_phase('network'), findsOneWidget);
    expect(_inDialog(ArabicMessages.biometricNetwork), findsOneWidget);
    expect(byKey('biometric-cancel'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(_phase('waiting'), findsOneWidget);
  });

  testWidgets('unlinked employee → contact admin; «حسنًا» closes; no poll', (
    tester,
  ) async {
    final h = _gated()
      ..backend.setBiometricMapping(Fx.workerA, FakeBiometricMapping.missing);
    await pumpGrindingApp(tester, h);
    await loginWithPin(tester, Fx.pinA);
    expect(_phase('contactAdmin'), findsOneWidget);
    expect(_inDialog(ArabicMessages.biometricMappingMissing), findsOneWidget);
    expect(byKey('biometric-cancel'), findsNothing);
    expect(byKey('biometric-retry'), findsNothing);

    await tester.tap(byKey('biometric-ok'));
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(byKey('pin-input'), findsOneWidget);
    expect(
      find.text(ArabicMessages.biometricMappingMissing),
      findsOneWidget,
      reason: 'the reason stays on the PIN screen',
    );
    expect(h.backend.biometricStatusRequests, isEmpty);
    expect(_logins(h), 1);
  });

  testWidgets('no attempt → retry; «إعادة المحاولة» re-submits without '
      're-typing', (tester) async {
    final h = _gated()..backend.biometricAttemptsAvailable = false;
    await pumpGrindingApp(tester, h);
    await loginWithPin(tester, Fx.pinA);
    expect(_phase('retry'), findsOneWidget);
    expect(
      _inDialog(ArabicMessages.biometricVerificationRequired),
      findsOneWidget,
    );
    expect(h.backend.biometricStatusRequests, isEmpty);

    h.backend.scanFingerprint(Fx.workerA);
    await tester.tap(byKey('biometric-retry'));
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(byKey('worker-name'), findsOneWidget);
    expect(_logins(h), 2);
    expect(h.backend.requestsTo('/auth/pin').last.body, <String, dynamic>{
      'pin': Fx.pinA,
    });
  });

  testWidgets('attempt expires (410) → retry; retry opens a fresh attempt', (
    tester,
  ) async {
    final h = _gated();
    await pumpGrindingApp(tester, h);
    await loginWithPin(tester, Fx.pinA);
    h.backend.expireBiometricAttempts();
    await tester.pumpAndSettle();
    expect(_phase('retry'), findsOneWidget);
    expect(_inDialog(ArabicMessages.biometricRetry), findsOneWidget);

    await tester.tap(byKey('biometric-retry'));
    await tester.pumpAndSettle();
    expect(_phase('waiting'), findsOneWidget);
    expect(h.backend.biometricAttempts, hasLength(2));
    expect(_logins(h), 2);
  });

  testWidgets('«إلغاء» closes the dialog and stops polling', (tester) async {
    final h = _gated();
    await pumpGrindingApp(tester, h);
    await loginWithPin(tester, Fx.pinA);
    final polls = h.backend.biometricStatusRequests.length;

    await tester.tap(byKey('biometric-cancel'));
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(byKey('pin-input'), findsOneWidget);
    expect(h.backend.biometricPollsAborted, 1, reason: 'held poll aborted');

    h.backend.scanFingerprint(Fx.workerA);
    await tester.pumpAndSettle();
    expect(h.backend.biometricStatusRequests, hasLength(polls));
    expect(_logins(h), 1);
    expect(byKey('worker-name'), findsNothing);
  });

  testWidgets('PIN changed meanwhile → dialog closes, credential error shown', (
    tester,
  ) async {
    final h = _gated();
    await pumpGrindingApp(tester, h);
    await loginWithPin(tester, Fx.pinA);
    h.backend
      ..changePin(Fx.workerA, '7777')
      ..scanFingerprint(Fx.workerA);
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    expect(find.text(ArabicMessages.pinInvalid), findsOneWidget);
  });

  testWidgets('a non-biometric 403 never opens the dialog', (tester) async {
    final h = _gated();
    await pumpGrindingApp(tester, h);
    await loginWithPin(tester, Fx.pinNotAllowed);
    expect(_dialog, findsNothing);
    expect(find.text(ArabicMessages.workerNotAllowed), findsOneWidget);
  });

  testWidgets('two quick taps on «دخول» → one login, one dialog', (
    tester,
  ) async {
    final h = _gated();
    await pumpGrindingApp(tester, h);
    await tester.enterText(byKey('pin-input'), Fx.pinA);
    await tester.pump();
    await tester.tap(byKey('pin-submit'));
    await tester.tap(byKey('pin-submit'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_dialog, findsOneWidget);
    expect(_logins(h), 1);
  });

  testWidgets('app resume polls at once', (tester) async {
    final h = _gated();
    await pumpGrindingApp(tester, h);
    await loginWithPin(tester, Fx.pinA);
    final polls = h.backend.biometricStatusRequests.length;
    ProviderScope.containerOf(
      tester.element(find.byType(GrindingApp)),
    ).read(lifecycleResumeProvider.notifier).onResume();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(h.backend.biometricStatusRequests, hasLength(polls + 1));
    expect(_phase('waiting'), findsOneWidget);
  });
}
