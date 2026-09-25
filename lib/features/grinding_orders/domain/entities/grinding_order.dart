import '../value_objects/grinding_source.dart';
import '../value_objects/grinding_status.dart';

/// `GrindingOrderView` (contract §6). Timestamps stay raw ISO-8601 strings
/// and are rendered with `FactoryTime` (Asia/Hebron). Decimals stay text
/// (`DecimalWeight`) — never rounded.
class GrindingOrder {
  const GrindingOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.statusRaw,
    required this.sourceType,
    required this.sourceOrigin,
    required this.sourceIdentifier,
    required this.directScrap,
    required this.legacy,
    this.statusLabel,
    this.materialName,
    this.expectedWeightKg,
    this.sourceQuantity,
    this.lineName,
    this.startedByName,
    this.startedAt,
    this.completedByName,
    this.completedAt,
    this.createdAt,
    this.version,
  });

  final int id;
  final String orderNumber;
  final GrindingStatus status;
  final String statusRaw;
  final String? statusLabel;
  final GrindingSourceType sourceType;
  final GrindingSourceOrigin sourceOrigin;
  final String sourceIdentifier;
  final String? materialName;

  /// Canonical 3-decimal text (`40.000`), or null.
  final String? expectedWeightKg;

  /// Pallet quantity as received, or null.
  final String? sourceQuantity;
  final String? lineName;
  final bool directScrap;
  final bool legacy;
  final String? startedByName;
  final String? startedAt;
  final String? completedByName;
  final String? completedAt;
  final String? createdAt;
  final int? version;

  /// Backend label first; local Arabic fallback only when absent.
  String get displayStatusLabel {
    final label = statusLabel;
    if (label != null && label.trim().isNotEmpty) return label;
    return status.fallbackLabel;
  }
}
