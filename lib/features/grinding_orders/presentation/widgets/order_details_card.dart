import 'package:flutter/material.dart';

import '../../../../core/errors/arabic_messages.dart';
import '../../../../core/formatting/bidi.dart';
import '../../../../core/formatting/decimal_weight.dart';
import '../../../../core/formatting/factory_time.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_theme.dart';
import '../../../../core/widgets/factory_card.dart';
import '../../../../core/widgets/field_row.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/entities/check_candidate.dart';
import '../../domain/entities/check_result.dart';
import '../../domain/entities/grinding_order.dart';
import '../../domain/value_objects/grinding_source.dart';
import '../../domain/value_objects/grinding_status.dart';
import '../order_copy.dart';

/// The order card (contract §5.4): order number, big status chip, source,
/// number, material, expected weight (rolls) or quantity (pallets), line,
/// «جرش مباشر», started by / at, completed by / at, legacy note.
///
/// [order] is the order to show (from `/check` or, right after a command,
/// the server's returned order). [check] supplies the `NOT_ELIGIBLE` details
/// when there is no order, and — when the number names a roll and a pallet
/// and neither can be acted on — both items' states. [otherItem] is the
/// other item of a shared number when the card shows one of them.
class OrderDetailsCard extends StatelessWidget {
  const OrderDetailsCard({
    required this.order,
    this.check,
    this.otherItem,
    super.key,
  });

  final GrindingOrder? order;
  final CheckResult? check;
  final CheckCandidate? otherItem;

  @override
  Widget build(BuildContext context) {
    final order = this.order;
    final check = this.check;
    final status = order?.status ?? check?.status ?? GrindingStatus.unknown;
    final statusLabel =
        order?.displayStatusLabel ?? check?.displayStatusLabel ?? '—';
    final sourceType = order?.sourceType ?? check?.sourceType;
    final identifier = order?.sourceIdentifier.isNotEmpty == true
        ? order!.sourceIdentifier
        : check?.identifier ?? '';

    return FactoryCard(
      key: const ValueKey('order-card'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wrap, not Row: a long label («بانتظار موافقة المدير», or any
          // server `statusLabel`) at 1.2× text scale drops under the order
          // number instead of overflowing a phone-width card.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              Text(
                order != null
                    ? Bidi.isolate(order.orderNumber)
                    : OrderCopy.orderTitleFallback,
                style: AppTextTheme.title,
              ),
              StatusChip(
                key: const ValueKey('order-status-chip'),
                label: statusLabel,
                tone: status.tone,
                large: true,
              ),
            ],
          ),
          if (order != null && order.directScrap) ...[
            const SizedBox(height: AppSpacing.sm),
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusChip(
                key: ValueKey('direct-scrap-tag'),
                label: ArabicMessages.directScrapTag,
                tone: StatusTone.accent,
              ),
            ),
          ],
          if (otherItem?.sourceType.label != null) ...[
            const SizedBox(height: AppSpacing.md),
            _SharedNumberNotice(other: otherItem!),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: AppSpacing.sm),
          if (sourceType?.label != null)
            FieldRow(label: OrderCopy.source, value: sourceType!.label!),
          if (identifier.isNotEmpty)
            FieldRow(
              label: OrderCopy.number,
              value: Bidi.ltr(identifier),
              valueStyle: AppTextTheme.bodyStrong.copyWith(letterSpacing: 1.2),
            ),
          if (order?.materialName != null)
            FieldRow(label: OrderCopy.material, value: order!.materialName!),
          ..._sizeRows(order, sourceType),
          if (order?.lineName != null)
            FieldRow(label: OrderCopy.line, value: order!.lineName!),
          if (order == null && check != null) ..._notEligibleRows(check),
          if (order == null && check != null && check.candidates.length >= 2)
            ..._candidateRows(check.candidates),
          if (order != null && status == GrindingStatus.inGrinding) ...[
            if (order.startedByName != null)
              FieldRow(label: OrderCopy.startedBy, value: order.startedByName!),
            if (order.startedAt != null)
              FieldRow(
                label: OrderCopy.startedAt,
                value: Bidi.ltr(FactoryTime.formatDateTime(order.startedAt)),
              ),
          ],
          if (order != null && status == GrindingStatus.completed)
            ..._completedRows(order),
        ],
      ),
    );
  }

  static List<Widget> _sizeRows(
    GrindingOrder? order,
    GrindingSourceType? sourceType,
  ) {
    if (order == null) return const <Widget>[];
    final weight = DecimalWeight.displayKg(order.expectedWeightKg);
    final quantity = order.sourceQuantity;
    return <Widget>[
      if (sourceType != GrindingSourceType.pallet && weight != null)
        FieldRow(
          key: const ValueKey('order-weight'),
          label: OrderCopy.expectedWeight,
          value: Bidi.isolate(weight),
        ),
      if (sourceType == GrindingSourceType.pallet && quantity != null)
        FieldRow(
          key: const ValueKey('order-quantity'),
          label: OrderCopy.quantity,
          value: Bidi.ltr(quantity),
        ),
    ];
  }

  static List<Widget> _notEligibleRows(CheckResult check) {
    return <Widget>[
      if (check.notEligibleProductName != null)
        FieldRow(
          label: OrderCopy.product,
          value: check.notEligibleProductName!,
        ),
      if (check.notEligibleQuantity != null)
        FieldRow(
          label: OrderCopy.quantity,
          value: Bidi.ltr(check.notEligibleQuantity!),
        ),
    ];
  }

  /// A number that names both a roll and a pallet, neither actionable: one
  /// row per item («رول» → its status, material).
  static List<Widget> _candidateRows(List<CheckCandidate> candidates) {
    return <Widget>[
      for (final candidate in candidates)
        if (candidate.sourceType.label != null)
          FieldRow(
            key: ValueKey(
              'candidate-row-${candidate.sourceType.wire.toLowerCase()}',
            ),
            label: candidate.sourceType.label!,
            value: <String>[
              candidate.displayStatusLabel ?? '—',
              ?candidate.materialName,
            ].join(' — '),
          ),
    ];
  }

  static List<Widget> _completedRows(GrindingOrder order) {
    if (order.legacy) {
      // Legacy orders have no worker — never show a name for them.
      return const <Widget>[
        Padding(
          padding: EdgeInsets.only(top: AppSpacing.sm),
          child: Text(
            ArabicMessages.legacyCompleted,
            key: ValueKey('legacy-note'),
            style: AppTextTheme.bodyStrong,
          ),
        ),
      ];
    }
    return <Widget>[
      if (order.completedByName != null)
        FieldRow(label: OrderCopy.completedBy, value: order.completedByName!),
      if (order.completedAt != null)
        FieldRow(
          label: OrderCopy.completedAt,
          value: Bidi.ltr(FactoryTime.formatDateTime(order.completedAt)),
        ),
    ];
  }
}

/// «الرقم نفسه موجود أيضاً لطبلية (غير مؤهل للجرش).» — the number also
/// names another item, so a worker holding that one notices before acting.
class _SharedNumberNotice extends StatelessWidget {
  const _SharedNumberNotice({required this.other});

  final CheckCandidate other;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('shared-number-notice'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning),
      ),
      child: Row(
        children: [
          const Icon(Icons.call_split_rounded, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              ArabicMessages.sharedNumberNotice(
                other.sourceType.label!,
                other.displayStatusLabel,
              ),
              style: AppTextTheme.bodyStrong,
            ),
          ),
        ],
      ),
    );
  }
}
