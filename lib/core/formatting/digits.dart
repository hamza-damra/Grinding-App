import 'package:flutter/services.dart';

/// Maps Arabic-Indic (`٠`–`٩`, U+0660–U+0669) and Extended Arabic-Indic
/// (`۰`–`۹`, U+06F0–U+06F9) digits to ASCII `0`–`9`. Every other character is
/// kept. Adapted from RollProduction's `toAsciiDigits`.
///
/// Arabic-locale Android keyboards and some hardware scanners emit
/// Arabic-Indic digits; the backend only accepts ASCII.
String toAsciiDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.writeCharCode(0x30 + (rune - 0x0660));
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.writeCharCode(0x30 + (rune - 0x06F0));
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Text-field formatter that converts Arabic-Indic digits to ASCII and drops
/// every non-digit. Unlike `FilteringTextInputFormatter.digitsOnly` it does
/// not silently discard `٤٨٢١` typed on an Arabic keyboard.
class AsciiDigitsInputFormatter extends TextInputFormatter {
  const AsciiDigitsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final converted = toAsciiDigits(newValue.text);
    final digits = converted.replaceAll(RegExp('[^0-9]'), '');
    if (digits == newValue.text) return newValue;
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
