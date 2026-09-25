import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_theme.dart';

enum DangerButtonStyle { filled, outlined }

class DangerButton extends StatelessWidget {
  const DangerButton({
    required this.label,
    required this.onPressed,
    this.style = DangerButtonStyle.outlined,
    this.icon,
    this.loading = false,
    this.fullWidth = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final DangerButtonStyle style;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null && !loading;
    final isFilled = style == DangerButtonStyle.filled;

    final child = loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: isFilled ? AppColors.textOnPrimary : AppColors.danger,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppSizes.iconMd),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );

    final shape = WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    );
    const size = WidgetStatePropertyAll(Size.fromHeight(AppSizes.buttonHeight));
    const text = WidgetStatePropertyAll(AppTextTheme.button);

    final button = isFilled
        ? ElevatedButton(
            onPressed: isEnabled ? onPressed : null,
            style: ButtonStyle(
              minimumSize: size,
              shape: shape,
              elevation: const WidgetStatePropertyAll(0),
              textStyle: text,
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return AppColors.disabledBg;
                }
                return AppColors.danger;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return AppColors.disabledFg;
                }
                return AppColors.textOnPrimary;
              }),
            ),
            child: child,
          )
        : OutlinedButton(
            onPressed: isEnabled ? onPressed : null,
            style: ButtonStyle(
              minimumSize: size,
              shape: shape,
              textStyle: text,
              backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return AppColors.disabledFg;
                }
                return AppColors.danger;
              }),
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return const BorderSide(color: AppColors.disabledFg);
                }
                return const BorderSide(
                  color: AppColors.danger,
                  width: AppBorders.thick,
                );
              }),
            ),
            child: child,
          );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
