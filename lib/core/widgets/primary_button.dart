import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_theme.dart';

enum PrimaryButtonVariant { green, orange }

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.variant = PrimaryButtonVariant.green,
    this.icon,
    this.loading = false,
    this.fullWidth = true,
    this.mirrorIconForRtl = false,
    this.height = AppSizes.buttonHeight,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final PrimaryButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;

  /// When true, the icon renders on the visual LEFT of the label with the
  /// glyph horizontally mirrored (so a directional icon like
  /// `Icons.login_rounded`, whose native glyph points right and does not
  /// auto-mirror, points left toward the text). Default false preserves the
  /// existing icon-follows-reading-direction layout for every other caller.
  final bool mirrorIconForRtl;

  /// Minimum height. Taller buttons (the START / COMPLETE command button)
  /// also get a larger label.
  final double height;

  @override
  Widget build(BuildContext context) {
    final bg = variant == PrimaryButtonVariant.green
        ? AppColors.primaryGreen
        : AppColors.accentOrange;
    final pressed = variant == PrimaryButtonVariant.green
        ? AppColors.primaryGreenDark
        : AppColors.accentOrangePressed;

    final isEnabled = onPressed != null && !loading;
    final button = ElevatedButton(
      onPressed: isEnabled ? onPressed : null,
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size.fromHeight(height)),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppColors.disabledBg;
          }
          if (states.contains(WidgetState.pressed)) return pressed;
          return bg;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppColors.disabledFg;
          }
          return AppColors.textOnPrimary;
        }),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        textStyle: WidgetStatePropertyAll(
          height > AppSizes.buttonHeight
              ? AppTextTheme.button.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                )
              : AppTextTheme.button,
        ),
      ),
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.textOnPrimary,
              ),
            )
          : Row(
              // When mirroring, force LTR so the child order is fixed
              // (icon left, text right) regardless of ambient direction — the
              // glyph itself is mirrored below, not repositioned by the row.
              // `Flex.textDirection` only sets main-axis start/end; it does not
              // insert a Directionality, so the Arabic label still shapes RTL.
              textDirection: mirrorIconForRtl ? TextDirection.ltr : null,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  mirrorIconForRtl
                      ? Transform.flip(
                          flipX: true,
                          child: Icon(icon, size: AppSizes.iconMd),
                        )
                      : Icon(icon, size: AppSizes.iconMd),
                  const SizedBox(width: AppSpacing.sm),
                ],
                // Flexible + ellipsis so a long label shrinks to fit a
                // narrow button (e.g. side-by-side in a Row) instead of
                // overflowing — mirrors SecondaryButton.
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
    );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
