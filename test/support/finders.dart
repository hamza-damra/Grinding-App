import 'package:flutter/material.dart';
import 'package:flutter_grinding_app/core/formatting/bidi.dart';
import 'package:flutter_grinding_app/core/widgets/confirm_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [Text] whose content equals [text] once bidi isolates are removed.
Finder textIgnoringIsolates(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data != null && Bidi.strip(w.data!) == text,
  description: 'Text "$text" (isolates ignored)',
);

/// A [Text] containing [text] once bidi isolates are removed.
Finder textContainingIgnoringIsolates(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data != null && Bidi.strip(w.data!).contains(text),
  description: 'Text containing "$text" (isolates ignored)',
);

/// [text] inside the open confirm dialog.
Finder inConfirmDialog(String text) =>
    find.descendant(of: find.byType(ConfirmDialog), matching: find.text(text));

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

/// Types [pin] and taps «دخول».
Future<void> loginWithPin(WidgetTester tester, String pin) async {
  await tester.enterText(byKey('pin-input'), pin);
  await tester.pump();
  await tester.tap(byKey('pin-submit'));
  await tester.pumpAndSettle();
}

/// Manual entry on Home + «تحقق».
Future<void> checkManually(WidgetTester tester, String number) async {
  await tester.enterText(byKey('manual-identifier'), number);
  await tester.pump();
  await tester.tap(byKey('manual-check'));
  await tester.pumpAndSettle();
}

/// A Home queue tab label (the same words also appear on status chips).
Finder queueTab(String label) =>
    find.descendant(of: byKey('queue-tabs'), matching: find.text(label));
