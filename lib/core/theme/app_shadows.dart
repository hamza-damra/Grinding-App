import 'package:flutter/material.dart';

/// Shared shadow recipes that match the sibling Roll Production app's
/// "double shadow" card style. Using these helpers keeps the visual
/// language consistent across the factory-apps family.
class AppShadows {
  AppShadows._();

  /// Main card elevation: a soft accent-tinted glow + a subtle black
  /// bottom shadow to anchor the card to the surface.
  static List<BoxShadow> card(Color accent) => [
    BoxShadow(
      color: accent.withValues(alpha: 0.10),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  /// Stronger accent shadow for gradient headers that sit over a light bg.
  static List<BoxShadow> header(Color accent) => [
    BoxShadow(
      color: accent.withValues(alpha: 0.35),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}
