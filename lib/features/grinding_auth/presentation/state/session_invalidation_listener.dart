import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/session_invalidation_signal.dart';
import '../../../../core/auth/auth_session.dart';
import 'grinding_auth_controller.dart';
import 'grinding_auth_state.dart';
import 'logout_reason.dart';

/// Subscribes to [SessionInvalidationSignal] (emitted from inside Dio) and
/// drives the auth cleanup the interceptor cannot perform without a Riverpod
/// cycle (Operator App `AppTokenInvalidationListener` pattern). Mounted in
/// `app.dart` for the app's lifetime.
///
/// Skips a signal when:
/// * its auth generation is not the live one (a late response for a previous
///   session — e.g. worker A's old token after worker B logged in);
/// * an intentional logout is in progress;
/// * the worker is not authenticated (an earlier signal already cleaned up).
class SessionInvalidationListener extends Notifier<void> {
  StreamSubscription<SessionInvalidation>? _sub;

  @override
  void build() {
    final signal = ref.watch(sessionInvalidationSignalProvider);
    _sub?.cancel();
    _sub = signal.stream.listen(_handle);
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
  }

  void _handle(SessionInvalidation event) {
    final generation = event.generation;
    final session = ref.read(authSessionProvider);
    if (generation == null || !session.isCurrent(generation)) {
      if (kDebugMode) {
        debugPrint(
          '[SessionInvalidation] ignored stale signal '
          '(signal=$generation current=${session.generation})',
        );
      }
      return;
    }
    if (ref.read(logoutReasonProvider) != null) return;
    final auth = ref.read(grindingAuthControllerProvider).valueOrNull;
    if (auth is! GrindingAuthAuthenticated) return;
    unawaited(
      ref
          .read(grindingAuthControllerProvider.notifier)
          .handleSessionInvalidated(event.failure, generation: generation),
    );
  }
}

final sessionInvalidationListenerProvider =
    NotifierProvider<SessionInvalidationListener, void>(
      SessionInvalidationListener.new,
    );
