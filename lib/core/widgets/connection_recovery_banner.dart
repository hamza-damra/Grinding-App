import 'package:flutter/material.dart';

import '../errors/arabic_messages.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_theme.dart';

/// Slim, non-blocking banner shown over an existing screen while the app
/// silently re-establishes the connection after a resume / cold-start
/// transient timeout. It deliberately does NOT block interaction — the
/// operator keeps seeing (and using) the cached screen behind it.
///
/// This is the calm first step of the recovery policy: only if the silent
/// auto-retry still fails AND there is no cached data to show does
/// `AsyncStatusView` escalate to the blocking [AppConnectionErrorDialog].
class ConnectionRecoveryBanner extends StatelessWidget {
  const ConnectionRecoveryBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.infoLight,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: AppSizes.iconSm,
                  height: AppSizes.iconSm,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Flexible(
                  child: Text(
                    ArabicMessages.reconnecting,
                    textAlign: TextAlign.center,
                    style: AppTextTheme.caption.copyWith(
                      color: AppColors.info,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
