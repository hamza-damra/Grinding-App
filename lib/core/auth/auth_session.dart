import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The in-memory session credential plus a monotonically increasing
/// **auth generation** (session epoch).
///
/// Every login, logout and session invalidation opens a new generation and
/// swaps the token in ONE synchronous step, so a request always carries a
/// consistent (token, generation) pair. That pair is what fences the
/// dangerous races:
///
/// * a late `GRINDING_WORKER_SESSION_*` response for worker A's old token is
///   stamped with A's generation and is ignored once worker B has logged in;
/// * a START / COMPLETE retry loop captures the generation it started under
///   and aborts (keeping its pending record) as soon as the generation moves,
///   so worker A's command is never resent under worker B's session.
///
/// Secure storage is the persistence; this holder is what requests read.
class AuthSession {
  int _generation = 0;
  String? _token;

  int get generation => _generation;

  String? get token => _token;

  bool get hasToken {
    final t = _token;
    return t != null && t.isNotEmpty;
  }

  /// Replaces the credential (null = none) and opens a new generation.
  /// Returns the new generation.
  int replace(String? token) {
    _generation++;
    _token = (token == null || token.isEmpty) ? null : token;
    return _generation;
  }

  /// Whether [generation] is still the live session epoch.
  bool isCurrent(int generation) => generation == _generation;
}

/// App-lifetime singleton. Has no dependencies, so `dioProvider` can watch it
/// without creating a provider cycle with the auth controller.
final authSessionProvider = Provider<AuthSession>((ref) => AuthSession());
