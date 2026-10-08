// lib/controllers/measurement_controller.dart
//
// Pulse Guard - Phase 5: measurement session orchestration.
//
// Owns the lifecycle of one PPG measurement:
//
//   idle -> starting -> detectingFinger -> calibrating -> measuring
//        -> completed -> saving -> saved            (or failed at any point)
//
// It requests camera permission, wires PpgCameraService.sampleStream into
// SignalProcessorService (bind), listens to the processor's metrics, runs a
// countdown that only advances while the signal is actually usable, and on
// completion packages the result into a PpgReading and stores it through
// DatabaseService.
//
// UI: listen with ListenableBuilder / AnimatedBuilder (or provider's
// ChangeNotifierProvider). For the live widgets use `controller.processor`
// (for example `PpgWaveformView.fromProcessor(controller.processor)`).
//
// Edge cases handled:
//   * finger removed       -> countdown pauses (or resets, see FingerLossPolicy)
//                             and `warning` becomes fingerRemoved
//   * noise / motion       -> countdown pauses, `warning` becomes highNoise
//   * clipped signal       -> countdown pauses, `warning` becomes saturated
//   * cancel / background  -> torch off, camera and subscriptions released
//   * low-quality result   -> kept for review, not auto-saved

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart' show CameraException;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBindingObserver, WidgetsFlutterBinding;
import 'package:permission_handler/permission_handler.dart';

import '../models/ppg_reading.dart';
import '../services/database_service.dart';
import '../services/permission_service.dart';
import '../services/ppg_camera_service.dart';
import '../services/signal_processor_service.dart';

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Called after a reading has been written to the database.
typedef ReadingSavedCallback = void Function(int id, PpgReading reading);

/// Where the session currently is.
enum MeasurementPhase {
  /// Nothing running.
  idle,

  /// Requesting permission and opening the camera.
  starting,

  /// Camera is running; waiting for a finger on the lens.
  detectingFinger,

  /// Finger found; the signal pipeline is settling. Keep still.
  calibrating,

  /// Collecting beats; the countdown advances while the signal is clean.
  measuring,

  /// Countdown finished and a result exists (see `result`).
  completed,

  /// Writing the result to the database.
  saving,

  /// Result stored (see `result.savedId`).
  saved,

  /// Session ended with an error (see `failure`).
  failed,
}

/// Transient condition the UI should tell the user about.
enum MeasurementWarning {
  none,

  /// The finger was lifted after the measurement had begun.
  fingerRemoved,

  /// Motion or noise is corrupting the signal ("stay steady").
  highNoise,

  /// The red channel is clipped; shift the finger slightly.
  saturated,

  /// The countdown is over but not enough clean beats exist yet.
  needMoreData,
}

/// Why a session failed.
enum MeasurementFailure {
  permissionDenied,
  permissionPermanentlyDenied,
  cameraUnavailable,
  torchUnavailable,
  insufficientData,
  timeout,
  interrupted,
  saveFailed,
  unexpected,
}

/// What happens to the countdown when the finger is removed.
enum FingerLossPolicy {
  /// Freeze the countdown; resume when the finger returns.
  pause,

  /// Restart from zero once the finger has been away longer than
  /// [MeasurementConfig.fingerLossGrace].
  reset,
}

/// Tunable session parameters.
class MeasurementConfig {
  const MeasurementConfig({
    this.duration = const Duration(seconds: 30),
    this.timeout,
    this.tickInterval = const Duration(milliseconds: 200),
    this.fingerLossPolicy = FingerLossPolicy.pause,
    this.fingerLossGrace = const Duration(seconds: 2),
    this.noiseSqiThreshold = 0.25,
    this.noiseMinBeats = 8,
    this.noiseStreakToWarn = 2,
    this.minSqiToSave = BiometricMetrics.reliableSqi,
    this.autoSave = true,
    this.recordRawTrace = false,
    this.maxTracePoints = 2400,
  })  : assert(noiseSqiThreshold >= 0 && noiseSqiThreshold <= 1),
        assert(noiseMinBeats >= 1),
        assert(noiseStreakToWarn >= 1),
        assert(minSqiToSave >= 0 && minSqiToSave <= 1),
        assert(maxTracePoints >= 2);

  /// Seconds of *clean* measuring required (for example 30 or 60 s).
  final Duration duration;

  /// Hard limit on the whole session including pauses. Defaults to three
  /// times [duration] plus 30 s.
  final Duration? timeout;

  /// How often the countdown is updated.
  final Duration tickInterval;

  final FingerLossPolicy fingerLossPolicy;

  /// With [FingerLossPolicy.reset]: how long the finger may be away before
  /// the countdown restarts.
  final Duration fingerLossGrace;

  /// SQI (0-1) below which a well-filled beat buffer counts as noisy.
  final double noiseSqiThreshold;

  /// Beats that must be buffered before a low SQI counts as noise (the SQI is
  /// naturally low while the buffer fills).
  final int noiseMinBeats;

  /// Consecutive noisy updates required before the warning is shown.
  final int noiseStreakToWarn;

  /// Minimum SQI (0-1) for a result to be auto-saved.
  final double minSqiToSave;

  /// Save automatically when a reliable result completes.
  final bool autoSave;

  /// Store the filtered waveform of the measured part as JSON in
  /// `PpgReading.rawPpgData`.
  final bool recordRawTrace;

  /// Upper bound on stored trace points.
  final int maxTracePoints;

  Duration get sessionTimeout =>
      timeout ?? duration * 3 + const Duration(seconds: 30);
}

/// Outcome of a completed measurement.
class MeasurementResult {
  const MeasurementResult({
    required this.reading,
    required this.metrics,
    required this.isReliable,
    required this.measuredDuration,
    this.savedId,
  });

  /// The record that is (or would be) stored.
  final PpgReading reading;

  /// Final metrics snapshot.
  final BiometricMetrics metrics;

  /// True when the SQI reached `MeasurementConfig.minSqiToSave`.
  final bool isReliable;

  /// Clean measuring time that went into the result.
  final Duration measuredDuration;

  /// Database id once saved.
  final int? savedId;

  MeasurementResult withSavedId(int id) {
    return MeasurementResult(
      reading: reading.copyWith(id: id),
      metrics: metrics,
      isReliable: isReliable,
      measuredDuration: measuredDuration,
      savedId: id,
    );
  }
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Orchestrates camera, signal processing and storage for one measurement at
/// a time. Services that are not passed in are created and owned (disposed)
/// by the controller.
class MeasurementController extends ChangeNotifier with WidgetsBindingObserver {
  MeasurementController({
    PpgCameraService? camera,
    SignalProcessorService? processor,
    DatabaseService? database,
    PermissionService? permissions,
    this.config = const MeasurementConfig(),
    this.onReadingSaved,
    bool observeAppLifecycle = true,
  })  : _camera = camera ?? PpgCameraService(),
        _processor = processor ?? SignalProcessorService(),
        _database = database ?? DatabaseService.instance,
        _permissions = permissions ?? PermissionService(),
        _ownsCamera = camera == null,
        _ownsProcessor = processor == null,
        _observesLifecycle = observeAppLifecycle {
    if (_observesLifecycle) {
      WidgetsFlutterBinding.ensureInitialized().addObserver(this);
    }
  }

  final MeasurementConfig config;

  /// Invoked after a successful save (for example to update a
  /// HistoryController).
  final ReadingSavedCallback? onReadingSaved;

  final PpgCameraService _camera;
  final SignalProcessorService _processor;
  final DatabaseService _database;
  final PermissionService _permissions;
  final bool _ownsCamera;
  final bool _ownsProcessor;
  final bool _observesLifecycle;

  late final int _durationMicros =
      math.max(1000000, config.duration.inMicroseconds);
  late final int _timeoutMicros =
      math.max(_durationMicros, config.sessionTimeout.inMicroseconds);
  late final int _lossGraceMicros = config.fingerLossGrace.inMicroseconds;

  // Session state.
  MeasurementPhase _phase = MeasurementPhase.idle;
  MeasurementWarning _warning = MeasurementWarning.none;
  MeasurementFailure? _failure;
  String? _failureDetail;
  BiometricMetrics _metrics = BiometricMetrics.idle;
  BiometricMetrics? _lastUsable;
  MeasurementResult? _result;

  bool _fingerSeen = false;
  int? _fingerLostSinceMicros;
  int _noisyStreak = 0;
  bool _awaitingData = false;

  // Timing.
  final Stopwatch _clock = Stopwatch();
  Timer? _ticker;
  int _lastTickMicros = 0;
  int _totalMicros = 0;
  int _activeMicros = 0;

  // Raw trace capture (optional).
  final List<int> _traceOffsetsMs = <int>[];
  final List<double> _traceValues = <double>[];
  int _traceStartMicros = 0;

  // Plumbing.
  StreamSubscription<BiometricMetrics>? _metricsSubscription;
  StreamSubscription<FilteredPpgPoint>? _waveformSubscription;
  Future<void>? _pendingTeardown;
  int _sessionId = 0;
  bool _disposed = false;

  // -------------------------------------------------------------------------
  // Read-only state for the UI
  // -------------------------------------------------------------------------

  /// The camera service, for camera preview rendering.
  PpgCameraService get camera => _camera;

  /// The signal processor, for widgets such as `PpgWaveformView.fromProcessor`.
  SignalProcessorService get processor => _processor;

  /// Filtered waveform points (pass-through of the processor's stream).
  Stream<FilteredPpgPoint> get waveformStream => _processor.waveformStream;

  /// Live metrics (pass-through of the processor's stream).
  Stream<BiometricMetrics> get metricsStream => _processor.metricsStream;

  MeasurementPhase get phase => _phase;

  /// Current user prompt condition.
  MeasurementWarning get warning =>
      (_warning == MeasurementWarning.none && _awaitingData)
          ? MeasurementWarning.needMoreData
          : _warning;

  MeasurementFailure? get failure => _failure;

  /// Technical description of the failure, for logs or a details dialog.
  String? get failureDetail => _failureDetail;

  /// Latest metrics (the final snapshot once completed).
  BiometricMetrics get metrics => _metrics;

  double? get bpm => _metrics.bpm;
  double? get rmssd => _metrics.rmssd;
  double? get stressIndex => _metrics.stressIndex;

  /// Signal Quality Index, 0.0-1.0.
  double get sqi => _metrics.signalQuality;

  /// Signal Quality Index as a whole percentage, 0-100.
  int get sqiPercent => math.max(0, math.min(100, (sqi * 100.0).round()));

  /// Countdown progress, 0.0-1.0.
  double get progress => math.min(1.0, _activeMicros / _durationMicros);

  /// Clean measuring time still required.
  Duration get remaining =>
      Duration(microseconds: math.max(0, _durationMicros - _activeMicros));

  /// [remaining] rounded up to whole seconds, for a countdown label.
  int get remainingSeconds => (remaining.inMicroseconds / 1e6).ceil();

  /// Elapsed time since the session started (including pauses).
  Duration get totalElapsed =>
      Duration(microseconds: _clock.elapsedMicroseconds);

  /// Clean measuring time accumulated so far.
  Duration get activeDuration => Duration(microseconds: _activeMicros);

  /// Final result once completed (persisted or pending save).
  MeasurementResult? get result => _result;

  /// True when the result is stored in the database.
  bool get isSaved => _phase == MeasurementPhase.saved;

  /// True while a session is active (countdown running, paused or waiting).
  bool get isMeasuring =>
      _phase == MeasurementPhase.starting ||
      _phase == MeasurementPhase.detectingFinger ||
      _phase == MeasurementPhase.calibrating ||
      _phase == MeasurementPhase.measuring;

  bool get _isRunningSession => isMeasuring;

  bool get _isLiveMeasuring =>
      _phase == MeasurementPhase.detectingFinger ||
      _phase == MeasurementPhase.calibrating ||
      _phase == MeasurementPhase.measuring;

  /// True when [start] can be called.
  bool get canStart =>
      !_disposed &&
      (_phase == MeasurementPhase.idle ||
          _phase == MeasurementPhase.completed ||
          _phase == MeasurementPhase.saved ||
          _phase == MeasurementPhase.failed);

  /// True when [saveResult] can be called (unsaved result available).
  bool get canSave =>
      !_disposed &&
      _result != null &&
      (_phase == MeasurementPhase.completed ||
          (_phase == MeasurementPhase.failed &&
              _failure == MeasurementFailure.saveFailed));

  // -------------------------------------------------------------------------
  // Commands
  // -------------------------------------------------------------------------

  /// Starts a session. Ignored while one is active or a save is in progress.
  /// Can be called from idle, completed, saved and failed.
  ///
  /// [baselineRmssdMs] optionally personalises the stress index (for example
  /// `HistoryController.preferredBaselineRmssd`).
  Future<void> start({double? baselineRmssdMs}) async {
    if (!canStart) return;

    // Let a previous teardown finish so the camera is fully released.
    final pending = _pendingTeardown;
    if (pending != null) await pending;
    if (!canStart) return;

    final session = ++_sessionId;
    _resetSessionState();
    _phase = MeasurementPhase.starting;
    if (baselineRmssdMs != null) {
      _processor.updateBaseline(rmssdMs: baselineRmssdMs);
    }
    notifyListeners();

    try {
      final access = await _permissions.ensureCameraPermission();
      if (!_isCurrent(session)) return;
      if (!access.isGranted) {
        await _fail(
          access.isPermanentlyDenied
              ? MeasurementFailure.permissionPermanentlyDenied
              : MeasurementFailure.permissionDenied,
          'Camera permission was not granted.',
        );
        return;
      }

      // Wire camera frames into the processor and listen to its output
      // before the first frame can arrive.
      _processor.bind(_camera.sampleStream);
      _metricsSubscription = _processor.metricsStream.listen(
        _onMetrics,
        onError: _onPipelineError,
      );
      if (config.recordRawTrace) {
        _waveformSubscription = _processor.waveformStream.listen(_onWaveform);
      }

      await _camera.startAcquisition();
      if (!_isCurrent(session)) {
        // Cancelled while the camera was opening.
        await _camera.stopAcquisition();
        return;
      }

      _clock
        ..reset()
        ..start();
      _lastTickMicros = 0;
      _phase = MeasurementPhase.detectingFinger;
      _ticker = Timer.periodic(config.tickInterval, (_) => _onTick());
      notifyListeners();
    } on CameraException catch (e) {
      if (!_isCurrent(session)) return;
      await _fail(
        e.code.toLowerCase().contains('torch')
            ? MeasurementFailure.torchUnavailable
            : MeasurementFailure.cameraUnavailable,
        e.description ?? e.toString(),
      );
    } catch (e) {
      if (!_isCurrent(session)) return;
      await _fail(MeasurementFailure.unexpected, '$e');
    }
  }

  /// Aborts the running session: stops the stream, turns the torch off and
  /// returns to idle. Does nothing if no session is running (a save in
  /// progress cannot be cancelled).
  Future<void> cancel() async {
    if (_disposed || !_isRunningSession) return;
    _sessionId++;
    _resetSessionState();
    _phase = MeasurementPhase.idle;
    notifyListeners();
    await _teardown();
  }

  /// Leaves a finished state (completed, saved or failed) and returns to
  /// idle, discarding any unsaved result.
  void reset() {
    if (_disposed) return;
    if (_phase == MeasurementPhase.completed ||
        _phase == MeasurementPhase.saved ||
        _phase == MeasurementPhase.failed) {
      _sessionId++;
      _resetSessionState();
      _phase = MeasurementPhase.idle;
      notifyListeners();
    }
  }

  /// Stores the current result. Used to retry after a failed save, or to keep
  /// a low-quality result that was not auto-saved. Returns true on success.
  Future<bool> saveResult() async {
    final current = _result;
    if (_disposed || current == null || !canSave) return false;

    _phase = MeasurementPhase.saving;
    _failure = null;
    _failureDetail = null;
    notifyListeners();

    try {
      final id = await _database.insertPpgReading(current.reading);
      if (_disposed) return true;
      final saved = current.withSavedId(id);
      _result = saved;
      _phase = MeasurementPhase.saved;
      notifyListeners();
      try {
        onReadingSaved?.call(id, saved.reading);
      } catch (e) {
        debugPrint('MeasurementController: onReadingSaved failed: $e');
      }
      return true;
    } catch (e) {
      if (_disposed) return false;
      _phase = MeasurementPhase.failed;
      _failure = MeasurementFailure.saveFailed;
      _failureDetail = e.toString();
      notifyListeners();
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Stream and timer handlers
  // -------------------------------------------------------------------------

  void _onMetrics(BiometricMetrics m) {
    if (_disposed || !_isLiveMeasuring) return;

    _metrics = m;
    final bpm = m.bpm;
    final rmssd = m.rmssd;
    final stress = m.stressIndex;
    if (m.status == AcquisitionStatus.measuring &&
        bpm != null &&
        rmssd != null &&
        stress != null) {
      _lastUsable = m;
    }

    final now = _clock.elapsedMicroseconds;
    switch (m.status) {
      case AcquisitionStatus.noFinger:
        _handleNoFinger(now);
        break;
      case AcquisitionStatus.settling:
        _handleSettling();
        break;
      case AcquisitionStatus.measuring:
        _handleMeasuring(m);
        break;
      case AcquisitionStatus.saturated:
        _handleSaturated();
        break;
    }
    notifyListeners();
  }

  void _handleNoFinger(int now) {
    if (_fingerSeen) {
      _warning = MeasurementWarning.fingerRemoved;
      _fingerLostSinceMicros ??= now;
    } else {
      _warning = MeasurementWarning.none;
    }
    _phase = MeasurementPhase.detectingFinger;
    _noisyStreak = 0;
  }

  void _handleSettling() {
    _fingerSeen = true;
    _fingerLostSinceMicros = null;
    _warning = MeasurementWarning.none;
    _phase = MeasurementPhase.calibrating;
    _noisyStreak = 0;
  }

  void _handleMeasuring(BiometricMetrics m) {
    _fingerSeen = true;
    _fingerLostSinceMicros = null;
    _phase = MeasurementPhase.measuring;

    if (_isNoisy(m)) {
      _noisyStreak++;
      if (_noisyStreak >= config.noiseStreakToWarn) {
        _warning = MeasurementWarning.highNoise;
      }
    } else {
      _noisyStreak = 0;
      _warning = MeasurementWarning.none;
    }
  }

  void _handleSaturated() {
    _fingerSeen = true;
    _fingerLostSinceMicros = null;
    _phase = MeasurementPhase.measuring;
    _warning = MeasurementWarning.saturated;
    _noisyStreak = 0;
  }

  bool _isNoisy(BiometricMetrics m) {
    final lostBeats = m.ibiCount >= 3 && m.bpm == null;
    final lowQuality = m.ibiCount >= config.noiseMinBeats &&
        m.signalQuality < config.noiseSqiThreshold;
    return lostBeats || lowQuality;
  }

  void _onWaveform(FilteredPpgPoint point) {
    if (_phase != MeasurementPhase.measuring ||
        _warning != MeasurementWarning.none ||
        !point.value.isFinite ||
        _traceValues.length >= config.maxTracePoints) {
      return;
    }
    if (_traceValues.isEmpty) _traceStartMicros = point.timestampMicros;
    _traceOffsetsMs.add((point.timestampMicros - _traceStartMicros) ~/ 1000);
    _traceValues.add(point.value);
  }

  void _onPipelineError(Object error, StackTrace stackTrace) {
    if (_disposed || !_isRunningSession) return;
    if (error is CameraException) {
      unawaited(_fail(
        error.code.toLowerCase().contains('torch')
            ? MeasurementFailure.torchUnavailable
            : MeasurementFailure.cameraUnavailable,
        error.description ?? error.toString(),
      ));
    } else {
      // The processor already reset itself; the session can recover.
      debugPrint('MeasurementController: pipeline error: $error');
    }
  }

  void _onTick() {
    if (_disposed || !_isLiveMeasuring) return;

    final now = _clock.elapsedMicroseconds;
    final dt = now - _lastTickMicros;
    _lastTickMicros = now;
    if (dt <= 0) return;

    _totalMicros += dt;
    if (_totalMicros >= _timeoutMicros) {
      unawaited(_fail(
        MeasurementFailure.timeout,
        'No clean measurement within ${config.sessionTimeout.inSeconds} s.',
      ));
      return;
    }

    // Optional restart when the finger has been away too long.
    final lostSince = _fingerLostSinceMicros;
    if (lostSince != null &&
        config.fingerLossPolicy == FingerLossPolicy.reset &&
        now - lostSince >= _lossGraceMicros &&
        (_activeMicros > 0 || _traceValues.isNotEmpty)) {
      _activeMicros = 0;
      _awaitingData = false;
      _clearTrace();
    }

    // The countdown only advances while the signal is clean.
    if (_phase == MeasurementPhase.measuring &&
        _warning == MeasurementWarning.none) {
      _activeMicros = math.min(_durationMicros, _activeMicros + dt);
    }

    if (_activeMicros >= _durationMicros) {
      final usable = _lastUsable;
      if (usable != null &&
          _phase == MeasurementPhase.measuring &&
          _warning == MeasurementWarning.none) {
        unawaited(_complete(usable));
        return;
      }
      _awaitingData = true;
    } else {
      _awaitingData = false;
    }
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Completion, failure, teardown
  // -------------------------------------------------------------------------

  Future<void> _complete(BiometricMetrics usable) async {
    final session = _sessionId;
    final bpm = usable.bpm;
    final rmssd = usable.rmssd;
    final stress = usable.stressIndex;
    if (bpm == null || rmssd == null || stress == null) {
      await _fail(
        MeasurementFailure.insufficientData,
        'Heart rate or HRV was not available at the end of the measurement.',
      );
      return;
    }

    // Everything up to the first await is synchronous, so no second
    // completion can start from the timer.
    _ticker?.cancel();
    _ticker = null;

    final reading = PpgReading(
      timestamp: DateTime.now().toIso8601String(),
      bpm: bpm,
      rmssd: rmssd,
      stressIndex: stress,
      signalQuality: (usable.signalQuality * 100.0).clamp(0.0, 100.0).toDouble(),
      rawPpgData: _buildTraceJson(),
    );

    _metrics = usable;
    _warning = MeasurementWarning.none;
    _awaitingData = false;
    _result = MeasurementResult(
      reading: reading,
      metrics: usable,
      isReliable: usable.signalQuality >= config.minSqiToSave,
      measuredDuration: Duration(microseconds: _activeMicros),
    );
    _phase = MeasurementPhase.completed;
    notifyListeners();

    // The camera is no longer needed: release it (torch off) right away.
    await _teardown();
    if (!_isCurrent(session)) return;

    final current = _result;
    if (config.autoSave && current != null && current.isReliable) {
      await saveResult();
    }
  }

  Future<void> _fail(MeasurementFailure failure, String detail) async {
    _sessionId++;
    _phase = MeasurementPhase.failed;
    _failure = failure;
    _failureDetail = detail;
    _warning = MeasurementWarning.none;
    _awaitingData = false;
    notifyListeners();
    await _teardown();
  }

  /// Stops the timer, drops subscriptions, turns the torch off and releases
  /// the camera. Safe to call repeatedly; never throws.
  Future<void> _teardown() {
    // Capture and clear synchronously so a quick restart is unaffected.
    _ticker?.cancel();
    _ticker = null;
    _clock.stop();
    final metricsSubscription = _metricsSubscription;
    final waveformSubscription = _waveformSubscription;
    _metricsSubscription = null;
    _waveformSubscription = null;

    final previous = _pendingTeardown;
    final future = _runTeardown(
      previous,
      metricsSubscription,
      waveformSubscription,
    );
    _pendingTeardown = future;
    return future;
  }

  Future<void> _runTeardown(
    Future<void>? previous,
    StreamSubscription<BiometricMetrics>? metricsSubscription,
    StreamSubscription<FilteredPpgPoint>? waveformSubscription,
  ) async {
    if (previous != null) await previous;
    try {
      await metricsSubscription?.cancel();
      await waveformSubscription?.cancel();
    } catch (e) {
      debugPrint('MeasurementController: cancelling subscriptions failed: $e');
    }
    try {
      await _camera.stopAcquisition();
    } catch (e) {
      debugPrint('MeasurementController: stopAcquisition failed: $e');
    }
    try {
      await _processor.unbind();
    } catch (e) {
      debugPrint('MeasurementController: unbind failed: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  bool _isCurrent(int session) => !_disposed && session == _sessionId;

  void _resetSessionState() {
    _warning = MeasurementWarning.none;
    _awaitingData = false;
    _failure = null;
    _failureDetail = null;
    _metrics = BiometricMetrics.idle;
    _lastUsable = null;
    _result = null;
    _fingerSeen = false;
    _fingerLostSinceMicros = null;
    _noisyStreak = 0;
    _totalMicros = 0;
    _activeMicros = 0;
    _clearTrace();
  }

  void _clearTrace() {
    _traceOffsetsMs.clear();
    _traceValues.clear();
  }

  String? _buildTraceJson() {
    if (!config.recordRawTrace || _traceValues.length < 2) return null;
    return jsonEncode(<String, Object>{
      'version': 1,
      'sampleRateHz':
          double.parse(_processor.measuredSampleRateHz.toStringAsFixed(2)),
      'offsetsMs': List<int>.of(_traceOffsetsMs),
      'values': _traceValues
          .map((double v) => double.parse(v.toStringAsFixed(3)))
          .toList(),
    });
  }

  // -------------------------------------------------------------------------
  // Framework hooks
  // -------------------------------------------------------------------------

  /// The camera session does not survive backgrounding, so a running
  /// measurement is ended. `inactive` is ignored on purpose: the permission
  /// dialog triggers it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        _isRunningSession) {
      unawaited(_fail(
        MeasurementFailure.interrupted,
        'The app moved to the background.',
      ));
    }
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sessionId++;
    if (_observesLifecycle) {
      WidgetsFlutterBinding.ensureInitialized().removeObserver(this);
    }
    unawaited(_shutdown());
    super.dispose();
  }

  /// Releases the camera and, for services created here, disposes them.
  Future<void> _shutdown() async {
    await _teardown();
    try {
      if (_ownsCamera) await _camera.dispose();
      if (_ownsProcessor) await _processor.dispose();
    } catch (e) {
      debugPrint('MeasurementController: disposing services failed: $e');
    }
  }
}
