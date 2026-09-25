import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_theme.dart';

/// Full-width green success banner (contract §5.5: «بدأ الجرش.» /
/// «تم الجرش فعليًا»). Shown only for a server-confirmed success.
class SuccessBanner extends StatelessWidget {
  const SuccessBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: AppColors.success,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle,
              color: AppColors.textOnPrimary,
              size: AppSizes.iconLg,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: AppTextTheme.title.copyWith(
                  color: AppColors.textOnPrimary,
                  fontSize: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
