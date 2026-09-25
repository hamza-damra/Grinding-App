import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_grinding_app/core/auth/auth_session.dart';
import 'package:flutter_grinding_app/core/config/app_config.dart';
import 'package:flutter_grinding_app/core/config/config_providers.dart';
import 'package:flutter_grinding_app/core/errors/app_failure.dart';
import 'package:flutter_grinding_app/core/errors/error_codes.dart';
import 'package:flutter_grinding_app/core/storage/prefs_store.dart';
import 'package:flutter_grinding_app/features/grinding_auth/presentation/state/grinding_auth_controller.dart';
import 'package:flutter_grinding_app/features/grinding_auth/presentation/state/grinding_auth_state.dart';
import 'package:flutter_grinding_app/features/grinding_auth/presentation/state/logout_reason.dart';
import 'package:flutter_grinding_app/features/grinding_auth/presentation/state/session_invalidation_listener.dart';
import 'package:flutter_grinding_app/features/grinding_orders/data/grinding_orders_repository_impl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_grinding_backend.dart';
import '../../support/test_harness.dart';

Future<GrindingAuthState> _auth(ProviderContainer c) =>
    c.read(grindingAuthControllerProvider.future);

GrindingAuthState? _now(ProviderContainer c) =>
    c.read(grindingAuthControllerProvider).valueOrNull;

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderContainer _withListener(GrindingTestHarness h) {
  final c = h.container();
  c.listen(sessionInvalidationListenerProvider, (_, _) {});
  return c;
}

void main() {
  setUpAll(silenceNetworkLogs);

  group('restore on launch', () {
    test('no token → PIN, no network call', () async {
      final h = GrindingTestHarness();
      final state = await _auth(h.container());
      expect(state, isA<GrindingAuthUnauthenticated>());
      expect(h.backend.requests, isEmpty);
    });

    test('valid token → verified with /sessions/me, identity cached', () async {
      final h = GrindingTestHarness();
      await h.signedIn(Fx.workerA);
      final state = await _auth(h.container());
      expect(state, isA<GrindingAuthAuthenticated>());
      expect((state as GrindingAuthAuthenticated).worker.name, Fx.workerAName);
      expect(state.expiresAt, '2026-09-22T21:41:07.312Z');
      expect(h.backend.requests.single.path, endsWith('/sessions/me'));
      final cached = await h.prefs.readLastWorker();
      expect(cached?.operatorId, Fx.workerA);
    });

    test('replaced / ended token → cleared, PIN with the reason', () async {
      final h = GrindingTestHarness();
      final token = await h.signedIn(Fx.workerA);
      h.backend.endSession(token);
      final state = await _auth(h.container());
      expect(state, isA<GrindingAuthUnauthenticated>());
      expect(
        (state as GrindingAuthUnauthenticated).lastError,
        isA<ApiFailure>().having(
          (f) => f.code,
          'code',
          ErrorCodes.sessionInvalid,
        ),
      );
      expect(await h.tokens.readSessionToken(), isNull);
    });

    test('expired session → cleared', () async {
      final h = GrindingTestHarness();
      h.backend.expireSession(await h.signedIn(Fx.workerA));
      final state = await _auth(h.container());
      expect(
        (state as GrindingAuthUnauthenticated).lastError,
        isA<ApiFailure>().having(
          (f) => f.code,
          'code',
          ErrorCodes.sessionExpired,
        ),
      );
      expect(await h.tokens.readSessionToken(), isNull);
    });

    test('network down → cached identity kept, token kept', () async {
      final h = GrindingTestHarness(
        prefs: InMemoryPrefsStore(
          lastWorker: const LastWorker(
            operatorId: Fx.workerA,
            name: Fx.workerAName,
          ),
        ),
      );
      final token = await h.signedIn(Fx.workerA);
      h.backend.faults.add(FakeFault(FaultKind.connectionError, times: 2));
      final state = await _auth(h.container());
      expect(state, isA<GrindingAuthAuthenticated>());
      expect(await h.tokens.readSessionToken(), token);
    });

    test('a build without configuration sends nothing', () async {
      final h = GrindingTestHarness();
      await h.signedIn(Fx.workerA);
      final c = h.container(
        extra: <Override>[
          appConfigProblemProvider.overrideWithValue(
            ConfigProblem.missingDeviceKey,
          ),
        ],
      );
      final state = await _auth(c);
      expect(
        (state as GrindingAuthUnauthenticated).lastError,
        isA<AppNotConfiguredFailure>(),
      );
      expect(h.backend.requests, isEmpty);
    });
  });

  group('login', () {
    test('wrong PIN → inline error, nothing stored', () async {
      final h = GrindingTestHarness();
      final c = h.container();
      await _auth(c);
      await c.read(grindingAuthControllerProvider.notifier).login('0000');
      final state = _now(c)! as GrindingAuthUnauthenticated;
      expect(
        state.lastError,
        isA<ApiFailure>().having(
          (f) => f.code,
          'code',
          ErrorCodes.operatorPinInvalid,
        ),
      );
      expect(await h.tokens.readSessionToken(), isNull);
    });

    test('not a grinding worker → «غير مخوّل» inline, no session', () async {
      final h = GrindingTestHarness();
      final c = h.container();
      await _auth(c);
      await c
          .read(grindingAuthControllerProvider.notifier)
          .login(Fx.pinNotAllowed);
      expect(
        (_now(c)! as GrindingAuthUnauthenticated).lastError,
        isA<ApiFailure>().having(
          (f) => f.code,
          'code',
          ErrorCodes.workerNotAllowed,
        ),
      );
    });

    test(
      'success → token in the secure store only; PIN kept nowhere',
      () async {
        final h = GrindingTestHarness();
        final c = h.container();
        await _auth(c);
        await c.read(grindingAuthControllerProvider.notifier).login(Fx.pinA);
        final state = _now(c)! as GrindingAuthAuthenticated;
        expect(state.worker.operatorId, Fx.workerA);
        final token = await h.tokens.readSessionToken();
        expect(token, h.backend.activeTokenFor(Fx.workerA));
        expect(c.read(authSessionProvider).token, token);
        final cached = await h.prefs.readLastWorker();
        expect(cached?.name, Fx.workerAName);
        expect(<Object?>[
          token,
          cached?.name,
          cached?.expiresAt,
        ], everyElement(isNot(contains(Fx.pinA))));
      },
    );

    test('invalid PIN format never reaches the network', () async {
      final h = GrindingTestHarness();
      final c = h.container();
      await _auth(c);
      await c.read(grindingAuthControllerProvider.notifier).login('12');
      expect(h.backend.requests, isEmpty);
    });

    test('single-flight: a double submit sends one login', () async {
      final h = GrindingTestHarness();
      final c = h.container();
      await _auth(c);
      final notifier = c.read(grindingAuthControllerProvider.notifier);
      await Future.wait(<Future<void>>[
        notifier.login(Fx.pinA),
        notifier.login(Fx.pinA),
      ]);
      expect(h.backend.requestsTo('/auth/pin'), hasLength(1));
    });

    test('each login opens a new auth generation', () async {
      final h = GrindingTestHarness();
      final c = h.container();
      await _auth(c);
      final before = c.read(authSessionProvider).generation;
      await c.read(grindingAuthControllerProvider.notifier).login(Fx.pinA);
      expect(c.read(authSessionProvider).generation, greaterThan(before));
    });
  });

  group('logout', () {
    test('ends the session server-side and clears everything local', () async {
      final h = GrindingTestHarness();
      final token = await h.signedIn(Fx.workerA);
      final c = h.container();
      await _auth(c);
      await c.read(grindingAuthControllerProvider.notifier).logout();
      expect(_now(c), isA<GrindingAuthUnauthenticated>());
      expect(h.backend.requestsTo('/auth/logout').single.sessionToken, token);
      expect(h.backend.sessions[token]!.usable, isFalse);
      expect(await h.tokens.readSessionToken(), isNull);
      expect(await h.prefs.readLastWorker(), isNull);
      expect(c.read(authSessionProvider).hasToken, isFalse);
      expect(c.read(logoutReasonProvider), LogoutReason.manualLogout);
    });

    test('no network → still logged out locally', () async {
      final h = GrindingTestHarness();
      await h.signedIn(Fx.workerA);
      final c = h.container();
      await _auth(c);
      h.backend.faults.add(FakeFault(FaultKind.connectionError));
      await c.read(grindingAuthControllerProvider.notifier).logout();
      expect(_now(c), isA<GrindingAuthUnauthenticated>());
      expect(await h.tokens.readSessionToken(), isNull);
    });

    test('a hanging logout call gives up after the short timeout', () {
      fakeAsync((async) {
        final h = GrindingTestHarness();
        h.backend.issueSession(Fx.workerA);
        unawaited(
          h.tokens.writeSessionToken(h.backend.activeTokenFor(Fx.workerA)!),
        );
        final c = h.container();
        GrindingAuthState? restored;
        unawaited(_auth(c).then((s) => restored = s));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        expect(restored, isA<GrindingAuthAuthenticated>());

        h.backend.faults.add(
          FakeFault(FaultKind.hang, pathEndsWith: '/auth/logout'),
        );
        var done = false;
        unawaited(
          c
              .read(grindingAuthControllerProvider.notifier)
              .logout()
              .then((_) => done = true),
        );
        async.elapse(AppConfig.logoutTimeout - const Duration(seconds: 1));
        expect(done, isFalse);
        async.elapse(const Duration(seconds: 2));
        expect(done, isTrue);
        expect(_now(c), isA<GrindingAuthUnauthenticated>());
      });
    });

    test('never touches pending START / COMPLETE records', () async {
      final h = GrindingTestHarness();
      await h.signedIn(Fx.workerA);
      final c = h.container();
      await _auth(c);
      await c.read(grindingAuthControllerProvider.notifier).logout();
      expect(h.memoryPending.log.where((e) => e.startsWith('remove')), isEmpty);
    });
  });

  group('session invalidation (contract §4.3)', () {
    test('an expired session on any call → PIN with the reason', () async {
      final h = GrindingTestHarness();
      final token = await h.signedIn(Fx.workerA);
      final c = _withListener(h);
      await _auth(c);
      h.backend.expireSession(token);
      await expectLater(
        c.read(grindingOrdersRepositoryProvider).check(Fx.readyNumber),
        throwsA(isA<ApiFailure>()),
      );
      await _settle();
      final state = _now(c)! as GrindingAuthUnauthenticated;
      expect(
        state.lastError,
        isA<ApiFailure>().having(
          (f) => f.code,
          'code',
          ErrorCodes.sessionExpired,
        ),
      );
      expect(await h.tokens.readSessionToken(), isNull);
    });

    test('access withdrawn mid-shift → PIN with «غير مخوّل»', () async {
      final h = GrindingTestHarness();
      await h.signedIn(Fx.workerA);
      final c = _withListener(h);
      await _auth(c);
      h.backend.revokeWorker(Fx.workerA);
      await expectLater(
        c.read(grindingOrdersRepositoryProvider).check(Fx.readyNumber),
        throwsA(isA<ApiFailure>()),
      );
      await _settle();
      expect(
        (_now(c)! as GrindingAuthUnauthenticated).lastError,
        isA<ApiFailure>().having(
          (f) => f.code,
          'code',
          ErrorCodes.workerNotAllowed,
        ),
      );
    });

    test(
      'device rejection keeps the session (admin problem, not the worker)',
      () async {
        final h = GrindingTestHarness();
        await h.signedIn(Fx.workerA);
        final c = _withListener(h);
        await _auth(c);
        h.backend.faults.add(FakeFault(FaultKind.deviceUnauthorized));
        await expectLater(
          c.read(grindingOrdersRepositoryProvider).check(Fx.readyNumber),
          throwsA(isA<DeviceNotAuthorizedFailure>()),
        );
        await _settle();
        expect(_now(c), isA<GrindingAuthAuthenticated>());
        expect(await h.tokens.readSessionToken(), isNotNull);
      },
    );

    test('a late 401 for worker A never logs out worker B', () async {
      final h = GrindingTestHarness();
      await h.signedIn(Fx.workerA);
      final c = _withListener(h);
      await _auth(c);

      // Worker A's /check is on the wire when the session changes hands.
      final release = Completer<void>();
      final arrived = Completer<void>();
      h.backend.onRequest = (r) async {
        if (r.path.endsWith('/check') && !arrived.isCompleted) {
          arrived.complete();
        }
      };
      h.backend.faults.add(
        FakeFault(
          FaultKind.hang,
          pathEndsWith: '/check',
          release: release,
          thenCommit: true,
        ),
      );
      final late = c
          .read(grindingOrdersRepositoryProvider)
          .check(Fx.readyNumber)
          .then<Object?>((v) => v, onError: (Object e) => e);
      await arrived.future;

      final auth = c.read(grindingAuthControllerProvider.notifier);
      await auth.logout();
      await auth.login(Fx.pinB);
      expect(_now(c), isA<GrindingAuthAuthenticated>());

      release.complete(); // A's token is now ended → 401 SESSION_INVALID.
      expect(await late, isA<ApiFailure>());
      await _settle();

      final state = _now(c)! as GrindingAuthAuthenticated;
      expect(state.worker.operatorId, Fx.workerB);
      expect(await h.tokens.readSessionToken(), isNotNull);
    });

    test('verifySession: transient failure keeps the session', () async {
      final h = GrindingTestHarness();
      await h.signedIn(Fx.workerA);
      final c = _withListener(h);
      await _auth(c);
      h.backend.faults.add(FakeFault(FaultKind.connectionError, times: 2));
      await c.read(grindingAuthControllerProvider.notifier).verifySession();
      expect(_now(c), isA<GrindingAuthAuthenticated>());
    });

    test('verifySession: session replaced elsewhere → PIN', () async {
      final h = GrindingTestHarness();
      final token = await h.signedIn(Fx.workerA);
      final c = _withListener(h);
      await _auth(c);
      h.backend.endSession(token);
      await c.read(grindingAuthControllerProvider.notifier).verifySession();
      await _settle();
      expect(_now(c), isA<GrindingAuthUnauthenticated>());
    });
  });
}
