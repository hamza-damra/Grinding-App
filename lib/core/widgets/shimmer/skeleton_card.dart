import 'package:flutter/material.dart';

import '../factory_card.dart';

/// Wraps children in a FactoryCard to ensure the skeleton matches the shape
/// and padding of the final loaded widget.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return FactoryCard(
      padding: padding ?? const EdgeInsets.all(16), // AppSizes.cardPadding
      child: child,
    );
  }
}
