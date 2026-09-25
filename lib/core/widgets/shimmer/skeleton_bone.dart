import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/dimensions.dart';

/// The atomic building block of the skeleton loading system.
/// A simple rounded rectangle with a flat color that receives the
/// gradient animation from a parent [AppShimmer].
class SkeletonBone extends StatelessWidget {
  const SkeletonBone({
    this.width,
    this.height,
    this.borderRadius = AppRadius.sm,
    this.color = AppColors.disabledBg,
    super.key,
  });

  final double? width;
  final double? height;
  final double borderRadius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
