import 'package:dio/dio.dart';
import 'package:flutter_grinding_app/core/api/api_paths.dart';
import 'package:flutter_grinding_app/core/api/interceptors/logging_interceptor.dart';
import 'package:flutter_grinding_app/core/auth/auth_session.dart';
import 'package:flutter_grinding_app/core/config/app_config.dart';
import 'package:flutter_grinding_app/core/errors/app_failure.dart';
import 'package:flutter_grinding_app/core/errors/biometric_denial.dart';
import 'package:flutter_grinding_app/core/errors/error_codes.dart';
import 'package:flutter_grinding_app/features/grinding_auth/data/dtos/biometric_dtos.dart';
import 'package:flutter_grinding_app/features/grinding_auth/data/grinding_auth_remote_data_source.dart';
import 'package:flutter_grinding_app/features/grinding_auth/data/grinding_auth_repository_impl.dart';
import 'package:flutter_grinding_app/features/grinding_auth/domain/entities/biometric_attempt.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_grinding_backend.dart';
import '../../support/test_harness.dart';

/// Biometric login gate at the API level
/// (`docs/FRONTEND_HANDOFF_GRINDING_APP_BIOMETRIC_LOGIN_GATE.md` §4, §7).
class _Api {
  _Api({bool enforced = true}) {
    backend.setBiometricEnforced(enforced);
    dio = buildTestDio(session: session, adapter: backend);
    auth = GrindingAuthRepositoryImpl(GrindingAuthRemoteDataSource(dio));
  }

  final FakeGrindingBackend backend = seededBackend();
  final AuthSession session = AuthSession();
  late final Dio dio;
  late final GrindingAuthRepositoryImpl auth;

  Future<BiometricDenial> refusal([String pin = Fx.pinA]) async {
    try {
      await auth.loginWithPin(pin);
    } on BiometricDeniedFailure catch (f) {
      return f.denial;
    }
    fail('expected a biometric refusal');
  }

  void answer(ResponseBody response) => backend.faults.add(
    FakeFault(
      FaultKind.custom,
      pathEndsWith: '/login-attempts/status',
      response: response,
    ),
  );
}

void main() {
  setUpAll(silenceNetworkLogs);

  group('login (§4.1, §4.2)', () {
    test('feature off → the login request and answer are unchanged', () async {
      final api = _Api(enforced: false);
      final result = await api.auth.loginWithPin(Fx.pinA);
      expect(result.worker.operatorId, Fx.workerA);
      final r = api.backend.requests.single;
      expect(r.path, ApiPaths.authPin);
      expect(r.body, <String, dynamic>{'pin': Fx.pinA});
      expect(r.deviceKey, FakeGrindingBackend.testDeviceKey);
      expect(r.attemptToken, isNull);
    });

    test('a BIOMETRIC_* 403 with a token → BiometricDeniedFailure', () async {
      final api = _Api();
      final denial = await api.refusal();
      expect(denial.code, ErrorCodes.biometricVerificationRequired);
      expect(denial.hasAttempt, isTrue);
      expect(denial.attemptToken, api.backend.biometricAttempts.keys.single);
      expect(denial.statusPath, FakeGrindingBackend.biometricStatusPath);
      expect(api.backend.sessions, isEmpty);
    });

    test('feature on → same request body and device key as before', () async {
      final api = _Api();
      await api.refusal();
      final r = api.backend.requests.single;
      expect(r.body, <String, dynamic>{'pin': Fx.pinA});
      expect(r.deviceKey, FakeGrindingBackend.testDeviceKey);
    });

    test('token absent (attemptAvailable:false) → no attempt', () async {
      final api = _Api()..backend.biometricAttemptsAvailable = false;
      final denial = await api.refusal();
      expect(denial.attemptAvailable, isFalse);
      expect(denial.attemptToken, isNull);
      expect(denial.hasAttempt, isFalse);
    });

    test('MAPPING_* → no attempt, the server message kept verbatim', () async {
      final api = _Api()
        ..backend.setBiometricMapping(
          Fx.workerA,
          FakeBiometricMapping.disabled,
        );
      final denial = await api.refusal();
      expect(denial.code, ErrorCodes.biometricMappingDisabled);
      expect(denial.hasAttempt, isFalse);
      expect(
        denial.message,
        FakeGrindingBackend.biometricMessages[ErrorCodes
            .biometricMappingDisabled],
      );
    });

    test('non-biometric 403s keep their current handling', () async {
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
      for (final body in <Object>[
        'Forbidden',
        <String, dynamic>{
          'success': false,
          'error': <String, dynamic>{'code': 'ACCESS_DENIED'},
        },
      ]) {
        api.backend.faults.add(
          FakeFault(
            FaultKind.custom,
            pathEndsWith: '/auth/pin',
            response: FakeGrindingBackend.jsonResponse(403, body),
          ),
        );
        await expectLater(
          api.auth.loginWithPin(Fx.pinA),
          throwsA(isA<DeviceNotAuthorizedFailure>()),
          reason: '$body',
        );
      }
    });
  });

  group('attempt status (§4.3)', () {
    test('sends ONLY the attempt token: no device key, no session token, '
        'nothing in the URL; long receive timeout', () async {
      final api = _Api();
      final denial = await api.refusal();
      // Even with a session held, the status call must not carry it.
      api.session.replace('some-session-token');
      await api.auth.getBiometricAttemptStatus(
        statusPath: denial.statusPath,
        attemptToken: denial.attemptToken!,
      );
      final r = api.backend.biometricStatusRequests.single;
      expect(r.method, 'GET');
      expect(r.uri.host, Uri.parse(testBaseUrl).host);
      expect(r.path, FakeGrindingBackend.biometricStatusPath);
      expect(r.uri.query, isEmpty);
      expect(r.uri.toString(), isNot(contains(denial.attemptToken!)));
      expect(r.attemptToken, denial.attemptToken);
      expect(r.headers.containsKey(ApiHeaders.deviceKey), isFalse);
      expect(r.headers.containsKey(ApiHeaders.sessionToken), isFalse);
      expect(r.headers.containsKey('Authorization'), isFalse);
      expect(
        r.receiveTimeout,
        greaterThanOrEqualTo(const Duration(seconds: 35)),
      );
      expect(
        AppConfig.biometricStatusReceiveTimeout,
        greaterThanOrEqualTo(const Duration(seconds: 35)),
      );
    });

    test('every status value maps; unknown → PENDING', () async {
      final api = _Api();
      final denial = await api.refusal();
      final expected = <String, BiometricAttemptStatus>{
        'PENDING': BiometricAttemptStatus.pending,
        'VERIFIED': BiometricAttemptStatus.verified,
        'ENFORCEMENT_SUSPENDED': BiometricAttemptStatus.enforcementSuspended,
        'NOT_REQUIRED': BiometricAttemptStatus.notRequired,
        'DEVICE_UNAVAILABLE': BiometricAttemptStatus.deviceUnavailable,
        'MAPPING_MISSING': BiometricAttemptStatus.mappingMissing,
        'MAPPING_DISABLED': BiometricAttemptStatus.mappingDisabled,
        'SOMETHING_NEW': BiometricAttemptStatus.pending,
      };
      for (final entry in expected.entries) {
        api.answer(FakeGrindingBackend.biometricStatus(entry.key));
        final answer = await api.auth.getBiometricAttemptStatus(
          statusPath: denial.statusPath,
          attemptToken: denial.attemptToken!,
        );
        expect(answer.status, entry.value, reason: entry.key);
        expect(answer.attemptExpiresAt, DateTime.utc(2026, 9, 24, 8, 15));
      }
      expect(
        BiometricAttemptStatusDto.fromJson(<String, dynamic>{}).status,
        BiometricAttemptStatus.pending,
      );
    });

    test('410 → BiometricAttemptExpiredFailure, with or without the '
        'envelope', () async {
      final api = _Api();
      final denial = await api.refusal();
      api.backend.expireBiometricAttempts();
      Future<void> poll() => api.auth.getBiometricAttemptStatus(
        statusPath: denial.statusPath,
        attemptToken: denial.attemptToken!,
      );
      await expectLater(
        poll(),
        throwsA(const AppFailure.biometricAttemptExpired()),
      );
      api.answer(FakeGrindingBackend.jsonResponse(410, 'Gone'));
      await expectLater(
        poll(),
        throwsA(const AppFailure.biometricAttemptExpired()),
      );
      expect(api.backend.biometricStatusRequests, hasLength(2));
    });

    test(
      'a failed poll is not auto-retried (the dialog owns backoff)',
      () async {
        final api = _Api();
        final denial = await api.refusal();
        api.backend.faults.add(
          FakeFault(
            FaultKind.connectionError,
            pathEndsWith: '/login-attempts/status',
          ),
        );
        await expectLater(
          api.auth.getBiometricAttemptStatus(
            statusPath: denial.statusPath,
            attemptToken: denial.attemptToken!,
          ),
          throwsA(const AppFailure.network()),
        );
        expect(api.backend.biometricStatusRequests, hasLength(1));
      },
    );

    test('cancel aborts a held long-poll', () async {
      final api = _Api();
      final denial = await api.refusal();
      Future<BiometricAttemptStatusResponse> poll([CancelToken? cancel]) =>
          api.auth.getBiometricAttemptStatus(
            statusPath: denial.statusPath,
            attemptToken: denial.attemptToken!,
            cancelToken: cancel,
          );
      await poll(); // PENDING, answered at once
      final cancel = CancelToken();
      final held = poll(cancel);
      await Future<void>.delayed(Duration.zero);
      cancel.cancel();
      await expectLater(held, throwsA(const AppFailure.cancelled()));
    });

    test('statusPath: only a plain path on the login host is used', () {
      const fallback = ApiPaths.biometricAttemptStatus;
      expect(
        ApiPaths.biometricStatus('/api/v2/attempts/status'),
        '/api/v2/attempts/status',
      );
      for (final unsafe in <String?>[
        null,
        '',
        '   ',
        'api/v1/auth/biometric/login-attempts/status',
        'https://evil.example/status',
        'http://evil.example/status',
        '//evil.example/status',
        '/api/v1/auth/biometric/login-attempts/status?token=x',
        '/api/v1/auth/biometric/login-attempts/status#x',
      ]) {
        expect(ApiPaths.biometricStatus(unsafe), fallback, reason: unsafe);
      }
    });

    test(
      'an unsafe statusPath from the server never leaves the login host',
      () async {
        final api = _Api();
        api.backend.faults.add(
          FakeFault(
            FaultKind.custom,
            pathEndsWith: '/auth/pin',
            response: FakeGrindingBackend.biometricDenial(
              ErrorCodes.biometricVerificationRequired,
              attemptToken: 'tok-from-server',
              statusPath: 'https://evil.example/steal',
            ),
          ),
        );
        final denial = await api.refusal();
        expect(denial.statusPath, 'https://evil.example/steal');
        await expectLater(
          api.auth.getBiometricAttemptStatus(
            statusPath: denial.statusPath,
            attemptToken: denial.attemptToken!,
          ),
          throwsA(const AppFailure.biometricAttemptExpired()),
          reason: 'the fake does not know this token',
        );
        final r = api.backend.biometricStatusRequests.single;
        expect(r.uri.host, Uri.parse(testBaseUrl).host);
        expect(r.path, FakeGrindingBackend.biometricStatusPath);
      },
    );
  });

  group('secrets', () {
    test('redaction covers the attempt token header and body field', () {
      expect(
        RedactingLoggingInterceptor.redactHeaders(<String, dynamic>{
          'X-Biometric-Attempt-Token': 'tok',
          'x-biometric-attempt-token': 'tok',
        }),
        <String, dynamic>{
          'X-Biometric-Attempt-Token': '***',
          'x-biometric-attempt-token': '***',
        },
      );
      expect(
        RedactingLoggingInterceptor.redactBody(<String, dynamic>{
          'success': false,
          'error': <String, dynamic>{
            'code': 'BIOMETRIC_VERIFICATION_REQUIRED',
            'details': <String, dynamic>{
              'attemptToken': 'tok',
              'statusPath': '/s',
            },
          },
        }),
        <String, dynamic>{
          'success': false,
          'error': <String, dynamic>{
            'code': 'BIOMETRIC_VERIFICATION_REQUIRED',
            'details': <String, dynamic>{
              'attemptToken': '***',
              'statusPath': '/s',
            },
          },
        },
      );
    });

    test('denial / failure toString never carries the token or message', () {
      final denial = BiometricDenial.fromEnvelope(
        code: ErrorCodes.biometricVerificationRequired,
        message: 'رسالة الخادم',
        details: <String, dynamic>{
          'attemptToken': 'q3Jx8d6cYt0H1m0yF3kZ0wS9gQx8B7nV2rP5aL4eK1c',
          'attemptAvailable': true,
        },
      );
      for (final text in <String>[
        denial.toString(),
        AppFailure.biometricDenied(denial).toString(),
      ]) {
        expect(text, isNot(contains('q3Jx8d6c')));
        expect(text, isNot(contains('رسالة')));
      }
    });
  });
}
