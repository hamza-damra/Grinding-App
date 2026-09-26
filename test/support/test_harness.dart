import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_grinding_app/app/app.dart';
import 'package:flutter_grinding_app/core/api/api_client.dart';
import 'package:flutter_grinding_app/core/api/session_invalidation_signal.dart';
import 'package:flutter_grinding_app/core/auth/auth_session.dart';
import 'package:flutter_grinding_app/core/config/config_providers.dart';
import 'package:flutter_grinding_app/core/storage/prefs_store.dart';
import 'package:flutter_grinding_app/core/storage/secure_token_store.dart';
import 'package:flutter_grinding_app/core/widgets/connectivity_banner.dart';
import 'package:flutter_grinding_app/features/grinding_auth/presentation/state/biometric_login_controller.dart';
import 'package:flutter_grinding_app/features/grinding_orders/data/file_pending_command_store.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/entities/pending_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/repositories/pending_command_store.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/presentation/state/order_command_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'fake_grinding_backend.dart';

const String testBaseUrl = 'https://grinding.test';

/// Builds the production Dio chain (`ApiClient.buildDio`) against [adapter].
Dio buildTestDio({
  required AuthSession session,
  required HttpClientAdapter adapter,
  SessionInvalidationSignal? signal,
  String baseUrl = testBaseUrl,
  String deviceKey = FakeGrindingBackend.testDeviceKey,
  Logger? logger,
}) {
  final dio = ApiClient.buildDio(
    session: session,
    sessionInvalidationSignal: signal,
    baseUrl: baseUrl,
    deviceKey: deviceKey,
    readRetryBackoff: const <Duration>[],
    logger: logger,
  );
  dio.httpClientAdapter = adapter;
  return dio;
}

/// Silences the debug-only request logger (keeps test output readable).
void silenceNetworkLogs() {
  Logger.level = Level.off;
}

/// Deterministic `clientRequestId` source that counts how often it minted.
class RecordingIdGenerator {
  RecordingIdGenerator([this.prefix = 'cid']);

  final String prefix;
  int calls = 0;

  String next() => '$prefix-${++calls}';
}

/// [PendingCommandStore] in memory, with failure injection and a log.
class InMemoryPendingCommandStore implements PendingCommandStore {
  final Map<String, PendingCommand> records = <String, PendingCommand>{};
  final List<String> log = <String>[];

  /// Makes every [save] throw (disk full / I/O error).
  bool failSaves = false;

  /// When set, [loadAll] waits for it (store still loading at app start).
  Completer<void>? loadGate;

  @override
  Future<List<PendingCommand>> loadAll() async {
    await loadGate?.future;
    return records.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<void> save(PendingCommand command) async {
    log.add('save:${command.key}:${command.clientRequestId}');
    if (failSaves) {
      throw const FileSystemException('fake: no space left on device');
    }
    records[command.key] = command;
  }

  @override
  Future<void> remove(int orderId, GrindingCommand command) async {
    final key = PendingCommand.keyFor(orderId, command);
    log.add('remove:$key');
    records.remove(key);
  }
}

/// Everything a provider / widget test needs, wired like the app but with
/// the fake backend, in-memory token / prefs stores and zero backoff.
class GrindingTestHarness {
  GrindingTestHarness({
    FakeGrindingBackend? backend,
    SecureTokenStore? tokens,
    PrefsStore? prefs,
    PendingCommandStore? pending,
    this.backoff = const <Duration>[
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ],
    this.biometricBackoff = const <Duration>[Duration.zero],
    this.logger,
  }) : backend = backend ?? seededBackend(),
       tokens = tokens ?? InMemoryTokenStore(),
       prefs = prefs ?? InMemoryPrefsStore(),
       pending = pending ?? InMemoryPendingCommandStore();

  final FakeGrindingBackend backend;
  final SecureTokenStore tokens;
  final PrefsStore prefs;
  final PendingCommandStore pending;
  final List<Duration> backoff;
  final List<Duration> biometricBackoff;

  /// Request logger for the Dio chain (tests that inspect the log).
  final Logger? logger;
  final RecordingIdGenerator ids = RecordingIdGenerator();

  InMemoryPendingCommandStore get memoryPending =>
      pending as InMemoryPendingCommandStore;

  List<Override> overrides({List<Override> extra = const <Override>[]}) =>
      <Override>[
        appConfigProblemProvider.overrideWithValue(null),
        dioProvider.overrideWith(
          (ref) => buildTestDio(
            session: ref.watch(authSessionProvider),
            signal: ref.watch(sessionInvalidationSignalProvider),
            adapter: backend,
            logger: logger,
          ),
        ),
        secureTokenStoreProvider.overrideWithValue(tokens),
        prefsStoreProvider.overrideWith((ref) async => prefs),
        pendingCommandStoreProvider.overrideWithValue(pending),
        commandRetryBackoffProvider.overrideWithValue(backoff),
        biometricPollBackoffProvider.overrideWithValue(biometricBackoff),
        clientRequestIdGeneratorProvider.overrideWithValue(ids.next),
        connectivityProvider.overrideWith(
          (ref) => Stream<List<ConnectivityResult>>.value(
            const <ConnectivityResult>[ConnectivityResult.wifi],
          ),
        ),
        ...extra,
      ];

  /// A container disposed at the end of the test.
  ProviderContainer container({List<Override> extra = const <Override>[]}) {
    final container = ProviderContainer(overrides: overrides(extra: extra));
    addTearDown(container.dispose);
    return container;
  }

  /// Stores a live session token as if [operatorId] had logged in earlier.
  Future<String> signedIn(int operatorId) async {
    final token = backend.issueSession(operatorId);
    await tokens.writeSessionToken(token);
    return token;
  }
}

// ── Fixtures ────────────────────────────────────────────────────────────

class Fx {
  Fx._();

  static const String pinA = '4821';
  static const int workerA = 57;
  static const String workerAName = 'محمد أحمد';
  static const String pinB = '1357';
  static const int workerB = 58;
  static const String workerBName = 'أحمد علي';
  static const String pinNotAllowed = '9999';

  /// READY_FOR_GRINDING direct-scrap roll (contract §4.2 example).
  static const int readyId = 1042;
  static const String readyNumber = '001000000255';

  static const int inGrindingId = 1043;
  static const String inGrindingNumber = '001000000262';

  static const int pendingApprovalId = 1044;
  static const String pendingApprovalNumber = '001000000279';

  static const int legacyId = 1045;
  static const String legacyNumber = '001000000286';

  static const int palletId = 1046;
  static const String palletNumber = '120000004428';

  /// Both a roll (with a READY order) and a pallet (no order): only the
  /// roll is actionable → `AUTO_RESOLVED` to the roll, no question.
  static const int sharedRollId = 1047;
  static const String sharedNumber = '001000000293';

  // Opt-in shared-number fixtures ([SharedNumberFixtures.seedSharedNumbers]).

  /// Roll IN_GRINDING + pallet READY: both actionable, different actions →
  /// 409 selection.
  static const String bothActionableNumber = '001000000309';
  static const int bothRollId = 1048;
  static const int bothPalletId = 1049;

  /// Roll without an order + pallet READY → `AUTO_RESOLVED` to the pallet.
  static const String palletActionableNumber = '001000000316';
  static const int palletActionableId = 1050;

  /// Roll PENDING_APPROVAL + pallet COMPLETED → `NONE_ACTIONABLE`.
  static const String noneActionableNumber = '001000000323';
  static const int noneRollPendingId = 1051;
  static const int nonePalletCompletedId = 1052;

  /// Roll whose recommendation was REJECTED + pallet READY → the pallet.
  static const String rejectedRollNumber = '001000000330';
  static const int rejectedRollId = 1053;
  static const int rejectedPalletReadyId = 1054;

  /// Both items exist, neither has an order → `NONE_ACTIONABLE`.
  static const String sharedNoOrderNumber = '001000000347';

  static const String notEligibleNumber = '120000004411';
  static const String unknownNumber = '999999999999';
}

FakeGrindingBackend seededBackend() {
  final backend = FakeGrindingBackend()
    ..addWorker(pin: Fx.pinA, operatorId: Fx.workerA, name: Fx.workerAName)
    ..addWorker(pin: Fx.pinB, operatorId: Fx.workerB, name: Fx.workerBName)
    ..addWorker(
      pin: Fx.pinNotAllowed,
      operatorId: 90,
      name: 'موظف آخر',
      allowed: false,
    )
    ..addOrder(id: Fx.readyId, identifier: Fx.readyNumber)
    ..addOrder(
      id: Fx.inGrindingId,
      identifier: Fx.inGrindingNumber,
      status: 'IN_GRINDING',
      startedByName: 'سامي خليل',
      startedAt: '2026-09-22T07:05:00.000Z',
      expectedWeightKg: 12.345,
    )
    ..addOrder(
      id: Fx.pendingApprovalId,
      identifier: Fx.pendingApprovalNumber,
      status: 'PENDING_APPROVAL',
      sourceOrigin: 'THERMOFORMING_ROLL_REMAINDER',
      directScrap: false,
    )
    ..addOrder(
      id: Fx.legacyId,
      identifier: Fx.legacyNumber,
      status: 'COMPLETED',
      legacy: true,
      directScrap: false,
    )
    ..addOrder(
      id: Fx.palletId,
      identifier: Fx.palletNumber,
      sourceType: 'PALLET',
      sourceOrigin: 'PALLETIZING_PALLET',
      materialName: 'كاسة 250',
      expectedWeightKg: null,
      sourceQuantity: 1200,
      directScrap: false,
    )
    ..addOrder(id: Fx.sharedRollId, identifier: Fx.sharedNumber)
    ..addNotEligible(identifier: Fx.sharedNumber)
    ..addNotEligible(identifier: Fx.notEligibleNumber);
  return backend;
}

/// Numbers shared by a roll and a pallet in every other combination the
/// backend resolves differently. Opt-in so the base queues stay unchanged.
extension SharedNumberFixtures on FakeGrindingBackend {
  void seedSharedNumbers() {
    this
      ..addOrder(
        id: Fx.bothRollId,
        identifier: Fx.bothActionableNumber,
        status: 'IN_GRINDING',
        startedByName: 'سامي خليل',
        startedAt: '2026-09-22T07:05:00.000Z',
      )
      ..addOrder(
        id: Fx.bothPalletId,
        identifier: Fx.bothActionableNumber,
        sourceType: 'PALLET',
        sourceOrigin: 'PALLETIZING_PALLET',
        materialName: 'كاسة 250',
        expectedWeightKg: null,
        sourceQuantity: 1200,
        directScrap: false,
      )
      ..addNotEligible(
        identifier: Fx.palletActionableNumber,
        sourceType: 'ROLL',
        details: <String, dynamic>{
          'generatedRollId': Fx.palletActionableNumber,
        },
      )
      ..addOrder(
        id: Fx.palletActionableId,
        identifier: Fx.palletActionableNumber,
        sourceType: 'PALLET',
        sourceOrigin: 'PALLETIZING_PALLET',
        materialName: 'كاسة 500',
        expectedWeightKg: null,
        sourceQuantity: 800,
        directScrap: false,
      )
      ..addOrder(
        id: Fx.noneRollPendingId,
        identifier: Fx.noneActionableNumber,
        status: 'PENDING_APPROVAL',
        sourceOrigin: 'THERMOFORMING_ROLL_REMAINDER',
        directScrap: false,
      )
      ..addOrder(
        id: Fx.nonePalletCompletedId,
        identifier: Fx.noneActionableNumber,
        sourceType: 'PALLET',
        status: 'COMPLETED',
        sourceOrigin: 'PALLETIZING_PALLET',
        materialName: 'كاسة 250',
        expectedWeightKg: null,
        sourceQuantity: 1200,
        directScrap: false,
        completedByName: 'سامي خليل',
        completedAt: '2026-09-22T06:00:00.000Z',
      )
      ..addOrder(
        id: Fx.rejectedRollId,
        identifier: Fx.rejectedRollNumber,
        status: 'REJECTED',
        sourceOrigin: 'THERMOFORMING_ROLL_REMAINDER',
        directScrap: false,
      )
      ..addOrder(
        id: Fx.rejectedPalletReadyId,
        identifier: Fx.rejectedRollNumber,
        sourceType: 'PALLET',
        sourceOrigin: 'PALLETIZING_PALLET',
        materialName: 'كاسة 250',
        expectedWeightKg: null,
        sourceQuantity: 1200,
        directScrap: false,
      )
      ..addNotEligible(identifier: Fx.sharedNoOrderNumber, sourceType: 'ROLL')
      ..addNotEligible(identifier: Fx.sharedNoOrderNumber);
  }
}

// ── Widget pumping ──────────────────────────────────────────────────────

/// A phone-sized, portrait test surface.
Future<void> usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(412, 915));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Pumps the whole app (router, theme, RTL) against [harness].
Future<void> pumpGrindingApp(
  WidgetTester tester,
  GrindingTestHarness harness, {
  List<Override> extra = const <Override>[],
}) async {
  await usePhoneSurface(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides(extra: extra),
      child: const GrindingApp(),
    ),
  );
  await tester.pumpAndSettle();
}
