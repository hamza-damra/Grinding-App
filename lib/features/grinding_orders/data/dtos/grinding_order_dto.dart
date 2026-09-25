import '../../../../core/api/json_read.dart';
import '../../../../core/formatting/decimal_weight.dart';
import '../../domain/entities/grinding_order.dart';
import '../../domain/value_objects/grinding_source.dart';
import '../../domain/value_objects/grinding_status.dart';

/// `GrindingOrderView` JSON → [GrindingOrder] (hand-written; see README
/// "Code generation").
class GrindingOrderDto {
  GrindingOrderDto._();

  /// Throws [FormatException] when a required field (`id`, `orderNumber`,
  /// `status`) is missing — a card without them could act on the wrong order.
  static GrindingOrder fromJson(Map<String, dynamic> json) {
    final id = JsonRead.integer(json['id']);
    final orderNumber = JsonRead.nonEmptyString(json['orderNumber']);
    final statusRaw = JsonRead.nonEmptyString(json['status']);
    if (id == null || orderNumber == null || statusRaw == null) {
      throw const FormatException('GrindingOrderView missing required field');
    }
    return GrindingOrder(
      id: id,
      orderNumber: orderNumber,
      status: GrindingStatus.fromWire(statusRaw),
      statusRaw: statusRaw,
      statusLabel: JsonRead.nonEmptyString(json['statusLabel']),
      sourceType: GrindingSourceType.fromWire(json['sourceType']),
      sourceOrigin: GrindingSourceOrigin.fromWire(json['sourceOrigin']),
      sourceIdentifier: JsonRead.string(json['sourceIdentifier']) ?? '',
      materialName: JsonRead.nonEmptyString(json['materialName']),
      expectedWeightKg: DecimalWeight.canonical(json['expectedWeightKg']),
      sourceQuantity: DecimalWeight.displayQuantity(json['sourceQuantity']),
      lineName: JsonRead.nonEmptyString(json['lineName']),
      directScrap: JsonRead.flag(json['directScrap']),
      legacy: JsonRead.flag(json['legacy']),
      startedByName: JsonRead.nonEmptyString(json['startedByName']),
      startedAt: JsonRead.nonEmptyString(json['startedAt']),
      completedByName: JsonRead.nonEmptyString(json['completedByName']),
      completedAt: JsonRead.nonEmptyString(json['completedAt']),
      createdAt: JsonRead.nonEmptyString(json['createdAt']),
      version: JsonRead.integer(json['version']),
    );
  }
}
