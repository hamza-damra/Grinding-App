import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_session.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/arabic_messages.dart';
import '../../../../core/formatting/bidi.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../../core/widgets/error_banner.dart';
import '../../../../core/widgets/message_dialog.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/success_banner.dart';
import '../../../grinding_auth/presentation/state/grinding_auth_controller.dart';
import '../../../grinding_auth/presentation/state/grinding_auth_state.dart';
import '../../../scanner/presentation/wedge_scan_listener.dart';
import '../../domain/entities/check_candidate.dart';
import '../../domain/entities/pending_command.dart';
import '../../domain/order_action.dart';
import '../../domain/value_objects/grinding_command.dart';
import '../../domain/value_objects/grinding_identifier.dart';
import '../order_copy.dart';
import '../state/current_order_controller.dart';
import '../state/order_command_controller.dart';
import '../widgets/command_confirm_dialogs.dart';
import '../widgets/order_details_card.dart';
import '../widgets/order_skeletons.dart';
import '../widgets/source_selection_dialog.dart';

/// The order card screen (contract §5.4–§5.5). Everything it shows comes
/// from [currentOrderControllerProvider] (the single authoritative order
/// state); the one primary action comes from [resolveOrderAction]; commands
/// go through [orderCommandControllerProvider].
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key});

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  /// A confirm / selection / message dialog is open: further taps are
  /// ignored so two dialogs can never both confirm.
  bool _dialogOpen = false;
  bool _ambiguityShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(currentOrderControllerProvider).ambiguity) {
        unawaited(_askAmbiguity());
      }
    });
  }

  CurrentOrderController get _orders =>
      ref.read(currentOrderControllerProvider.notifier);

  Future<void> _askAmbiguity() async {
    final candidates = ref.read(currentOrderControllerProvider).selection;
    if (_ambiguityShowing || candidates == null) return;
    _ambiguityShowing = true;
    final choice = await showSourceSelectionDialog(
      context,
      candidates: candidates,
    );
    _ambiguityShowing = false;
    if (!mounted) return;
    if (choice == null) {
      // «إلغاء»: nothing is opened, nothing is inferred.
      _orders.clear();
      if (context.canPop()) context.pop();
      return;
    }
    await _orders.answerAmbiguity(choice);
  }

  Future<void> _refresh() async {
    final commands = ref.read(orderCommandControllerProvider);
    if (commands.hasError) {
      ref.invalidate(orderCommandControllerProvider);
    }
    // The command's own result re-checks the order when it lands; a manual
    // re-check meanwhile could only show the pre-command state.
    final shown = ref.read(currentOrderControllerProvider).displayOrder?.id;
    if (shown != null &&
        commands.valueOrNull?.inFlightForOrder(shown) != null) {
      return;
    }
    await _orders.refresh();
  }

  void _onWedgeScan(String raw) {
    final identifier = GrindingIdentifier.normalize(raw);
    if (identifier == null) {
      AppSnackbar.error(context, ArabicMessages.identifierInvalid);
      return;
    }
    unawaited(_orders.open(identifier));
  }

  int? get _workerId {
    final auth = ref.read(grindingAuthControllerProvider).valueOrNull;
    return auth is GrindingAuthAuthenticated ? auth.worker.operatorId : null;
  }

  String? _otherWorkerWarning(PendingCommand? pending) {
    final me = _workerId;
    if (pending == null || me == null || pending.workerOperatorId == me) {
      return null;
    }
    return ArabicMessages.pendingOtherWorker(pending.workerName);
  }

  /// The number also names the other item (roll / pallet): the confirmation
  /// says which one is being acted on.
  String? _sharedNumberWarning() {
    final state = ref.read(currentOrderControllerProvider);
    final definite = state.usableCheck?.sourceType.definiteLabel;
    if (definite == null || state.sharedCandidates.length < 2) return null;
    return ArabicMessages.sharedNumberConfirmWarning(definite);
  }

  Future<void> _onCommand(CommandOrderAction action) async {
    if (_dialogOpen) return;
    final target = ref.read(currentOrderControllerProvider).usableCheck?.order;
    if (target == null) return;
    setState(() => _dialogOpen = true);
    final warnings = <String>[
      ?_sharedNumberWarning(),
      ?_otherWorkerWarning(action.pending),
    ];
    final confirmed = await showCommandConfirmDialog(
      context,
      command: action.command,
      orderNumber: target.orderNumber,
      warning: warnings.isEmpty ? null : warnings.join('\n'),
    );
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    if (!confirmed) return; // nothing sent, no id minted
    await _execute(
      action.command,
      orderId: target.id,
      orderNumber: target.orderNumber,
      reconcile: false,
    );
  }

  Future<void> _onReconcile(ReconcileOrderAction action) async {
    if (_dialogOpen) return;
    final pending = action.pending;
    setState(() => _dialogOpen = true);
    final number = Bidi.isolate(pending.orderNumber);
    final confirmed = await showConfirmDialog(
      context,
      title: ArabicMessages.verifyPreviousRequest,
      body: switch (pending.command) {
        GrindingCommand.start => ArabicMessages.pendingStartBody(number),
        GrindingCommand.complete => ArabicMessages.pendingCompleteBody(number),
      },
      warning: _otherWorkerWarning(pending),
      confirmLabel: ArabicMessages.checkButton,
      cancelLabel: ArabicMessages.cancel,
      icon: Icons.sync_problem,
    );
    if (!mounted) return;
    setState(() => _dialogOpen = false);
    if (!confirmed) return;
    await _execute(
      pending.command,
      orderId: pending.orderId,
      orderNumber: pending.orderNumber,
      reconcile: true,
    );
  }

  /// «إعادة المحاولة» after the automatic retries of THIS session ran out:
  /// the same in-session action, same id, no new confirmation (contract §9).
  Future<void> _onQuickRetry(
    PendingCommand pending, {
    required bool reconcile,
  }) {
    return _execute(
      pending.command,
      orderId: pending.orderId,
      orderNumber: pending.orderNumber,
      reconcile: reconcile,
    );
  }

  Future<void> _execute(
    GrindingCommand command, {
    required int orderId,
    required String orderNumber,
    required bool reconcile,
  }) async {
    final identifier = ref.read(currentOrderControllerProvider).identifier;
    if (identifier == null) return;
    final outcome = await ref
        .read(orderCommandControllerProvider.notifier)
        .run(
          command: command,
          orderId: orderId,
          orderNumber: orderNumber,
          identifier: identifier,
          reconcile: reconcile,
        );
    if (!mounted) return;
    switch (outcome.kind) {
      case CommandOutcomeKind.businessError:
        // Contract §9: Arabic message in a dialog, then re-check the truth.
        await _showMessage(ArabicMessages.forFailure(outcome.failure!));
        if (mounted) await _orders.refresh();
      case CommandOutcomeKind.failed:
        await _showMessage(
          ArabicMessages.forFailure(
            outcome.failure ?? const AppFailure.unknown(),
          ),
        );
      case CommandOutcomeKind.notPersisted:
        await _showMessage(ArabicMessages.genericError);
      case CommandOutcomeKind.success:
      case CommandOutcomeKind.networkLost:
      case CommandOutcomeKind.sessionEnded:
      case CommandOutcomeKind.aborted:
      case CommandOutcomeKind.ignored:
        break;
    }
  }

  Future<void> _showMessage(String message) async {
    setState(() => _dialogOpen = true);
    await showMessageDialog(context, message: message);
    if (mounted) setState(() => _dialogOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      currentOrderControllerProvider.select((s) => s.ambiguity),
      (previous, next) {
        if (next && previous != true) unawaited(_askAmbiguity());
      },
    );
    final order = ref.watch(currentOrderControllerProvider);
    final commandsAsync = ref.watch(orderCommandControllerProvider);
    final commands = commandsAsync.valueOrNull;
    final session = ref.watch(authSessionProvider);

    final check = order.usableCheck;
    final pending = commands == null
        ? null
        : selectPendingForCheck(
            records: commands.pending.values,
            identifier: order.identifier,
            chosenSourceType: order.chosenSourceType,
            checkedOrderId: check?.order?.id,
          );
    final targetOrderId = pending?.orderId ?? order.displayOrder?.id;
    final inFlight = targetOrderId == null
        ? null
        : commands?.inFlightForOrder(targetOrderId);
    final action = resolveOrderAction(
      check: check,
      pending: pending,
      inFlight: inFlight,
      locked: order.isChecking || commands == null,
      checkRejected: order.checkRejected,
    );
    final failure = pending == null ? null : commands?.failures[pending.key];
    final quickRetry =
        failure != null &&
        session.isCurrent(failure.generation) &&
        inFlight == null;

    final displayOrder = order.displayOrder;
    final title = displayOrder != null
        ? Bidi.isolate(displayOrder.orderNumber)
        : order.identifier != null
        ? Bidi.ltr(order.identifier!)
        : OrderCopy.orderTitleFallback;
    final checkValue = order.check?.valueOrNull;
    final message = checkValue?.displayMessage;
    final checkError = order.check?.error;

    return PopScope(
      // Contract §11: the button stays disabled with a spinner while a
      // START / COMPLETE is in flight; leaving would hide its outcome.
      canPop: inFlight == null,
      child: AppScaffold(
        appBar: AppBar(title: Text(title)),
        body: WedgeScanListener(
          enabled: inFlight == null && !_dialogOpen,
          onScan: _onWedgeScan,
          child: RefreshIndicator(
            color: AppColors.primaryGreen,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (order.success != null) ...[
                  SuccessBanner(
                    key: const ValueKey('success-banner'),
                    message: order.success!.successMessage,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (order.ambiguity ||
                    (displayOrder == null &&
                        checkValue == null &&
                        (order.check?.isLoading ?? true)))
                  const OrderCardSkeleton()
                else if (displayOrder == null && checkValue == null)
                  ErrorBanner(
                    key: const ValueKey('check-error'),
                    message: ArabicMessages.forFailure(
                      checkError is AppFailure
                          ? checkError
                          : const AppFailure.unknown(),
                    ),
                    retryLabel: ArabicMessages.retry,
                    onRetry: () => unawaited(_refresh()),
                  )
                else
                  OrderDetailsCard(
                    order: displayOrder,
                    check: checkValue,
                    otherItem: _otherItem(order),
                  ),
                if (checkError is AppFailure &&
                    (displayOrder != null || checkValue != null)) ...[
                  const SizedBox(height: AppSpacing.md),
                  ErrorBanner(
                    key: const ValueKey('check-refresh-error'),
                    message: ArabicMessages.forFailure(checkError),
                    retryLabel: ArabicMessages.retry,
                    onRetry: () => unawaited(_refresh()),
                  ),
                ],
                if (commandsAsync.hasError) ...[
                  const SizedBox(height: AppSpacing.md),
                  ErrorBanner(
                    message: ArabicMessages.genericError,
                    retryLabel: ArabicMessages.retry,
                    onRetry: () =>
                        ref.invalidate(orderCommandControllerProvider),
                  ),
                ],
                if (message != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _MessageBox(message: message),
                ],
                const SizedBox(height: AppSpacing.xl),
                _ActionArea(
                  action: action,
                  quickRetry: quickRetry,
                  otherWorker: _otherWorkerWarning(pending),
                  onCommand: _onCommand,
                  onReconcile: _onReconcile,
                  onQuickRetry: _onQuickRetry,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The other item of a number shared by a roll and a pallet, when the card
/// shows ONE of them (auto-resolved or chosen); `null` otherwise.
CheckCandidate? _otherItem(CurrentOrderState state) {
  final shown =
      state.displayOrder?.sourceType ?? state.check?.valueOrNull?.sourceType;
  if (shown == null || state.sharedCandidates.length < 2) return null;
  for (final candidate in state.sharedCandidates) {
    if (candidate.sourceType != shown) return candidate;
  }
  return null;
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('order-message'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: AppTextTheme.bodyStrong)),
        ],
      ),
    );
  }
}

class _ActionArea extends StatelessWidget {
  const _ActionArea({
    required this.action,
    required this.quickRetry,
    required this.otherWorker,
    required this.onCommand,
    required this.onReconcile,
    required this.onQuickRetry,
  });

  final OrderAction action;
  final bool quickRetry;
  final String? otherWorker;
  final Future<void> Function(CommandOrderAction) onCommand;
  final Future<void> Function(ReconcileOrderAction) onReconcile;
  final Future<void> Function(PendingCommand, {required bool reconcile})
  onQuickRetry;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    switch (action) {
      case NoOrderAction():
        return const SizedBox.shrink();
      case CommandOrderAction():
        final variant = action.command == GrindingCommand.start
            ? PrimaryButtonVariant.green
            : PrimaryButtonVariant.orange;
        final pending = action.pending;
        if (quickRetry && pending != null) {
          return _RetryBlock(
            variant: variant,
            busy: action.busy,
            onRetry: () => onQuickRetry(pending, reconcile: false),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (otherWorker != null) ...[
              _Notice(text: otherWorker!),
              const SizedBox(height: AppSpacing.md),
            ],
            PrimaryButton(
              key: ValueKey('command-${action.command.fileKey}'),
              label: action.command.buttonLabel,
              variant: variant,
              height: AppSizes.commandButtonHeight,
              icon: action.command == GrindingCommand.start
                  ? Icons.play_arrow_rounded
                  : Icons.task_alt,
              loading: action.busy,
              onPressed: action.enabled ? () => onCommand(action) : null,
            ),
          ],
        );
      case ReconcileOrderAction():
        final pending = action.pending;
        final number = Bidi.isolate(pending.orderNumber);
        if (quickRetry) {
          return _RetryBlock(
            variant: PrimaryButtonVariant.orange,
            busy: action.busy,
            onRetry: () => onQuickRetry(pending, reconcile: true),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Notice(
              text: switch (pending.command) {
                GrindingCommand.start => ArabicMessages.pendingStartBody(
                  number,
                ),
                GrindingCommand.complete => ArabicMessages.pendingCompleteBody(
                  number,
                ),
              },
            ),
            if (otherWorker != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _Notice(text: otherWorker!),
            ],
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              key: const ValueKey('command-reconcile'),
              label: ArabicMessages.verifyPreviousRequest,
              variant: PrimaryButtonVariant.orange,
              height: AppSizes.commandButtonHeight,
              icon: Icons.sync_problem,
              loading: action.busy,
              onPressed: action.enabled ? () => onReconcile(action) : null,
            ),
          ],
        );
    }
  }
}

class _RetryBlock extends StatelessWidget {
  const _RetryBlock({
    required this.variant,
    required this.busy,
    required this.onRetry,
  });

  final PrimaryButtonVariant variant;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ErrorBanner(
          key: ValueKey('network-lost'),
          message: ArabicMessages.networkLost,
        ),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          key: const ValueKey('command-retry'),
          label: ArabicMessages.retry,
          variant: variant,
          height: AppSizes.commandButtonHeight,
          icon: Icons.refresh,
          loading: busy,
          onPressed: busy ? null : onRetry,
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning),
      ),
      child: Text(text, style: AppTextTheme.bodyStrong),
    );
  }
}
