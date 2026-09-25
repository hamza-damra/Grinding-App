import 'package:flutter/material.dart';

import '../errors/arabic_messages.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_theme.dart';
import 'primary_button.dart';

/// Shows the reusable technical-connection error dialog (Operator App
/// `AppConnectionErrorDialog`, without the WhatsApp support action).
///
/// [onRetry] must re-run the original load and **throw on failure**. The
/// dialog ignores duplicate presses, stays open on a failed retry, and closes
/// (returns `true`) only once the retry succeeds.
Future<bool?> showConnectionErrorDialog(
  BuildContext context, {
  required Future<void> Function() onRetry,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AppConnectionErrorDialog(onRetry: onRetry),
  );
}

class AppConnectionErrorDialog extends StatefulWidget {
  const AppConnectionErrorDialog({required this.onRetry, super.key});

  final Future<void> Function() onRetry;

  static const String title = 'تعذر الاتصال بالخادم';
  static const String message =
      'انتهت مهلة الاتصال بالخادم. تحقق من اتصال الإنترنت ثم أعد المحاولة.';

  @override
  State<AppConnectionErrorDialog> createState() =>
      _AppConnectionErrorDialogState();
}

class _AppConnectionErrorDialogState extends State<AppConnectionErrorDialog> {
  bool _retrying = false;

  Future<void> _handleRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _retrying = false);
    }
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
              const Center(
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.dangerLight,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.wifi_off_rounded,
                      color: AppColors.danger,
                      size: AppSizes.iconLg,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                AppConnectionErrorDialog.title,
                textAlign: TextAlign.center,
                style: AppTextTheme.title,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppConnectionErrorDialog.message,
                textAlign: TextAlign.center,
                style: AppTextTheme.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              PrimaryButton(
                label: ArabicMessages.retry,
                onPressed: _handleRetry,
                loading: _retrying,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
