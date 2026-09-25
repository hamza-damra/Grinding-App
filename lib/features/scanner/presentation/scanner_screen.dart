import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/errors/arabic_messages.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/dimensions.dart';
import '../../../core/theme/text_theme.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';
import '../../grinding_orders/domain/value_objects/grinding_identifier.dart';
import '../data/camera_permissions.dart';
import 'scanner_result.dart';

/// What stands between the worker and a running camera.
enum _CameraPhase {
  /// Reading / asking for the camera permission.
  permission,

  /// The permission is missing and may be asked for again.
  permissionDenied,

  /// The permission can only be granted in the app's system settings.
  permissionBlocked,

  /// Permission granted: the controller owns the rest (starting, running,
  /// or failed — the latter shown by the scanner's error builder).
  camera,
}

/// Camera scanner (QR + Code 128; the 12-digit validation filters anything
/// else). Manual entry is always one tap away at the bottom.
///
/// Camera lifecycle — `mobile_scanner` 6 keeps the camera texture in ONE
/// process-wide platform object, which makes ordering matter:
///
/// * the permission is asked for explicitly BEFORE the camera starts, so the
///   system dialog never interleaves with a start;
/// * the controller does not auto-start (`autoStart: false`); every start /
///   stop runs through one serial queue ([_enqueue]), so the widget, the
///   app-lifecycle handler and the retry button can never overlap;
/// * leaving the screen while a start is still in flight used to leak the
///   camera: the platform stop is a no-op until the start returns, so the
///   camera stayed bound and every later scanner failed with
///   `controllerAlreadyInitialized` («تعذر تشغيل الكاميرا») until the app was
///   restarted. [dispose] therefore stops AFTER the queued start, and every
///   fresh start first releases a camera an earlier screen still holds;
/// * the app going inactive stops the camera; resuming restarts it only if
///   it was running then — a failed camera is never restarted in a loop,
///   only by the worker's «إعادة المحاولة».
///
/// An invalid code never triggers a network call: it shows the validation
/// message and keeps scanning. The first valid code stops the camera and
/// pops once (`noDuplicates` + [_consumed]).
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode, BarcodeFormat.code128],
  );

  _CameraPhase _phase = _CameraPhase.permission;
  bool _consumed = false;
  bool _disposed = false;
  bool _permissionBusy = false;
  bool _retrying = false;

  /// The camera was running when the app went inactive.
  bool _pausedByLifecycle = false;

  String? _invalidMessage;
  Timer? _messageTimer;

  /// Every camera start / stop, one at a time, in order.
  Future<void> _cameraOps = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_ensurePermissionThenStart(request: true));
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _messageTimer?.cancel();
    final controller = _controller;
    // After any start still in the queue — see the class comment.
    unawaited(
      _cameraOps.then((_) async {
        await _guarded('stop', controller.stop);
        await _guarded('dispose', controller.dispose);
      }),
    );
    super.dispose();
  }

  Future<void> _enqueue(String what, Future<void> Function() op) {
    final next = _cameraOps.then((_) => _guarded(what, op));
    _cameraOps = next;
    return next;
  }

  static Future<void> _guarded(String what, Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      debugPrint('[Scanner] $what failed: ${e.runtimeType}');
    }
  }

  // ── Permission ────────────────────────────────────────────────────────

  Future<void> _ensurePermissionThenStart({required bool request}) async {
    if (_permissionBusy || _disposed) return;
    _permissionBusy = true;
    final permissions = ref.read(cameraPermissionsProvider);
    try {
      var permission = await permissions.status();
      if (permission == CameraPermissionState.denied && request) {
        permission = await permissions.request();
      }
      if (!mounted || _consumed) return;
      switch (permission) {
        case CameraPermissionState.granted:
          setState(() => _phase = _CameraPhase.camera);
          unawaited(_startFresh());
        case CameraPermissionState.denied:
          setState(() => _phase = _CameraPhase.permissionDenied);
        case CameraPermissionState.permanentlyDenied:
          setState(() => _phase = _CameraPhase.permissionBlocked);
      }
    } catch (e) {
      // The permission could not be read: let the scanner ask by itself
      // (mobile_scanner requests it on start).
      debugPrint('[Scanner] permission check failed: ${e.runtimeType}');
      if (mounted && !_consumed) {
        setState(() => _phase = _CameraPhase.camera);
        unawaited(_startFresh());
      }
    } finally {
      _permissionBusy = false;
    }
  }

  Future<void> _openSettings() async {
    try {
      await ref.read(cameraPermissionsProvider).openSettings();
    } catch (e) {
      debugPrint('[Scanner] open settings failed: ${e.runtimeType}');
    }
  }

  // ── Camera ────────────────────────────────────────────────────────────

  /// A start from scratch (first start, «إعادة المحاولة»).
  Future<void> _startFresh() => _enqueue('start', () async {
    if (_disposed || _consumed || _controller.value.isRunning) return;
    // Release a camera an earlier scanner still holds; a no-op otherwise.
    await MobileScannerPlatform.instance.stop();
    await _controller.start();
    final error = _controller.value.error;
    if (error != null) {
      // Diagnosable from logcat in release builds; no personal data.
      debugPrint(
        '[Scanner] camera did not start: ${error.errorCode.name} '
        '${error.errorDetails?.code ?? ''}',
      );
    }
  });

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await _startFresh();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed || _consumed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        if (_phase == _CameraPhase.camera) {
          unawaited(
            _enqueue('resume', () async {
              if (!_pausedByLifecycle || _disposed || _consumed) return;
              _pausedByLifecycle = false;
              await _controller.start();
            }),
          );
        } else if (_phase != _CameraPhase.permission) {
          // Back from the system settings: the permission may have changed.
          unawaited(_ensurePermissionThenStart(request: false));
        }
      case AppLifecycleState.inactive:
        if (_phase == _CameraPhase.camera) {
          unawaited(
            _enqueue('pause', () async {
              if (!_controller.value.isRunning) return;
              _pausedByLifecycle = true;
              await _controller.stop();
            }),
          );
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_consumed || _disposed) return;
    String? identifier;
    for (final barcode in capture.barcodes) {
      identifier = GrindingIdentifier.normalize(barcode.rawValue);
      if (identifier != null) break;
    }
    if (identifier == null) {
      _showInvalid();
      return;
    }
    _consumed = true;
    await _enqueue('stop', _controller.stop);
    if (!mounted) return;
    context.pop<ScannerResult>(ScannedIdentifier(identifier));
  }

  void _showInvalid() {
    setState(() => _invalidMessage = ArabicMessages.identifierInvalid);
    _messageTimer?.cancel();
    _messageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _invalidMessage = null);
    });
  }

  void _manualEntry() {
    if (_consumed) return;
    _consumed = true;
    context.pop<ScannerResult>(const ManualEntryRequested());
  }

  // ── UI ────────────────────────────────────────────────────────────────

  Widget? _permissionPanel() {
    return switch (_phase) {
      _CameraPhase.permission || _CameraPhase.camera => null,
      _CameraPhase.permissionDenied => _CameraProblem(
        key: const ValueKey('camera-permission-denied'),
        icon: Icons.no_photography_outlined,
        message: ArabicMessages.cameraPermissionRequired,
        actionKey: 'camera-allow',
        actionLabel: ArabicMessages.allowCamera,
        onAction: () => unawaited(_ensurePermissionThenStart(request: true)),
      ),
      _CameraPhase.permissionBlocked => _CameraProblem(
        key: const ValueKey('camera-permission-blocked'),
        icon: Icons.no_photography_outlined,
        message: ArabicMessages.cameraPermissionBlocked,
        actionKey: 'camera-open-settings',
        actionLabel: ArabicMessages.openAppSettings,
        onAction: () => unawaited(_openSettings()),
      ),
    };
  }

  Widget _cameraError(MobileScannerException error) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => _CameraProblem(
        key: const ValueKey('camera-permission-denied'),
        icon: Icons.no_photography_outlined,
        message: ArabicMessages.cameraPermissionRequired,
        actionKey: 'camera-allow',
        actionLabel: ArabicMessages.allowCamera,
        onAction: () => unawaited(_ensurePermissionThenStart(request: true)),
      ),
      MobileScannerErrorCode.unsupported => const _CameraProblem(
        key: ValueKey('camera-unsupported'),
        icon: Icons.no_photography_outlined,
        message: ArabicMessages.noCameraOnDevice,
      ),
      _ => _CameraProblem(
        key: const ValueKey('camera-failed'),
        icon: Icons.no_photography_outlined,
        message: ArabicMessages.cameraUnavailable,
        actionKey: 'camera-retry',
        actionLabel: ArabicMessages.retry,
        busy: _retrying,
        onAction: () => unawaited(_retry()),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final permissionPanel = _permissionPanel();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(ArabicMessages.scanButton),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              if (!state.isRunning ||
                  state.torchState == TorchState.unavailable) {
                return const SizedBox.shrink();
              }
              final on = state.torchState == TorchState.on;
              return IconButton(
                tooltip: 'الكشاف',
                icon: Icon(on ? Icons.flash_on : Icons.flash_off),
                onPressed: () => unawaited(_controller.toggleTorch()),
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            placeholderBuilder: (context, child) =>
                _phase == _CameraPhase.camera
                ? const _CameraStarting()
                : const ColoredBox(color: Colors.black),
            errorBuilder: (context, error, child) => _cameraError(error),
          ),
          ?permissionPanel,
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) =>
                state.isRunning ? const _Reticle() : const SizedBox.shrink(),
          ),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.xxl,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_invalidMessage != null) ...[
                    Container(
                      key: const ValueKey('scanner-invalid'),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Text(
                        _invalidMessage!,
                        textAlign: TextAlign.center,
                        style: AppTextTheme.bodyStrong.copyWith(
                          color: AppColors.textOnPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ] else
                    ValueListenableBuilder<MobileScannerState>(
                      valueListenable: _controller,
                      builder: (context, state, _) => state.isRunning
                          ? Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.md,
                              ),
                              child: Text(
                                ArabicMessages.scanHint,
                                textAlign: TextAlign.center,
                                style: AppTextTheme.bodyStrong.copyWith(
                                  color: AppColors.textOnPrimary,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  PrimaryButton(
                    key: const ValueKey('scanner-manual-entry'),
                    label: ArabicMessages.enterManually,
                    icon: Icons.keyboard,
                    variant: PrimaryButtonVariant.orange,
                    onPressed: _manualEntry,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Reticle extends StatelessWidget {
  const _Reticle();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          key: const ValueKey('scanner-reticle'),
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.accentOrange, width: 4),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
      ),
    );
  }
}

class _CameraStarting extends StatelessWidget {
  const _CameraStarting();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          key: const ValueKey('camera-starting'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.textOnPrimary),
            const SizedBox(height: AppSpacing.md),
            Text(
              ArabicMessages.cameraStarting,
              style: AppTextTheme.body.copyWith(color: AppColors.textOnPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact card in the camera area — only the camera is unavailable, the
/// rest of the app (and manual entry below) keeps working.
class _CameraProblem extends StatelessWidget {
  const _CameraProblem({
    required this.icon,
    required this.message,
    this.actionKey,
    this.actionLabel,
    this.onAction,
    this.busy = false,
    super.key,
  });

  final IconData icon;
  final String message;
  final String? actionKey;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final actionLabel = this.actionLabel;
    return ColoredBox(
      color: Colors.black,
      child: Align(
        alignment: const Alignment(0, -0.35),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(icon, size: 40, color: AppColors.textTertiary),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTextTheme.bodyStrong,
                  ),
                  if (actionLabel != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    SecondaryButton(
                      key: actionKey == null
                          ? null
                          : ValueKey<String>(actionKey!),
                      label: actionLabel,
                      loading: busy,
                      onPressed: onAction,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
