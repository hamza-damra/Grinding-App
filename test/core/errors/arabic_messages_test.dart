import 'dart:io';

import 'package:flutter_grinding_app/core/errors/app_failure.dart';
import 'package:flutter_grinding_app/core/errors/arabic_messages.dart';
import 'package:flutter_grinding_app/core/errors/error_codes.dart';
import 'package:flutter_test/flutter_test.dart';

/// The contract file is the source of truth for worker-facing copy: every
/// contract string must appear in it byte for byte (tanween, hamza, the
/// em-dash and the Arabic question mark included).
void main() {
  late String contract;

  setUpAll(() {
    contract = File(
      'docs/GRINDING_APP_BACKEND_CONTRACT.md',
    ).readAsStringSync().replaceAll('\r\n', '\n');
  });

  group('§10 strings are verbatim contract text', () {
    final contractStrings = <String, String>{
      'appTitle': ArabicMessages.appTitle,
      'pinScreenTitle': ArabicMessages.pinScreenTitle,
      'loginButton': ArabicMessages.loginButton,
      'logout': ArabicMessages.logout,
      'scanButton': ArabicMessages.scanButton,
      'manualEntryLabel': ArabicMessages.manualEntryLabel,
      'checkButton': ArabicMessages.checkButton,
      'readyList': ArabicMessages.readyList,
      'inGrindingList': ArabicMessages.inGrindingList,
      'startButton': ArabicMessages.startButton,
      'completeButton': ArabicMessages.completeButton,
      'startConfirmAction': ArabicMessages.startConfirmAction,
      'completeConfirmTitle': ArabicMessages.completeConfirmTitle,
      'completeConfirmAction': ArabicMessages.completeConfirmAction,
      'cancel': ArabicMessages.cancel,
      'startSuccess': ArabicMessages.startSuccess,
      'completeSuccess': ArabicMessages.completeSuccess,
      'directScrapTag': ArabicMessages.directScrapTag,
      'sourceRoll': ArabicMessages.sourceRoll,
      'sourcePallet': ArabicMessages.sourcePallet,
      'selectionTitle': ArabicMessages.selectionTitle,
      'selectionText': ArabicMessages.selectionText,
      'emptyList': ArabicMessages.emptyList,
      'pendingApprovalMessage': ArabicMessages.pendingApprovalMessage,
      'pendingApprovalLabel': ArabicMessages.pendingApprovalLabel,
      'notEligibleLabel': ArabicMessages.notEligibleLabel,
      'legacyCompleted': ArabicMessages.legacyCompleted,
      'completedLabel': ArabicMessages.completedLabel,
      'genericError': ArabicMessages.genericError,
      'networkLost': ArabicMessages.networkLost,
      'startConfirmTitle': ArabicMessages.startConfirmTitle('{رقم الأمر}'),
    };
    for (final entry in contractStrings.entries) {
      test(entry.key, () {
        expect(
          contract.contains(entry.value),
          isTrue,
          reason: '«${entry.value}» is not in the contract',
        );
      });
    }
  });

  test('every `error.code` row of the §10 table maps to its exact text', () {
    final section = contract.substring(
      contract.indexOf('## 10. Arabic UI Text'),
      contract.indexOf('## 11. Edge Cases'),
    );
    final row = RegExp(r'^\| `([A-Z_]+)` \| (.+?) \|$', multiLine: true);
    final rows = row.allMatches(section).toList();
    expect(rows, hasLength(15), reason: 'contract §10 lists 15 error codes');
    for (final match in rows) {
      final code = match.group(1)!;
      final arabic = match.group(2)!.trim();
      expect(ArabicMessages.forCode(code), arabic, reason: code);
    }
  });

  test('every contract error code has a constant and a mapping', () {
    final codes =
        RegExp(
            r'`((?:GRINDING|OPERATOR)_[A-Z_]+)`',
          ).allMatches(contract).map((m) => m.group(1)!).toSet()
          // The worker ROLE name, not an error code.
          ..remove('GRINDING_WORKER');
    expect(codes, hasLength(greaterThanOrEqualTo(15)));
    for (final code in codes) {
      expect(
        ArabicMessages.forCode(code),
        isNot(ArabicMessages.genericError),
        reason: '$code has no Arabic mapping',
      );
    }
  });

  group('forFailure', () {
    test('unknown code → generic Arabic, never the English message', () {
      const failure = AppFailure.api(
        code: 'GRINDING_SOMETHING_NEW',
        backendMessage: 'Order 1042 exploded in module X',
        status: 409,
      );
      final text = ArabicMessages.forFailure(failure);
      expect(text, ArabicMessages.genericError);
      expect(text, isNot(contains('1042')));
    });

    test('known code ignores the backend message', () {
      const failure = AppFailure.api(
        code: ErrorCodes.orderNotReady,
        backendMessage: 'Order is not READY_FOR_GRINDING',
        status: 409,
      );
      expect(ArabicMessages.forFailure(failure), ArabicMessages.orderNotReady);
    });

    test('transport failures → «انقطع الاتصال — أعد المحاولة»', () {
      expect(
        ArabicMessages.forFailure(const AppFailure.network()),
        ArabicMessages.networkLost,
      );
      expect(
        ArabicMessages.forFailure(const AppFailure.timeout()),
        ArabicMessages.networkLost,
      );
    });

    test('server / unknown / cancelled → generic', () {
      expect(
        ArabicMessages.forFailure(const AppFailure.server(status: 503)),
        ArabicMessages.genericError,
      );
      expect(
        ArabicMessages.forFailure(const AppFailure.unknown()),
        ArabicMessages.genericError,
      );
      expect(
        ArabicMessages.forFailure(const AppFailure.cancelled()),
        ArabicMessages.genericError,
      );
    });

    test('device / config / session failures have their own copy', () {
      expect(
        ArabicMessages.forFailure(const AppFailure.deviceNotAuthorized()),
        ArabicMessages.deviceNotAuthorized,
      );
      expect(
        ArabicMessages.forFailure(const AppFailure.appNotConfigured()),
        ArabicMessages.appNotConfigured,
      );
      expect(
        ArabicMessages.forFailure(const AppFailure.sessionExpired()),
        ArabicMessages.sessionRequired,
      );
    });
  });

  group('ErrorCodes', () {
    test('session-terminal codes (contract §4.3)', () {
      for (final code in <String>[
        ErrorCodes.sessionRequired,
        ErrorCodes.sessionInvalid,
        ErrorCodes.sessionExpired,
        ErrorCodes.workerNotAllowed,
      ]) {
        expect(ErrorCodes.isSessionTerminal(code), isTrue, reason: code);
      }
      expect(ErrorCodes.isSessionTerminal(ErrorCodes.orderNotReady), isFalse);
      expect(ErrorCodes.isSessionTerminal(null), isFalse);
    });

    test('401/403 without a GRINDING_* code = device rejected (§4.1)', () {
      expect(ErrorCodes.isDeviceRejection(status: 401, code: null), isTrue);
      expect(ErrorCodes.isDeviceRejection(status: 403, code: ''), isTrue);
      expect(
        ErrorCodes.isDeviceRejection(status: 401, code: 'DEVICE_KEY_INVALID'),
        isTrue,
      );
      expect(
        ErrorCodes.isDeviceRejection(
          status: 401,
          code: ErrorCodes.sessionInvalid,
        ),
        isFalse,
      );
      expect(
        ErrorCodes.isDeviceRejection(
          status: 401,
          code: ErrorCodes.operatorPinInvalid,
        ),
        isFalse,
        reason: 'the one documented non-GRINDING 401 is a wrong PIN',
      );
      expect(ErrorCodes.isDeviceRejection(status: 409, code: null), isFalse);
    });
  });

  test('failure toString never carries backend text or details', () {
    const failure = AppFailure.api(
      code: 'X',
      backendMessage: 'secret-ish text',
      details: <String, dynamic>{'identifier': '001000000255'},
    );
    expect(failure.toString(), isNot(contains('secret-ish')));
    expect(failure.toString(), isNot(contains('001000000255')));
    expect(
      const AppFailure.unknown(cause: FormatException('pin=4821')).toString(),
      isNot(contains('4821')),
    );
  });
}
