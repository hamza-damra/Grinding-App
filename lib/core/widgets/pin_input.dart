import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../formatting/digits.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import '../theme/text_theme.dart';

class PinInput extends StatefulWidget {
  const PinInput({
    required this.controller,
    required this.onSubmitted,
    this.length = 4,
    this.enabled = true,
    this.hasError = false,
    this.autofocus = true,
    this.semanticLabel,
    super.key,
  });

  final TextEditingController controller;
  final void Function(String) onSubmitted;
  final int length;
  final bool enabled;
  final bool hasError;
  final bool autofocus;

  /// Accessible name announced for the input itself. The field has no visible
  /// `labelText` (the visible label is a sibling widget), so without this a
  /// screen reader announces an unlabeled field. When set, it names the field
  /// node without swallowing the visibility-toggle button.
  final String? semanticLabel;

  @override
  State<PinInput> createState() => _PinInputState();
}

class _PinInputState extends State<PinInput> {
  bool _obscure = true;
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.hasError ? AppColors.danger : AppColors.border;
    final focusedColor = widget.hasError
        ? AppColors.danger
        : AppColors.primaryGreen;

    final field = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      obscureText: _obscure,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: widget.length,
      style: AppTextTheme.title.copyWith(
        fontSize: 28,
        letterSpacing: 12,
        color: AppColors.textPrimary,
      ),
      inputFormatters: [
        // Converts Arabic-Indic digits (Arabic-locale keyboards) instead of
        // silently dropping them, then keeps digits only.
        const AsciiDigitsInputFormatter(),
        LengthLimitingTextInputFormatter(widget.length),
      ],
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        counterText: '',
        hintText: '••••',
        hintStyle: AppTextTheme.title.copyWith(
          fontSize: 28,
          letterSpacing: 12,
          color: AppColors.disabledFg,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: focusedColor, width: AppBorders.thick),
        ),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'إظهار' : 'إخفاء',
          icon: Icon(
            _obscure ? Icons.visibility_off : Icons.visibility,
            color: AppColors.textSecondary,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );

    final label = widget.semanticLabel;
    if (label == null) return field;
    // Contribute the accessible name to the field's own node. Only a `label`
    // (no control flags, no MergeSemantics) so the suffix visibility-toggle
    // button keeps its own independent semantics node.
    return Semantics(label: label, child: field);
  }
}
