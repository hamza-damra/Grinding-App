import '../../../../core/errors/arabic_messages.dart';

/// The two physical commands (contract §4.2 endpoints 6 and 7).
enum GrindingCommand {
  start('START', 'start'),
  complete('COMPLETE', 'complete');

  const GrindingCommand(this.wire, this.fileKey);

  /// Stable serialized name (persisted records).
  final String wire;

  /// Lower-case key used in persisted record names.
  final String fileKey;

  static GrindingCommand? fromWire(Object? raw) {
    for (final command in values) {
      if (command.wire == raw) return command;
    }
    return null;
  }

  String get buttonLabel => switch (this) {
    GrindingCommand.start => ArabicMessages.startButton,
    GrindingCommand.complete => ArabicMessages.completeButton,
  };

  String get successMessage => switch (this) {
    GrindingCommand.start => ArabicMessages.startSuccess,
    GrindingCommand.complete => ArabicMessages.completeSuccess,
  };
}
