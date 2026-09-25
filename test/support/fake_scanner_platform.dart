// The fake must implement `start(StartOptions)` returning
// `MobileScannerViewAttributes`; mobile_scanner 6 does not export either type.
// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_grinding_app/features/scanner/data/camera_permissions.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_scanner/src/mobile_scanner_view_attributes.dart';
import 'package:mobile_scanner/src/objects/start_options.dart';

/// In-process stand-in for mobile_scanner's platform object, installed as
/// `MobileScannerPlatform.instance`, so the REAL `MobileScannerController`
/// and `MobileScanner` widget run in widget tests.
///
/// It mirrors `MethodChannelMobileScanner`'s texture bookkeeping — the part
/// that made the camera leak: [start] refuses while a texture is held
/// (`controllerAlreadyInitialized`), and [stop] is a no-op while none is.
class FakeScannerPlatform extends MobileScannerPlatform {
  final StreamController<BarcodeCapture?> _barcodes =
      StreamController<BarcodeCapture?>.broadcast();
  final StreamController<TorchState> _torch =
      StreamController<TorchState>.broadcast();
  final StreamController<double> _zoom = StreamController<double>.broadcast();

  /// The camera texture the platform holds; `null` = released.
  int? textureId;

  int startCalls = 0;

  /// Native stops that actually released a camera.
  int releases = 0;

  /// Failures for the next starts, in order; empty → the start succeeds.
  final List<MobileScannerException> startFailures = <MobileScannerException>[];

  /// When set, a start waits for it (a slow camera start).
  Completer<void>? startGate;

  bool get cameraHeld => textureId != null;

  Future<void> close() async {
    await _barcodes.close();
    await _torch.close();
    await _zoom.close();
  }

  void emit(List<String> rawValues) => _barcodes.add(
    BarcodeCapture(
      barcodes: <Barcode>[for (final v in rawValues) Barcode(rawValue: v)],
    ),
  );

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodes.stream;

  @override
  Stream<TorchState> get torchStateStream => _torch.stream;

  @override
  Stream<double> get zoomScaleStateStream => _zoom.stream;

  @override
  Widget buildCameraView() => const ColoredBox(
    key: ValueKey<String>('fake-camera-preview'),
    color: Color(0xFF444444),
  );

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    startCalls++;
    if (textureId != null) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerAlreadyInitialized,
      );
    }
    if (startFailures.isNotEmpty) throw startFailures.removeAt(0);
    final gate = startGate;
    if (gate != null) await gate.future;
    textureId = startCalls;
    return const MobileScannerViewAttributes(
      currentTorchMode: TorchState.unavailable,
      numberOfCameras: 1,
      size: Size(720, 1280),
    );
  }

  @override
  Future<void> stop() async {
    if (textureId == null) return;
    textureId = null;
    releases++;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> dispose() async {
    await updateScanWindow(null);
    await stop();
  }

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Future<void> toggleTorch() async {}

  @override
  Future<void> setZoomScale(double zoomScale) async {}

  @override
  Future<void> resetZoomScale() async {}
}

/// Scripted camera permission.
class FakeCameraPermissions implements CameraPermissions {
  FakeCameraPermissions(this.current, {this.answer});

  CameraPermissionState current;

  /// What the next system dialog answers; `null` keeps [current].
  CameraPermissionState? answer;

  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<CameraPermissionState> status() async => current;

  @override
  Future<CameraPermissionState> request() async {
    requests++;
    current = answer ?? current;
    return current;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}
