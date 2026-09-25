import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_grinding_app/features/scanner/presentation/wedge_scan_listener.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<String>> _pump(
  WidgetTester tester, {
  bool enabled = true,
  bool withField = false,
  FocusNode? fieldFocus,
}) async {
  final scans = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WedgeScanListener(
          enabled: enabled,
          onScan: scans.add,
          child: withField
              ? TextField(focusNode: fieldFocus)
              : const SizedBox.expand(),
        ),
      ),
    ),
  );
  await tester.pump();
  return scans;
}

Future<void> _type(WidgetTester tester, String digits) async {
  for (final char in digits.split('')) {
    await tester.sendKeyEvent(
      LogicalKeyboardKey(char.codeUnitAt(0)),
      character: char,
    );
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
}

void main() {
  testWidgets('digits + Enter → one scan', (tester) async {
    final scans = await _pump(tester);
    await _type(tester, '001000000255');
    expect(scans, <String>['001000000255']);
  });

  testWidgets('Arabic-Indic digits are converted', (tester) async {
    final scans = await _pump(tester);
    for (final char in '٠٠١'.split('')) {
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0, character: char);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(scans, <String>['001']);
  });

  testWidgets('Enter with an empty buffer does nothing', (tester) async {
    final scans = await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(scans, isEmpty);
  });

  testWidgets('disabled (dialog open / command in flight) → ignored', (
    tester,
  ) async {
    final scans = await _pump(tester, enabled: false);
    await _type(tester, '001000000255');
    expect(scans, isEmpty);
  });

  testWidgets('keys go to a focused text field instead (never both)', (
    tester,
  ) async {
    final field = FocusNode();
    addTearDown(field.dispose);
    final scans = await _pump(tester, withField: true, fieldFocus: field);
    field.requestFocus();
    await tester.pump();
    await tester.enterText(find.byType(TextField), '001000000255');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(scans, isEmpty);
  });
}
