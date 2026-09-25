/// How `/check` resolved the scanned number (contract §4.2 "How a number is
/// resolved"). Rolls and pallets share the 12-digit namespace; the backend
/// decides which item the worker can act on. Unknown values parse to
/// [unknown] and change nothing.
enum CheckResolution {
  /// The number names exactly one roll or pallet.
  singleMatch('SINGLE_MATCH'),

  /// The app sent `sourceType` (a worker's choice or a pinned item).
  sourceTypeSelected('SOURCE_TYPE_SELECTED'),

  /// The number names both; only one is relevant to grinding and the
  /// backend answered with it — no question for the worker.
  autoResolved('AUTO_RESOLVED'),

  /// The number names both and neither can be acted on.
  noneActionable('NONE_ACTIONABLE'),

  /// The number names both and both can be acted on (only ever inside a
  /// 409 `GRINDING_IDENTIFIER_AMBIGUOUS`).
  requiresSelection('REQUIRES_SELECTION'),

  unknown('');

  const CheckResolution(this.wire);

  final String wire;

  static CheckResolution fromWire(Object? raw) {
    if (raw is! String || raw.isEmpty) return CheckResolution.unknown;
    for (final resolution in values) {
      if (resolution != unknown && resolution.wire == raw) return resolution;
    }
    return CheckResolution.unknown;
  }
}
