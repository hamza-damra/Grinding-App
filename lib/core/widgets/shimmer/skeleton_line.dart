import 'package:flutter/material.dart';

import 'skeleton_bone.dart';

/// A wrapper around [SkeletonBone] sized to match standard text styles.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    required this.height,
    this.widthFraction = 1.0,
    super.key,
  });

  /// Approximate matching height for `AppTextTheme.title` (22 * 1.4 ~ 30, but
  /// using raw font size looks cleaner for bones).
  factory SkeletonLine.title({double widthFraction = 0.6}) {
    return SkeletonLine(height: 22, widthFraction: widthFraction);
  }

  /// Approximate matching height for `AppTextTheme.headline` (18).
  factory SkeletonLine.headline({double widthFraction = 0.7}) {
    return SkeletonLine(height: 18, widthFraction: widthFraction);
  }

  /// Approximate matching height for `AppTextTheme.body` (16).
  factory SkeletonLine.body({double widthFraction = 1.0}) {
    return SkeletonLine(height: 16, widthFraction: widthFraction);
  }

  /// Approximate matching height for `AppTextTheme.label` (14).
  factory SkeletonLine.label({double widthFraction = 0.5}) {
    return SkeletonLine(height: 14, widthFraction: widthFraction);
  }

  /// Approximate matching height for `AppTextTheme.caption` (12).
  factory SkeletonLine.caption({double widthFraction = 0.4}) {
    return SkeletonLine(height: 12, widthFraction: widthFraction);
  }

  final double height;
  final double widthFraction;

  @override
  Widget build(BuildContext context) {
    // We deliberately avoid [FractionallySizedBox] / [LayoutBuilder]
    // here: both fail when the surrounding layout enters an intrinsic
    // measurement pass (e.g. inside [IntrinsicHeight], inside [Row]
    // with `Expanded`, or while shimmer's [ShaderMask] paints). A fixed
    // proxy width keyed off [height] (the text-style proxy) keeps the
    // bone laying out in every container without breaking intrinsics.
    const proxyBaseWidthByHeight = <int, double>{
      22: 240, // title
      18: 220, // headline
      16: 200, // body
      14: 100, // label
      12: 80, // caption
    };
    final base = proxyBaseWidthByHeight[height.round()] ?? 200.0;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        width: base * widthFraction,
        child: SkeletonBone(height: height),
      ),
    );
  }
}
