import '../../../../core/api/json_read.dart';
import '../../domain/entities/grinding_worker.dart';

/// `PinLoginRequest { pin }`. `toString` is redacted: a request object must
/// never print the PIN (the Operator App's generated freezed `toString`
/// did).
class PinLoginRequest {
  const PinLoginRequest(this.pin);

  final String pin;

  Map<String, dynamic> toJson() => <String, dynamic>{'pin': pin};

  @override
  String toString() => 'PinLoginRequest(pin: ***)';
}

class WorkerDto {
  WorkerDto._();

  static GrindingWorker fromJson(Object? raw) {
    final json = JsonRead.map(raw);
    final id = json == null ? null : JsonRead.integer(json['operatorId']);
    final name = json == null ? null : JsonRead.string(json['name']);
    if (id == null || name == null) {
      throw const FormatException('worker missing operatorId/name');
    }
    return GrindingWorker(operatorId: id, name: name);
  }
}

class PinLoginResponseDto {
  PinLoginResponseDto._();

  static PinLoginResult fromJson(Map<String, dynamic> json) {
    final token = JsonRead.nonEmptyString(json['sessionToken']);
    if (token == null) {
      throw const FormatException('login response missing sessionToken');
    }
    return PinLoginResult(
      sessionToken: token,
      expiresAt: JsonRead.nonEmptyString(json['expiresAt']),
      worker: WorkerDto.fromJson(json['worker']),
    );
  }
}

class SessionViewDto {
  SessionViewDto._();

  static GrindingSession fromJson(Map<String, dynamic> json) {
    return GrindingSession(
      sessionId: JsonRead.integer(json['sessionId']),
      createdAt: JsonRead.nonEmptyString(json['createdAt']),
      expiresAt: JsonRead.nonEmptyString(json['expiresAt']),
      worker: WorkerDto.fromJson(json['worker']),
    );
  }
}

class LogoutResponseDto {
  LogoutResponseDto._();

  /// `ended`; anything unreadable counts as `false` (still logged out).
  static bool endedFrom(Object? raw) {
    final json = JsonRead.map(raw);
    return json != null && JsonRead.flag(json['ended']);
  }
}
