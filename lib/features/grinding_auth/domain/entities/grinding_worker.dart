/// `Worker { operatorId, name }` (contract §6).
class GrindingWorker {
  const GrindingWorker({required this.operatorId, required this.name});

  final int operatorId;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is GrindingWorker &&
      other.operatorId == operatorId &&
      other.name == name;

  @override
  int get hashCode => Object.hash(operatorId, name);

  @override
  String toString() => 'GrindingWorker(operatorId: $operatorId)';
}

/// `SessionView { sessionId, createdAt, expiresAt, worker }`.
class GrindingSession {
  const GrindingSession({
    required this.worker,
    this.sessionId,
    this.createdAt,
    this.expiresAt,
  });

  final int? sessionId;
  final String? createdAt;

  /// Raw ISO-8601 instant, displayed in Asia/Hebron. Never compared with the
  /// device clock — the server decides expiry.
  final String? expiresAt;
  final GrindingWorker worker;
}

/// `PinLoginResponse { sessionToken, expiresAt, worker }`. `toString` never
/// includes the token.
class PinLoginResult {
  const PinLoginResult({
    required this.sessionToken,
    required this.worker,
    this.expiresAt,
  });

  final String sessionToken;
  final String? expiresAt;
  final GrindingWorker worker;

  @override
  String toString() =>
      'PinLoginResult(sessionToken: ***, worker: $worker, expiresAt: $expiresAt)';
}
