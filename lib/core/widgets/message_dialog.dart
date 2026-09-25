import 'package:flutter/material.dart';

import '../errors/arabic_messages.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_theme.dart';
import 'primary_button.dart';

/// Single-button Arabic message dialog (contract §9: "show the Arabic message
/// in a dialog, then re-`/check`"). Same shell as [ConfirmDialog].
Future<void> showMessageDialog(
  BuildContext context, {
  required String message,
  String? title,
  IconData icon = Icons.info_outline,
  Color iconColor = AppColors.warning,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MessageDialog(
      message: message,
      title: title,
      icon: icon,
      iconColor: iconColor,
    ),
  );
}

class MessageDialog extends StatelessWidget {
  const MessageDialog({
    required this.message,
    this.title,
    this.icon = Icons.info_outline,
    this.iconColor = AppColors.warning,
    super.key,
  });

  final String message;
  final String? title;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 48, color: iconColor),
              const SizedBox(height: AppSpacing.md),
              if (title != null) ...[
                Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: AppTextTheme.dialogTitle,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextTheme.bodyStrong,
              ),
              const SizedBox(height: AppSpacing.xxl),
              PrimaryButton(
                label: ArabicMessages.ok,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
