import '../value_objects/grinding_command.dart';
import '../value_objects/grinding_source.dart';
import '../value_objects/grinding_status.dart';

/// One of the two items a number shared by a roll and a pallet names
/// (`candidates` in `/check` and in the 409 `GRINDING_IDENTIFIER_AMBIGUOUS`
/// details). Display-only: the action the worker ends up taking always comes
/// from the follow-up `/check` for the chosen item, never from these flags.
class CheckCandidate {
  const CheckCandidate({
    required this.sourceType,
    required this.status,
    required this.allowedToStartGrinding,
    required this.allowedToCompleteGrinding,
    this.statusLabel,
    this.orderNumber,
    this.materialName,
  });

  /// A 409 without readable candidates (an older backend): both types, no
  /// state. The worker still chooses; nothing is inferred.
  static const List<CheckCandidate> unknownPair = <CheckCandidate>[
    CheckCandidate(
      sourceType: GrindingSourceType.roll,
      status: GrindingStatus.unknown,
      allowedToStartGrinding: false,
      allowedToCompleteGrinding: false,
    ),
    CheckCandidate(
      sourceType: GrindingSourceType.pallet,
      status: GrindingStatus.unknown,
      allowedToStartGrinding: false,
      allowedToCompleteGrinding: false,
    ),
  ];

  final GrindingSourceType sourceType;
  final GrindingStatus status;
  final String? statusLabel;
  final bool allowedToStartGrinding;
  final bool allowedToCompleteGrinding;
  final String? orderNumber;
  final String? materialName;

  /// `null` when the status is unknown (nothing to show).
  String? get displayStatusLabel {
    final label = statusLabel;
    if (label != null && label.trim().isNotEmpty) return label;
    return status == GrindingStatus.unknown ? null : status.fallbackLabel;
  }

  /// What the worker could do with this item — the same exclusive-flag rule
  /// as the order card, so START and COMPLETE read as different actions.
  GrindingCommand? get command {
    if (allowedToStartGrinding &&
        !allowedToCompleteGrinding &&
        status == GrindingStatus.readyForGrinding) {
      return GrindingCommand.start;
    }
    if (allowedToCompleteGrinding &&
        !allowedToStartGrinding &&
        status == GrindingStatus.inGrinding) {
      return GrindingCommand.complete;
    }
    return null;
  }
}
