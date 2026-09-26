import '../../../../core/api/json_read.dart';
import '../../domain/entities/biometric_attempt.dart';

class BiometricAttemptStatusDto {
  BiometricAttemptStatusDto._();

  static BiometricAttemptStatusResponse fromJson(Object? raw) {
    final json = JsonRead.map(raw);
    if (json == null) {
      throw const FormatException('attempt status: data not a map');
    }
    final expiresAt = JsonRead.nonEmptyString(json['attemptExpiresAt']);
    return BiometricAttemptStatusResponse(
      status: BiometricAttemptStatus.fromWire(json['status']),
      attemptExpiresAt: expiresAt == null
          ? null
          : DateTime.tryParse(expiresAt)?.toUtc(),
    );
  }
}
