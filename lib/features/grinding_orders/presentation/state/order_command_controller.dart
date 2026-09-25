import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/auth/auth_session.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../grinding_auth/presentation/state/grinding_auth_controller.dart';
import '../../../grinding_auth/presentation/state/grinding_auth_state.dart';
import '../../data/file_pending_command_store.dart';
import '../../data/grinding_orders_repository_impl.dart';
import '../../domain/command_failure_policy.dart';
import '../../domain/entities/execution_result.dart';
import '../../domain/entities/pending_command.dart';
import '../../domain/order_action.dart';
import '../../domain/repositories/grinding_orders_repository.dart';
import '../../domain/repositories/pending_command_store.dart';
import '../../domain/value_objects/grinding_command.dart';
import 'current_order_controller.dart';
import 'grinding_queue_controller.dart';

/// Backoff before each automatic resend of a START / COMPLETE (contract §9:
/// up to 3 automatic retries with the same id). Overridable in tests.
final commandRetryBackoffProvider = Provider<List<Duration>>(
  (ref) => AppConfig.commandRetryBackoff,
);

/// Mints `clientRequestId`s (UUID v4). Overridable in tests.
final clientRequestIdGeneratorProvider = Provider<String Function()>((ref) {
  const uuid = Uuid();
  return uuid.v4;
});

enum CommandOutcomeKind {
  /// 2xx (including `replayed:true`). Record cleared.
  success,

  /// Definitive 4xx business answer. Record cleared; show the Arabic
  /// message in a dialog, then re-check.
  businessError,

  /// Transport failure after the automatic retries. Record kept; the screen
  /// shows «انقطع الاتصال — أعد المحاولة» with a retry that reuses the id.
  networkLost,

  /// Session ended (the worker goes to PIN). Record kept.
  sessionEnded,

  /// Stopped locally (session changed mid-flight). Record kept, silent.
  aborted,

  /// Anything else (device rejected, unreadable reply…). Record kept.
  failed,

  /// The id could not be persisted, so NOTHING was sent.
  notPersisted,

  /// Dropped: duplicate tap, stale gate, records not loaded yet.
  ignored,
}

class CommandOutcome {
  const CommandOutcome(this.kind, {this.failure, this.result});

  final CommandOutcomeKind kind;
  final AppFailure? failure;
  final ExecutionResult? result;
}

/// A retry-exhausted transport failure of the CURRENT session. Only such a
/// failure grants the no-confirmation «أعد المحاولة» retry; after a restart
/// or a re-login the worker must confirm again.
class CommandFailureInfo {
  const CommandFailureInfo({required this.failure, required this.generation});

  final AppFailure failure;
  final int generation;
}

class OrderCommandState {
  const OrderCommandState({
    this.pending = const <String, PendingCommand>{},
    this.inFlight = const <String>{},
    this.failures = const <String, CommandFailureInfo>{},
  });

  /// Persisted records by [PendingCommand.key] — the in-memory mirror of the
  /// durable store and the source of truth for the UI.
  final Map<String, PendingCommand> pending;

  /// Keys whose request is being sent right now.
  final Set<String> inFlight;

  /// Keys whose automatic retries were exhausted in this session.
  final Map<String, CommandFailureInfo> failures;

  bool get hasInFlight => inFlight.isNotEmpty;

  PendingCommand? pendingForOrder(int orderId) {
    for (final record in pending.values) {
      if (record.orderId == orderId) return record;
    }
    return null;
  }

  GrindingCommand? inFlightForOrder(int orderId) {
    for (final command in GrindingCommand.values) {
      if (inFlight.contains(PendingCommand.keyFor(orderId, command))) {
        return command;
      }
    }
    return null;
  }

  OrderCommandState copyWith({
    Map<String, PendingCommand>? pending,
    Set<String>? inFlight,
    Map<String, CommandFailureInfo>? failures,
  }) {
    return OrderCommandState(
      pending: pending ?? this.pending,
      inFlight: inFlight ?? this.inFlight,
      failures: failures ?? this.failures,
    );
  }
}

/// Executes START / COMPLETE with contract §4.4 idempotency.
///
/// * `build()` loads every persisted record BEFORE any tap can be served
///   (the provider has no value until then, and [run] refuses to mint), so a
///   tap can never create a second id for an action that already has one.
/// * A tap mints a UUID v4 only when no record exists for `orderId+command`,
///   durably persists it, and only then sends. A failed persist sends
///   nothing.
/// * Transport failures are retried up to 3 times with the SAME id. Before
///   every attempt the auth generation is re-checked: if the session ended or
///   another worker logged in, the loop stops and the record is kept —
///   worker A's command is never resent under worker B's session.
/// * Nothing is ever sent automatically after a restart, a resume or a
///   re-login: [run] is only called from an explicit (confirmed) tap.
class OrderCommandController extends AsyncNotifier<OrderCommandState> {
  late PendingCommandStore _store;
  late GrindingOrdersRepository _repo;
  late AuthSession _session;

  /// Synchronous double-tap guard, updated before the first `await`.
  final Set<String> _inFlight = <String>{};
  final Map<String, CancelToken> _cancelTokens = <String, CancelToken>{};

  @override
  Future<OrderCommandState> build() async {
    _store = ref.watch(pendingCommandStoreProvider);
    _repo = ref.watch(grindingOrdersRepositoryProvider);
    _session = ref.watch(authSessionProvider);

    ref.listen<AsyncValue<GrindingAuthState>>(grindingAuthControllerProvider, (
      previous,
      next,
    ) {
      final before = _workerId(previous);
      final after = _workerId(next);
      if (after == null || (before != null && before != after)) {
        _onSessionEnded();
      }
    });
    ref.onDispose(_cancelAll);

    final records = await _store.loadAll();
    return OrderCommandState(
      pending: <String, PendingCommand>{
        for (final record in records) record.key: record,
      },
    );
  }

  static int? _workerId(AsyncValue<GrindingAuthState>? value) {
    final auth = value?.valueOrNull;
    return auth is GrindingAuthAuthenticated ? auth.worker.operatorId : null;
  }

  /// Sends [command] for [orderId] after the worker confirmed it.
  ///
  /// [reconcile]: resend an existing record that no longer matches the
  /// order's state (never mints). The gate is re-validated against the
  /// current order state, so a stale dialog can never send.
  Future<CommandOutcome> run({
    required GrindingCommand command,
    required int orderId,
    required String orderNumber,
    required String identifier,
    bool reconcile = false,
  }) async {
    final current = state.valueOrNull;
    if (current == null) {
      return const CommandOutcome(CommandOutcomeKind.ignored);
    }
    final key = PendingCommand.keyFor(orderId, command);
    if (_inFlight.contains(key)) {
      return const CommandOutcome(CommandOutcomeKind.ignored);
    }
    if (!_gateAllows(current, command, orderId, reconcile: reconcile)) {
      return const CommandOutcome(CommandOutcomeKind.ignored);
    }
    final auth = ref.read(grindingAuthControllerProvider).valueOrNull;
    if (auth is! GrindingAuthAuthenticated || !_session.hasToken) {
      return const CommandOutcome(
        CommandOutcomeKind.sessionEnded,
        failure: AppFailure.sessionExpired(),
      );
    }
    final generation = _session.generation;

    _inFlight.add(key);
    _publish((s) => s.copyWith(failures: _without(s.failures, key)));
    try {
      var record = current.pending[key];
      if (record == null) {
        if (reconcile) return const CommandOutcome(CommandOutcomeKind.ignored);
        record = PendingCommand(
          orderId: orderId,
          orderNumber: orderNumber,
          identifier: identifier,
          sourceType: ref.read(currentOrderControllerProvider).chosenSourceType,
          command: command,
          clientRequestId: ref.read(clientRequestIdGeneratorProvider)(),
          workerOperatorId: auth.worker.operatorId,
          workerName: auth.worker.name,
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );
        try {
          await _store.save(record);
        } catch (e, st) {
          // Not durable → must not send (a kill could otherwise lose the id).
          return CommandOutcome(
            CommandOutcomeKind.notPersisted,
            failure: ErrorMapper.fromException(e, st),
          );
        }
        final saved = record;
        _publish(
          (s) => s.copyWith(
            pending: <String, PendingCommand>{...s.pending, key: saved},
          ),
        );
      }
      return await _send(record, generation);
    } finally {
      _inFlight.remove(key);
      _cancelTokens.remove(key);
      _publish((s) => s);
    }
  }

  /// Re-validates the tap against the order currently on screen.
  bool _gateAllows(
    OrderCommandState current,
    GrindingCommand command,
    int orderId, {
    required bool reconcile,
  }) {
    final order = ref.read(currentOrderControllerProvider);
    final check = order.usableCheck;
    final pending = selectPendingForCheck(
      records: current.pending.values,
      identifier: order.identifier,
      chosenSourceType: order.chosenSourceType,
      checkedOrderId: check?.order?.id,
    );
    final action = resolveOrderAction(
      check: check,
      pending: pending,
      inFlight: null,
      locked: order.isChecking,
      checkRejected: order.checkRejected,
    );
    if (reconcile) {
      return action is ReconcileOrderAction &&
          action.enabled &&
          action.pending.orderId == orderId &&
          action.pending.command == command;
    }
    return action is CommandOrderAction &&
        action.enabled &&
        action.command == command &&
        check?.order?.id == orderId;
  }

  Future<CommandOutcome> _send(PendingCommand record, int generation) async {
    final cancel = CancelToken();
    _cancelTokens[record.key] = cancel;
    final backoff = ref.read(commandRetryBackoffProvider);
    var retries = 0;
    while (true) {
      if (!_session.isCurrent(generation) ||
          !_session.hasToken ||
          cancel.isCancelled) {
        return const CommandOutcome(CommandOutcomeKind.aborted);
      }
      try {
        final result = await _repo.execute(
          record.command,
          orderId: record.orderId,
          clientRequestId: record.clientRequestId,
          cancelToken: cancel,
        );
        await _clear(record);
        _onSuccess(record, result);
        return CommandOutcome(CommandOutcomeKind.success, result: result);
      } catch (e, st) {
        final failure = ErrorMapper.fromException(e, st);
        switch (classifyCommandFailure(failure)) {
          case CommandFailureClass.definitive:
            await _clear(record);
            ref.invalidate(grindingQueueProvider);
            return CommandOutcome(
              CommandOutcomeKind.businessError,
              failure: failure,
            );
          case CommandFailureClass.sessionEnded:
            return CommandOutcome(
              CommandOutcomeKind.sessionEnded,
              failure: failure,
            );
          case CommandFailureClass.cancelled:
            return const CommandOutcome(CommandOutcomeKind.aborted);
          case CommandFailureClass.keep:
            return CommandOutcome(CommandOutcomeKind.failed, failure: failure);
          case CommandFailureClass.retryable:
            if (cancel.isCancelled || !_session.isCurrent(generation)) {
              return const CommandOutcome(CommandOutcomeKind.aborted);
            }
            if (retries >= AppConfig.commandAutoRetryCount) {
              _publish(
                (s) => s.copyWith(
                  failures: <String, CommandFailureInfo>{
                    ...s.failures,
                    record.key: CommandFailureInfo(
                      failure: failure,
                      generation: generation,
                    ),
                  },
                ),
              );
              return CommandOutcome(
                CommandOutcomeKind.networkLost,
                failure: failure,
              );
            }
            final delay = backoff.isEmpty
                ? Duration.zero
                : backoff[retries.clamp(0, backoff.length - 1)];
            retries++;
            if (kDebugMode) {
              debugPrint(
                '[OrderCommand] ${record.command.wire} order=${record.orderId} '
                'retry=$retries in ${delay.inMilliseconds}ms '
                '(${failure.runtimeType})',
              );
            }
            await _wait(delay, cancel);
        }
      }
    }
  }

  Future<void> _clear(PendingCommand record) async {
    try {
      await _store.remove(record.orderId, record.command);
    } catch (e) {
      // The file stays; a later reconcile gets `replayed:true` or a
      // definitive 4xx and clears it. Never blocks the success UI.
      if (kDebugMode) {
        debugPrint('[OrderCommand] clear failed: ${e.runtimeType}');
      }
    }
    _publish(
      (s) => s.copyWith(
        pending: _without(s.pending, record.key),
        failures: _without(s.failures, record.key),
      ),
    );
  }

  void _onSuccess(PendingCommand record, ExecutionResult result) {
    ref
        .read(currentOrderControllerProvider.notifier)
        .applyExecutionResult(
          orderId: record.orderId,
          command: record.command,
          result: result,
        );
    ref.invalidate(grindingQueueProvider);
  }

  /// Logout / session invalidation / another worker: stop every in-flight
  /// request (records are kept) and revoke no-confirmation retries.
  void _onSessionEnded() {
    _cancelAll();
    _publish((s) => s.copyWith(failures: const <String, CommandFailureInfo>{}));
  }

  void _cancelAll() {
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) token.cancel('session changed');
    }
  }

  static Future<void> _wait(Duration delay, CancelToken cancel) {
    if (delay <= Duration.zero) return Future<void>.value();
    final completer = Completer<void>();
    final timer = Timer(delay, () {
      if (!completer.isCompleted) completer.complete();
    });
    unawaited(
      cancel.whenCancel.then((_) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }),
    );
    return completer.future;
  }

  void _publish(OrderCommandState Function(OrderCommandState) update) {
    final value = state.valueOrNull;
    if (value == null) return;
    state = AsyncData(
      update(value).copyWith(inFlight: Set<String>.unmodifiable(_inFlight)),
    );
  }

  static Map<String, V> _without<V>(Map<String, V> map, String key) {
    if (!map.containsKey(key)) return map;
    return Map<String, V>.of(map)..remove(key);
  }
}

final orderCommandControllerProvider =
    AsyncNotifierProvider<OrderCommandController, OrderCommandState>(
      OrderCommandController.new,
    );
