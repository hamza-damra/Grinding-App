import 'package:flutter_grinding_app/core/errors/app_failure.dart';
import 'package:flutter_grinding_app/core/errors/error_codes.dart';
import 'package:flutter_grinding_app/core/widgets/status_chip.dart';
import 'package:flutter_grinding_app/features/grinding_auth/domain/value_objects/pin_rule.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/command_failure_policy.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/entities/pending_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_command.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_identifier.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_source.dart';
import 'package:flutter_grinding_app/features/grinding_orders/domain/value_objects/grinding_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GrindingIdentifier (exactly 12 digits, before any call)', () {
    test('valid numbers, leading zeros kept', () {
      expect(GrindingIdentifier.normalize('001000000255'), '001000000255');
      expect(GrindingIdentifier.normalize('000000000000'), '000000000000');
    });

    test('trimmed', () {
      expect(GrindingIdentifier.normalize('  001000000255\n'), '001000000255');
    });

    test('Arabic-Indic digits are converted, not rejected', () {
      expect(GrindingIdentifier.normalize('٠٠١٠٠٠٠٠٠٢٥٥'), '001000000255');
      expect(GrindingIdentifier.normalize('۰۰۱۰۰۰۰۰۰۲۵۵'), '001000000255');
    });

    test('11 / 13 digits, letters, separators, empty → invalid', () {
      for (final raw in <String?>[
        '00100000025',
        '0010000002555',
        '00100000025a',
        '001-000-000-255',
        '001 000000255',
        '',
        null,
      ]) {
        expect(GrindingIdentifier.normalize(raw), isNull, reason: '$raw');
        expect(GrindingIdentifier.isValid(raw), isFalse, reason: '$raw');
      }
    });
  });

  group('PinRule (exactly 4 digits)', () {
    test('valid', () {
      expect(PinRule.normalize('4821'), '4821');
      expect(PinRule.normalize(' 4821 '), '4821');
      expect(PinRule.normalize('٤٨٢١'), '4821');
      expect(PinRule.normalize('0000'), '0000');
    });

    test('invalid', () {
      for (final raw in <String?>['482', '48211', '48a1', '', null]) {
        expect(PinRule.normalize(raw), isNull, reason: '$raw');
      }
    });
  });

  group('GrindingStatus parsing', () {
    test('all contract values', () {
      expect(
        GrindingStatus.fromWire('PENDING_APPROVAL'),
        GrindingStatus.pendingApproval,
      );
      expect(
        GrindingStatus.fromWire('READY_FOR_GRINDING'),
        GrindingStatus.readyForGrinding,
      );
      expect(GrindingStatus.fromWire('REJECTED'), GrindingStatus.rejected);
      expect(GrindingStatus.fromWire('IN_GRINDING'), GrindingStatus.inGrinding);
      expect(GrindingStatus.fromWire('COMPLETED'), GrindingStatus.completed);
      expect(GrindingStatus.fromWire('CANCELLED'), GrindingStatus.cancelled);
      expect(
        GrindingStatus.fromWire('NOT_ELIGIBLE'),
        GrindingStatus.notEligible,
      );
    });

    test('unknown / malformed values are lenient', () {
      expect(GrindingStatus.fromWire('ON_HOLD'), GrindingStatus.unknown);
      expect(GrindingStatus.fromWire(''), GrindingStatus.unknown);
      expect(GrindingStatus.fromWire(null), GrindingStatus.unknown);
      expect(GrindingStatus.fromWire(7), GrindingStatus.unknown);
      expect(
        GrindingStatus.fromWire('ready_for_grinding'),
        GrindingStatus.unknown,
      );
    });

    test('chip tones: green (success) only for COMPLETED', () {
      expect(GrindingStatus.completed.tone, StatusTone.success);
      for (final status in GrindingStatus.values) {
        if (status == GrindingStatus.completed) continue;
        expect(status.tone, isNot(StatusTone.success), reason: status.name);
      }
      expect(GrindingStatus.pendingApproval.tone, StatusTone.warning);
      expect(GrindingStatus.readyForGrinding.tone, StatusTone.accent);
      expect(GrindingStatus.inGrinding.tone, StatusTone.info);
      expect(GrindingStatus.rejected.tone, StatusTone.danger);
    });

    test('queue filters are exactly the two accepted values', () {
      expect(GrindingQueueStatus.values.map((s) => s.wire), <String>[
        'READY_FOR_GRINDING',
        'IN_GRINDING',
      ]);
    });
  });

  test('source type / origin parse leniently and never echo unknowns', () {
    expect(GrindingSourceType.fromWire('ROLL'), GrindingSourceType.roll);
    expect(GrindingSourceType.fromWire('PALLET'), GrindingSourceType.pallet);
    expect(GrindingSourceType.fromWire('BOX'), GrindingSourceType.unknown);
    expect(GrindingSourceType.unknown.label, isNull);
    expect(
      GrindingSourceOrigin.fromWire('PALLETIZING_PALLET'),
      GrindingSourceOrigin.palletizingPallet,
    );
    expect(GrindingSourceOrigin.fromWire('X'), GrindingSourceOrigin.unknown);
  });

  group('classifyCommandFailure (contract §4.4 clearing rules)', () {
    test('definitive 4xx business errors clear the record', () {
      for (final code in <String>[
        ErrorCodes.orderNotReady,
        ErrorCodes.orderNotInProgress,
        ErrorCodes.orderAlreadyCompleted,
        ErrorCodes.approvalRequired,
        ErrorCodes.sourceStateChanged,
        ErrorCodes.idempotencyKeyReused,
        ErrorCodes.validationError,
        'GRINDING_FUTURE_CODE',
      ]) {
        expect(
          classifyCommandFailure(AppFailure.api(code: code, status: 409)),
          CommandFailureClass.definitive,
          reason: code,
        );
      }
      expect(
        classifyCommandFailure(
          const AppFailure.api(code: ErrorCodes.orderNotFound, status: 404),
        ),
        CommandFailureClass.definitive,
      );
    });

    test('session codes keep the record', () {
      for (final code in ErrorCodes.sessionTerminalCodes) {
        expect(
          classifyCommandFailure(AppFailure.api(code: code, status: 401)),
          CommandFailureClass.sessionEnded,
          reason: code,
        );
      }
      expect(
        classifyCommandFailure(const AppFailure.sessionExpired()),
        CommandFailureClass.sessionEnded,
      );
    });

    test('transport / 408 / 429 / 5xx are retried with the same id', () {
      for (final failure in <AppFailure>[
        const AppFailure.network(),
        const AppFailure.timeout(),
        const AppFailure.server(status: null),
        const AppFailure.server(status: 500),
        const AppFailure.server(status: 503),
        const AppFailure.server(status: 408),
        const AppFailure.server(status: 429),
        const AppFailure.api(code: 'RATE_LIMITED', status: 429),
        const AppFailure.api(code: 'INTERNAL', status: 500),
      ]) {
        expect(
          classifyCommandFailure(failure),
          CommandFailureClass.retryable,
          reason: '$failure',
        );
      }
    });

    test('ambiguous answers keep the record without auto-resend', () {
      for (final failure in <AppFailure>[
        const AppFailure.deviceNotAuthorized(status: 401),
        const AppFailure.server(status: 200), // captive portal
        const AppFailure.server(status: 404), // backend older than V198
        const AppFailure.unknown(),
        const AppFailure.appNotConfigured(),
        const AppFailure.api(code: 'X'), // envelope without a status
      ]) {
        expect(
          classifyCommandFailure(failure),
          CommandFailureClass.keep,
          reason: '$failure',
        );
      }
    });

    test('local cancellation is silent', () {
      expect(
        classifyCommandFailure(const AppFailure.cancelled()),
        CommandFailureClass.cancelled,
      );
    });
  });

  group('PendingCommand persistence format', () {
    const record = PendingCommand(
      orderId: 1042,
      orderNumber: 'GR-001042',
      identifier: '001000000255',
      sourceType: GrindingSourceType.pallet,
      command: GrindingCommand.complete,
      clientRequestId: 'c1f0f1b8-9a57-4a0e-9a0e-5d2f7d7d9b10',
      workerOperatorId: 57,
      workerName: 'محمد أحمد',
      createdAt: '2026-09-22T09:41:07.312Z',
    );

    test('key is per order + command', () {
      expect(record.key, 'pending_1042_complete');
      expect(
        PendingCommand.keyFor(1042, GrindingCommand.start),
        'pending_1042_start',
      );
    });

    test('JSON round trip', () {
      final restored = PendingCommand.tryFromJson(record.toJson())!;
      expect(restored.clientRequestId, record.clientRequestId);
      expect(restored.command, GrindingCommand.complete);
      expect(restored.sourceType, GrindingSourceType.pallet);
      expect(restored.key, record.key);
    });

    test('unreadable shapes → null (left untouched on disk)', () {
      expect(PendingCommand.tryFromJson(null), isNull);
      expect(PendingCommand.tryFromJson('x'), isNull);
      expect(
        PendingCommand.tryFromJson(<String, dynamic>{
          ...record.toJson(),
          'clientRequestId': '',
        }),
        isNull,
      );
      expect(
        PendingCommand.tryFromJson(<String, dynamic>{
          ...record.toJson(),
          'command': 'PAUSE',
        }),
        isNull,
      );
    });
  });
}
