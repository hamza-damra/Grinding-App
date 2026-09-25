import 'package:flutter_grinding_app/core/api/api_client.dart';
import 'package:flutter_grinding_app/core/auth/auth_session.dart';
import 'package:flutter_grinding_app/core/config/app_config.dart';
import 'package:flutter_grinding_app/core/errors/app_failure.dart';
import 'package:flutter_grinding_app/core/errors/error_codes.dart';
import 'package:flutter_grinding_app/features/grinding_auth/data/grinding_auth_remote_data_source.dart';
import 'package:flutter_grinding_app/features/grinding_auth/data/grinding_auth_repository_impl.dart';
import 'package:flutter_grinding_app/features/grinding_orders/data/grinding_orders_remote_data_source.dart';
import 'package:flutter_grinding_app/features/grinding_orders/data/grinding_orders_repository_impl.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/check_resolution.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_source.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

/// LIVE smoke against a disposable TEST backend (contract §12 / §13), through
/// the real `ApiClient` chain and repositories.
///
/// Gate (owner correction #3): compile-time `SMOKE_ENABLED=true`, normally via
/// `flutter test integration_test/live_smoke_test.dart -d DEVICE
/// --dart-define-from-file=env/smoke.local.json`.
/// `env/smoke.local.json` is a HOST-side input (gitignored), not a file on
/// the device. Any other value → the whole group is skipped. When enabled,
/// a missing required value fails immediately, naming the KEY only.
///
/// Transport (owner correction #2): refuses anything but HTTPS or the device
/// loopback (`adb reverse`) — the PIN, device key and session token never go
/// over cleartext. Refuses `taleeb.me` outright: START / COMPLETE must never
/// be exercised on production (contract §13).
///
/// Output: step names, statuses and order numbers only. Never the PIN, the
/// device key, the session token or the base URL.
const String _enabled = String.fromEnvironment('SMOKE_ENABLED');

const Map<String, String> _required = <String, String>{
  'API_BASE_URL': String.fromEnvironment('API_BASE_URL'),
  'DEVICE_KEY': String.fromEnvironment('DEVICE_KEY'),
  'SMOKE_PIN': String.fromEnvironment('SMOKE_PIN'),
  'SMOKE_READY_IDENTIFIER': String.fromEnvironment('SMOKE_READY_IDENTIFIER'),
};

const String _pinB = String.fromEnvironment('SMOKE_PIN_B');
const String _ambiguous = String.fromEnvironment('SMOKE_AMBIGUOUS_IDENTIFIER');
const String _pending = String.fromEnvironment('SMOKE_PENDING_IDENTIFIER');

void _log(String line) {
  // ignore: avoid_print
  print('SMOKE $line');
}

class _Client {
  _Client() {
    final dio = ApiClient.buildDio(
      session: session,
      baseUrl: _required['API_BASE_URL'],
      deviceKey: _required['DEVICE_KEY']!,
      // No request/response logging at all in the smoke run.
      logger: Logger(level: Level.off),
    );
    auth = GrindingAuthRepositoryImpl(GrindingAuthRemoteDataSource(dio));
    orders = GrindingOrdersRepositoryImpl(GrindingOrdersRemoteDataSource(dio));
  }

  final AuthSession session = AuthSession();
  late final GrindingAuthRepositoryImpl auth;
  late final GrindingOrdersRepositoryImpl orders;

  Future<void> login(String pin) async {
    final result = await auth.loginWithPin(pin);
    session.replace(result.sessionToken);
    _log('login ok operatorId=${result.worker.operatorId}');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('live smoke (test backend only)', () {
    setUpAll(() {
      final missing = _required.entries
          .where((e) => e.value.trim().isEmpty)
          .map((e) => e.key)
          .toList();
      if (missing.isNotEmpty) {
        fail(
          'SMOKE_ENABLED=true but required values are missing: '
          '${missing.join(', ')}',
        );
      }
      final uri = Uri.tryParse(_required['API_BASE_URL']!.trim());
      if (uri == null || uri.host.isEmpty) fail('API_BASE_URL is not a URL');
      final host = uri.host.toLowerCase();
      if (host == 'taleeb.me' || host.endsWith('.taleeb.me')) {
        fail('Refusing to run START / COMPLETE against production.');
      }
      // The cleartext lab exception is for manual lab builds, never smoke.
      if (!AppConfig.isSecureTransport(uri, allowCleartextLab: false)) {
        fail(
          'Refusing cleartext: use an HTTPS test backend or the device '
          'loopback (adb reverse / encrypted tunnel).',
        );
      }
      _log(
        'transport=${uri.scheme} loopback=${AppConfig.isLoopbackHost(host)}',
      );
    });

    test(
      'PIN → check → START → COMPLETE → replay → ambiguity → pending → logout',
      () async {
        final client = _Client();
        const uuid = Uuid();

        await client.login(_required['SMOKE_PIN']!);
        final me = await client.auth.getSession();
        _log('sessions/me ok operatorId=${me.worker.operatorId}');

        final ready = _required['SMOKE_READY_IDENTIFIER']!;
        final before = await client.orders.check(ready);
        _log(
          'check status=${before.statusRaw} order=${before.order?.orderNumber}',
        );
        expect(before.status, GrindingStatus.readyForGrinding);
        expect(before.allowedToStartGrinding, isTrue);
        final orderId = before.order!.id;

        final startId = uuid.v4();
        final started = await client.orders.execute(
          GrindingCommand.start,
          orderId: orderId,
          clientRequestId: startId,
        );
        _log(
          'start replayed=${started.replayed} status=${started.order?.statusRaw}',
        );
        expect(started.replayed, isFalse);
        expect(started.order?.status, GrindingStatus.inGrinding);

        final inGrinding = await client.orders.check(ready);
        _log('check status=${inGrinding.statusRaw}');
        expect(inGrinding.allowedToCompleteGrinding, isTrue);

        final completeId = uuid.v4();
        final completed = await client.orders.execute(
          GrindingCommand.complete,
          orderId: orderId,
          clientRequestId: completeId,
        );
        _log(
          'complete replayed=${completed.replayed} status=${completed.order?.statusRaw}',
        );
        expect(completed.order?.status, GrindingStatus.completed);

        // Retry of the same COMPLETE (contract §12): replayed, order unchanged.
        final replay = await client.orders.execute(
          GrindingCommand.complete,
          orderId: orderId,
          clientRequestId: completeId,
        );
        _log(
          'complete-again replayed=${replay.replayed} status=${replay.order?.statusRaw}',
        );
        expect(replay.replayed, isTrue);
        expect(replay.order?.status, GrindingStatus.completed);
        expect(replay.order?.version, completed.order?.version);

        // The same id for the other command is rejected, never applied.
        try {
          await client.orders.execute(
            GrindingCommand.start,
            orderId: orderId,
            clientRequestId: completeId,
          );
          fail('expected GRINDING_IDEMPOTENCY_KEY_REUSED');
        } on ApiFailure catch (failure) {
          _log('reuse-for-start code=${failure.code}');
          expect(failure.code, ErrorCodes.idempotencyKeyReused);
        }

        if (_pinB.isNotEmpty) {
          final other = _Client();
          await other.login(_pinB);
          final byB = await other.orders.execute(
            GrindingCommand.complete,
            orderId: orderId,
            clientRequestId: completeId,
          );
          _log('worker-B replay replayed=${byB.replayed}');
          expect(byB.replayed, isTrue);
          await other.auth.logout();
        } else {
          _log('worker-B replay SKIPPED (SMOKE_PIN_B not set)');
        }

        if (_ambiguous.isNotEmpty) {
          // A number shared by a roll and a pallet: 409 only when BOTH can be
          // acted on; otherwise one answer naming both items.
          try {
            final shared = await client.orders.check(_ambiguous);
            _log(
              'shared resolution=${shared.resolution.wire} '
              'status=${shared.statusRaw}',
            );
            expect(
              shared.resolution,
              isIn(<CheckResolution>[
                CheckResolution.autoResolved,
                CheckResolution.noneActionable,
              ]),
            );
            expect(shared.candidates, hasLength(2));
          } on ApiFailure catch (failure) {
            _log(
              'shared code=${failure.code} '
              'resolution=${failure.details?['resolution']}',
            );
            expect(failure.code, ErrorCodes.identifierAmbiguous);
            expect(failure.details?['resolution'], 'REQUIRES_SELECTION');
          }
          final roll = await client.orders.check(
            _ambiguous,
            sourceType: GrindingSourceType.roll,
          );
          _log('ambiguous+ROLL status=${roll.statusRaw}');
        } else {
          _log('ambiguity SKIPPED (SMOKE_AMBIGUOUS_IDENTIFIER not set)');
        }

        if (_pending.isNotEmpty) {
          final pending = await client.orders.check(_pending);
          _log(
            'pending status=${pending.statusRaw} start=${pending.allowedToStartGrinding}',
          );
          expect(pending.status, GrindingStatus.pendingApproval);
          expect(pending.allowedToStartGrinding, isFalse);
        } else {
          _log('pending-approval SKIPPED (SMOKE_PENDING_IDENTIFIER not set)');
        }

        for (final status in GrindingQueueStatus.values) {
          final rows = await client.orders.getQueue(status);
          _log('orders ${status.wire} count=${rows.length}');
        }

        final ended = await client.auth.logout();
        _log('logout ended=$ended');
        expect(ended, isTrue);
        try {
          final again = await client.auth.logout();
          _log('logout-again ended=$again');
          expect(again, isFalse);
        } on AppFailure catch (failure) {
          // Tolerated: an ended token may also be answered with a session code.
          _log('logout-again failure=${failure.runtimeType}');
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }, skip: _enabled != 'true');

  test('the smoke never runs silently: gate state is reported', () {
    _log('SMOKE_ENABLED=${_enabled == 'true'}');
  });
}
