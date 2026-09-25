import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Why the session is being cleared locally. While set, a racing session
/// error (our own `POST /auth/logout` ends the session server-side) is
/// expected and must not be treated as a remote invalidation. Mirrors the
/// Operator App's `OperatorLogoutReason`.
enum LogoutReason { manualLogout }

/// App-scoped (NOT autoDispose): the value must survive the window between
/// starting a logout and the auth state settling. Cleared by the next login.
class LogoutReasonController extends Notifier<LogoutReason?> {
  @override
  LogoutReason? build() => null;

  void set(LogoutReason reason) => state = reason;

  void clear() => state = null;
}

final logoutReasonProvider =
    NotifierProvider<LogoutReasonController, LogoutReason?>(
      LogoutReasonController.new,
    );
