import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_session.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/config/config_providers.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/error_codes.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/storage/prefs_store.dart';
import '../../../../core/storage/secure_token_store.dart';
import '../../data/grinding_auth_repository_impl.dart';
import '../../domain/entities/grinding_worker.dart';
import '../../domain/repositories/grinding_auth_repository.dart';
import '../../domain/value_objects/pin_rule.dart';
import 'grinding_auth_state.dart';
import 'logout_reason.dart';

/// Owns the worker session (Operator App `OperatorAuthController` pattern).
///
/// * **Restore:** no token → PIN. Token → `GET /sessions/me`: fresh identity;
///   a session-terminal code → clear + PIN with the reason; a transient
///   failure → keep the cached identity (the next call surfaces a real
///   problem). The local clock never decides expiry.
/// * **Login:** single-flight; the PIN is used for one request and never
///   stored, logged or kept in state.
/// * **Logout:** best-effort `POST /auth/logout` (short timeout, errors
///   swallowed — the contract makes it tolerant), then the local session is
///   cleared regardless. Orders and pending START/COMPLETE records are never
///   touched.
///
/// Every session change goes through [AuthSession.replace], which opens a
/// new auth generation (see [AuthSession]).
class GrindingAuthController extends AsyncNotifier<GrindingAuthState> {
  late GrindingAuthRepository _repo;
  late SecureTokenStore _tokenStore;
  late AuthSession _session;

  bool _loggingIn = false;

  /// Set while a local session teardown (logout / invalidation) runs.
  bool _clearing = false;

  @override
  Future<GrindingAuthState> build() async {
    _repo = ref.watch(grindingAuthRepositoryProvider);
    _tokenStore = ref.watch(secureTokenStoreProvider);
    _session = ref.watch(authSessionProvider);

    if (ref.watch(appConfigProblemProvider) != null) {
      _session.replace(null);
      return const GrindingAuthState.unauthenticated(
        lastError: AppFailure.appNotConfigured(),
      );
    }

    final token = await _readToken();
    if (token == null) {
      _session.replace(null);
      return const GrindingAuthState.unauthenticated();
    }
    _session.replace(token);

    final prefs = await _prefs();
    try {
      final session = await _repo.getSession();
      await _cacheWorker(prefs, session.worker, session.expiresAt);
      return GrindingAuthState.authenticated(
        worker: session.worker,
        expiresAt: session.expiresAt,
      );
    } on AppFailure catch (failure) {
      if (failure is ApiFailure && ErrorCodes.isSessionTerminal(failure.code)) {
        await _clearLocal(prefs);
        return GrindingAuthState.unauthenticated(lastError: failure);
      }
      // Transient (network / timeout / server / device) — keep the cached
      // identity so a flaky network does not strand the worker on PIN.
      final cached = await _readCachedWorker(prefs);
      if (cached != null) return cached;
      return GrindingAuthState.unauthenticated(lastError: failure);
    }
  }

  /// Submits the PIN. The value is consumed once and released — never
  /// assigned to a field, logged, or echoed back to the UI.
  ///
  /// Returns `null` once the worker is signed in, else the failure that
  /// refused the login (also kept as `lastError`). An ignored call (malformed
  /// PIN, a login or logout already running) returns
  /// [AppFailure.cancelled]. A `BiometricDeniedFailure` means the fingerprint
  /// dialog must take over (biometric handoff §9); it clears nothing.
  Future<AppFailure?> login(String rawPin) async {
    final pin = PinRule.normalize(rawPin);
    if (pin == null) return const AppFailure.cancelled();
    if (_loggingIn || _clearing) return const AppFailure.cancelled();
    if (state.valueOrNull is GrindingAuthAuthenticated) return null;
    _loggingIn = true;
    state = const AsyncLoading<GrindingAuthState>().copyWithPrevious(state);
    try {
      final result = await _repo.loginWithPin(pin);
      await _safe(() => _tokenStore.writeSessionToken(result.sessionToken));
      // New session epoch: any late response for a previous session is now
      // stale, and any retry loop started under it stops.
      _session.replace(result.sessionToken);
      ref.read(logoutReasonProvider.notifier).clear();
      await _cacheWorker(await _prefs(), result.worker, result.expiresAt);
      state = AsyncData(
        GrindingAuthState.authenticated(
          worker: result.worker,
          expiresAt: result.expiresAt,
        ),
      );
      return null;
    } catch (e, st) {
      final failure = ErrorMapper.fromException(e, st);
      state = AsyncData(GrindingAuthState.unauthenticated(lastError: failure));
      return failure;
    } finally {
      _loggingIn = false;
    }
  }

  /// Worker-initiated logout. Re-entrant calls are no-ops. Callers must not
  /// offer it while a START / COMPLETE is in flight.
  Future<void> logout() async {
    if (_clearing || _loggingIn) return;
    if (state.valueOrNull is! GrindingAuthAuthenticated) return;
    _clearing = true;
    // Our own logout ends the session server-side; a racing session error
    // is expected and must not be treated as a remote invalidation.
    ref.read(logoutReasonProvider.notifier).set(LogoutReason.manualLogout);
    try {
      try {
        await _repo.logout().timeout(AppConfig.logoutTimeout);
      } catch (e) {
        // Best effort: `ended:false`, a session error, a timeout or no
        // network all still end in a local logout.
        if (kDebugMode) {
          debugPrint('[GrindingAuth] logout call failed: ${e.runtimeType}');
        }
      }
      await _clearLocal(await _prefs());
      state = const AsyncData(GrindingAuthState.unauthenticated());
    } finally {
      _clearing = false;
    }
  }

  /// Session-terminal response (contract §4.3) for the session of
  /// [generation]. Stale generations are ignored: a late 401 for worker A
  /// never logs out worker B.
  Future<void> handleSessionInvalidated(
    ApiFailure failure, {
    required int? generation,
  }) async {
    if (generation == null || !_session.isCurrent(generation)) return;
    if (_clearing || _loggingIn) return;
    if (state.valueOrNull is! GrindingAuthAuthenticated) return;
    _clearing = true;
    try {
      await _clearLocal(await _prefs());
      state = AsyncData(GrindingAuthState.unauthenticated(lastError: failure));
    } finally {
      _clearing = false;
    }
  }

  /// App resume: `GET /sessions/me`. Transient failures keep the session.
  Future<void> verifySession() async {
    if (_clearing || _loggingIn) return;
    if (state.valueOrNull is! GrindingAuthAuthenticated) return;
    final generation = _session.generation;
    try {
      final session = await _repo.getSession();
      if (!_session.isCurrent(generation)) return;
      if (state.valueOrNull is! GrindingAuthAuthenticated) return;
      await _cacheWorker(await _prefs(), session.worker, session.expiresAt);
      state = AsyncData(
        GrindingAuthState.authenticated(
          worker: session.worker,
          expiresAt: session.expiresAt,
        ),
      );
    } on ApiFailure catch (failure) {
      if (ErrorCodes.isSessionTerminal(failure.code)) {
        await handleSessionInvalidated(failure, generation: generation);
      }
    } on AppFailure {
      // Transient — stay on the current identity.
    }
  }

  GrindingWorker? get currentWorker {
    final value = state.valueOrNull;
    return value is GrindingAuthAuthenticated ? value.worker : null;
  }

  Future<void> _clearLocal(PrefsStore? prefs) async {
    // Synchronous epoch bump first: from here on no request carries the old
    // token and every in-flight command sees a stale generation.
    _session.replace(null);
    await _safe(_tokenStore.clearSessionToken);
    if (prefs != null) await _safe(prefs.clearLastWorker);
  }

  Future<String?> _readToken() async {
    try {
      final token = await _tokenStore.readSessionToken();
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }

  Future<PrefsStore?> _prefs() async {
    try {
      return await ref.read(prefsStoreProvider.future);
    } catch (_) {
      return null;
    }
  }

  Future<GrindingAuthState?> _readCachedWorker(PrefsStore? prefs) async {
    if (prefs == null) return null;
    try {
      final cached = await prefs.readLastWorker();
      if (cached == null) return null;
      return GrindingAuthState.authenticated(
        worker: GrindingWorker(
          operatorId: cached.operatorId,
          name: cached.name,
        ),
        expiresAt: cached.expiresAt,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _cacheWorker(
    PrefsStore? prefs,
    GrindingWorker worker,
    String? expiresAt,
  ) async {
    if (prefs == null) return;
    await _safe(
      () => prefs.writeLastWorker(
        LastWorker(
          operatorId: worker.operatorId,
          name: worker.name,
          expiresAt: expiresAt,
        ),
      ),
    );
  }

  static Future<void> _safe(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      if (kDebugMode) debugPrint('[GrindingAuth] storage: ${e.runtimeType}');
    }
  }
}

final grindingAuthControllerProvider =
    AsyncNotifierProvider<GrindingAuthController, GrindingAuthState>(
      GrindingAuthController.new,
    );
