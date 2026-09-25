import '../value_objects/grinding_command.dart';
import '../value_objects/grinding_source.dart';

/// A START / COMPLETE whose `clientRequestId` has been durably persisted and
/// whose outcome is not yet known (contract §4.4). Exactly one record per
/// `orderId + command`; never more than one command pending per order.
///
/// Cleared only after a 2xx (including `replayed:true`) or a definitive 4xx
/// business error. Never sent automatically after a restart, a resume or a
/// re-login: the worker must confirm it again.
class PendingCommand {
  const PendingCommand({
    required this.orderId,
    required this.orderNumber,
    required this.identifier,
    required this.command,
    required this.clientRequestId,
    required this.workerOperatorId,
    required this.workerName,
    required this.createdAt,
    this.sourceType,
  });

  static const int schemaVersion = 1;

  final int orderId;
  final String orderNumber;

  /// The 12-digit number the order was opened with (re-check on banner tap).
  final String identifier;

  /// The worker's own ROLL/PALLET answer, if the number was ambiguous.
  final GrindingSourceType? sourceType;
  final GrindingCommand command;

  /// UUID v4 minted when the worker confirmed the action.
  final String clientRequestId;

  /// The worker who confirmed the action — used to warn a different worker.
  final int workerOperatorId;
  final String workerName;

  /// ISO-8601 UTC instant of the tap.
  final String createdAt;

  String get key => keyFor(orderId, command);

  static String keyFor(int orderId, GrindingCommand command) =>
      'pending_${orderId}_${command.fileKey}';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'v': schemaVersion,
    'orderId': orderId,
    'orderNumber': orderNumber,
    'identifier': identifier,
    if (sourceType != null && sourceType != GrindingSourceType.unknown)
      'sourceType': sourceType!.wire,
    'command': command.wire,
    'clientRequestId': clientRequestId,
    'workerOperatorId': workerOperatorId,
    'workerName': workerName,
    'createdAt': createdAt,
  };

  /// Returns `null` for a record this version cannot read (it is left on
  /// disk untouched).
  static PendingCommand? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final orderId = json['orderId'];
    final command = GrindingCommand.fromWire(json['command']);
    final clientRequestId = json['clientRequestId'];
    final orderNumber = json['orderNumber'];
    final identifier = json['identifier'];
    final workerId = json['workerOperatorId'];
    final workerName = json['workerName'];
    final createdAt = json['createdAt'];
    if (orderId is! int ||
        command == null ||
        clientRequestId is! String ||
        clientRequestId.isEmpty ||
        orderNumber is! String ||
        identifier is! String ||
        workerId is! int ||
        workerName is! String ||
        createdAt is! String) {
      return null;
    }
    final rawSource = json['sourceType'];
    return PendingCommand(
      orderId: orderId,
      orderNumber: orderNumber,
      identifier: identifier,
      sourceType: rawSource == null
          ? null
          : GrindingSourceType.fromWire(rawSource),
      command: command,
      clientRequestId: clientRequestId,
      workerOperatorId: workerId,
      workerName: workerName,
      createdAt: createdAt,
    );
  }
}
