import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_theme.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle({required this.text, this.icon, this.trailing, super.key});

  final String text;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: AppSizes.iconMd, color: AppColors.primaryGreen),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(child: Text(text, style: AppTextTheme.headline)),
        ?trailing,
      ],
    );
  }
}
