import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/arabic_messages.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_theme.dart';

final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  final connectivity = Connectivity();
  return connectivity.onConnectivityChanged;
});

/// Red strip shown while the device has no network at all. Advisory only —
/// requests are never blocked on it (the OS report can lag reality).
class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(connectivityProvider);
    final isOffline = results.maybeWhen(
      data: (list) => list.every((r) => r == ConnectivityResult.none),
      orElse: () => false,
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: isOffline
          ? Container(
              key: const ValueKey('offline'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              color: AppColors.danger,
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_off,
                    color: AppColors.textOnPrimary,
                    size: AppSizes.iconSm,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      ArabicMessages.networkLost,
                      style: AppTextTheme.caption.copyWith(
                        color: AppColors.textOnPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
