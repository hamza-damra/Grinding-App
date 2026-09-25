import 'package:flutter/material.dart';

import '../../../../core/theme/dimensions.dart';
import '../../../../core/widgets/shimmer/shimmer.dart';

/// Shimmer placeholder matching [OrderRowCard].
class OrderRowSkeleton extends StatelessWidget {
  const OrderRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine.headline(widthFraction: 0.5),
                const SizedBox(height: AppSpacing.sm),
                SkeletonLine.body(widthFraction: 0.8),
                const SizedBox(height: AppSpacing.sm),
                SkeletonLine.body(widthFraction: 0.6),
              ],
            ),
          ),
          const SkeletonChip(width: 72, height: 26),
        ],
      ),
    );
  }
}

/// Shimmer list for a loading queue.
class QueueSkeletonList extends StatelessWidget {
  const QueueSkeletonList({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, _) => const OrderRowSkeleton(),
      ),
    );
  }
}

/// Shimmer placeholder matching [OrderDetailsCard].
class OrderCardSkeleton extends StatelessWidget {
  const OrderCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: SkeletonCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: SkeletonLine.title()),
                const SkeletonChip(width: 110, height: 36),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            for (var i = 0; i < 4; i++) ...[
              SkeletonLine.body(widthFraction: 0.9),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}
