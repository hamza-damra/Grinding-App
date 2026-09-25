import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/errors/arabic_messages.dart';
import '../../../../core/formatting/digits.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_theme.dart';
import '../../../../core/widgets/primary_button.dart';

/// Very large «مسح رقم» button + manual 12-digit entry with «تحقق»
/// (contract §5.2). Validation happens before any network call; the error
/// text is shown inline under the field.
class ScanEntryPanel extends StatelessWidget {
  const ScanEntryPanel({
    required this.controller,
    required this.focusNode,
    required this.onScan,
    required this.onSubmit,
    this.errorText,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onScan;
  final ValueChanged<String> onSubmit;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          key: const ValueKey('scan-button'),
          label: ArabicMessages.scanButton,
          icon: Icons.qr_code_scanner,
          height: AppSizes.scanButtonHeight,
          onPressed: onScan,
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('manual-identifier'),
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: AppTextTheme.headline.copyWith(letterSpacing: 2),
                inputFormatters: [
                  const AsciiDigitsInputFormatter(),
                  // Room for a stray digit so an over-long entry is reported
                  // instead of silently truncated to 12.
                  LengthLimitingTextInputFormatter(16),
                ],
                decoration: InputDecoration(
                  labelText: ArabicMessages.manualEntryLabel,
                  errorText: errorText,
                  errorMaxLines: 2,
                ),
                onSubmitted: onSubmit,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 110,
              child: PrimaryButton(
                key: const ValueKey('manual-check'),
                label: ArabicMessages.checkButton,
                variant: PrimaryButtonVariant.orange,
                onPressed: () => onSubmit(controller.text),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
