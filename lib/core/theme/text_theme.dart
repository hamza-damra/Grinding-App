import 'package:flutter/material.dart';

import 'app_fonts.dart';
import 'colors.dart';

/// Cairo-based typography. Weights: 400 body, 500 secondary, 600 UI/buttons/cards, 700 titles.
class AppTextTheme {
  AppTextTheme._();

  static const _height = 1.4;

  static const TextStyle display = TextStyle(
    fontFamily: AppFonts.family,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: _height,
  );

  static const TextStyle title = TextStyle(
    fontFamily: AppFonts.family,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: _height,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: AppFonts.family,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: _height,
  );

  static const TextStyle body = TextStyle(
    fontFamily: AppFonts.family,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: _height,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: AppFonts.family,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: _height,
  );

  static const TextStyle label = TextStyle(
    fontFamily: AppFonts.family,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    height: _height,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: AppFonts.family,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: _height,
  );

  /// Primary / danger / secondary action labels on buttons.
  static const TextStyle button = TextStyle(
    fontFamily: AppFonts.family,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  // ── Readable dialog hierarchy ──────────────────────────────────────────
  // Workers read these on the factory floor at arm's length; prefer these
  // semantic styles over ad-hoc font sizes so the hierarchy stays consistent.

  /// Top-of-dialog title.
  static const TextStyle dialogTitle = TextStyle(
    fontFamily: AppFonts.family,
    fontSize: 19,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: _height,
  );

  /// Section header inside a dialog body.
  static const TextStyle dialogSectionTitle = TextStyle(
    fontFamily: AppFonts.family,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: _height,
  );

  /// Readable caption/helper/validation text (13sp floor instead of
  /// [caption]'s 12sp).
  static const TextStyle captionReadable = TextStyle(
    fontFamily: AppFonts.family,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: _height,
  );

  static TextTheme buildTextTheme() {
    return const TextTheme(
      displayLarge: display,
      titleLarge: title,
      titleMedium: headline,
      bodyLarge: body,
      bodyMedium: body,
      labelLarge: label,
      labelMedium: label,
      bodySmall: caption,
    );
  }
}
