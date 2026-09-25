import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/arabic_messages.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/widgets/async_status_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../grinding_orders/domain/entities/grinding_order.dart';
import '../../../grinding_orders/domain/value_objects/grinding_status.dart';
import '../../../grinding_orders/presentation/state/grinding_queue_controller.dart';
import '../../../grinding_orders/presentation/widgets/order_row_card.dart';
import '../../../grinding_orders/presentation/widgets/order_skeletons.dart';

/// One queue list («جاهز للجرش» / «قيد الجرش»). Lazily built rows,
/// pull-to-refresh, shimmer while loading, «لا توجد أوامر» when empty, and
/// the Operator App's `AsyncStatusView` connection treatment. Kept alive
/// while Home is mounted so switching tabs does not refetch or flicker.
class QueueTab extends ConsumerStatefulWidget {
  const QueueTab({required this.status, required this.onOpen, super.key});

  final GrindingQueueStatus status;
  final ValueChanged<GrindingOrder> onOpen;

  @override
  ConsumerState<QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends ConsumerState<QueueTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = grindingQueueProvider(widget.status);
    return AsyncStatusView<List<GrindingOrder>>(
      value: ref.watch(provider),
      onRetry: () => ref.refresh(provider.future),
      loading: () => const QueueSkeletonList(),
      data: (orders) => RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: () => ref.read(provider.notifier).refresh(),
        child: orders.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: AppSpacing.xxl),
                  EmptyState(
                    icon: Icons.inbox_outlined,
                    title: ArabicMessages.emptyList,
                  ),
                ],
              )
            : ListView.separated(
                key: PageStorageKey<String>('queue-${widget.status.wire}'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: orders.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  final order = orders[index];
                  return OrderRowCard(
                    key: ValueKey('queue-row-${order.id}'),
                    order: order,
                    onTap: () => widget.onOpen(order),
                  );
                },
              ),
      ),
    );
  }
}
