import 'package:flutter/material.dart';

import '../../theme/dimensions.dart';
import 'skeleton_bone.dart';

class SkeletonChip extends StatelessWidget {
  const SkeletonChip({this.width = 60, this.height = 24, super.key});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SkeletonBone(
      width: width,
      height: height,
      borderRadius: AppRadius.pill,
    );
  }
}
