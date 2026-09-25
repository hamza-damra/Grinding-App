import '../../../../core/errors/app_failure.dart';
import '../../domain/entities/grinding_worker.dart';

/// Operator App's `OperatorAuthState` shape (hand-written sealed class).
sealed class GrindingAuthState {
  const GrindingAuthState();

  /// No usable session: the PIN screen is shown. [lastError] carries the
  /// reason (wrong PIN, session ended, access withdrawn…) for inline display.
  const factory GrindingAuthState.unauthenticated({AppFailure? lastError}) =
      GrindingAuthUnauthenticated;

  /// A session token is held and the worker is known.
  const factory GrindingAuthState.authenticated({
    required GrindingWorker worker,
    String? expiresAt,
  }) = GrindingAuthAuthenticated;
}

final class GrindingAuthUnauthenticated extends GrindingAuthState {
  const GrindingAuthUnauthenticated({this.lastError});

  final AppFailure? lastError;
}

final class GrindingAuthAuthenticated extends GrindingAuthState {
  const GrindingAuthAuthenticated({required this.worker, this.expiresAt});

  final GrindingWorker worker;

  /// Raw ISO-8601 instant (display only, Asia/Hebron).
  final String? expiresAt;
}
