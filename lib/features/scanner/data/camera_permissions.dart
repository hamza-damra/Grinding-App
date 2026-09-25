import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// What the scanner needs to know about the camera permission. `denied` can
/// be asked for again; `permanentlyDenied` can only be changed in the
/// system's app settings.
enum CameraPermissionState { granted, denied, permanentlyDenied }

/// The camera permission, asked for explicitly BEFORE the scanner starts, so
/// the system dialog never interleaves with the camera start (Operator App
/// pattern: `permission_handler` for the microphone).
abstract interface class CameraPermissions {
  Future<CameraPermissionState> status();

  Future<CameraPermissionState> request();

  /// Opens this app's page in the system settings.
  Future<bool> openSettings();
}

class PermissionHandlerCameraPermissions implements CameraPermissions {
  const PermissionHandlerCameraPermissions();

  @override
  Future<CameraPermissionState> status() async =>
      _map(await Permission.camera.status);

  @override
  Future<CameraPermissionState> request() async =>
      _map(await Permission.camera.request());

  @override
  Future<bool> openSettings() => openAppSettings();

  static CameraPermissionState _map(PermissionStatus status) {
    return switch (status) {
      PermissionStatus.granted ||
      PermissionStatus.limited => CameraPermissionState.granted,
      // `restricted` (device policy) cannot be requested either.
      PermissionStatus.permanentlyDenied ||
      PermissionStatus.restricted => CameraPermissionState.permanentlyDenied,
      PermissionStatus.denied ||
      PermissionStatus.provisional => CameraPermissionState.denied,
    };
  }
}

final cameraPermissionsProvider = Provider<CameraPermissions>(
  (ref) => const PermissionHandlerCameraPermissions(),
);
