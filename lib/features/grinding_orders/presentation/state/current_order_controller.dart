import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/error_codes.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../grinding_auth/presentation/state/grinding_auth_controller.dart';
import '../../../grinding_auth/presentation/state/grinding_auth_state.dart';
import '../../data/grinding_orders_repository_impl.dart';
import '../../data/dtos/check_dtos.dart';
import '../../domain/command_failure_policy.dart';
import '../../domain/entities/check_candidate.dart';
import '../../domain/entities/check_result.dart';
import '../../domain/entities/execution_result.dart';
import '../../domain/entities/grinding_order.dart';
import '../../domain/value_objects/check_resolution.dart';
import '../../domain/value_objects/grinding_command.dart';
import '../../domain/value_objects/grinding_source.dart';

/// The ONE authoritative state of the order the worker opened (scan, manual
/// entry, queue row or pending banner).
class CurrentOrderState {
  const CurrentOrderState({
    this.identifier,
    this.chosenSourceType,
    this.check,
    this.selection,
    this.sharedCandidates = const <CheckCandidate>[],
    this.success,
    this.executedOrder,
  });

  /// The 12-digit number, or `null` when nothing is open.
  final String? identifier;

  /// The ROLL / PALLET this opened number is pinned to, reused for every
  /// re-check so the card stays on the same physical item: the worker's own
  /// «رول» / «طبلية» answer, or the item the SERVER picked for a number
  /// shared by a roll and a pallet (`AUTO_RESOLVED`). Never inferred locally.
  final GrindingSourceType? chosenSourceType;

  /// Latest `/check`. `null` while waiting for the worker's selection or
  /// right after a command succeeded (the server's order is shown meanwhile).
  final AsyncValue<CheckResult>? check;

  /// The last `/check` answered `GRINDING_IDENTIFIER_AMBIGUOUS`: the number
  /// names a roll and a pallet and BOTH can be acted on. The worker picks
  /// one of these; the app never does.
  final List<CheckCandidate>? selection;

  /// Both items of a number shared by a roll and a pallet, kept while this
  /// number stays open (a pinned re-check no longer lists them), so the card
  /// can say which other item the number also names.
  final List<CheckCandidate> sharedCandidates;

  /// Waiting for the worker's «رول» / «طبلية» answer.
  bool get ambiguity => selection != null;

  /// The command the server just confirmed for this order (success banner).
  final GrindingCommand? success;

  /// The order returned by that command — shown, with no action, until the
  /// follow-up `/check` lands. Never a locally fabricated order.
  final GrindingOrder? executedOrder;

  bool get isOpen => identifier != null;

  bool get isChecking => check?.isLoading ?? false;

  /// The latest successful check, or `null` if it is loading-without-data,
  /// failed, or absent. Actions are only ever derived from this.
  CheckResult? get usableCheck {
    final c = check;
    if (c == null || c.hasError) return null;
    return c.valueOrNull;
  }

  /// The order card to display.
  GrindingOrder? get displayOrder => check?.valueOrNull?.order ?? executedOrder;

  /// The latest `/check` was definitively rejected (4xx, e.g. the number no
  /// longer resolves) — only a pending record can then be reconciled.
  bool get checkRejected {
    final failure = check?.error;
    return failure is AppFailure &&
        classifyCommandFailure(failure) == CommandFailureClass.definitive;
  }
}

/// Owns [CurrentOrderState]. Every `/check` carries a sequence number; only
/// the latest request may write the state, so a slow response for an older
/// scan (or a response arriving after the worker changed) is dropped.
class CurrentOrderController extends Notifier<CurrentOrderState> {
  int _seq = 0;

  @override
  CurrentOrderState build() {
    ref.listen<AsyncValue<GrindingAuthState>>(grindingAuthControllerProvider, (
      previous,
      next,
    ) {
      final before = _workerId(previous);
      final after = _workerId(next);
      if (after == null || (before != null && before != after)) reset();
    });
    return const CurrentOrderState();
  }

  static int? _workerId(AsyncValue<GrindingAuthState>? value) {
    final auth = value?.valueOrNull;
    return auth is GrindingAuthAuthenticated ? auth.worker.operatorId : null;
  }

  /// Opens [identifier] (already validated, 12 ASCII digits). A repeat of
  /// the identifier currently being checked is ignored (double scan, double
  /// Enter from a keyboard-wedge scanner).
  Future<void> open(String identifier, {GrindingSourceType? sourceType}) =>
      _open(identifier, sourceType, const <CheckCandidate>[]);

  Future<void> _open(
    String identifier,
    GrindingSourceType? sourceType,
    List<CheckCandidate> sharedCandidates,
  ) async {
    if (state.identifier == identifier &&
        state.chosenSourceType == sourceType &&
        state.isChecking) {
      return;
    }
    final seq = ++_seq;
    state = CurrentOrderState(
      identifier: identifier,
      chosenSourceType: sourceType,
      check: const AsyncLoading<CheckResult>(),
      sharedCandidates: sharedCandidates,
    );
    await _runCheck(seq, identifier, sourceType);
  }

  /// The worker's answer to the «رول» / «طبلية» selection.
  Future<void> answerAmbiguity(GrindingSourceType choice) async {
    final identifier = state.identifier;
    final selection = state.selection;
    if (identifier == null || selection == null) return;
    await _open(identifier, choice, selection);
  }

  /// Re-runs `/check` for the opened number (after every action, on resume,
  /// pull-to-refresh). Keeps the displayed data while loading.
  Future<void> refresh() async {
    final identifier = state.identifier;
    if (identifier == null || state.ambiguity) return;
    final seq = ++_seq;
    final previous = state.check;
    state = CurrentOrderState(
      identifier: identifier,
      chosenSourceType: state.chosenSourceType,
      check: previous == null || previous.hasError
          ? const AsyncLoading<CheckResult>()
          : const AsyncLoading<CheckResult>().copyWithPrevious(previous),
      sharedCandidates: state.sharedCandidates,
      success: state.success,
      executedOrder: state.executedOrder,
    );
    await _runCheck(seq, identifier, state.chosenSourceType);
  }

  /// A START / COMPLETE for [orderId] was confirmed by the server. Shows the
  /// server's order (actions disabled — the old check is dropped so its
  /// gates cannot be reused) and re-checks for the current truth.
  void applyExecutionResult({
    required int orderId,
    required GrindingCommand command,
    required ExecutionResult result,
  }) {
    final shown = state.usableCheck?.order?.id ?? state.executedOrder?.id;
    if (!state.isOpen || shown != orderId) return;
    _seq++;
    state = CurrentOrderState(
      identifier: state.identifier,
      chosenSourceType: state.chosenSourceType,
      sharedCandidates: state.sharedCandidates,
      success: command,
      executedOrder: result.order,
    );
    unawaited(refresh());
  }

  /// Closes the order (back to Home). In-flight checks are dropped.
  void clear() {
    _seq++;
    state = const CurrentOrderState();
  }

  /// Logout / worker change.
  void reset() => clear();

  Future<void> _runCheck(
    int seq,
    String identifier,
    GrindingSourceType? sourceType,
  ) async {
    try {
      final result = await ref
          .read(grindingOrdersRepositoryProvider)
          .check(identifier, sourceType: sourceType);
      if (seq != _seq) return;
      state = CurrentOrderState(
        identifier: identifier,
        chosenSourceType: sourceType ?? _serverPick(result),
        check: AsyncData(result),
        sharedCandidates: result.candidates.length >= 2
            ? result.candidates
            : state.sharedCandidates,
        success: state.success,
      );
    } catch (e, st) {
      if (seq != _seq) return;
      final failure = ErrorMapper.fromException(e, st);
      if (failure is ApiFailure &&
          failure.code == ErrorCodes.identifierAmbiguous &&
          sourceType == null) {
        // Both items can be acted on: ask the worker; never infer.
        final candidates = CheckCandidateDto.listFromJson(
          failure.details?['candidates'],
        );
        state = CurrentOrderState(
          identifier: identifier,
          selection: candidates.length >= 2
              ? candidates
              : CheckCandidate.unknownPair,
        );
        return;
      }
      state = CurrentOrderState(
        identifier: identifier,
        chosenSourceType: sourceType,
        check: AsyncError<CheckResult>(failure, st),
        sharedCandidates: state.sharedCandidates,
        success: state.success,
        executedOrder: state.executedOrder,
      );
    }
  }

  /// The item the server picked for a shared number, pinned so re-checks
  /// (after a command, on resume) stay on it instead of re-resolving.
  static GrindingSourceType? _serverPick(CheckResult result) {
    if (result.resolution != CheckResolution.autoResolved) return null;
    return result.sourceType == GrindingSourceType.unknown
        ? null
        : result.sourceType;
  }
}

final currentOrderControllerProvider =
    NotifierProvider<CurrentOrderController, CurrentOrderState>(
      CurrentOrderController.new,
    );
