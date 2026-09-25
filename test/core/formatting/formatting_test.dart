import 'package:flutter_grinding_app/core/formatting/bidi.dart';
import 'package:flutter_grinding_app/core/formatting/decimal_weight.dart';
import 'package:flutter_grinding_app/core/formatting/digits.dart';
import 'package:flutter_grinding_app/core/formatting/factory_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  group('DecimalWeight (contract §6: display as-is, never round)', () {
    test('JSON int / double / string → 3-decimal text', () {
      expect(DecimalWeight.canonical(40), '40.000');
      expect(DecimalWeight.canonical(40.0), '40.000');
      expect(DecimalWeight.canonical(40.5), '40.500');
      expect(DecimalWeight.canonical(12.345), '12.345');
      expect(DecimalWeight.canonical(0.1), '0.100');
      expect(DecimalWeight.canonical('40'), '40.000');
      expect(DecimalWeight.canonical('40.5'), '40.500');
      expect(DecimalWeight.canonical(' 7.25 '), '7.250');
    });

    test('DECIMAL(12,3) extremes survive without rounding', () {
      expect(DecimalWeight.canonical(999999999.999), '999999999.999');
      expect(DecimalWeight.canonical('999999999.999'), '999999999.999');
      expect(DecimalWeight.canonical(0.001), '0.001');
      expect(DecimalWeight.canonical('0.001'), '0.001');
    });

    test('values that look roundable are shown exactly', () {
      // A naive toStringAsFixed(2) would show 12.35 / 0.00.
      expect(DecimalWeight.canonical(12.345), isNot('12.35'));
      expect(DecimalWeight.canonical(0.004), '0.004');
    });

    test('more than 3 decimals (outside the contract) is not truncated', () {
      expect(DecimalWeight.canonical('1.23456'), '1.23456');
      expect(DecimalWeight.canonical(1.23456), '1.23456');
    });

    test('null / garbage → null (row hidden, never «0.000»)', () {
      expect(DecimalWeight.canonical(null), isNull);
      expect(DecimalWeight.canonical('abc'), isNull);
      expect(DecimalWeight.canonical('1,5'), isNull);
      expect(DecimalWeight.canonical(double.nan), isNull);
      expect(DecimalWeight.canonical(true), isNull);
    });

    test('display helpers', () {
      expect(DecimalWeight.displayKg(40), '40.000 كغ');
      expect(DecimalWeight.displayKg(null), isNull);
      expect(DecimalWeight.displayQuantity(1200), '1200');
      expect(DecimalWeight.displayQuantity(1200.0), '1200');
      expect(DecimalWeight.displayQuantity(12.5), '12.5');
      expect(DecimalWeight.displayQuantity('12'), '12');
      expect(DecimalWeight.displayQuantity('x'), isNull);
    });
  });

  group('FactoryTime (Asia/Hebron, never the device zone)', () {
    test('winter instant is UTC+2, summer instant is UTC+3', () {
      expect(FactoryTime.formatClock('2026-01-15T10:00:00Z'), '12:00');
      expect(FactoryTime.formatClock('2026-07-15T10:00:00Z'), '13:00');
    });

    test('contract example instants', () {
      // 2026-09-22 is summer time in Hebron.
      expect(
        FactoryTime.formatDateTime('2026-09-22T09:41:07.312Z'),
        '2026-09-22 12:41',
      );
      expect(FactoryTime.formatClock('2026-09-22T21:41:07.312Z'), '00:41');
    });

    test('day rollover uses the factory calendar', () {
      expect(FactoryTime.formatDate('2026-07-15T22:30:00Z'), '2026-07-16');
      expect(FactoryTime.formatDate('2026-01-15T21:59:00Z'), '2026-01-15');
      expect(FactoryTime.formatDate('2026-01-15T22:00:00Z'), '2026-01-16');
    });

    test('offset-qualified instants resolve to the same wall-clock', () {
      expect(
        FactoryTime.formatClock('2026-07-15T13:00:00+03:00'),
        FactoryTime.formatClock('2026-07-15T10:00:00Z'),
      );
    });

    test('DST transitions from the bundled tz data are honoured', () {
      final zone = FactoryTime.zone;
      // Discover the transitions (no hard-coded dates: the rules change).
      final transitions = <DateTime>[];
      var cursor = DateTime.utc(2026);
      var offset = tz.TZDateTime.from(cursor, zone).timeZoneOffset;
      while (cursor.year == 2026) {
        final next = cursor.add(const Duration(hours: 1));
        final nextOffset = tz.TZDateTime.from(next, zone).timeZoneOffset;
        if (nextOffset != offset) transitions.add(next);
        cursor = next;
        offset = nextOffset;
      }
      expect(transitions, hasLength(2), reason: 'spring + autumn change');

      for (final change in transitions) {
        final before = change.subtract(const Duration(minutes: 1));
        final beforeWall = FactoryTime.parse(before.toIso8601String())!;
        final afterWall = FactoryTime.parse(change.toIso8601String())!;
        final expectedBefore = before.add(
          tz.TZDateTime.from(before, zone).timeZoneOffset,
        );
        final expectedAfter = change.add(
          tz.TZDateTime.from(change, zone).timeZoneOffset,
        );
        expect(beforeWall.hour, expectedBefore.hour);
        expect(beforeWall.minute, expectedBefore.minute);
        expect(afterWall.hour, expectedAfter.hour);
        expect(afterWall.minute, expectedAfter.minute);
        // Exactly one hour of offset change across the transition.
        final delta =
            tz.TZDateTime.from(change, zone).timeZoneOffset -
            tz.TZDateTime.from(before, zone).timeZoneOffset;
        expect(delta.inMinutes.abs(), 60);
      }
    });

    test('a naive timestamp is already factory wall-clock', () {
      expect(FactoryTime.formatClock('2026-07-15T10:00:00'), '10:00');
    });

    test('null / empty / garbage never throws', () {
      expect(FactoryTime.formatClock(null), FactoryTime.fallback);
      expect(FactoryTime.formatDateTime(''), FactoryTime.fallback);
      expect(FactoryTime.formatDate('yesterday'), FactoryTime.fallback);
      expect(FactoryTime.isValid('nope'), isFalse);
    });
  });

  group('Arabic-Indic digits', () {
    test('toAsciiDigits maps both Arabic-Indic ranges', () {
      expect(toAsciiDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
      expect(toAsciiDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
      expect(toAsciiDigits('GR-٠٠١'), 'GR-001');
    });

    test('formatter converts instead of dropping, and strips non-digits', () {
      const formatter = AsciiDigitsInputFormatter();
      TextEditingValue apply(String text) => formatter.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(text: text),
      );
      expect(apply('٤٨٢١').text, '4821');
      expect(apply('a1-2 3').text, '123');
      expect(apply('0012').text, '0012');
    });
  });

  group('Bidi isolates', () {
    test('wrap and strip', () {
      final wrapped = Bidi.isolate('GR-001042');
      expect(wrapped.startsWith(Bidi.fsi), isTrue);
      expect(wrapped.endsWith(Bidi.pdi), isTrue);
      expect(Bidi.strip(wrapped), 'GR-001042');
      expect(Bidi.strip(Bidi.ltr('001000000255')), '001000000255');
    });

    test('isolate characters are the Unicode isolates', () {
      expect(Bidi.fsi.codeUnits.single, 0x2068);
      expect(Bidi.lri.codeUnits.single, 0x2066);
      expect(Bidi.pdi.codeUnits.single, 0x2069);
    });
  });
}
