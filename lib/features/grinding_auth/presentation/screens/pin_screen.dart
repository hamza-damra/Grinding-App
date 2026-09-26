import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/arabic_messages.dart';
import '../../../../core/errors/biometric_denial.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_theme.dart';
import '../../../../core/widgets/connectivity_banner.dart';
import '../../../../core/widgets/pin_input.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/grinding_auth_repository_impl.dart';
import '../../domain/value_objects/pin_rule.dart';
import '../state/biometric_login_controller.dart';
import '../state/grinding_auth_controller.dart';
import '../state/grinding_auth_state.dart';
import '../widgets/biometric_login_dialog.dart';

/// PIN login — Operator App `PinScreen` layout (gradient green header with an
/// elliptical bottom, round `sign.png` logo, white card with the PIN field,
/// inline Arabic error, green «دخول» button).
class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({super.key});

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  final _controller = TextEditingController();

  /// The fingerprint dialog is open: one attempt at a time.
  bool _biometricGateOpen = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    // Clear before disposal so the buffer doesn't linger in memory.
    _controller.removeListener(_onChanged);
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _submit() async {
    final pin = PinRule.normalize(_controller.text);
    if (pin == null) return;
    if (_biometricGateOpen) return;
    if (ref.read(grindingAuthControllerProvider).isLoading) return;
    final auth = ref.read(grindingAuthControllerProvider.notifier);
    final failure = await auth.login(pin);
    if (!mounted) return;
    // The PIN never lingers in the field beyond a single attempt.
    _controller.clear();
    if (failure is BiometricDeniedFailure) {
      await _openBiometricGate(pin, failure.denial, auth.login);
    }
  }

  /// Biometric handoff §9: the fingerprint dialog waits for a scan and
  /// re-submits the same PIN once — the worker never re-types it. The PIN
  /// is handed to the dialog's controller in memory only and dropped with it.
  Future<void> _openBiometricGate(
    String pin,
    BiometricDenial denial,
    Future<AppFailure?> Function(String pin) resubmit,
  ) async {
    _biometricGateOpen = true;
    try {
      await showBiometricLoginDialog(
        context,
        controller: BiometricLoginController(
          pin: pin,
          denial: denial,
          repository: ref.read(grindingAuthRepositoryProvider),
          resubmit: resubmit,
          backoff: ref.read(biometricPollBackoffProvider),
        ),
      );
    } finally {
      _biometricGateOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(grindingAuthControllerProvider);
    final isSubmitting = asyncState.isLoading;
    final value = asyncState.valueOrNull;
    final lastError = value is GrindingAuthUnauthenticated
        ? value.lastError
        : null;
    final errorMessage = lastError != null
        ? ArabicMessages.forFailure(lastError)
        : null;
    final canSubmit =
        !isSubmitting && PinRule.normalize(_controller.text) != null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body: Column(
          children: [
            const ConnectivityBanner(),
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeaderWithLogo(context),
                    const SizedBox(height: AppSpacing.lg),
                    _buildTitleAndSubtitle(),
                    const SizedBox(height: AppSpacing.xxl),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: _buildLoginCard(
                        isSubmitting: isSubmitting,
                        errorMessage: errorMessage,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: PrimaryButton(
                        key: const ValueKey('pin-submit'),
                        label: ArabicMessages.loginButton,
                        onPressed: canSubmit ? _submit : null,
                        loading: isSubmitting,
                        icon: Icons.login_rounded,
                        mirrorIconForRtl: true,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderWithLogo(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final headerContentHeight = topPadding + 170;
    const logoSize = 132.0;
    const logoOverlap = logoSize / 2;

    return SizedBox(
      height: headerContentHeight + logoOverlap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: headerContentHeight,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.primaryGreen, AppColors.primaryGreenDark],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.elliptical(280, 70),
                  bottomRight: Radius.elliptical(280, 70),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  top: topPadding + AppSpacing.xl,
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                ),
                child: const Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    ArabicMessages.pinScreenTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppFonts.family,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textOnPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: headerContentHeight - logoOverlap,
            left: 0,
            right: 0,
            child: Center(child: _buildLogo(logoSize)),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: ClipOval(
        child: Image.asset(
          'assets/images/sign.png',
          fit: BoxFit.cover,
          cacheWidth: 400,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.factory_outlined,
            color: AppColors.primaryGreen,
            size: 64,
          ),
        ),
      ),
    );
  }

  Widget _buildTitleAndSubtitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          const Text(
            ArabicMessages.appTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'يرجى إدخال الرمز السري الخاص بك للمتابعة',
            textAlign: TextAlign.center,
            style: AppTextTheme.body.copyWith(
              color: AppColors.textSecondary,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard({
    required bool isSubmitting,
    required String? errorMessage,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              'الرمز السري',
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          PinInput(
            key: const ValueKey('pin-input'),
            controller: _controller,
            onSubmitted: (_) => _submit(),
            enabled: !isSubmitting,
            hasError: errorMessage != null,
            semanticLabel: 'الرمز السري',
          ),
          const SizedBox(height: AppSpacing.md),
          if (errorMessage != null)
            _buildErrorBanner(errorMessage)
          else
            _buildSecrecyHint(),
        ],
      ),
    );
  }

  Widget _buildSecrecyHint() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.shield_outlined,
          size: 16,
          color: AppColors.primaryGreen.withValues(alpha: 0.85),
        ),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            'حافظ على سرية الرمز الخاص بك',
            textAlign: TextAlign.center,
            style: AppTextTheme.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      key: const ValueKey('pin-error'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: AppColors.danger,
            size: AppSizes.iconSm,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextTheme.body.copyWith(
                color: AppColors.danger,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
