/// Unicode bidirectional isolates for embedding left-to-right values (order
/// numbers such as `GR-001042`, 12-digit identifiers, weights) inside Arabic
/// right-to-left sentences. Without an isolate the neutral characters around
/// the value (`-`, `؟`, spaces) can be reordered and the sentence renders
/// scrambled.
class Bidi {
  Bidi._();

  /// FIRST STRONG ISOLATE — direction taken from the value's first strong
  /// character.
  static const String fsi = '\u2068';

  /// LEFT-TO-RIGHT ISOLATE.
  static const String lri = '\u2066';

  /// POP DIRECTIONAL ISOLATE — closes [fsi] / [lri].
  static const String pdi = '\u2069';

  /// Wraps [value] in a first-strong isolate.
  static String isolate(String value) => '$fsi$value$pdi';

  /// Wraps [value] in a left-to-right isolate (digits-only values have no
  /// strong character, so first-strong would not force LTR).
  static String ltr(String value) => '$lri$value$pdi';

  /// Removes isolate/embedding control characters (tests, comparisons).
  static String strip(String value) =>
      value.replaceAll(RegExp('[\u2066-\u2069\u202A-\u202E]'), '');
}
