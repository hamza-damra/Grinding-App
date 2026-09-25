import '../../../../core/errors/arabic_messages.dart';

/// `ROLL` / `PALLET` (contract §6). Unknown values parse to [unknown] and are
/// never sent back to the server.
enum GrindingSourceType {
  roll('ROLL'),
  pallet('PALLET'),
  unknown('');

  const GrindingSourceType(this.wire);

  final String wire;

  static GrindingSourceType fromWire(Object? raw) {
    if (raw == 'ROLL') return GrindingSourceType.roll;
    if (raw == 'PALLET') return GrindingSourceType.pallet;
    return GrindingSourceType.unknown;
  }

  /// «رول» / «طبلية»; `null` when unknown (the row is then omitted).
  String? get label => switch (this) {
    GrindingSourceType.roll => ArabicMessages.sourceRoll,
    GrindingSourceType.pallet => ArabicMessages.sourcePallet,
    GrindingSourceType.unknown => null,
  };

  /// «الرول» / «الطبلية»; `null` when unknown.
  String? get definiteLabel => switch (this) {
    GrindingSourceType.roll => ArabicMessages.sourceRollDefinite,
    GrindingSourceType.pallet => ArabicMessages.sourcePalletDefinite,
    GrindingSourceType.unknown => null,
  };
}

/// Where the order came from. Parsed for completeness but never displayed as
/// a raw enum (the worker sees «جرش مباشر» via `directScrap` instead).
enum GrindingSourceOrigin {
  rollProductionScrap('ROLL_PRODUCTION_SCRAP'),
  thermoformingRollRemainder('THERMOFORMING_ROLL_REMAINDER'),
  palletizingPallet('PALLETIZING_PALLET'),
  unknown('');

  const GrindingSourceOrigin(this.wire);

  final String wire;

  static GrindingSourceOrigin fromWire(Object? raw) {
    for (final origin in values) {
      if (origin != unknown && origin.wire == raw) return origin;
    }
    return GrindingSourceOrigin.unknown;
  }
}
