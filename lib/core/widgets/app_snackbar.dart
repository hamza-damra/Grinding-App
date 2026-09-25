import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_theme.dart';

/// Root `ScaffoldMessenger` key — lets app-wide listeners mounted above the
/// router `Navigator` (the session-invalidation listener) show a snackbar
/// without a per-screen `Scaffold` in scope.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>(
  debugLabel: 'rootScaffoldMessenger',
);

class AppSnackbar {
  AppSnackbar._();

  static void success(BuildContext context, String message) {
    _show(
      context,
      message: message,
      bg: AppColors.success,
      icon: Icons.check_circle_outline,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message: message,
      bg: AppColors.danger,
      icon: Icons.error_outline,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void info(BuildContext context, String message) {
    _show(
      context,
      message: message,
      bg: AppColors.info,
      icon: Icons.info_outline,
    );
  }

  /// Shows an info snackbar through the root `ScaffoldMessenger`; survives
  /// the route swap of a redirect to the PIN screen.
  static void infoGlobal(String message) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    _showOnMessenger(
      messenger,
      message: message,
      bg: AppColors.info,
      icon: Icons.info_outline,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required Color bg,
    required IconData icon,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    _showOnMessenger(
      messenger,
      message: message,
      bg: bg,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void _showOnMessenger(
    ScaffoldMessengerState messenger, {
    required String message,
    required Color bg,
    required IconData icon,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final hasAction = actionLabel != null && onAction != null;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: bg,
          duration: Duration(seconds: hasAction ? 10 : 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          content: Row(
            children: [
              Icon(icon, color: AppColors.textOnPrimary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: AppTextTheme.body.copyWith(
                    color: AppColors.textOnPrimary,
                  ),
                ),
              ),
            ],
          ),
          action: hasAction
              ? SnackBarAction(
                  label: actionLabel,
                  textColor: AppColors.textOnPrimary,
                  onPressed: onAction,
                )
              : null,
        ),
      );
  }
}
