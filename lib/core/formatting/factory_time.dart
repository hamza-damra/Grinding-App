import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Renders backend timestamps on the factory's wall-clock (`Asia/Hebron`),
/// independently of the device timezone. Ported from the Operator App.
///
/// The backend sends absolute instants as ISO-8601 UTC
/// (`2026-09-22T09:41:07.312Z`). Reading the parsed fields directly prints
/// the UTC wall-clock; `.toLocal()` prints the DEVICE's wall-clock. Both are
/// wrong on the shop floor, so [toFactoryTime] maps an instant into
/// `Asia/Hebron` (UTC+02:00 in winter, UTC+03:00 in summer) through the IANA
/// database — a fixed offset cannot express the DST transitions.
///
/// A naive string (no `Z`, no offset) is not an instant: its fields already
/// are the factory wall-clock and are read as-is.
class FactoryTime {
  FactoryTime._();

  /// Shown for null / empty / unparseable input. Never throws.
  static const String fallback = '—';

  static const String zoneName = 'Asia/Hebron';

  static tz.Location? _cachedZone;

  /// The `Asia/Hebron` location, loading the timezone database on first use
  /// if `main()` has not already done so (keeps tests working without setup).
  static tz.Location get zone {
    final cached = _cachedZone;
    if (cached != null) return cached;
    try {
      return _cachedZone = tz.getLocation(zoneName);
    } on tz.LocationNotFoundException {
      tzdata.initializeTimeZones();
      return _cachedZone = tz.getLocation(zoneName);
    }
  }

  /// Converts an absolute [instant] to the factory wall-clock. Never use
  /// `.toLocal()` for a backend instant.
  static tz.TZDateTime toFactoryTime(DateTime instant) =>
      tz.TZDateTime.from(instant.toUtc(), zone);

  /// `HH:mm` factory wall-clock, or [fallback].
  static String formatClock(String? raw) {
    final wall = parse(raw);
    return wall == null
        ? fallback
        : '${_pad2(wall.hour)}:${_pad2(wall.minute)}';
  }

  /// `YYYY-MM-DD` factory-calendar date, or [fallback]. The factory's day —
  /// `2026-07-15T22:30:00Z` falls on 2026-07-16 in Hebron.
  static String formatDate(String? raw) {
    final wall = parse(raw);
    return wall == null
        ? fallback
        : '${wall.year}-${_pad2(wall.month)}-${_pad2(wall.day)}';
  }

  /// `YYYY-MM-DD HH:mm` factory wall-clock, or [fallback].
  static String formatDateTime(String? raw) {
    final wall = parse(raw);
    if (wall == null) return fallback;
    return '${wall.year}-${_pad2(wall.month)}-${_pad2(wall.day)} '
        '${_pad2(wall.hour)}:${_pad2(wall.minute)}';
  }

  /// `true` when [raw] is a parseable backend timestamp.
  static bool isValid(String? raw) => parse(raw) != null;

  /// Resolves any backend timestamp string onto the factory wall-clock.
  ///
  /// `DateTime.parse` sets `isUtc` for every zone-qualified string (`Z`,
  /// `+03:00`, …), normalizing it to the correct absolute instant, and leaves
  /// it clear for a naive one — an exact "is this an instant?" test.
  static tz.TZDateTime? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    if (parsed.isUtc) return toFactoryTime(parsed);
    return tz.TZDateTime(
      zone,
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
    );
  }

  static String _pad2(int value) => value.toString().padLeft(2, '0');
}
