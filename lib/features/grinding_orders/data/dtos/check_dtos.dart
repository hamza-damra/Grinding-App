import '../../../../core/api/json_read.dart';
import '../../../../core/formatting/decimal_weight.dart';
import '../../domain/entities/check_candidate.dart';
import '../../domain/entities/check_result.dart';
import '../../domain/entities/execution_result.dart';
import '../../domain/entities/grinding_order.dart';
import '../../domain/value_objects/check_resolution.dart';
import '../../domain/value_objects/grinding_source.dart';
import '../../domain/value_objects/grinding_status.dart';
import 'grinding_order_dto.dart';

/// `CheckRequest { identifier, sourceType? }`.
class CheckRequestDto {
  const CheckRequestDto({required this.identifier, this.sourceType});

  final String identifier;
  final GrindingSourceType? sourceType;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'identifier': identifier,
    if (sourceType != null && sourceType != GrindingSourceType.unknown)
      'sourceType': sourceType!.wire,
  };
}

/// `CheckResponse` → [CheckResult].
class CheckResponseDto {
  CheckResponseDto._();

  static CheckResult fromJson(Map<String, dynamic> json) {
    final statusRaw = JsonRead.nonEmptyString(json['status']);
    if (statusRaw == null) {
      throw const FormatException('CheckResponse missing status');
    }
    final orderJson = JsonRead.map(json['order']);
    final GrindingOrder? order = orderJson == null
        ? null
        : GrindingOrderDto.fromJson(orderJson);
    final details = JsonRead.map(json['details']);
    return CheckResult(
      identifier: JsonRead.string(json['identifier']) ?? '',
      sourceType: GrindingSourceType.fromWire(json['sourceType']),
      status: GrindingStatus.fromWire(statusRaw),
      statusRaw: statusRaw,
      statusLabel: JsonRead.nonEmptyString(json['statusLabel']),
      message: JsonRead.nonEmptyString(json['message']),
      allowedToStartGrinding: JsonRead.flag(json['allowedToStartGrinding']),
      allowedToCompleteGrinding: JsonRead.flag(
        json['allowedToCompleteGrinding'],
      ),
      order: order,
      notEligibleProductName: details == null
          ? null
          : JsonRead.nonEmptyString(details['productName']),
      notEligibleQuantity: details == null
          ? null
          : DecimalWeight.displayQuantity(details['quantity']),
      resolution: CheckResolution.fromWire(json['resolution']),
      candidates: CheckCandidateDto.listFromJson(json['candidates']),
    );
  }
}

/// `CheckCandidate` (in `CheckResponse.candidates` and in the 409
/// `GRINDING_IDENTIFIER_AMBIGUOUS` `details.candidates`). Lenient: a row
/// without a known `sourceType` is skipped, and only `sourceType` + `label`
/// are guaranteed by older backends (the rest parses to "unknown state").
class CheckCandidateDto {
  CheckCandidateDto._();

  static List<CheckCandidate> listFromJson(Object? raw) {
    if (raw is! List) return const <CheckCandidate>[];
    final candidates = <CheckCandidate>[];
    for (final item in raw) {
      final json = JsonRead.map(item);
      if (json == null) continue;
      final sourceType = GrindingSourceType.fromWire(json['sourceType']);
      if (sourceType == GrindingSourceType.unknown) continue;
      candidates.add(
        CheckCandidate(
          sourceType: sourceType,
          status: GrindingStatus.fromWire(json['status']),
          statusLabel: JsonRead.nonEmptyString(json['statusLabel']),
          allowedToStartGrinding: JsonRead.flag(json['allowedToStartGrinding']),
          allowedToCompleteGrinding: JsonRead.flag(
            json['allowedToCompleteGrinding'],
          ),
          orderNumber: JsonRead.nonEmptyString(json['orderNumber']),
          materialName: JsonRead.nonEmptyString(json['materialName']),
        ),
      );
    }
    return List<CheckCandidate>.unmodifiable(candidates);
  }
}

/// `QueueResponse { orders, limit }` → orders. A malformed row is skipped
/// rather than failing the whole list.
class QueueResponseDto {
  QueueResponseDto._();

  static List<GrindingOrder> fromJson(Map<String, dynamic> json) {
    final raw = json['orders'];
    if (raw is! List) {
      throw const FormatException('QueueResponse missing orders');
    }
    final orders = <GrindingOrder>[];
    for (final item in raw) {
      final map = JsonRead.map(item);
      if (map == null) continue;
      try {
        orders.add(GrindingOrderDto.fromJson(map));
      } on FormatException {
        continue;
      }
    }
    return List<GrindingOrder>.unmodifiable(orders);
  }
}

/// `ExecutionRequest { clientRequestId }`.
class ExecutionRequestDto {
  const ExecutionRequestDto(this.clientRequestId);

  final String clientRequestId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'clientRequestId': clientRequestId,
  };
}

/// `ExecutionResponse { order, replayed, message }` → [ExecutionResult].
class ExecutionResponseDto {
  ExecutionResponseDto._();

  /// Never throws: the caller already knows the server answered
  /// `success:true`, i.e. the command was committed. An unreadable payload
  /// yields `order: null` and the app re-checks for the truth.
  static ExecutionResult fromData(Object? data) {
    final json = JsonRead.map(data);
    if (json == null) {
      return const ExecutionResult(order: null, replayed: false);
    }
    GrindingOrder? order;
    final orderJson = JsonRead.map(json['order']);
    if (orderJson != null) {
      try {
        order = GrindingOrderDto.fromJson(orderJson);
      } on FormatException {
        order = null;
      }
    }
    return ExecutionResult(
      order: order,
      replayed: JsonRead.flag(json['replayed']),
    );
  }
}
