import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/arabic_messages.dart';
import '../../../../core/errors/biometric_denial.dart';
import '../../../../core/errors/connection_failure.dart';
import '../../../../core/errors/error_codes.dart';
import '../../domain/entities/biometric_attempt.dart';
import '../../domain/repositories/grinding_auth_repository.dart';

/// Pause between failed attempt-status polls. Overridable in tests.
final biometricPollBackoffProvider = Provider<List<Duration>>(
  (ref) => AppConfig.biometricPollBackoff,
);

/// What the fingerprint dialog shows (biometric handoff §5).
enum BiometricGatePhase {
  /// Polling; no valid fingerprint yet.
  waiting,

  /// Polling; the terminal reports offline.
  deviceOffline,

  /// A status call failed; polling again after a backoff.
  network,

  /// The single re-submitted login is in flight.
  verifying,

  /// Nothing to poll (410 / no attempt token): «إعادة المحاولة» re-submits.
  retry,

  /// `MAPPING_*`: only a SYSTEM_ADMIN can fix it. No poll, no retry.
  contactAdmin,

  /// The re-submitted login returned 2xx: the dialog closes.
  succeeded,

  /// The re-submitted login was refused for a non-biometric reason (e.g. the
  /// PIN changed meanwhile): the dialog closes and the PIN screen shows it.
  failed,
}

@immutable
class BiometricGateState {
  const BiometricGateState(this.phase, {this.message});

  final BiometricGatePhase phase;

  /// Server-worded body for this phase (the `BIOMETRIC_*` 403 message, shown
  /// verbatim), or `null` for the dialog's own §10 text.
  final String? message;

  bool get isPolling =>
      phase == BiometricGatePhase.waiting ||
      phase == BiometricGatePhase.deviceOffline ||
      phase == BiometricGatePhase.network;

  /// The dialog closes by itself.
  bool get isClosed =>
      phase == BiometricGatePhase.succeeded ||
      phase == BiometricGatePhase.failed;

  @override
  bool operator ==(Object other) =>
      other is BiometricGateState &&
      other.phase == phase &&
      other.message == message;

  @override
  int get hashCode => Object.hash(phase, message);

  @override
  String toString() => 'BiometricGateState(${phase.name})';
}

/// Runs ONE biometric login attempt for the fingerprint dialog (biometric
/// handoff §8): `waiting ⇄ deviceOffline → verifying → (succeeded |
/// new attempt | failed)`.
///
/// * Long-polls the attempt status back to back; a failed poll backs off
///   (1 s, 2 s, 4 s, then 10 s) and keeps trying until the server's 410 —
///   the device clock never decides expiry.
/// * `VERIFIED` / `ENFORCEMENT_SUSPENDED` / `NOT_REQUIRED` re-submit the
///   original login exactly once per status answer. Another `BIOMETRIC_*`
///   refusal replaces the attempt (new token) instead of re-submitting again.
/// * The PIN and the attempt token live only in this object, only while the
///   dialog is open: never logged, persisted, shown or put in a URL.
///   [cancel] / [dispose] stop polling and drop both.
///
/// Owned by the dialog, one instance per attempt; the dialog is modal, so
/// only one attempt runs at a time.
class BiometricLoginController extends ChangeNotifier {
  BiometricLoginController({
    required String this._pin,
    required BiometricDenial denial,
    required this._repository,
    required Future<AppFailure?> Function(String pin) resubmit,
    this._backoff = AppConfig.biometricPollBackoff,
  }) : _initialDenial = denial,
       _resubmitLogin = resubmit;

  final GrindingAuthRepository _repository;
  final Future<AppFailure?> Function(String pin) _resubmitLogin;
  final List<Duration> _backoff;
  BiometricDenial? _initialDenial;

  String? _pin;
  String? _attemptToken;
  String? _statusPath;

  /// The phase a 403 opened in and its server message: shown again whenever
  /// polling returns to that phase.
  BiometricGatePhase? _denialPhase;
  String? _denialMessage;

  /// One token per run of work (a poll loop or a re-submit). Cancelling it
  /// aborts the held request and any backoff wait.
  CancelToken _run = CancelToken();
  bool _disposed = false;

  BiometricGateState _state = const BiometricGateState(
    BiometricGatePhase.waiting,
  );

  BiometricGateState get state => _state;

  /// Whether an attempt token is held (tests: it must be gone after close).
  @visibleForTesting
  bool get holdsAttempt => _attemptToken != null;

  @visibleForTesting
  bool get holdsPin => _pin != null;

  /// Shows the state for the refusal the dialog was opened with and starts
  /// polling when it carries an attempt.
  void start() {
    final denial = _initialDenial;
    if (denial == null || _disposed) return;
    _initialDenial = null;
    _adopt(denial);
  }

  /// «إعادة المحاولة»: re-submits the original login (no re-typing).
  Future<void> retry() async {
    if (_state.phase != BiometricGatePhase.retry) return;
    await _resubmit();
  }

  /// «إلغاء»: stops polling and discards the token and the PIN.
  void cancel() {
    _run.cancel('biometric attempt closed');
    _dropAttempt();
    _pin = null;
  }

  /// App resumed: poll now instead of waiting on a possibly dead socket or a
  /// backoff.
  void onAppResumed() {
    if (_attemptToken == null || !_state.isPolling) return;
    _startPolling();
  }

  @override
  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
    super.dispose();
  }

  // ── Attempt ────────────────────────────────────────────────────────────

  void _adopt(BiometricDenial denial) {
    final message =
        denial.message ?? ArabicMessages.forBiometricCode(denial.code);
    if (ErrorCodes.isBiometricMapping(denial.code)) {
      _finishAttempt();
      _emit(BiometricGatePhase.contactAdmin, message: message);
      return;
    }
    if (!denial.hasAttempt) {
      _dropAttempt();
      _emit(BiometricGatePhase.retry, message: message);
      return;
    }
    _attemptToken = denial.attemptToken;
    _statusPath = denial.statusPath;
    final phase = denial.code == ErrorCodes.biometricDeviceUnavailable
        ? BiometricGatePhase.deviceOffline
        : BiometricGatePhase.waiting;
    _denialPhase = phase;
    _denialMessage = message;
    _emit(phase, message: message);
    _startPolling();
  }

  void _startPolling({Duration delay = Duration.zero}) {
    unawaited(_poll(_newRun(), delay));
  }

  Future<void> _poll(CancelToken run, Duration delay) async {
    await _wait(delay, run);
    var failures = 0;
    while (!run.isCancelled) {
      final token = _attemptToken;
      if (token == null) return;
      final BiometricAttemptStatusResponse answer;
      try {
        answer = await _repository.getBiometricAttemptStatus(
          statusPath: _statusPath,
          attemptToken: token,
          cancelToken: run,
        );
      } on BiometricAttemptExpiredFailure {
        if (run.isCancelled) return;
        _dropAttempt();
        _emit(BiometricGatePhase.retry);
        return;
      } on AppFailure catch (failure) {
        if (run.isCancelled) return;
        if (kDebugMode) {
          debugPrint('[BiometricGate] status poll failed: $failure');
        }
        _emit(BiometricGatePhase.network);
        await _wait(_delayFor(failures++), run);
        continue;
      }
      if (run.isCancelled) return;
      failures = 0;
      switch (answer.status) {
        case BiometricAttemptStatus.verified ||
            BiometricAttemptStatus.enforcementSuspended ||
            BiometricAttemptStatus.notRequired:
          await _resubmit();
          return;
        case BiometricAttemptStatus.pending:
          _emitPolling(BiometricGatePhase.waiting);
        case BiometricAttemptStatus.deviceUnavailable:
          _emitPolling(BiometricGatePhase.deviceOffline);
        case BiometricAttemptStatus.mappingMissing:
          _finishAttempt();
          _emit(
            BiometricGatePhase.contactAdmin,
            message: ArabicMessages.biometricMappingMissing,
          );
          return;
        case BiometricAttemptStatus.mappingDisabled:
          _finishAttempt();
          _emit(
            BiometricGatePhase.contactAdmin,
            message: ArabicMessages.biometricMappingDisabled,
          );
          return;
      }
    }
  }

  /// Re-submits the original login ONCE. Callers: a settled status answer,
  /// or the worker's «إعادة المحاولة».
  Future<void> _resubmit() async {
    final pin = _pin;
    if (pin == null) return;
    final run = _newRun();
    _emit(BiometricGatePhase.verifying);
    final failure = await _resubmitLogin(pin);
    if (run.isCancelled) return;
    switch (failure) {
      case null:
        _finishAttempt();
        _emit(BiometricGatePhase.succeeded);
      case BiometricDeniedFailure(:final denial):
        // A new attempt (new token) replaces this one — e.g. the fingerprint
        // expired between VERIFIED and the re-submit.
        _adopt(denial);
      case final AppFailure f when isConnectionFailure(f):
        if (_attemptToken != null) {
          // Keep the attempt: a fresh status answer allows one more
          // re-submit.
          _emit(BiometricGatePhase.network);
          _startPolling(delay: _delayFor(0));
        } else {
          _emit(BiometricGatePhase.retry, message: ArabicMessages.networkLost);
        }
      case _:
        _finishAttempt();
        _emit(BiometricGatePhase.failed);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  CancelToken _newRun() {
    _run.cancel('superseded');
    return _run = CancelToken();
  }

  /// A polling phase from a status answer; the 403's server message comes
  /// back with the phase it was given for.
  void _emitPolling(BiometricGatePhase phase) {
    if (_state.phase == phase) return;
    _emit(phase, message: phase == _denialPhase ? _denialMessage : null);
  }

  void _emit(BiometricGatePhase phase, {String? message}) {
    if (_disposed) return;
    final next = BiometricGateState(phase, message: message);
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  void _dropAttempt() {
    _attemptToken = null;
    _statusPath = null;
    _denialPhase = null;
    _denialMessage = null;
  }

  /// The attempt is over for good: stop work, drop the token and the PIN.
  void _finishAttempt() {
    _run.cancel('biometric attempt finished');
    _dropAttempt();
    _pin = null;
  }

  Duration _delayFor(int failures) {
    if (_backoff.isEmpty) return Duration.zero;
    return _backoff[failures.clamp(0, _backoff.length - 1)];
  }

  static Future<void> _wait(Duration delay, CancelToken run) {
    if (delay <= Duration.zero || run.isCancelled) return Future<void>.value();
    final completer = Completer<void>();
    final timer = Timer(delay, () {
      if (!completer.isCompleted) completer.complete();
    });
    unawaited(
      run.whenCancel.then((_) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }),
    );
    return completer.future;
  }
}
