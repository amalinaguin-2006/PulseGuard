/// PulseGuard — Permission & Camera Discovery Service
///
/// A modular, null-safe utility that handles:
///   1. Runtime camera permission checks and requests.
///   2. Permanently-denied fallback (opens device app settings).
///   3. Rear-camera + torch/flash hardware detection.
///
/// Usage:
///   final service = PermissionService();
///   final granted = await service.ensureCameraPermission();
///   final info    = await service.discoverRearCameraWithTorch();
library;

import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data class returned by camera discovery
// ─────────────────────────────────────────────────────────────────────────────

/// Holds the result of scanning for a suitable rear camera.
///
/// [camera] is the matching [CameraDescription], or `null` if none was found.
/// [hasTorch] indicates whether the matched camera supports a flash/torch unit.
/// [errorMessage] contains a human-readable reason when [camera] is `null`.
class RearCameraInfo {
  /// The rear-facing [CameraDescription] that was discovered, if any.
  final CameraDescription? camera;

  /// Whether the discovered camera has a torch (flash) unit available.
  final bool hasTorch;

  /// A human-readable explanation when no suitable camera was found.
  final String? errorMessage;

  const RearCameraInfo({
    this.camera,
    this.hasTorch = false,
    this.errorMessage,
  });

  /// Convenience getter — `true` when a usable rear camera was found.
  bool get isAvailable => camera != null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Permission & Camera Service
// ─────────────────────────────────────────────────────────────────────────────

/// Provides a clean API for camera permission management and hardware
/// discovery.  Designed to be injected or instantiated anywhere in the
/// widget tree without tight coupling to UI code.
class PermissionService {
  // ── Permission Handling ────────────────────────────────────────────────

  /// Returns `true` if the camera permission is currently granted.
  ///
  /// This is a lightweight status check that does **not** trigger a system
  /// permission dialog.
  Future<bool> isCameraPermissionGranted() async {
    final status = await Permission.camera.status;
    return status.isGranted;
  }

  /// Ensures the app has camera permission, requesting it if necessary.
  ///
  /// Returns a [PermissionStatus] reflecting the final state after the
  /// request cycle:
  ///   - [PermissionStatus.granted] — ready to use the camera.
  ///   - [PermissionStatus.denied] — user dismissed or denied the dialog.
  ///   - [PermissionStatus.permanentlyDenied] — user selected "Don't ask
  ///     again"; the caller should direct them to app settings via
  ///     [openAppSettings].
  ///   - [PermissionStatus.restricted] (iOS) — parental controls, etc.
  Future<PermissionStatus> ensureCameraPermission() async {
    // Fast path: already granted.
    PermissionStatus status = await Permission.camera.status;
    if (status.isGranted) return status;

    // Request the permission (shows the system dialog on first ask).
    status = await Permission.camera.request();

    // If the user permanently denied, we cannot re-ask.  The caller
    // should show a rationale and call [openAppSettings].
    if (status.isPermanentlyDenied) {
      return status;
    }

    return status;
  }

  /// Opens the device's application-settings screen so the user can
  /// manually re-enable the camera permission after a permanent denial.
  ///
  /// Returns `true` if the settings screen was successfully opened.
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  // ── Camera Hardware Discovery ──────────────────────────────────────────

  /// Scans the device for a **rear-facing** camera that also has a
  /// **torch/flash** unit — the exact hardware configuration required for
  /// PPG signal acquisition.
  ///
  /// The `camera` plugin's [availableCameras] returns metadata for every
  /// sensor on the device.  We filter for [CameraLensDirection.back] and
  /// then probe for torch support by briefly initialising the controller.
  ///
  /// Returns a [RearCameraInfo] with either:
  ///   - a valid [CameraDescription] and [hasTorch] flag, **or**
  ///   - an [errorMessage] explaining what hardware is missing.
  Future<RearCameraInfo> discoverRearCameraWithTorch() async {
    try {
      // Enumerate all available camera sensors on the device.
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        return const RearCameraInfo(
          errorMessage: 'No cameras detected on this device.',
        );
      }

      // Find the first rear-facing camera.
      final rearCamera = cameras.cast<CameraDescription?>().firstWhere(
            (c) => c!.lensDirection == CameraLensDirection.back,
            orElse: () => null,
          );

      if (rearCamera == null) {
        return const RearCameraInfo(
          errorMessage: 'No rear-facing camera found. '
              'PulseGuard requires the back camera for PPG measurement.',
        );
      }

      // Probe for torch support by briefly initialising the controller.
      // ResolutionPreset.low keeps the probe lightweight and fast.
      final controller = CameraController(
        rearCamera,
        ResolutionPreset.low,
        enableAudio: false,
      );

      bool hasTorch = false;
      try {
        await controller.initialize();

        // Attempt to toggle the torch — if the hardware supports it the
        // call succeeds silently; otherwise it throws.
        await controller.setFlashMode(FlashMode.torch);
        hasTorch = true;

        // Immediately turn the torch back off.
        await controller.setFlashMode(FlashMode.off);
      } on CameraException {
        // Torch is not supported on this camera sensor.
        hasTorch = false;
      } finally {
        // Always release the camera resource after probing.
        await controller.dispose();
      }

      if (!hasTorch) {
        return RearCameraInfo(
          camera: rearCamera,
          hasTorch: false,
          errorMessage: 'Rear camera found but it does not have a torch/flash. '
              'PulseGuard requires the flashlight for PPG illumination.',
        );
      }

      // ✅ All hardware requirements satisfied.
      return RearCameraInfo(
        camera: rearCamera,
        hasTorch: true,
      );
    } catch (e) {
      // Catch-all for unexpected platform errors during discovery.
      return RearCameraInfo(
        errorMessage: 'Camera discovery failed: $e',
      );
    }
  }
}
