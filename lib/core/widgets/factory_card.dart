import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimensions.dart';

class FactoryCard extends StatelessWidget {
  const FactoryCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSizes.cardPadding),
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // The transparent `Material` wrapping `child` exists to satisfy
    // Flutter's `ListTile`/`SwitchListTile`/etc ancestor invariant:
    // those widgets paint ink + selected-row backgrounds on the
    // nearest `Material`, and inserting them directly under a coloured
    // `DecoratedBox` (which `FactoryCard` is) trips the
    // "ListTile background color or ink splashes may be invisible"
    // assertion. The transparent Material satisfies the invariant
    // without contributing visual chrome — the card's surface colour
    // still comes from the outer `Container`.
    final card = Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      padding: padding,
      child: Material(type: MaterialType.transparency, child: child),
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: card,
      ),
    );
  }
}
