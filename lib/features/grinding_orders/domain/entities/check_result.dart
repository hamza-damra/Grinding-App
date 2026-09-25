import '../../../../core/errors/arabic_messages.dart';
import '../value_objects/check_resolution.dart';
import '../value_objects/grinding_source.dart';
import '../value_objects/grinding_status.dart';
import 'check_candidate.dart';
import 'grinding_order.dart';

/// `POST /check` result (contract §4.2 / §6).
class CheckResult {
  const CheckResult({
    required this.identifier,
    required this.sourceType,
    required this.status,
    required this.statusRaw,
    required this.allowedToStartGrinding,
    required this.allowedToCompleteGrinding,
    this.statusLabel,
    this.message,
    this.order,
    this.notEligibleProductName,
    this.notEligibleQuantity,
    this.resolution = CheckResolution.unknown,
    this.candidates = const <CheckCandidate>[],
  });

  final String identifier;

  /// The item this answer is about; [GrindingSourceType.unknown] for
  /// [CheckResolution.noneActionable], which is about both.
  final GrindingSourceType sourceType;
  final GrindingStatus status;
  final String statusRaw;
  final String? statusLabel;

  /// Arabic server message (e.g. «جاهز للجرش — يمكنك بدء الجرش.»).
  final String? message;

  /// The backend's final action gate.
  final bool allowedToStartGrinding;
  final bool allowedToCompleteGrinding;

  /// Absent for `NOT_ELIGIBLE`.
  final GrindingOrder? order;

  /// `NOT_ELIGIBLE` pallet details (only these are shown; raw roll enums such
  /// as `rollType` / `productionKind` are never displayed).
  final String? notEligibleProductName;
  final String? notEligibleQuantity;

  final CheckResolution resolution;

  /// Both items, when the number names a roll AND a pallet
  /// ([CheckResolution.autoResolved] / [CheckResolution.noneActionable]).
  final List<CheckCandidate> candidates;

  String get displayStatusLabel {
    final label = statusLabel;
    if (label != null && label.trim().isNotEmpty) return label;
    return status.fallbackLabel;
  }

  /// The explanatory line under the card. Contract fallbacks when the server
  /// omits `message`.
  String? get displayMessage {
    final m = message;
    if (m != null && m.trim().isNotEmpty) return m;
    return switch (status) {
      GrindingStatus.pendingApproval => ArabicMessages.pendingApprovalMessage,
      GrindingStatus.notEligible => ArabicMessages.notEligibleLabel,
      _ => null,
    };
  }
}
