import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_grinding_app/core/api/api_paths.dart';
import 'package:flutter_grinding_app/core/api/interceptors/logging_interceptor.dart';
import 'package:flutter_grinding_app/core/api/session_invalidation_signal.dart';
import 'package:flutter_grinding_app/core/auth/auth_session.dart';
import 'package:flutter_grinding_app/core/errors/app_failure.dart';
import 'package:flutter_grinding_app/core/errors/error_codes.dart';
import 'package:flutter_grinding_app/features/grinding_auth/data/dtos/auth_dtos.dart';
import 'package:flutter_grinding_app/features/grinding_auth/data/grinding_auth_remote_data_source.dart';
import 'package:flutter_grinding_app/features/grinding_auth/data/grinding_auth_repository_impl.dart';
import 'package:flutter_grinding_app/features/grinding_auth/domain/entities/grinding_worker.dart';
import 'package:flutter_grinding_app/features/grinding_orders/data/dtos/check_dtos.dart';
import 'package:flutter_grinding_app/features/grinding_orders/data/grinding_orders_remote_data_source.dart';
import 'package:flutter_grinding_app/features/grinding_orders/data/grinding_orders_repository_impl.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/check_resolution.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_source.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../support/fake_grinding_backend.dart';
import '../../support/test_harness.dart';

class _Api {
  _Api({String baseUrl = testBaseUrl, Logger? logger}) {
    dio = buildTestDio(
      session: session,
      adapter: backend,
      signal: signal,
      baseUrl: baseUrl,
      logger: logger,
    );
    auth = GrindingAuthRepositoryImpl(GrindingAuthRemoteDataSource(dio));
    orders = GrindingOrdersRepositoryImpl(GrindingOrdersRemoteDataSource(dio));
    signal.stream.listen(events.add);
  }

  final FakeGrindingBackend backend = seededBackend();
  final AuthSession session = AuthSession();
  final SessionInvalidationSignal signal = SessionInvalidationSignal();
  final List<SessionInvalidation> events = <SessionInvalidation>[];
  late final Dio dio;
  late final GrindingAuthRepositoryImpl auth;
  late final GrindingOrdersRepositoryImpl orders;

  Future<void> login([String pin = Fx.pinA]) async {
    final result = await auth.loginWithPin(pin);
    session.replace(result.sessionToken);
  }
}

class _CaptureOutput extends LogOutput {
  final List<String> lines = <String>[];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

class _AlwaysFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => true;
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  setUpAll(silenceNetworkLogs);

  group('headers (contract §4.1)', () {
    test(
      'device key on all 7 endpoints; session token on all but login',
      () async {
        final api = _Api();
        await api.login();
        await api.auth.getSession();
        await api.orders.check(Fx.readyNumber);
        await api.orders.getQueue(GrindingQueueStatus.ready);
        await api.orders.execute(
          GrindingCommand.start,
          orderId: Fx.readyId,
          clientRequestId: 'cid-a',
        );
        await api.orders.execute(
          GrindingCommand.complete,
          orderId: Fx.readyId,
          clientRequestId: 'cid-b',
        );
        await api.auth.logout();

        final requests = api.backend.requests;
        expect(requests.map((r) => r.path), <String>[
          ApiPaths.authPin,
          ApiPaths.sessionsMe,
          ApiPaths.check,
          ApiPaths.orders,
          ApiPaths.orderStart(Fx.readyId),
          ApiPaths.orderComplete(Fx.readyId),
          ApiPaths.authLogout,
        ]);
        for (final r in requests) {
          expect(
            r.deviceKey,
            FakeGrindingBackend.testDeviceKey,
            reason: r.path,
          );
          expect(
            r.contentType,
            startsWith(ApiHeaders.contentTypeJson),
            reason: r.path,
          );
        }
        expect(requests.first.sessionToken, isNull, reason: 'login');
        for (final r in requests.skip(1)) {
          expect(r.sessionToken, api.session.token, reason: r.path);
        }
      },
    );

    test('the token never goes into a URL', () async {
      final api = _Api();
      await api.login();
      await api.orders.getQueue(GrindingQueueStatus.inGrinding);
      for (final r in api.backend.requests) {
        expect(r.uri.toString(), isNot(contains(api.session.token!)));
      }
      expect(api.backend.requests.last.uri.queryParameters, <String, String>{
        'status': 'IN_GRINDING',
      });
    });

    test('redirects are never followed (credentials stay on one host)', () {
      expect(_Api().dio.options.followRedirects, isFalse);
    });
  });

  group('envelope parsing', () {
    test('login / session / logout', () async {
      final api = _Api();
      final login = await api.auth.loginWithPin(Fx.pinA);
      expect(
        login.worker,
        const GrindingWorker(operatorId: 57, name: 'محمد أحمد'),
      );
      expect(login.expiresAt, '2026-09-22T21:41:07.312Z');
      api.session.replace(login.sessionToken);
      final session = await api.auth.getSession();
      expect(session.worker.operatorId, 57);
      expect(await api.auth.logout(), isTrue);
      expect(await api.auth.logout(), isFalse, reason: 'already ended');
    });

    test('check READY', () async {
      final api = _Api();
      await api.login();
      final check = await api.orders.check(Fx.readyNumber);
      expect(check.status, GrindingStatus.readyForGrinding);
      expect(check.allowedToStartGrinding, isTrue);
      expect(check.allowedToCompleteGrinding, isFalse);
      expect(check.order!.id, Fx.readyId);
      expect(check.order!.orderNumber, 'GR-001042');
      expect(check.order!.expectedWeightKg, '40.000');
      expect(check.order!.directScrap, isTrue);
      expect(check.message, 'جاهز للجرش — يمكنك بدء الجرش.');
      expect(api.backend.requests.last.body, <String, dynamic>{
        'identifier': Fx.readyNumber,
      });
    });

    test('check NOT_ELIGIBLE: no order, pallet details only', () async {
      final api = _Api();
      await api.login();
      final check = await api.orders.check(Fx.notEligibleNumber);
      expect(check.status, GrindingStatus.notEligible);
      expect(check.order, isNull);
      expect(check.notEligibleProductName, 'كاسة 250');
      expect(check.notEligibleQuantity, '1200');
    });

    test('both items actionable → ApiFailure 409 carrying both candidates; '
        'sourceType sent only on the answer', () async {
      final api = _Api();
      api.backend.seedSharedNumbers();
      await api.login();
      await expectLater(
        api.orders.check(Fx.bothActionableNumber),
        throwsA(
          isA<ApiFailure>()
              .having((f) => f.code, 'code', ErrorCodes.identifierAmbiguous)
              .having((f) => f.status, 'status', 409)
              .having(
                (f) => f.details?['resolution'],
                'resolution',
                'REQUIRES_SELECTION',
              )
              .having(
                (f) => (f.details?['candidates'] as List<Object?>).length,
                'candidates',
                2,
              ),
        ),
      );
      final check = await api.orders.check(
        Fx.bothActionableNumber,
        sourceType: GrindingSourceType.roll,
      );
      expect(check.order!.id, Fx.bothRollId);
      expect(check.resolution, CheckResolution.sourceTypeSelected);
      expect(api.backend.requests.last.body, <String, dynamic>{
        'identifier': Fx.bothActionableNumber,
        'sourceType': 'ROLL',
      });
    });

    test(
      'one actionable item → 200 AUTO_RESOLVED with both candidates',
      () async {
        final api = _Api();
        await api.login();
        final check = await api.orders.check(Fx.sharedNumber);
        expect(check.order!.id, Fx.sharedRollId);
        expect(check.sourceType, GrindingSourceType.roll);
        expect(check.resolution, CheckResolution.autoResolved);
        expect(check.candidates.map((c) => c.sourceType), <Object>[
          GrindingSourceType.roll,
          GrindingSourceType.pallet,
        ]);
        expect(check.candidates.last.status, GrindingStatus.notEligible);
        expect(api.backend.requests.last.body, <String, dynamic>{
          'identifier': Fx.sharedNumber,
        });
      },
    );

    test('queue keeps rows in server order and skips malformed rows', () {
      final orders = QueueResponseDto.fromJson(<String, dynamic>{
        'orders': <Object?>[
          <String, dynamic>{
            'id': 1,
            'orderNumber': 'GR-000001',
            'status': 'READY_FOR_GRINDING',
          },
          <String, dynamic>{'id': 2}, // missing required fields
          'garbage',
          <String, dynamic>{
            'id': 3,
            'orderNumber': 'GR-000003',
            'status': 'SOMETHING_NEW',
          },
        ],
        'limit': 100,
      });
      expect(orders.map((o) => o.id), <int>[1, 3]);
      expect(orders.last.status, GrindingStatus.unknown);
    });

    test(
      'execution: replayed:true on the same id, KEY_REUSED on another order',
      () async {
        final api = _Api();
        await api.login();
        final first = await api.orders.execute(
          GrindingCommand.start,
          orderId: Fx.readyId,
          clientRequestId: 'same-id',
        );
        expect(first.replayed, isFalse);
        expect(first.order!.status, GrindingStatus.inGrinding);
        expect(first.order!.startedByName, Fx.workerAName);
        final again = await api.orders.execute(
          GrindingCommand.start,
          orderId: Fx.readyId,
          clientRequestId: 'same-id',
        );
        expect(again.replayed, isTrue);
        expect(api.backend.transitionsFor(Fx.readyId), 1);
        await expectLater(
          api.orders.execute(
            GrindingCommand.start,
            orderId: Fx.palletId,
            clientRequestId: 'same-id',
          ),
          throwsA(
            isA<ApiFailure>().having(
              (f) => f.code,
              'code',
              ErrorCodes.idempotencyKeyReused,
            ),
          ),
        );
      },
    );

    test(
      'an unreadable 2xx success payload is still a success (no fabricated order)',
      () {
        final result = ExecutionResponseDto.fromData('not a map');
        expect(result.order, isNull);
        expect(result.replayed, isFalse);
      },
    );

    test(
      '2xx without success:true (captive portal) → ServerFailure(200)',
      () async {
        final api = _Api();
        await api.login();
        api.backend.faults.add(FakeFault(FaultKind.captivePortal));
        await expectLater(
          api.orders.execute(
            GrindingCommand.start,
            orderId: Fx.readyId,
            clientRequestId: 'cid',
          ),
          throwsA(const AppFailure.server(status: 200)),
        );
      },
    );

    test(
      'business error keeps the code, never exposes the English message',
      () async {
        final api = _Api();
        await api.login();
        try {
          await api.orders.execute(
            GrindingCommand.complete,
            orderId: Fx.readyId,
            clientRequestId: 'cid',
          );
          fail('expected ApiFailure');
        } on ApiFailure catch (failure) {
          expect(failure.code, ErrorCodes.orderNotInProgress);
          expect(failure.status, 409);
        }
      },
    );
  });

  group('session errors (contract §4.3) → signal with the auth generation', () {
    test('expired session emits once with the request generation', () async {
      final api = _Api();
      await api.login();
      final generation = api.session.generation;
      api.backend.expireSession(api.session.token!);
      await expectLater(
        api.orders.check(Fx.readyNumber),
        throwsA(
          isA<ApiFailure>().having(
            (f) => f.code,
            'code',
            ErrorCodes.sessionExpired,
          ),
        ),
      );
      await _flush();
      expect(api.events, hasLength(1));
      expect(api.events.single.failure.code, ErrorCodes.sessionExpired);
      expect(api.events.single.generation, generation);
    });

    test(
      'access withdrawn → GRINDING_WORKER_NOT_ALLOWED 403 is session-terminal',
      () async {
        final api = _Api();
        await api.login();
        api.backend.revokeWorker(Fx.workerA);
        await expectLater(
          api.orders.getQueue(GrindingQueueStatus.ready),
          throwsA(isA<ApiFailure>()),
        );
        await _flush();
        expect(api.events.single.failure.code, ErrorCodes.workerNotAllowed);
      },
    );

    test(
      'a NOT_ALLOWED login rejection is inline, not an invalidation',
      () async {
        final api = _Api();
        await expectLater(
          api.auth.loginWithPin(Fx.pinNotAllowed),
          throwsA(
            isA<ApiFailure>().having(
              (f) => f.code,
              'code',
              ErrorCodes.workerNotAllowed,
            ),
          ),
        );
        await expectLater(
          api.auth.loginWithPin('0000'),
          throwsA(
            isA<ApiFailure>().having(
              (f) => f.code,
              'code',
              ErrorCodes.operatorPinInvalid,
            ),
          ),
        );
        await _flush();
        expect(api.events, isEmpty);
      },
    );

    test(
      'a late 401 for the previous session carries the OLD generation',
      () async {
        final api = _Api();
        await api.login();
        final oldGeneration = api.session.generation;
        final release = Completer<void>();
        api.backend.faults.add(
          FakeFault(FaultKind.hang, release: release, thenCommit: true),
        );
        final arrived = Completer<void>();
        api.backend.onRequest = (r) async {
          if (r.path.endsWith('/sessions/me')) arrived.complete();
        };
        final pending = api.auth.getSession();
        // The request (token A, generation of A) is on the wire.
        await arrived.future;
        // Worker A's session ends and worker B logs in meanwhile.
        api.backend.endSession(api.session.token!);
        api.session.replace('token-of-worker-b');
        release.complete();
        await expectLater(pending, throwsA(isA<ApiFailure>()));
        await _flush();
        expect(api.events.single.generation, oldGeneration);
        expect(api.session.isCurrent(oldGeneration), isFalse);
      },
    );
  });

  group('device rejection (contract §4.1)', () {
    test(
      '401 without an envelope → device not authorized, session untouched',
      () async {
        final api = _Api();
        await api.login();
        api.backend.faults.add(FakeFault(FaultKind.deviceUnauthorized));
        await expectLater(
          api.orders.check(Fx.readyNumber),
          throwsA(isA<DeviceNotAuthorizedFailure>()),
        );
        await _flush();
        expect(api.events, isEmpty);
      },
    );

    test('a wrong device key is rejected by the server', () async {
      final backend = seededBackend();
      final dio = buildTestDio(
        session: AuthSession(),
        adapter: backend,
        deviceKey: 'wrong-key',
      );
      final auth = GrindingAuthRepositoryImpl(
        GrindingAuthRemoteDataSource(dio),
      );
      await expectLater(
        auth.loginWithPin(Fx.pinA),
        throwsA(isA<DeviceNotAuthorizedFailure>()),
      );
    });
  });

  group('read-only auto-retry never touches START / COMPLETE', () {
    test('GET queue is retried once after a connection error', () async {
      final api = _Api();
      await api.login();
      api.backend.faults.add(
        FakeFault(FaultKind.connectionError, pathEndsWith: '/orders'),
      );
      final rows = await api.orders.getQueue(GrindingQueueStatus.ready);
      expect(rows, isNotEmpty);
      expect(api.backend.requestsTo('/orders'), hasLength(2));
    });

    test('POST /check (read-only, opted in) is retried once', () async {
      final api = _Api();
      await api.login();
      api.backend.faults.add(
        FakeFault(FaultKind.receiveTimeout, pathEndsWith: '/check'),
      );
      await api.orders.check(Fx.readyNumber);
      expect(api.backend.requestsTo('/check'), hasLength(2));
    });

    for (final command in GrindingCommand.values) {
      test('${command.wire} is sent exactly once by the Dio chain', () async {
        final api = _Api();
        await api.login();
        final orderId = command == GrindingCommand.start
            ? Fx.readyId
            : Fx.inGrindingId;
        api.backend.faults.add(FakeFault(FaultKind.connectionError, times: 5));
        await expectLater(
          api.orders.execute(command, orderId: orderId, clientRequestId: 'x'),
          throwsA(const AppFailure.network()),
        );
        expect(api.backend.commandRequests, hasLength(1));
      });
    }

    test('login is never auto-retried', () async {
      final api = _Api();
      api.backend.faults.add(FakeFault(FaultKind.connectionError));
      await expectLater(
        api.auth.loginWithPin(Fx.pinA),
        throwsA(const AppFailure.network()),
      );
      expect(api.backend.requests, hasLength(1));
    });

    test(
      '503 on a GET is retried once, then surfaces as ServerFailure',
      () async {
        final api = _Api();
        await api.login();
        api.backend.faults.add(
          FakeFault(FaultKind.serverError, pathEndsWith: '/orders', times: 2),
        );
        await expectLater(
          api.orders.getQueue(GrindingQueueStatus.ready),
          throwsA(const AppFailure.server(status: 503)),
        );
        expect(api.backend.requestsTo('/orders'), hasLength(2));
      },
    );
  });

  group('transport guard (no credentials over cleartext)', () {
    test('a remote http:// base URL sends NOTHING', () async {
      final api = _Api(baseUrl: 'http://hamzadamra.ddns.net:8080');
      await expectLater(
        api.auth.loginWithPin(Fx.pinA),
        throwsA(isA<AppNotConfiguredFailure>()),
      );
      expect(api.backend.requests, isEmpty);
    });

    test(
      'loopback http:// (adb reverse) is allowed in a debug build',
      () async {
        final api = _Api(baseUrl: 'http://127.0.0.1:8080');
        await api.login();
        expect(api.backend.requests.single.uri.host, '127.0.0.1');
      },
    );
  });

  group('secrets never reach the log', () {
    test(
      'real request/response logging redacts PIN, token and device key',
      () async {
        final output = _CaptureOutput();
        final api = _Api(
          logger: Logger(
            filter: _AlwaysFilter(),
            output: output,
            printer: SimplePrinter(colors: false),
          ),
        );
        await api.login();
        final token = api.session.token!;
        await api.orders.check(Fx.readyNumber);
        api.backend.expireSession(token);
        await expectLater(
          api.orders.check(Fx.readyNumber),
          throwsA(isA<ApiFailure>()),
        );
        final log = output.lines.join('\n');
        expect(log, isNotEmpty);
        expect(log, isNot(contains(Fx.pinA)));
        expect(log, isNot(contains(token)));
        expect(log, isNot(contains(FakeGrindingBackend.testDeviceKey)));
      },
    );

    test('redaction helpers', () {
      expect(
        RedactingLoggingInterceptor.redactHeaders(<String, dynamic>{
          'X-Device-Key': 'k',
          'x-session-token': 't',
          'Accept': 'application/json',
        }),
        <String, dynamic>{
          'X-Device-Key': '***',
          'x-session-token': '***',
          'Accept': 'application/json',
        },
      );
      expect(
        RedactingLoggingInterceptor.redactBody(<String, dynamic>{
          'pin': '4821',
          'data': <String, dynamic>{'sessionToken': 't', 'n': 1},
          'list': <Object>[
            <String, dynamic>{'pin': '1'},
          ],
        }),
        <String, dynamic>{
          'pin': '***',
          'data': <String, dynamic>{'sessionToken': '***', 'n': 1},
          'list': <Object>[
            <String, dynamic>{'pin': '***'},
          ],
        },
      );
    });

    test('request / result objects never print the PIN or token', () {
      expect(const PinLoginRequest('4821').toString(), isNot(contains('4821')));
      const result = PinLoginResult(
        sessionToken: '5b0f6c9e-token',
        worker: GrindingWorker(operatorId: 57, name: 'x'),
      );
      expect(result.toString(), isNot(contains('5b0f6c9e')));
    });
  });
}
