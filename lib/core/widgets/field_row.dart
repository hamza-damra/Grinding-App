import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_theme.dart';

class FieldRow extends StatelessWidget {
  const FieldRow({
    required this.label,
    required this.value,
    this.helperText,
    this.valueStyle,
    super.key,
  });

  final String label;
  final String value;
  final String? helperText;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Narrow widths (e.g. phone cards, dense shift-line cards) stack
          // the label above the value so long values stop wrapping into a
          // skinny column. Wider layouts retain the side-by-side form.
          final stack = constraints.maxWidth < 360;
          final labelWidget = Text(
            label,
            style: AppTextTheme.label.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          );
          final valueWidget = Text(
            value,
            style: valueStyle ?? AppTextTheme.bodyStrong,
          );

          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                labelWidget,
                const SizedBox(height: AppSpacing.xs),
                valueWidget,
                if (helperText != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    helperText!,
                    style: AppTextTheme.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: labelWidget),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(flex: 6, child: valueWidget),
                ],
              ),
              if (helperText != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(flex: 4, child: SizedBox.shrink()),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 6,
                        child: Text(
                          helperText!,
                          style: AppTextTheme.caption.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
