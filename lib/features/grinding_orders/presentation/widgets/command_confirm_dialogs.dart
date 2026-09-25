import 'package:flutter/material.dart';

import '../../../../core/errors/arabic_messages.dart';
import '../../../../core/formatting/bidi.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../domain/value_objects/grinding_command.dart';

/// Contract §5.4 confirmations. Cancelling sends nothing and mints no id.
///
/// * START: «بدء جرش {رقم الأمر}؟» — «بدء» / «إلغاء»;
/// * COMPLETE: «هل تم جرش هذه المادة فعليًا؟» — «نعم، تم الجرش» / «إلغاء».
Future<bool> showCommandConfirmDialog(
  BuildContext context, {
  required GrindingCommand command,
  required String orderNumber,
  String? warning,
}) {
  final isolatedNumber = Bidi.isolate(orderNumber);
  return switch (command) {
    GrindingCommand.start => showConfirmDialog(
      context,
      title: ArabicMessages.startConfirmTitle(isolatedNumber),
      confirmLabel: ArabicMessages.startConfirmAction,
      cancelLabel: ArabicMessages.cancel,
      warning: warning,
      icon: Icons.play_circle_outline,
    ),
    GrindingCommand.complete => showConfirmDialog(
      context,
      title: ArabicMessages.completeConfirmTitle,
      subtitle: isolatedNumber,
      confirmLabel: ArabicMessages.completeConfirmAction,
      cancelLabel: ArabicMessages.cancel,
      warning: warning,
      icon: Icons.task_alt,
    ),
  };
}
