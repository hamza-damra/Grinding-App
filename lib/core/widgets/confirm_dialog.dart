import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_theme.dart';
import 'danger_button.dart';
import 'primary_button.dart';
import 'secondary_button.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? body,
  required String confirmLabel,
  String cancelLabel = 'إلغاء',
  String? subtitle,
  String? warning,
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ConfirmDialog(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      subtitle: subtitle,
      warning: warning,
      destructive: destructive,
      icon: icon,
    ),
  );
  return result ?? false;
}

class ConfirmDialog extends StatefulWidget {
  const ConfirmDialog({
    required this.title,
    this.body,
    required this.confirmLabel,
    this.cancelLabel = 'إلغاء',
    this.subtitle,
    this.warning,
    this.destructive = false,
    this.icon,
    super.key,
  });

  final String title;
  final String? body;
  final String confirmLabel;
  final String cancelLabel;
  final String? subtitle;
  final String? warning;
  final bool destructive;
  final IconData? icon;

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  bool _submitting = false;

  void _handleConfirm() {
    if (_submitting) return;
    setState(() => _submitting = true);
    Navigator.of(context).pop(true);
  }

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
              Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      size: AppSizes.iconLg,
                      color: widget.destructive
                          ? AppColors.danger
                          : AppColors.primaryGreen,
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: Text(widget.title, style: AppTextTheme.title),
                  ),
                ],
              ),
              if (widget.body != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(widget.body!, style: AppTextTheme.body),
              ],
              if (widget.subtitle != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  widget.subtitle!,
                  style: AppTextTheme.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (widget.warning != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.warning),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: AppSizes.iconMd,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          widget.warning!,
                          style: AppTextTheme.body.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              if (widget.destructive)
                DangerButton(
                  label: widget.confirmLabel,
                  onPressed: _handleConfirm,
                  loading: _submitting,
                  style: DangerButtonStyle.filled,
                )
              else
                PrimaryButton(
                  label: widget.confirmLabel,
                  onPressed: _handleConfirm,
                  loading: _submitting,
                  variant: PrimaryButtonVariant.orange,
                ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: widget.cancelLabel,
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
