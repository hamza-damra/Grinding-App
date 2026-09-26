import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_grinding_app/core/auth/auth_session.dart';
import 'package:flutter_grinding_app/core/config/app_config.dart';
import 'package:flutter_grinding_app/core/errors/app_failure.dart';
import 'package:flutter_grinding_app/core/errors/arabic_messages.dart';
import 'package:flutter_grinding_app/core/errors/error_codes.dart';
import 'package:flutter_grinding_app/features/grinding_auth/data/grinding_auth_repository_impl.dart';
import 'package:flutter_grinding_app/features/grinding_auth/presentation/state/biometric_login_controller.dart';
import 'package:flutter_grinding_app/features/grinding_auth/presentation/state/grinding_auth_controller.dart';
import 'package:flutter_grinding_app/features/grinding_auth/presentation/state/grinding_auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../support/fake_grinding_backend.dart';
import '../../support/test_harness.dart';

const String _statusSuffix = '/login-attempts/status';

/// Harness with the biometric gate switched on (the backend default is off).
GrindingTestHarness _gated() =>
    GrindingTestHarness()..backend.setBiometricEnforced(true);

/// Logs in with [pin] and returns the biometric refusal it must produce.
Future<BiometricDeniedFailure> _denied(
  ProviderContainer c, [
  String pin = Fx.pinA,
]) async {
  await c.read(grindingAuthControllerProvider.future);
  final failure = await c
      .read(grindingAuthControllerProvider.notifier)
      .login(pin);
  expect(failure, isA<BiometricDeniedFailure>());
  return failure! as BiometricDeniedFailure;
}

BiometricLoginController _gate(
  ProviderContainer c,
  BiometricDeniedFailure refusal, {
  String pin = Fx.pinA,
  List<Duration> backoff = const <Duration>[Duration.zero],
}) {
  final gate = BiometricLoginController(
    pin: pin,
    denial: refusal.denial,
    repository: c.read(grindingAuthRepositoryProvider),
    resubmit: c.read(grindingAuthControllerProvider.notifier).login,
    backoff: backoff,
  );
  addTearDown(gate.dispose);
  return gate;
}

/// Lets the real Dio chain run until [done] holds.
Future<void> _until(bool Function() done, {String? reason}) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: reason);
}

Future<void> _untilPhase(BiometricLoginController g, BiometricGatePhase p) =>
    _until(() => g.state.phase == p, reason: 'phase ${g.state.phase} != $p');

/// The long-poll is held once the server answered and the next poll is out.
Future<void> _untilHeld(GrindingTestHarness h, int polls) => _until(
  () => h.backend.biometricStatusRequests.length >= polls,
  reason: 'expected $polls status polls',
);

Future<void> _idle() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GrindingAuthState? _auth(ProviderContainer c) =>
    c.read(grindingAuthControllerProvider).valueOrNull;

int _logins(GrindingTestHarness h) => h.backend.requestsTo('/auth/pin').length;

class _CaptureOutput extends LogOutput {
  final List<String> lines = <String>[];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

class _AlwaysFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => true;
}

void main() {
  setUpAll(silenceNetworkLogs);

  group('login refusal', () {
    test('a BIOMETRIC_* 403 is a typed failure; nothing is stored', () async {
      final h = _gated();
      final c = h.container();
      final refusal = await _denied(c);
      final denial = refusal.denial;
      expect(denial.code, ErrorCodes.biometricVerificationRequired);
      expect(denial.message, ArabicMessages.biometricVerificationRequired);
      expect(denial.validitySeconds, 300);
      expect(denial.hasAttempt, isTrue);
      expect(denial.attemptToken, h.backend.biometricAttempts.keys.single);
      expect(denial.attemptExpiresAt, DateTime.utc(2026, 9, 24, 8, 15));
      expect(denial.statusPath, FakeGrindingBackend.biometricStatusPath);
      expect(
        (_auth(c)! as GrindingAuthUnauthenticated).lastError,
        refusal,
        reason: 'kept for the PIN screen, not counted as a wrong PIN',
      );
      expect(await h.tokens.readSessionToken(), isNull);
      expect(await h.prefs.readLastWorker(), isNull);
      expect(c.read(authSessionProvider).hasToken, isFalse);
      expect(h.backend.sessions, isEmpty, reason: 'no session was created');
    });

    test('an ignored login reports cancelled, not success', () async {
      final h = _gated();
      final c = h.container();
      await c.read(grindingAuthControllerProvider.future);
      final notifier = c.read(grindingAuthControllerProvider.notifier);
      expect(await notifier.login('12'), const AppFailure.cancelled());
      final results = await Future.wait(<Future<AppFailure?>>[
        notifier.login(Fx.pinA),
        notifier.login(Fx.pinA),
      ]);
      expect(results[1], const AppFailure.cancelled());
      expect(_logins(h), 1);
    });
  });

  group('status → state', () {
    test('403 with a token → waiting with the server message; polls', () async {
      final h = _gated();
      final c = h.container();
      final g = _gate(c, await _denied(c))..start();
      expect(g.state.phase, BiometricGatePhase.waiting);
      expect(g.state.message, ArabicMessages.biometricVerificationRequired);
      await _untilHeld(h, 2);
      expect(g.state.phase, BiometricGatePhase.waiting);
      expect(_logins(h), 1);
    });

    test(
      'scan → VERIFIED → exactly one re-submit → signed in; secrets dropped',
      () async {
        final h = _gated();
        final c = h.container();
        final g = _gate(c, await _denied(c))..start();
        await _untilHeld(h, 2);
        h.backend.scanFingerprint(Fx.workerA);
        await _untilPhase(g, BiometricGatePhase.succeeded);
        expect(_logins(h), 2);
        expect(_auth(c), isA<GrindingAuthAuthenticated>());
        expect(g.holdsAttempt, isFalse);
        expect(g.holdsPin, isFalse);
        expect(
          h.backend.requestsTo('/auth/pin').last.body,
          <String, dynamic>{'pin': Fx.pinA},
          reason: 'the original body, re-submitted as is',
        );
        await _idle();
        expect(h.backend.biometricStatusRequests, hasLength(2));
      },
    );

    for (final entry in <String, void Function(FakeGrindingBackend)>{
      'ENFORCEMENT_SUSPENDED (agent offline)': (b) =>
          b.setBiometricAgentOnline(false),
      'NOT_REQUIRED (check switched off)': (b) => b.setBiometricEnforced(false),
      'NOT_REQUIRED (employee exempted)': (b) =>
          b.exemptFromBiometric(Fx.workerA),
    }.entries) {
      test('${entry.key} → one re-submit → signed in', () async {
        final h = _gated();
        final c = h.container();
        final g = _gate(c, await _denied(c))..start();
        await _untilHeld(h, 2);
        entry.value(h.backend);
        await _untilPhase(g, BiometricGatePhase.succeeded);
        expect(_logins(h), 2);
        expect(_auth(c), isA<GrindingAuthAuthenticated>());
      });
    }

    test(
      'DEVICE_UNAVAILABLE refusal → deviceOffline with the server message',
      () async {
        final h = _gated()..backend.setBiometricTerminalOnline(false);
        final c = h.container();
        final g = _gate(c, await _denied(c))..start();
        expect(g.state.phase, BiometricGatePhase.deviceOffline);
        expect(g.state.message, ArabicMessages.biometricDeviceUnavailable);
        await _untilHeld(h, 2);
        h.backend.setBiometricTerminalOnline(true);
        await _untilPhase(g, BiometricGatePhase.waiting);
        expect(g.state.message, isNull, reason: 'not the phase it was for');
        h.backend.scanFingerprint(Fx.workerA);
        await _untilPhase(g, BiometricGatePhase.succeeded);
      },
    );

    test(
      'status DEVICE_UNAVAILABLE while waiting → deviceOffline, keeps polling',
      () async {
        final h = _gated();
        final c = h.container();
        final g = _gate(c, await _denied(c))..start();
        await _untilHeld(h, 2);
        h.backend.setBiometricTerminalOnline(false);
        await _untilPhase(g, BiometricGatePhase.deviceOffline);
        expect(g.state.message, isNull);
        await _untilHeld(h, 3);
        h.backend.setBiometricTerminalOnline(true);
        await _untilPhase(g, BiometricGatePhase.waiting);
        expect(
          g.state.message,
          ArabicMessages.biometricVerificationRequired,
          reason: 'back in the phase the 403 described',
        );
        expect(_logins(h), 1);
      },
    );

    for (final entry in <FakeBiometricMapping, String>{
      FakeBiometricMapping.missing: ArabicMessages.biometricMappingMissing,
      FakeBiometricMapping.disabled: ArabicMessages.biometricMappingDisabled,
    }.entries) {
      test('status MAPPING_${entry.key.name.toUpperCase()} → contact admin; '
          'polling stops, no re-submit', () async {
        final h = _gated();
        final c = h.container();
        final g = _gate(c, await _denied(c))..start();
        await _untilHeld(h, 2);
        h.backend.setBiometricMapping(Fx.workerA, entry.key);
        await _untilPhase(g, BiometricGatePhase.contactAdmin);
        expect(g.state.message, entry.value);
        expect(g.holdsAttempt, isFalse);
        expect(g.holdsPin, isFalse);
        await _idle();
        expect(h.backend.biometricStatusRequests, hasLength(2));
        expect(_logins(h), 1);
      });

      test('403 MAPPING_${entry.key.name.toUpperCase()} → contact admin with '
          'the server message; never polls', () async {
        final h = _gated()..backend.setBiometricMapping(Fx.workerA, entry.key);
        final c = h.container();
        final refusal = await _denied(c);
        expect(refusal.denial.hasAttempt, isFalse);
        final g = _gate(c, refusal)..start();
        expect(g.state.phase, BiometricGatePhase.contactAdmin);
        expect(g.state.message, entry.value);
        await _idle();
        expect(h.backend.biometricStatusRequests, isEmpty);
        expect(_logins(h), 1);
      });
    }

    test('unknown status value → treated as PENDING', () async {
      final h = _gated();
      h.backend.faults.add(
        FakeFault(
          FaultKind.custom,
          pathEndsWith: _statusSuffix,
          response: FakeGrindingBackend.biometricStatus('SOMETHING_NEW'),
        ),
      );
      final c = h.container();
      final g = _gate(c, await _denied(c))..start();
      await _untilHeld(h, 3);
      expect(g.state.phase, BiometricGatePhase.waiting);
      expect(_logins(h), 1);
    });
  });

  group('retry', () {
    test('no token → retry without polling; «إعادة المحاولة» re-submits '
        'once and opens a fresh attempt', () async {
      final h = _gated()..backend.biometricAttemptsAvailable = false;
      final c = h.container();
      final refusal = await _denied(c);
      expect(refusal.denial.attemptAvailable, isFalse);
      expect(refusal.denial.attemptToken, isNull);
      final g = _gate(c, refusal)..start();
      expect(g.state.phase, BiometricGatePhase.retry);
      expect(g.state.message, ArabicMessages.biometricVerificationRequired);
      await _idle();
      expect(h.backend.biometricStatusRequests, isEmpty);

      h.backend.biometricAttemptsAvailable = true;
      await g.retry();
      expect(_logins(h), 2);
      expect(g.state.phase, BiometricGatePhase.waiting);
      await _untilHeld(h, 2);
      expect(
        h.backend.biometricStatusRequests.map((r) => r.attemptToken).toSet(),
        <String>{h.backend.biometricAttempts.keys.single},
      );
    });

    test(
      '410 → retry; «إعادة المحاولة» re-submits the original login',
      () async {
        final h = _gated();
        final c = h.container();
        final g = _gate(c, await _denied(c))..start();
        await _untilHeld(h, 2);
        h.backend.expireBiometricAttempts();
        await _untilPhase(g, BiometricGatePhase.retry);
        expect(g.state.message, isNull, reason: 'the dialog words a 410');
        expect(g.holdsAttempt, isFalse);

        h.backend.scanFingerprint(Fx.workerA);
        await g.retry();
        expect(g.state.phase, BiometricGatePhase.succeeded);
        expect(_logins(h), 2);
        expect(_auth(c), isA<GrindingAuthAuthenticated>());
      },
    );

    test('a 410 without the envelope also ends polling', () async {
      final h = _gated();
      h.backend.faults.add(
        FakeFault(
          FaultKind.custom,
          pathEndsWith: _statusSuffix,
          response: FakeGrindingBackend.jsonResponse(410, 'Gone'),
        ),
      );
      final c = h.container();
      final g = _gate(c, await _denied(c))..start();
      await _untilPhase(g, BiometricGatePhase.retry);
      expect(h.backend.biometricStatusRequests, hasLength(1));
    });

    test('retry while offline → retry again with «انقطع الاتصال»', () async {
      final h = _gated()..backend.biometricAttemptsAvailable = false;
      final c = h.container();
      final g = _gate(c, await _denied(c))..start();
      h.backend.faults.add(
        FakeFault(FaultKind.connectionError, pathEndsWith: '/auth/pin'),
      );
      await g.retry();
      expect(g.state.phase, BiometricGatePhase.retry);
      expect(g.state.message, ArabicMessages.networkLost);
      expect(g.holdsPin, isTrue, reason: 'the next retry still needs it');
    });
  });

  group('re-submit', () {
    test('fingerprint expired between VERIFIED and the re-submit → the new '
        'attempt replaces the old one; no re-submit loop', () async {
      final h = _gated();
      final c = h.container();
      final first = await _denied(c);
      final oldToken = first.denial.attemptToken!;
      // The status sees a valid scan, but by the time the login is
      // re-submitted the punch is too old.
      h.backend.ageFingerprint(Fx.workerA);
      h.backend.faults.add(
        FakeFault(
          FaultKind.custom,
          pathEndsWith: _statusSuffix,
          response: FakeGrindingBackend.biometricStatus('VERIFIED'),
        ),
      );
      final g = _gate(c, first)..start();
      await _until(() => _logins(h) == 2);
      await _untilPhase(g, BiometricGatePhase.waiting);
      expect(g.state.message, ArabicMessages.biometricVerificationExpired);
      await _untilHeld(h, 3);
      final tokens = h.backend.biometricStatusRequests
          .map((r) => r.attemptToken)
          .toList();
      final newToken = h.backend.biometricAttempts.keys.last;
      expect(newToken, isNot(oldToken));
      expect(tokens, <String>[oldToken, newToken, newToken]);
      await _idle();
      expect(_logins(h), 2, reason: 'one re-submit per status answer');

      h.backend.scanFingerprint(Fx.workerA);
      await _untilPhase(g, BiometricGatePhase.succeeded);
      expect(_logins(h), 3);
    });

    test('PIN changed meanwhile → failed; the credential error is kept for '
        'the PIN screen', () async {
      final h = _gated();
      final c = h.container();
      final g = _gate(c, await _denied(c))..start();
      await _untilHeld(h, 2);
      h.backend
        ..changePin(Fx.workerA, '7777')
        ..scanFingerprint(Fx.workerA);
      await _untilPhase(g, BiometricGatePhase.failed);
      expect(
        (_auth(c)! as GrindingAuthUnauthenticated).lastError,
        isA<ApiFailure>().having(
          (f) => f.code,
          'code',
          ErrorCodes.operatorPinInvalid,
        ),
      );
      expect(g.holdsPin, isFalse);
      expect(g.holdsAttempt, isFalse);
    });

    test('the re-submit loses the connection → polls again and re-submits '
        'once more on the next VERIFIED', () async {
      final h = _gated();
      final c = h.container();
      final g = _gate(c, await _denied(c))..start();
      await _untilHeld(h, 2);
      h.backend.faults.add(
        FakeFault(FaultKind.connectionError, pathEndsWith: '/auth/pin'),
      );
      h.backend.scanFingerprint(Fx.workerA);
      await _untilPhase(g, BiometricGatePhase.succeeded);
      expect(_logins(h), 3);
      expect(h.backend.biometricStatusRequests, hasLength(3));
    });
  });

  group('network, cancel, resume', () {
    test('status errors back off 1 s, 2 s, 4 s, 10 s, 10 s and recover', () {
      fakeAsync((async) {
        final h = _gated();
        final c = h.container();
        BiometricDeniedFailure? refusal;
        unawaited(
          c
              .read(grindingAuthControllerProvider.future)
              .then(
                (_) => c
                    .read(grindingAuthControllerProvider.notifier)
                    .login(Fx.pinA),
              )
              .then((f) => refusal = f! as BiometricDeniedFailure),
        );
        async.elapse(const Duration(milliseconds: 10));
        expect(refusal, isNotNull);

        h.backend.faults.add(
          FakeFault(
            FaultKind.connectionError,
            pathEndsWith: _statusSuffix,
            times: 5,
          ),
        );
        final g = _gate(c, refusal!, backoff: AppConfig.biometricPollBackoff)
          ..start();
        async.elapse(Duration.zero);
        int polls() => h.backend.biometricStatusRequests.length;
        expect(polls(), 1);
        expect(g.state.phase, BiometricGatePhase.network);

        for (final (wait, expected) in <(Duration, int)>[
          (const Duration(seconds: 1), 2),
          (const Duration(seconds: 2), 3),
          (const Duration(seconds: 4), 4),
          (const Duration(seconds: 10), 5),
          (const Duration(seconds: 10), 6),
        ]) {
          async.elapse(wait - const Duration(milliseconds: 1));
          expect(polls(), expected - 1, reason: 'too early for #$expected');
          async.elapse(const Duration(milliseconds: 1));
          expect(polls(), greaterThanOrEqualTo(expected));
        }
        // The 6th poll got through: PENDING, and the 7th is held.
        expect(g.state.phase, BiometricGatePhase.waiting);
        expect(polls(), 7);
        g.dispose();
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('«إلغاء» stops polling, aborts the held poll and drops the token '
        'and the PIN', () async {
      final h = _gated();
      final c = h.container();
      final g = _gate(c, await _denied(c))..start();
      await _untilHeld(h, 2);
      g.cancel();
      expect(g.holdsAttempt, isFalse);
      expect(g.holdsPin, isFalse);
      await _until(() => h.backend.biometricPollsAborted == 1);
      h.backend.scanFingerprint(Fx.workerA);
      await _idle();
      expect(h.backend.biometricStatusRequests, hasLength(2));
      expect(_logins(h), 1);
      expect(_auth(c), isA<GrindingAuthUnauthenticated>());
    });

    test('app resume polls immediately (held poll or backoff)', () async {
      final h = _gated();
      final c = h.container();
      final g = _gate(
        c,
        await _denied(c),
        backoff: const <Duration>[Duration(minutes: 5)],
      )..start();
      await _untilHeld(h, 2);
      g.onAppResumed();
      await _untilHeld(h, 3);
      await _until(() => h.backend.biometricPollsAborted == 1);

      h.backend.faults.add(
        FakeFault(FaultKind.connectionError, pathEndsWith: _statusSuffix),
      );
      h.backend.setBiometricTerminalOnline(false); // wakes the held poll
      await _untilHeld(h, 4);
      await _untilPhase(g, BiometricGatePhase.network);
      g.onAppResumed(); // skips the 5-minute backoff
      await _untilHeld(h, 5);
    });
  });

  test(
    'the attempt token never reaches a log and is never persisted',
    () async {
      final output = _CaptureOutput();
      final prints = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) =>
          prints.add(message ?? '');
      addTearDown(() => debugPrint = originalDebugPrint);

      final h = GrindingTestHarness(
        logger: Logger(
          filter: _AlwaysFilter(),
          output: output,
          printer: SimplePrinter(colors: false),
        ),
      )..backend.setBiometricEnforced(true);
      final c = h.container();
      final refusal = await _denied(c);
      final token = refusal.denial.attemptToken!;
      h.backend.faults.add(
        FakeFault(FaultKind.connectionError, pathEndsWith: _statusSuffix),
      );
      final g = _gate(c, refusal)..start();
      await _untilHeld(h, 3);
      h.backend.scanFingerprint(Fx.workerA);
      await _untilPhase(g, BiometricGatePhase.succeeded);

      final log = output.lines.join('\n');
      expect(log, contains(FakeGrindingBackend.biometricStatusPath));
      expect(log, isNot(contains(token)));
      expect(prints.join('\n'), isNot(contains(token)));
      for (final text in <String>[
        refusal.toString(),
        refusal.denial.toString(),
        g.state.toString(),
      ]) {
        expect(text, isNot(contains(token)));
      }
      expect(await h.tokens.readSessionToken(), isNot(token));
      final cached = await h.prefs.readLastWorker();
      expect(<Object?>[
        cached?.name,
        cached?.expiresAt,
      ], everyElement(isNot(contains(token))));
      expect(
        h.memoryPending.log.join(),
        isNot(contains(token)),
        reason: 'nothing biometric goes near the durable store',
      );
    },
  );
}
