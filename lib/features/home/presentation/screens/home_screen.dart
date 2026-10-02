import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/errors/arabic_messages.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/dimensions.dart';
import '../../../../core/theme/text_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../grinding_auth/presentation/state/grinding_auth_controller.dart';
import '../../../grinding_auth/presentation/state/grinding_auth_state.dart';
import '../../../grinding_orders/domain/entities/pending_command.dart';
import '../../../grinding_orders/domain/value_objects/grinding_identifier.dart';
import '../../../grinding_orders/domain/value_objects/grinding_source.dart';
import '../../../grinding_orders/domain/value_objects/grinding_status.dart';
import '../../../grinding_orders/presentation/state/current_order_controller.dart';
import '../../../grinding_orders/presentation/state/order_command_controller.dart';
import '../../../grinding_orders/presentation/widgets/pending_command_banner.dart';
import '../../../scanner/presentation/scanner_result.dart';
import '../../../scanner/presentation/wedge_scan_listener.dart';
import '../widgets/queue_tab.dart';
import '../widgets/scan_entry_panel.dart';
import '../widgets/worker_identity_card.dart';

/// Home (contract §5.1–§5.3): worker identity, unconfirmed-command banners,
/// «مسح رقم» + manual entry, and the two display-only queues.
///
/// Every way of opening an order — camera, keyboard-wedge scanner, manual
/// entry, queue row, pending banner — goes through [_openOrder]: one
/// `/check` in [currentOrderControllerProvider], then the order screen.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _manual = TextEditingController();
  final FocusNode _manualFocus = FocusNode(debugLabel: 'manual-identifier');
  final FocusNode _wedgeFocus = FocusNode(debugLabel: 'home-wedge-scan');

  String? _manualError;

  /// A route (order / scanner) is being pushed or is open: further opens
  /// are ignored so a double tap or a double scan never stacks two screens.
  bool _navigating = false;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _manual.addListener(_clearManualError);
  }

  @override
  void dispose() {
    _manual
      ..removeListener(_clearManualError)
      ..dispose();
    _manualFocus.dispose();
    _wedgeFocus.dispose();
    super.dispose();
  }

  void _clearManualError() {
    if (_manualError != null && _manual.text.isNotEmpty) {
      setState(() => _manualError = null);
    }
  }

  /// Opens [identifier] on the order screen. [sourceType] is only ever a
  /// ROLL / PALLET answer the worker gave explicitly (a pending record keeps
  /// the answer its command was created under); never inferred.
  Future<void> _openOrder(
    String identifier, {
    GrindingSourceType? sourceType,
  }) async {
    if (_navigating) return;
    _navigating = true;
    final orders = ref.read(currentOrderControllerProvider.notifier);
    unawaited(orders.open(identifier, sourceType: sourceType));
    try {
      await context.push<void>(AppRoutes.orderPath);
    } finally {
      _navigating = false;
    }
    if (!mounted) return;
    orders.clear();
    _wedgeFocus.requestFocus();
  }

  Future<void> _scan() async {
    if (_navigating) return;
    _navigating = true;
    ScannerResult? result;
    try {
      result = await context.push<ScannerResult>(AppRoutes.scanPath);
    } finally {
      _navigating = false;
    }
    if (!mounted) return;
    switch (result) {
      case ScannedIdentifier(:final identifier):
        await _openOrder(identifier);
      case ManualEntryRequested():
        _manualFocus.requestFocus();
      case null:
        _wedgeFocus.requestFocus();
    }
  }

  /// «تحقق» / Enter in the manual field. Validated before any call.
  void _submitManual(String raw) {
    final identifier = GrindingIdentifier.normalize(raw);
    if (identifier == null) {
      setState(() => _manualError = ArabicMessages.identifierInvalid);
      return;
    }
    setState(() => _manualError = null);
    _manual.clear();
    // Back to the scanner focus: hides the soft keyboard and re-arms the
    // keyboard-wedge listener for the next scan.
    _wedgeFocus.requestFocus();
    unawaited(_openOrder(identifier));
  }

  void _onWedgeScan(String raw) {
    final identifier = GrindingIdentifier.normalize(raw);
    if (identifier == null) {
      AppSnackbar.error(context, ArabicMessages.identifierInvalid);
      return;
    }
    unawaited(_openOrder(identifier));
  }

  bool get _commandInFlight =>
      ref.read(orderCommandControllerProvider).valueOrNull?.hasInFlight ??
      false;

  Future<void> _logout() async {
    if (_loggingOut) return;
    if (_commandInFlight) {
      AppSnackbar.info(context, ArabicMessages.logoutBlockedInFlight);
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: ArabicMessages.logoutConfirmTitle,
      body: ArabicMessages.logoutConfirmBody,
      confirmLabel: ArabicMessages.logout,
      cancelLabel: ArabicMessages.cancel,
      destructive: true,
      icon: Icons.logout,
    );
    if (!confirmed || !mounted) return;
    if (_commandInFlight) {
      AppSnackbar.info(context, ArabicMessages.logoutBlockedInFlight);
      return;
    }
    setState(() => _loggingOut = true);
    try {
      await ref.read(grindingAuthControllerProvider.notifier).logout();
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(grindingAuthControllerProvider).valueOrNull;
    final worker = auth is GrindingAuthAuthenticated ? auth : null;
    final pending =
        (ref
                  .watch(orderCommandControllerProvider)
                  .valueOrNull
                  ?.pending
                  .values
                  .toList() ??
              <PendingCommand>[])
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return AppScaffold(
      appBar: AppBar(
        title: const Text(ArabicMessages.appTitle),
        actions: [
          IconButton(
            key: const ValueKey('logout-button'),
            tooltip: ArabicMessages.logout,
            onPressed: _loggingOut ? null : _logout,
            icon: Transform.flip(
              flipX: true,
              child: const Icon(Icons.logout, color: AppColors.textOnPrimary),
            ),
          ),
        ],
      ),
      body: WedgeScanListener(
        focusNode: _wedgeFocus,
        onScan: _onWedgeScan,
        child: DefaultTabController(
          length: 2,
          child: NestedScrollView(
            // The header (identity, banners, scan panel) scrolls away so the
            // queue gets the whole screen on small devices; the tab bar sits
            // at the top of the body and therefore stays visible.
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (worker != null)
                        WorkerIdentityCard(
                          worker: worker.worker,
                          expiresAt: worker.expiresAt,
                        ),
                      for (final record in pending) ...[
                        const SizedBox(height: AppSpacing.md),
                        PendingCommandBanner(
                          record: record,
                          currentWorkerId: worker?.worker.operatorId,
                          onOpen: () => unawaited(
                            _openOrder(
                              record.identifier,
                              sourceType: record.sourceType,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      ScanEntryPanel(
                        controller: _manual,
                        focusNode: _manualFocus,
                        errorText: _manualError,
                        onScan: () => unawaited(_scan()),
                        onSubmit: _submitManual,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            body: Column(
              children: [
                const Material(
                  color: AppColors.surface,
                  child: TabBar(
                    key: ValueKey('queue-tabs'),
                    labelColor: AppColors.primaryGreen,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicatorColor: AppColors.primaryGreen,
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: AppColors.border,
                    labelStyle: AppTextTheme.bodyStrong,
                    unselectedLabelStyle: AppTextTheme.body,
                    tabs: [
                      Tab(text: ArabicMessages.readyList),
                      Tab(text: ArabicMessages.inGrindingList),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final status in GrindingQueueStatus.values)
                        QueueTab(
                          key: ValueKey('queue-${status.wire}'),
                          status: status,
                          // Display-only: a row opens the same `/check` flow
                          // as a scan, by number only.
                          onOpen: (order) =>
                              unawaited(_openOrder(order.sourceIdentifier)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
