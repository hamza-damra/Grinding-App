import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/arabic_messages.dart';
import '../../../../core/lifecycle/lifecycle_resume_notifier.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_theme.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/secondary_button.dart';
import '../state/biometric_login_controller.dart';

/// Opens the fingerprint dialog for [controller] and completes when it
/// closes. The dialog takes ownership: it starts the controller and disposes
/// it (dropping the PIN and the attempt token) when it goes away.
Future<void> showBiometricLoginDialog(
  BuildContext context, {
  required BiometricLoginController controller,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BiometricLoginDialog(controller: controller),
  );
}

/// Modal fingerprint dialog (biometric handoff §5). Never dismissible by a
/// barrier tap or the back button, and never offers a way around the check:
/// the only exits are «إلغاء», «حسنًا» (contact admin) and the automatic
/// close once the re-submitted login has been answered.
class BiometricLoginDialog extends ConsumerStatefulWidget {
  const BiometricLoginDialog({required this.controller, super.key});

  final BiometricLoginController controller;

  @override
  ConsumerState<BiometricLoginDialog> createState() =>
      _BiometricLoginDialogState();
}

class _BiometricLoginDialogState extends ConsumerState<BiometricLoginDialog> {
  bool _closing = false;

  BiometricLoginController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // The first state is set synchronously (no setState during initState);
    // every later change comes from async polling.
    _controller.start();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    if (_controller.state.isClosed) {
      _close();
    } else {
      setState(() {});
    }
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  void _cancel() {
    _controller.cancel();
    _close();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(lifecycleResumeProvider, (previous, next) {
      if (previous != null && next != previous) _controller.onAppResumed();
    });
    final state = _controller.state;
    return PopScope(
      canPop: false,
      child: Dialog(
        key: const ValueKey('biometric-dialog'),
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  ArabicMessages.biometricTitle,
                  textAlign: TextAlign.center,
                  style: AppTextTheme.dialogTitle,
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(child: _buildVisual(state.phase)),
                const SizedBox(height: AppSpacing.lg),
                Semantics(liveRegion: true, child: _buildTexts(state)),
                ..._buildActions(state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVisual(BiometricGatePhase phase) {
    final (IconData icon, Color color) = switch (phase) {
      BiometricGatePhase.waiting ||
      BiometricGatePhase.succeeded ||
      BiometricGatePhase.failed ||
      BiometricGatePhase.verifying => (
        Icons.fingerprint,
        AppColors.primaryGreen,
      ),
      BiometricGatePhase.deviceOffline => (
        Icons.sensors_off_outlined,
        AppColors.warning,
      ),
      BiometricGatePhase.network => (Icons.wifi_off_rounded, AppColors.warning),
      BiometricGatePhase.retry => (Icons.timer_off_outlined, AppColors.warning),
      BiometricGatePhase.contactAdmin => (
        Icons.admin_panel_settings_outlined,
        AppColors.danger,
      ),
    };
    if (phase == BiometricGatePhase.verifying) {
      return const SizedBox(
        width: 72,
        height: 72,
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.sm),
          child: CircularProgressIndicator(
            strokeWidth: 4,
            color: AppColors.primaryGreen,
          ),
        ),
      );
    }
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 60, color: color),
    );
  }

  Widget _buildTexts(BiometricGateState state) {
    final message = state.message;
    final (String headline, String? body, String? hint) = switch (state.phase) {
      BiometricGatePhase.waiting => (
        ArabicMessages.biometricWaiting,
        message,
        ArabicMessages.biometricWaitingHint,
      ),
      BiometricGatePhase.deviceOffline => (
        message ?? ArabicMessages.biometricDeviceOffline,
        null,
        null,
      ),
      BiometricGatePhase.network => (
        ArabicMessages.biometricNetwork,
        null,
        null,
      ),
      BiometricGatePhase.verifying ||
      BiometricGatePhase.succeeded ||
      BiometricGatePhase.failed => (
        ArabicMessages.biometricVerifying,
        null,
        null,
      ),
      BiometricGatePhase.retry => (
        message ?? ArabicMessages.biometricRetry,
        null,
        null,
      ),
      BiometricGatePhase.contactAdmin => (
        message ?? ArabicMessages.biometricVerificationRequired,
        null,
        null,
      ),
    };
    return Column(
      key: ValueKey('biometric-phase-${state.phase.name}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          headline,
          textAlign: TextAlign.center,
          style: AppTextTheme.dialogSectionTitle,
        ),
        if (body != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(body, textAlign: TextAlign.center, style: AppTextTheme.body),
        ],
        if (hint != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: AppTextTheme.captionReadable,
          ),
        ],
      ],
    );
  }

  List<Widget> _buildActions(BiometricGateState state) {
    switch (state.phase) {
      case BiometricGatePhase.retry:
        return [
          const SizedBox(height: AppSpacing.xxl),
          PrimaryButton(
            key: const ValueKey('biometric-retry'),
            label: ArabicMessages.retry,
            icon: Icons.refresh_rounded,
            onPressed: _controller.retry,
          ),
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            key: const ValueKey('biometric-cancel'),
            label: ArabicMessages.cancel,
            onPressed: _cancel,
          ),
        ];
      case BiometricGatePhase.waiting ||
          BiometricGatePhase.deviceOffline ||
          BiometricGatePhase.network:
        return [
          const SizedBox(height: AppSpacing.xxl),
          SecondaryButton(
            key: const ValueKey('biometric-cancel'),
            label: ArabicMessages.cancel,
            onPressed: _cancel,
          ),
        ];
      case BiometricGatePhase.contactAdmin:
        return [
          const SizedBox(height: AppSpacing.xxl),
          PrimaryButton(
            key: const ValueKey('biometric-ok'),
            label: ArabicMessages.biometricOk,
            onPressed: _close,
          ),
        ];
      case BiometricGatePhase.verifying ||
          BiometricGatePhase.succeeded ||
          BiometricGatePhase.failed:
        return const [];
    }
  }
}
