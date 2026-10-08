/// PulseGuard — Real-Time Camera Acquisition & Raw PPG Signal Service
///
/// Orchestrates the device's rear camera hardware for high-speed photoplethysmography
/// (PPG) acquisition:
///   1. Configures camera stream with optimal low-latency, low-overhead resolution.
///   2. Engages flashlight/torch illumination for transilluminating finger capillary beds.
///   3. Locks Auto-Exposure (AE) and Auto-Focus (AF) to eliminate optical artifact swings.
///   4. Efficiently processes Android YUV_420_888 (and BGRA fallback) frames at 30+ FPS
///      with zero heap allocations within inner pixel extraction loops.
///   5. Validates finger contact via multi-parameter colorimetric & chrominance heuristics.
///   6. Streams real-time [PpgFrameSample] objects to downstream signal processing engines.
library;

import 'dart:async';
import 'package:camera/camera.dart';

import '../models/ppg_sample.dart';

/// Lightweight container for frame color and luminance metrics extracted
/// from the sensor region of interest.
class FrameMetrics {
  /// Mean red channel intensity [0.0 - 255.0].
  final double red;

  /// Mean green channel intensity [0.0 - 255.0].
  final double green;

  /// Mean luminance (Y channel) [0.0 - 255.0].
  final double luminance;

  /// Mean chrominance V (Cr, red difference) in YUV space [0.0 - 255.0], or null for RGB.
  final double? chromaV;

  const FrameMetrics({
    required this.red,
    required this.green,
    required this.luminance,
    this.chromaV,
  });
}

/// Service managing camera lifecycle and real-time raw PPG frame extraction.
class PpgCameraService {
  // ─────────────────────────────────────────────────────────────────────────────
  // Tunable Thresholds for Finger Detection
  // ─────────────────────────────────────────────────────────────────────────────

  /// Minimum mean red channel value (0–255) required for finger coverage.
  static const double kMinRedThreshold = 60.0;

  /// Minimum ratio of red to green channel intensity (capillary hemoglobin absorbs green).
  static const double kRedGreenDominanceRatio = 1.25;

  /// Minimum chrominance V (Cr) in YUV_420_888 confirming tissue transillumination.
  /// Neutral gray/black is 128.0; finger on torch typically ranges 145.0–220.0.
  static const double kMinChromaVThreshold = 135.0;

  /// Minimum overall luminance to confirm torch illumination is active on the sensor.
  static const double kMinLuminanceThreshold = 30.0;

  /// Maximum luminance to filter out unshielded direct bulb reflections.
  static const double kMaxLuminanceThreshold = 252.0;

  // ─────────────────────────────────────────────────────────────────────────────
  // State & Controllers
  // ─────────────────────────────────────────────────────────────────────────────

  /// Active camera controller.
  CameraController? _controller;

  /// Broadcast stream controller delivering extracted PPG frame samples.
  final StreamController<PpgFrameSample> _sampleController =
      StreamController<PpgFrameSample>.broadcast();

  /// Flag indicating whether image stream acquisition is active.
  bool _isStreaming = false;

  /// Re-entrancy guard preventing frame processing backlog and GC pressure.
  bool _isProcessingFrame = false;

  /// Cached state of finger detection from the most recent frame.
  bool _lastFingerDetected = false;

  /// Cached frame dimensions from the active stream.
  int? _lastImageWidth;
  int? _lastImageHeight;

  // ─────────────────────────────────────────────────────────────────────────────
  // Public Getters
  // ─────────────────────────────────────────────────────────────────────────────

  /// The underlying [CameraController], accessible for UI preview widgets.
  CameraController? get controller => _controller;

  /// Broadcast stream emitting parsed [PpgFrameSample]s at the camera's frame rate (~30 FPS).
  Stream<PpgFrameSample> get sampleStream => _sampleController.stream;

  /// Whether the camera is currently actively capturing and streaming frames.
  bool get isStreaming => _isStreaming;

  /// Whether the camera controller has been successfully initialized.
  bool get isInitialized =>
      _controller != null && _controller!.value.isInitialized;

  /// True if the most recent frame confirmed valid finger placement on the camera lens.
  bool get isFingerDetected => _lastFingerDetected;

  // ─────────────────────────────────────────────────────────────────────────────
  // Lifecycle Management
  // ─────────────────────────────────────────────────────────────────────────────

  /// Begins PPG acquisition on the device's rear camera.
  ///
  /// If [camera] is omitted, automatically discovers the first rear-facing camera sensor.
  /// Initializes the controller with [ResolutionPreset.low], turns on the torch,
  /// locks auto-focus and auto-exposure to prevent artificial photometric drift,
  /// and starts the raw frame processing loop.
  Future<void> startAcquisition({CameraDescription? camera}) async {
    if (_isStreaming) return;

    // 1. Resolve camera and instantiate controller if not already prepared
    if (_controller == null || !_controller!.value.isInitialized) {
      CameraDescription? selectedCamera = camera;

      if (selectedCamera == null) {
        final cameras = await availableCameras();
        selectedCamera = cameras.cast<CameraDescription?>().firstWhere(
              (c) => c!.lensDirection == CameraLensDirection.back,
              orElse: () => null,
            );

        if (selectedCamera == null) {
          throw CameraException(
            'no_rear_camera',
            'No rear-facing camera detected on this device for PPG measurement.',
          );
        }
      }

      // ResolutionPreset.low (320x240 / 352x288) ensures minimal CPU/battery
      // thermal load and guarantees consistent 30+ FPS stream delivery.
      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
    }

    // 2. Activate torch for transillumination
    try {
      await _controller!.setFlashMode(FlashMode.torch);
    } catch (_) {
      // Gracefully continue if hardware flash control is restricted
    }

    // Brief stabilization window (250ms) to allow sensor automatic gain control (AGC)
    // to adapt to intense torch illumination before locking parameters.
    await Future.delayed(const Duration(milliseconds: 250));

    // 3. Lock Auto-Exposure and Auto-Focus to avoid artificial baseline swings
    try {
      await _controller!.setExposureMode(ExposureMode.locked);
    } catch (_) {
      // Exposure locking may not be supported by all OEM camera HAL drivers
    }

    try {
      await _controller!.setFocusMode(FocusMode.locked);
    } catch (_) {
      // Focus locking may not be supported on fixed-focus lenses
    }

    // 4. Start high-frequency image stream
    _isStreaming = true;
    await _controller!.startImageStream(_onCameraImage);
  }

  /// Halts image acquisition, turns off the torch, and restores auto modes.
  ///
  /// Keeps the controller initialized for instant resumption. To release the
  /// hardware entirely, call [dispose].
  Future<void> stopAcquisition() async {
    if (!_isStreaming && _controller == null) return;

    _isStreaming = false;
    _lastFingerDetected = false;

    if (_controller != null && _controller!.value.isInitialized) {
      try {
        if (_controller!.value.isStreamingImages) {
          await _controller!.stopImageStream();
        }
      } catch (_) {}

      try {
        await _controller!.setFlashMode(FlashMode.off);
      } catch (_) {}

      try {
        await _controller!.setExposureMode(ExposureMode.auto);
      } catch (_) {}

      try {
        await _controller!.setFocusMode(FocusMode.auto);
      } catch (_) {}
    }
  }

  /// Releases all camera hardware resources and closes stream controllers.
  Future<void> dispose() async {
    await stopAcquisition();

    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }

    if (!_sampleController.isClosed) {
      await _sampleController.close();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // High-Performance Frame Extraction Loop
  // ─────────────────────────────────────────────────────────────────────────────

  /// Callback executed for every incoming frame (~30-33ms interval).
  void _onCameraImage(CameraImage image) {
    // Drop frame immediately if acquisition was stopped or previous frame is still evaluating
    if (!_isStreaming || _isProcessingFrame) return;
    _isProcessingFrame = true;

    try {
      _lastImageWidth = image.width;
      _lastImageHeight = image.height;

      final now = DateTime.now();

      // Extract average RGB luminance and chroma without per-pixel heap allocations
      final metrics = extractFrameMetrics(
        image.planes,
        width: image.width,
        height: image.height,
      );

      // Evaluate finger presence using multi-channel optical heuristics
      final isFinger = isFingerDetectedFromMetrics(
        avgRed: metrics.red,
        avgGreen: metrics.green,
        avgLuminance: metrics.luminance,
        avgChromaV: metrics.chromaV,
      );

      _lastFingerDetected = isFinger;

      // Construct and dispatch immutable sample to listeners
      final sample = PpgFrameSample(
        timestampMicros: now.microsecondsSinceEpoch,
        timestamp: now,
        redValue: metrics.red,
        greenValue: metrics.green,
        isFingerPresent: isFinger,
      );

      if (!_sampleController.isClosed) {
        _sampleController.add(sample);
      }
    } catch (_) {
      // Silently swallow transient frame drop or stride mismatch
    } finally {
      _isProcessingFrame = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Signal Processing & Feature Extraction
  // ─────────────────────────────────────────────────────────────────────────────

  /// Computes optical and color metrics across the central Region of Interest (ROI).
  ///
  /// Optimized for:
  ///   - Android `YUV_420_888` (Y, U, V multi-planar and semi-planar layouts).
  ///   - `BGRA8888` fallback (single-plane iOS / desktop / simulator).
  ///
  /// Uses a spatial subsampling stride (step = 4) inside a central 50% bounding
  /// box to achieve >34x noise reduction while running in under 0.1ms on CPU.
  static FrameMetrics extractFrameMetrics(
    List<Plane> planes, {
    required int width,
    required int height,
  }) {
    if (planes.isEmpty) {
      return const FrameMetrics(red: 0.0, green: 0.0, luminance: 0.0);
    }

    // Central 50% Region of Interest (ROI)
    final int startX = (width * 0.25).toInt();
    final int endX = (width * 0.75).toInt();
    final int startY = (height * 0.25).toInt();
    final int endY = (height * 0.75).toInt();
    const int step = 4;

    // ── Mode 1: Android YUV_420_888 ──────────────────────────────────────────
    if (planes.length >= 3) {
      final planeY = planes[0];
      final planeU = planes[1];
      final planeV = planes[2];

      final yBytes = planeY.bytes;
      final uBytes = planeU.bytes;
      final vBytes = planeV.bytes;

      final int yRowStride = planeY.bytesPerRow;
      final int yPixelStride = planeY.bytesPerPixel ?? 1;

      final int uRowStride = planeU.bytesPerRow;
      final int uPixelStride = planeU.bytesPerPixel ?? 1;

      final int vRowStride = planeV.bytesPerRow;
      final int vPixelStride = planeV.bytesPerPixel ?? 1;

      final int yLen = yBytes.length;
      final int uLen = uBytes.length;
      final int vLen = vBytes.length;

      int sumY = 0;
      int sumU = 0;
      int sumV = 0;
      int sampleCount = 0;

      for (int y = startY; y < endY; y += step) {
        final int yRowOffset = y * yRowStride;
        final int uvRow = y >> 1;
        final int uRowOffset = uvRow * uRowStride;
        final int vRowOffset = uvRow * vRowStride;

        for (int x = startX; x < endX; x += step) {
          final int yIdx = yRowOffset + x * yPixelStride;
          final int uvCol = x >> 1;
          final int uIdx = uRowOffset + uvCol * uPixelStride;
          final int vIdx = vRowOffset + uvCol * vPixelStride;

          if (yIdx < yLen && uIdx < uLen && vIdx < vLen) {
            sumY += yBytes[yIdx];
            sumU += uBytes[uIdx];
            sumV += vBytes[vIdx];
            sampleCount++;
          }
        }
      }

      if (sampleCount == 0) {
        return const FrameMetrics(red: 0.0, green: 0.0, luminance: 0.0);
      }

      final double avgY = sumY / sampleCount;
      final double avgU = sumU / sampleCount;
      final double avgV = sumV / sampleCount;

      // ITU-R BT.601 conversion:
      // Red   = Y + 1.40200 * (Cr - 128)
      // Green = Y - 0.34414 * (Cb - 128) - 0.71414 * (Cr - 128)
      final double red = (avgY + 1.402 * (avgV - 128.0)).clamp(0.0, 255.0);
      final double green =
          (avgY - 0.344136 * (avgU - 128.0) - 0.714136 * (avgV - 128.0))
              .clamp(0.0, 255.0);

      return FrameMetrics(
        red: red,
        green: green,
        luminance: avgY,
        chromaV: avgV,
      );
    }

    // ── Mode 2: Single-plane BGRA8888 Fallback ────────────────────────────────
    final plane = planes[0];
    final bytes = plane.bytes;
    final int rowStride = plane.bytesPerRow;
    final int len = bytes.length;

    int sumR = 0;
    int sumG = 0;
    int sumB = 0;
    int sampleCount = 0;

    for (int y = startY; y < endY; y += step) {
      final int rowOffset = y * rowStride;
      for (int x = startX; x < endX; x += step) {
        final int idx = rowOffset + (x * 4);
        if (idx + 2 < len) {
          sumB += bytes[idx];
          sumG += bytes[idx + 1];
          sumR += bytes[idx + 2];
          sampleCount++;
        }
      }
    }

    if (sampleCount == 0) {
      return const FrameMetrics(red: 0.0, green: 0.0, luminance: 0.0);
    }

    final double avgR = sumR / sampleCount;
    final double avgG = sumG / sampleCount;
    final double avgB = sumB / sampleCount;
    final double avgY = 0.299 * avgR + 0.587 * avgG + 0.114 * avgB;

    return FrameMetrics(
      red: avgR,
      green: avgG,
      luminance: avgY,
      chromaV: null,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Finger Presence Detection
  // ─────────────────────────────────────────────────────────────────────────────

  /// Evaluates whether a finger is placed against the rear camera lens given raw [planes].
  ///
  /// Uses [width] and [height] if provided; otherwise falls back to cached image dimensions.
  bool detectFinger(
    List<Plane> planes, {
    int? width,
    int? height,
  }) {
    final w = width ?? _lastImageWidth ?? 320;
    final h = height ?? _lastImageHeight ?? 240;

    final metrics = extractFrameMetrics(planes, width: w, height: h);
    return isFingerDetectedFromMetrics(
      avgRed: metrics.red,
      avgGreen: metrics.green,
      avgLuminance: metrics.luminance,
      avgChromaV: metrics.chromaV,
    );
  }

  /// Determines finger placement using multi-parametric spectral thresholds:
  ///   1. [avgRed] >= [kMinRedThreshold]: confirms light penetration through capillary beds.
  ///   2. [avgRed] > [avgGreen] * [kRedGreenDominanceRatio]: confirms hemoglobin absorption.
  ///   3. [avgLuminance] within [kMinLuminanceThreshold] and [kMaxLuminanceThreshold].
  ///   4. [avgChromaV] >= [kMinChromaVThreshold] (when available): validates strong red tint in YUV space.
  static bool isFingerDetectedFromMetrics({
    required double avgRed,
    required double avgGreen,
    required double avgLuminance,
    double? avgChromaV,
  }) {
    final bool redSufficient = avgRed >= kMinRedThreshold;
    final bool redDominant = avgRed > (avgGreen * kRedGreenDominanceRatio);
    final bool luminanceValid = avgLuminance >= kMinLuminanceThreshold &&
        avgLuminance <= kMaxLuminanceThreshold;
    final bool chromaValid =
        avgChromaV == null || avgChromaV >= kMinChromaVThreshold;

    return redSufficient && redDominant && luminanceValid && chromaValid;
  }
}
