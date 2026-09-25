import 'package:flutter/material.dart';

import '../../../../core/errors/arabic_messages.dart';
import '../../../../core/formatting/bidi.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_theme.dart';
import '../../../../core/widgets/factory_card.dart';
import '../../../../core/widgets/secondary_button.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/entities/check_candidate.dart';
import '../../domain/value_objects/grinding_command.dart';
import '../../domain/value_objects/grinding_source.dart';

/// Contract §5.3: shown only when the number names a roll AND a pallet and
/// the worker can act on BOTH (409 `GRINDING_IDENTIFIER_AMBIGUOUS`). One big
/// card per item — «رول» / «طبلية» with its material, order number, status
/// and what can be done next — plus «إلغاء». Returns the worker's own choice,
/// or `null` on cancel; the app never picks.
Future<GrindingSourceType?> showSourceSelectionDialog(
  BuildContext context, {
  required List<CheckCandidate> candidates,
}) {
  return showDialog<GrindingSourceType>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SourceSelectionDialog(candidates: candidates),
  );
}

class SourceSelectionDialog extends StatelessWidget {
  const SourceSelectionDialog({required this.candidates, super.key});

  final List<CheckCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.call_split_rounded,
                size: 48,
                color: AppColors.accentOrange,
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                ArabicMessages.selectionTitle,
                textAlign: TextAlign.center,
                style: AppTextTheme.title,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                ArabicMessages.selectionText,
                textAlign: TextAlign.center,
                style: AppTextTheme.body,
              ),
              const SizedBox(height: AppSpacing.xl),
              for (final candidate in candidates) ...[
                _CandidateOption(
                  candidate: candidate,
                  onTap: () => Navigator.of(context).pop(candidate.sourceType),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                key: const ValueKey('selection-cancel'),
                label: ArabicMessages.cancel,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CandidateOption extends StatelessWidget {
  const _CandidateOption({required this.candidate, required this.onTap});

  final CheckCandidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typeLabel = candidate.sourceType.label ?? '—';
    final statusLabel = candidate.displayStatusLabel;
    final command = candidate.command;
    final material = candidate.materialName;
    final orderNumber = candidate.orderNumber;

    return Semantics(
      button: true,
      label: <String>[typeLabel, ?statusLabel, ?material].join('، '),
      excludeSemantics: true,
      child: FactoryCard(
        key: ValueKey('selection-${candidate.sourceType.wire.toLowerCase()}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.commandButtonHeight,
          ),
          child: Row(
            children: [
              Icon(
                candidate.sourceType == GrindingSourceType.pallet
                    ? Icons.pallet
                    : Icons.donut_large_rounded,
                size: AppSizes.iconLg,
                color: AppColors.primaryGreen,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(typeLabel, style: AppTextTheme.title),
                    if (material != null)
                      Text(
                        material,
                        style: AppTextTheme.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    if (orderNumber != null)
                      Text(
                        Bidi.isolate(orderNumber),
                        style: AppTextTheme.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    if (command != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            command == GrindingCommand.start
                                ? Icons.play_arrow_rounded
                                : Icons.task_alt,
                            size: AppSizes.iconSm,
                            color: AppColors.accentOrangePressed,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              command.buttonLabel,
                              style: AppTextTheme.bodyStrong.copyWith(
                                color: AppColors.accentOrangePressed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (statusLabel != null) ...[
                const SizedBox(width: AppSpacing.sm),
                StatusChip(label: statusLabel, tone: candidate.status.tone),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
