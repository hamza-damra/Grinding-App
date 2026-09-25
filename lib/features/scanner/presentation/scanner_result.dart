/// What the camera scanner route pops with.
sealed class ScannerResult {
  const ScannerResult();
}

/// A valid 12-digit number was read (already normalized).
final class ScannedIdentifier extends ScannerResult {
  const ScannedIdentifier(this.identifier);

  final String identifier;
}

/// The worker chose «إدخال الرقم يدويًا» (e.g. camera denied / unavailable).
final class ManualEntryRequested extends ScannerResult {
  const ManualEntryRequested();
}
