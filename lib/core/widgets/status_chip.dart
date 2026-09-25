import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_theme.dart';

/// Semantic tone of a status pill — Operator App status-badge semantics:
/// waiting → warning, actionable-next → accent orange, active → info,
/// done → success, rejected → danger, anything else → neutral.
enum StatusTone { warning, accent, info, success, danger, neutral }

/// Pill-shaped status chip (caption w700 on a light tint, as the Operator
/// App's maintenance-request / grinding-hold chips). [large] is used for the
/// order card's big status chip.
class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    required this.tone,
    this.large = false,
    super.key,
  });

  final String label;
  final StatusTone tone;
  final bool large;

  static (Color fg, Color bg) colorsFor(StatusTone tone) {
    return switch (tone) {
      StatusTone.warning => (const Color(0xFF8D6E00), AppColors.warningLight),
      StatusTone.accent => (
        AppColors.accentOrangePressed,
        AppColors.accentOrangeLight,
      ),
      StatusTone.info => (AppColors.info, AppColors.infoLight),
      StatusTone.success => (AppColors.success, AppColors.successLight),
      StatusTone.danger => (AppColors.danger, AppColors.dangerLight),
      StatusTone.neutral => (AppColors.textSecondary, AppColors.disabledBg),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = colorsFor(tone);
    final base = large ? AppTextTheme.headline : AppTextTheme.caption;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? AppSpacing.lg : AppSpacing.md,
        vertical: large ? AppSpacing.sm : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: base.copyWith(color: fg, fontWeight: FontWeight.w700),
        textAlign: TextAlign.center,
      ),
    );
  }
}
