/// `data.status` of the biometric attempt-status endpoint (biometric handoff
/// §4.3).
enum BiometricAttemptStatus {
  /// No valid fingerprint yet — poll again immediately.
  pending('PENDING'),

  /// A valid fingerprint arrived — re-submit the original login once.
  verified('VERIFIED'),

  /// The factory agent is offline, so the check is suspended — re-submit.
  enforcementSuspended('ENFORCEMENT_SUSPENDED'),

  /// An admin exempted the employee or switched the check off — re-submit.
  notRequired('NOT_REQUIRED'),

  /// The terminal reports offline (the agent is up) — keep polling.
  deviceUnavailable('DEVICE_UNAVAILABLE'),

  /// The admin removed / disabled the link meanwhile — stop polling.
  mappingMissing('MAPPING_MISSING'),
  mappingDisabled('MAPPING_DISABLED');

  const BiometricAttemptStatus(this.wire);

  final String wire;

  /// Unknown or missing values read as [pending], so a future server value
  /// never breaks the dialog.
  static BiometricAttemptStatus fromWire(Object? raw) {
    for (final status in values) {
      if (status.wire == raw) return status;
    }
    return pending;
  }
}

class BiometricAttemptStatusResponse {
  const BiometricAttemptStatusResponse({
    required this.status,
    this.attemptExpiresAt,
  });

  final BiometricAttemptStatus status;

  /// UTC. Display only; the server's 410 decides expiry.
  final DateTime? attemptExpiresAt;

  @override
  String toString() => 'BiometricAttemptStatusResponse(${status.wire})';
}
