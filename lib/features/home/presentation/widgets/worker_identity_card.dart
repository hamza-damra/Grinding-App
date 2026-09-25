import 'package:flutter/material.dart';

import '../../../../core/errors/arabic_messages.dart';
import '../../../../core/formatting/bidi.dart';
import '../../../../core/formatting/factory_time.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_theme.dart';
import '../../../../core/widgets/factory_card.dart';
import '../../../grinding_auth/domain/entities/grinding_worker.dart';

/// Logged-in worker + session end time (Asia/Hebron wall-clock).
class WorkerIdentityCard extends StatelessWidget {
  const WorkerIdentityCard({required this.worker, this.expiresAt, super.key});

  final GrindingWorker worker;
  final String? expiresAt;

  @override
  Widget build(BuildContext context) {
    final showExpiry = FactoryTime.isValid(expiresAt);
    return FactoryCard(
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primaryGreenLight,
            child: Icon(Icons.person, color: AppColors.primaryGreen),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  worker.name,
                  key: const ValueKey('worker-name'),
                  style: AppTextTheme.headline.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (showExpiry)
                  Text(
                    '${ArabicMessages.sessionEndsAt} '
                    '${Bidi.ltr(FactoryTime.formatClock(expiresAt))}',
                    style: AppTextTheme.captionReadable,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
