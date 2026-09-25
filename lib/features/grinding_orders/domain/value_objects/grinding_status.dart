import '../../../../core/errors/arabic_messages.dart';
import '../../../../core/widgets/status_chip.dart';

/// `/check` `status` values (contract §4.2): the six order statuses plus
/// `NOT_ELIGIBLE`. Unknown values parse leniently to [unknown] — they never
/// crash and never enable an action.
enum GrindingStatus {
  pendingApproval('PENDING_APPROVAL'),
  readyForGrinding('READY_FOR_GRINDING'),
  rejected('REJECTED'),
  inGrinding('IN_GRINDING'),
  completed('COMPLETED'),
  cancelled('CANCELLED'),
  notEligible('NOT_ELIGIBLE'),
  unknown('');

  const GrindingStatus(this.wire);

  final String wire;

  static GrindingStatus fromWire(Object? raw) {
    if (raw is! String || raw.isEmpty) return GrindingStatus.unknown;
    for (final status in values) {
      if (status != unknown && status.wire == raw) return status;
    }
    return GrindingStatus.unknown;
  }

  /// Chip tone (Operator App status semantics; green only for done).
  StatusTone get tone => switch (this) {
    GrindingStatus.pendingApproval => StatusTone.warning,
    GrindingStatus.readyForGrinding => StatusTone.accent,
    GrindingStatus.inGrinding => StatusTone.info,
    GrindingStatus.completed => StatusTone.success,
    GrindingStatus.rejected => StatusTone.danger,
    GrindingStatus.cancelled => StatusTone.neutral,
    GrindingStatus.notEligible => StatusTone.neutral,
    GrindingStatus.unknown => StatusTone.neutral,
  };

  /// Local label, used only when the backend's `statusLabel` is absent.
  String get fallbackLabel => switch (this) {
    GrindingStatus.pendingApproval => ArabicMessages.pendingApprovalLabel,
    GrindingStatus.readyForGrinding => ArabicMessages.readyList,
    GrindingStatus.inGrinding => ArabicMessages.inGrindingList,
    GrindingStatus.completed => ArabicMessages.completedLabel,
    GrindingStatus.notEligible => ArabicMessages.notEligibleLabel,
    GrindingStatus.rejected => ArabicMessages.rejectedLabel,
    GrindingStatus.cancelled => ArabicMessages.cancelledLabel,
    GrindingStatus.unknown => '—',
  };
}

/// Queue filter of `GET /orders?status=` (the only two accepted values).
enum GrindingQueueStatus {
  ready(GrindingStatus.readyForGrinding),
  inGrinding(GrindingStatus.inGrinding);

  const GrindingQueueStatus(this.status);

  final GrindingStatus status;

  String get wire => status.wire;
}
