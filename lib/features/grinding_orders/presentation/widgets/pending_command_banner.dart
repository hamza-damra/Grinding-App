import 'package:flutter/material.dart';

import '../../../../core/errors/arabic_messages.dart';
import '../../../../core/formatting/bidi.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_theme.dart';
import '../../domain/entities/pending_command.dart';
import '../../domain/value_objects/grinding_command.dart';

/// Warning banner for a START / COMPLETE whose outcome is unknown (connection
/// lost, app killed, session ended). Never sent automatically: [onOpen]
/// opens the order through a fresh `/check`, where the worker must confirm
/// again. Names the original worker when it was someone else.
class PendingCommandBanner extends StatelessWidget {
  const PendingCommandBanner({
    required this.record,
    required this.currentWorkerId,
    required this.onOpen,
    super.key,
  });

  final PendingCommand record;
  final int? currentWorkerId;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final number = Bidi.isolate(record.orderNumber);
    final body = switch (record.command) {
      GrindingCommand.start => ArabicMessages.pendingStartBody(number),
      GrindingCommand.complete => ArabicMessages.pendingCompleteBody(number),
    };
    final otherWorker =
        currentWorkerId != null && record.workerOperatorId != currentWorkerId;
    return Container(
      key: ValueKey('pending-banner-${record.key}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
                size: AppSizes.iconMd,
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  ArabicMessages.pendingCommandTitle,
                  style: AppTextTheme.bodyStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(body, style: AppTextTheme.body),
          if (otherWorker) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              ArabicMessages.pendingOtherWorker(record.workerName),
              key: ValueKey('pending-other-worker-${record.key}'),
              style: AppTextTheme.bodyStrong.copyWith(
                color: AppColors.accentOrangePressed,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: onOpen,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryGreenDark,
                minimumSize: const Size(48, 48),
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text(ArabicMessages.pendingOpenOrder),
            ),
          ),
        ],
      ),
    );
  }
}
