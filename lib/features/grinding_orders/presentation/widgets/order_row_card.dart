import 'package:flutter/material.dart';

import '../../../../core/errors/arabic_messages.dart';
import '../../../../core/formatting/bidi.dart';
import '../../../../core/formatting/decimal_weight.dart';
import '../../../../core/formatting/factory_time.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_theme.dart';
import '../../../../core/widgets/factory_card.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/entities/grinding_order.dart';
import '../../domain/value_objects/grinding_source.dart';
import '../../domain/value_objects/grinding_status.dart';

/// Large, display-only queue row. Tapping it runs the same `/check` flow as
/// a scan (the row's data is never used to act).
class OrderRowCard extends StatelessWidget {
  const OrderRowCard({required this.order, required this.onTap, super.key});

  final GrindingOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weight = order.sourceType == GrindingSourceType.pallet
        ? (order.sourceQuantity == null
              ? null
              : Bidi.ltr(order.sourceQuantity!))
        : DecimalWeight.displayKg(order.expectedWeightKg);
    final sourceLabel = order.sourceType.label;
    return FactoryCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Bidi.isolate(order.orderNumber),
                    style: AppTextTheme.headline.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    [
                      ?sourceLabel,
                      if (order.sourceIdentifier.isNotEmpty)
                        Bidi.ltr(order.sourceIdentifier),
                    ].join(' · '),
                    style: AppTextTheme.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (order.materialName != null || weight != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      [?order.materialName, ?weight].join(' · '),
                      style: AppTextTheme.body,
                    ),
                  ],
                  if (order.status == GrindingStatus.inGrinding &&
                      order.startedByName != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${order.startedByName} · '
                      '${Bidi.ltr(FactoryTime.formatClock(order.startedAt))}',
                      style: AppTextTheme.captionReadable,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Bounded so a long server `statusLabel` wraps inside the chip
            // instead of squeezing the order details off the card.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusChip(
                    label: order.displayStatusLabel,
                    tone: order.status.tone,
                  ),
                  if (order.directScrap) ...[
                    const SizedBox(height: AppSpacing.xs),
                    const StatusChip(
                      label: ArabicMessages.directScrapTag,
                      tone: StatusTone.accent,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_left, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
