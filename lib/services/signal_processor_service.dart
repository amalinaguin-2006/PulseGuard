// lib/services/signal_processor_service.dart
//
// Pulse Guard — DSP pipeline, real-finger verification, and biometric metrics engine.
//
// Consumes Stream<PpgFrameSample> (from PpgCameraService) and produces:
//   * waveformStream : one filtered point per frame (flattened to 0.0 until verified)
//   * metricsStream  : BiometricMetrics (BPM, RMSSD, SDNN, Stress Index, SQI, status)
//   * buildReading() : packages verified metrics into PpgReading for SQLite storage

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/ppg_reading.dart';
import '../models/ppg_sample.dart';
import 'dsp/bandpass_filter.dart';
import 'dsp/peak_detector.dart';
import 'dsp/real_finger_checker.dart';

// ---------------------------------------------------------------------------
// Public data types
// ---------------------------------------------------------------------------

/// What the pipeline is currently doing.
enum AcquisitionStatus {
  /// No finger on the lens.
  noFinger,

  /// Finger detected; measuring the frame rate and letting the filter settle.
  settling,

  /// Detecting beats and computing metrics.
  measuring,

  /// Red channel is clipped / saturated.
  saturated,
}

/// One filtered waveform point, for live drawing.
class FilteredPpgPoint {
  const FilteredPpgPoint({
    required this.timestampMicros,
    required this.value,
    required this.isPeak,
  });

  final int timestampMicros;

  /// Band-passed signal (zero-mean, pixel-intensity units; 0.0 when unverified).
  final double value;

  /// True when a beat was detected at this sample.
  final bool isPeak;

  Map<String, dynamic> toMap() => {
        't': timestampMicros,
        'v': double.parse(value.toStringAsFixed(3)),
        'p': isPeak ? 1 : 0,
      };
}

/// Snapshot of all derived biometrics. Nullable values mean not available or unverified.
class BiometricMetrics {
  const BiometricMetrics({
    required this.status,
    required this.signalQuality,
    required this.beatCount,
    required this.ibiCount,
    required this.timestampMicros,
    this.isRealFingerVerified = false,
    this.bpm,
    this.rmssd,
    this.sdnn,
    this.stressIndex,
    this.lastIbiMs,
  });

  /// Pipeline state at [timestampMicros].
  final AcquisitionStatus status;

  /// Whether biometric anti-spoofing confirmed a living human pulse.
  final bool isRealFingerVerified;

  /// Smoothed heart rate in beats per minute.
  final double? bpm;

  /// HRV: root mean square of successive IBI differences, in milliseconds.
  final double? rmssd;

  /// Standard deviation of NN intervals (ms).
  final double? sdnn;

  /// Stress score 0 (relaxed) to 100 (stressed); decreases as RMSSD rises.
  final double? stressIndex;

  /// Signal Quality Index, 0.0 (unusable) to 1.0 (excellent).
  final double signalQuality;

  /// Most recent valid inter-beat interval in milliseconds.
  final double? lastIbiMs;

  /// Valid beat intervals counted in this session.
  final int beatCount;

  /// Intervals currently held in the rolling buffer.
  final int ibiCount;

  /// Time of the sample that triggered this snapshot (microseconds).
  final int timestampMicros;

  /// Minimum SQI considered reliable enough to store or show as a result.
  static const double reliableSqi = 0.6;

  /// True when verified, BPM and HRV exist, and signal quality >= 0.6.
  bool get isReliable =>
      status == AcquisitionStatus.measuring &&
      isRealFingerVerified &&
      bpm != null &&
      rmssd != null &&
      signalQuality >= reliableSqi;

  static const BiometricMetrics idle = BiometricMetrics(
    status: AcquisitionStatus.noFinger,
    signalQuality: 0.0,
    beatCount: 0,
    ibiCount: 0,
    timestampMicros: 0,
    isRealFingerVerified: false,
  );

  @override
  String toString() =>
      'BiometricMetrics($status, verified: $isRealFingerVerified, '
      'bpm: ${bpm?.toStringAsFixed(1)}, rmssd: ${rmssd?.toStringAsFixed(1)}, '
      'sdnn: ${sdnn?.toStringAsFixed(1)}, '
      'stress: ${stressIndex?.toStringAsFixed(0)}, '
      'sqi: ${signalQuality.toStringAsFixed(2)})';
}

/// Tunable parameters. Defaults suit a finger on the rear camera at ~30 FPS.
class SignalProcessorConfig {
  const SignalProcessorConfig({
    this.nominalSampleRateHz = 30.0,
    this.lowCutHz = 0.7,
    this.highCutHz = 3.5,
    this.rateProbeFrames = 20,
    this.settleMs = 1500,
    this.maxGapMs = 200,
    this.saturationLevel = 254.0,
    this.saturationFrameLimit = 10,
    this.artifactAmplitudeRatio = 5.0,
    this.artifactHoldMs = 1000,
    this.hrWindowBeats = 6,
    this.rmssdWindowBeats = 20,
    this.minBeatsForBpm = 3,
    this.minDiffsForRmssd = 5,
    this.populationRmssdMs = 40.0,
    this.stressSteepness = 2.0,
    this.targetBeatsForFullQuality = 15,
    this.rhythmCvLimit = 0.30,
    this.staleAfterMs = 4000,
    this.metricsHeartbeatMs = 1000,
    this.minPeakAmplitude = 0.05,
    this.waveformHistoryCapacity = 150,
  });

  final double nominalSampleRateHz;
  final double lowCutHz;
  final double highCutHz;
  final int rateProbeFrames;
  final int settleMs;
  final int maxGapMs;
  final double saturationLevel;
  final int saturationFrameLimit;
  final double artifactAmplitudeRatio;
  final int artifactHoldMs;
  final int hrWindowBeats;
  final int rmssdWindowBeats;
  final int minBeatsForBpm;
  final int minDiffsForRmssd;
  final double populationRmssdMs;
  final double stressSteepness;
  final int targetBeatsForFullQuality;
  final double rhythmCvLimit;
  final int staleAfterMs;
  final int metricsHeartbeatMs;
  final double minPeakAmplitude;
  final int waveformHistoryCapacity;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

enum _Phase { noFinger, probing, settling, running }

class SignalProcessorService {
  SignalProcessorService({
    this.config = const SignalProcessorConfig(),
    double? baselineRmssdMs,
  })  : _baselineRmssdMs = (baselineRmssdMs != null && baselineRmssdMs > 0)
            ? baselineRmssdMs
            : null,
        _filter = BandpassFilter(
          sampleRateHz: config.nominalSampleRateHz,
          lowCutHz: config.lowCutHz,
          highCutHz: config.highCutHz,
        ),
        _detector = PeakDetector(minAmplitude: config.minPeakAmplitude),
        _realFingerChecker = RealFingerChecker();

  final SignalProcessorConfig config;

  final BandpassFilter _filter;
  final PeakDetector _detector;
  final RealFingerChecker _realFingerChecker;

  final StreamController<FilteredPpgPoint> _waveformController =
      StreamController<FilteredPpgPoint>.broadcast();
  final StreamController<BiometricMetrics> _metricsController =
      StreamController<BiometricMetrics>.broadcast();

  final Queue<FilteredPpgPoint> _waveformHistory = Queue<FilteredPpgPoint>();

  StreamSubscription<PpgFrameSample>? _subscription;
  bool _disposed = false;

  /// Personal resting RMSSD (ms) used to normalize the stress index.
  double? _baselineRmssdMs;

  late final int _settleMicros = config.settleMs * 1000;
  late final int _maxGapMicros = config.maxGapMs * 1000;
  late final int _artifactHoldMicros = config.artifactHoldMs * 1000;
  late final int _staleMicros = config.staleAfterMs * 1000;
  late final int _heartbeatMicros = config.metricsHeartbeatMs * 1000;

  _Phase _phase = _Phase.noFinger;
  int _lastSampleMicros = 0;
  int _probeFrames = 0;
  int _probeStartMicros = 0;
  int _settleEndMicros = 0;
  int _holdUntilMicros = 0;
  int _saturatedFrames = 0;
  bool _saturated = false;
  int _lastValidBeatMicros = 0;
  double _measuredSampleRateHz = 0.0;

  BiometricMetrics _current = BiometricMetrics.idle;
  AcquisitionStatus _lastStatus = AcquisitionStatus.noFinger;
  int _lastPublishMicros = 0;
  bool _pendingPublish = false;
  bool _errorReported = false;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  Stream<FilteredPpgPoint> get waveformStream => _waveformController.stream;
  Stream<BiometricMetrics> get metricsStream => _metricsController.stream;
  BiometricMetrics get currentMetrics => _current;
  double get measuredSampleRateHz => _measuredSampleRateHz;
  bool get isRealFingerVerified => _realFingerChecker.isVerified;

  void updateBaseline({double? rmssdMs}) {
    _baselineRmssdMs = (rmssdMs != null && rmssdMs > 0) ? rmssdMs : null;
  }

  void processSample(PpgFrameSample sample) => _onSample(sample);

  void bind(Stream<PpgFrameSample> source) {
    if (_disposed) {
      throw StateError('SignalProcessorService has been disposed.');
    }
    final previous = _subscription;
    if (previous != null) unawaited(previous.cancel());
    _resetPipeline();
    _subscription = source.listen(_onSample, onError: _onSourceError);
  }

  Future<void> unbind() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    _resetPipeline();
    _publish(_lastSampleMicros);
  }

  void reset() {
    _resetPipeline();
    _publish(_lastSampleMicros);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _waveformController.close();
    await _metricsController.close();
  }

  /// Converts the current metrics to a [PpgReading] for SQLite storage.
  /// Requires real-finger verification and complete biometric metrics.
  PpgReading? buildReading({String? rawPpgData}) {
    final m = _current;
    final bpm = m.bpm;
    final rmssd = m.rmssd;
    final stress = m.stressIndex;
    if (!m.isRealFingerVerified ||
        m.status != AcquisitionStatus.measuring ||
        bpm == null ||
        rmssd == null ||
        stress == null) {
      return null;
    }
    final trace = rawPpgData ?? exportRecentWaveformJson();
    return PpgReading(
      timestamp: DateTime.now().toUtc().toIso8601String(),
      bpm: bpm,
      rmssd: rmssd,
      sdnn: m.sdnn ?? 0.0,
      stressIndex: stress,
      signalQuality: (m.signalQuality * 100.0).clamp(0.0, 100.0).toDouble(),
      rawPpgData: trace,
    );
  }

  String exportRecentWaveformJson({int? maxPoints}) {
    final limit = maxPoints ?? config.waveformHistoryCapacity;
    final points = _waveformHistory.toList();
    final start = points.length > limit ? points.length - limit : 0;
    final slice = points.sublist(start).map((p) => p.toMap()).toList();
    return jsonEncode(slice);
  }

  static double stressFromRmssd(
    double rmssd, {
    required double referenceRmssd,
    double steepness = 2.0,
  }) {
    if (!(rmssd > 0) || !(referenceRmssd > 0)) return 100.0;
    final ratio = rmssd / referenceRmssd;
    final score = 100.0 / (1.0 + math.pow(ratio, steepness));
    return score.clamp(0.0, 100.0).toDouble();
  }

  // -------------------------------------------------------------------------
  // Stream handlers
  // -------------------------------------------------------------------------

  void _onSample(PpgFrameSample sample) {
    if (_disposed) return;
    try {
      _step(sample);
      _afterSample(sample.timestampMicros);
    } catch (e, stackTrace) {
      debugPrint('SignalProcessorService: processing error: $e\n$stackTrace');
      _resetPipeline();
      if (!_errorReported) {
        _errorReported = true;
        _forwardError(e, stackTrace);
      }
    }
  }

  void _onSourceError(Object error, StackTrace stackTrace) {
    debugPrint('SignalProcessorService: source error: $error');
    _resetPipeline();
    _forwardError(error, stackTrace);
  }

  void _forwardError(Object error, StackTrace stackTrace) {
    if (!_metricsController.isClosed && _metricsController.hasListener) {
      _metricsController.addError(error, stackTrace);
    }
  }

  // -------------------------------------------------------------------------
  // Per-frame pipeline
  // -------------------------------------------------------------------------

  void _step(PpgFrameSample sample) {
    final int t = sample.timestampMicros;
    final double x = sample.redValue;
    if (!x.isFinite) return;

    if (!sample.isFingerPresent) {
      if (_phase != _Phase.noFinger) _resetPipeline();
      return;
    }

    switch (_phase) {
      case _Phase.noFinger:
        _phase = _Phase.probing;
        _probeFrames = 1;
        _probeStartMicros = t;
        _lastSampleMicros = t;
        return;

      case _Phase.probing:
        _stepProbing(t, x);
        return;

      case _Phase.settling:
      case _Phase.running:
        _stepFiltering(t, x);
        return;
    }
  }

  void _stepProbing(int t, double x) {
    if (t - _lastSampleMicros > _maxGapMicros || t <= _lastSampleMicros) {
      _probeFrames = 1;
      _probeStartMicros = t;
      _lastSampleMicros = t;
      return;
    }
    _lastSampleMicros = t;
    _probeFrames++;
    if (_probeFrames < config.rateProbeFrames) return;

    final elapsedMicros = t - _probeStartMicros;
    var rate = config.nominalSampleRateHz;
    if (elapsedMicros > 0) {
      rate = (_probeFrames - 1) * 1e6 / elapsedMicros;
    }
    rate = math.min(120.0, math.max(15.0, rate));
    _measuredSampleRateHz = rate;
    _filter.configure(sampleRateHz: rate);
    _enterSettling(t, x);
  }

  void _stepFiltering(int t, double x) {
    final dt = t - _lastSampleMicros;
    if (dt <= 0) return;
    if (dt > _maxGapMicros) {
      _enterSettling(t, x);
      return;
    }
    _lastSampleMicros = t;

    if (x >= config.saturationLevel) {
      _saturatedFrames++;
      if (_saturatedFrames >= config.saturationFrameLimit && !_saturated) {
        _saturated = true;
        _detector.markDiscontinuity();
      }
    } else {
      _saturatedFrames = 0;
      if (_saturated) {
        _saturated = false;
        _enterSettling(t, x);
        return;
      }
    }
    if (_saturated) return;

    final double y = _filter.process(x);

    // Feed real-finger anti-spoofing checker
    _realFingerChecker.addSample(
      timestampMicros: t,
      rawRed: x,
      filteredRed: y,
    );

    if (_phase == _Phase.settling) {
      if (t >= _settleEndMicros) _phase = _Phase.running;
      _emitWaveform(t, y, false);
      return;
    }

    // Motion artifact detection
    final level = _detector.signalLevel;
    if (level > 0.0 && y.abs() > config.artifactAmplitudeRatio * level) {
      _holdUntilMicros = t + _artifactHoldMicros;
      _detector.markDiscontinuity();
    }
    if (t < _holdUntilMicros) {
      _emitWaveform(t, y, false);
      return;
    }

    final event = _detector.update(y, t);

    // Evaluate anti-spoofing checker periodically (~1/s)
    if (_realFingerChecker.isCheckDue(t)) {
      final rmssdVal = _detector.ibiCount >= 3 ? _computeRmssd(_detector.ibiCount) : null;
      _realFingerChecker.evaluate(
        sampleRateHz: _measuredSampleRateHz > 0 ? _measuredSampleRateHz : config.nominalSampleRateHz,
        currentRmssdMs: rmssdVal,
        validBeatCount: _detector.validBeats,
      );
      _pendingPublish = true;
    }

    // Flatten waveform if real-finger is not verified
    final isVerified = _realFingerChecker.isVerified;
    _emitWaveform(t, isVerified ? y : 0.0, isVerified ? (event != BeatEvent.none) : false);

    switch (event) {
      case BeatEvent.none:
        break;
      case BeatEvent.validBeat:
        _lastValidBeatMicros = t;
        _pendingPublish = true;
        break;
      case BeatEvent.firstBeat:
      case BeatEvent.artifactBeat:
        _pendingPublish = true;
        break;
    }
  }

  void _enterSettling(int t, double x) {
    _filter.prime(x);
    _detector.markDiscontinuity();
    _settleEndMicros = t + _settleMicros;
    _holdUntilMicros = 0;
    _lastSampleMicros = t;
    _phase = _Phase.settling;
  }

  void _resetPipeline() {
    _filter.reset();
    _detector.reset();
    _realFingerChecker.reset();
    _phase = _Phase.noFinger;
    _lastSampleMicros = 0;
    _probeFrames = 0;
    _probeStartMicros = 0;
    _settleEndMicros = 0;
    _holdUntilMicros = 0;
    _saturatedFrames = 0;
    _saturated = false;
    _lastValidBeatMicros = 0;
    _pendingPublish = false;
    _errorReported = false;
    _waveformHistory.clear();
  }

  void _emitWaveform(int t, double y, bool isPeak) {
    final point = FilteredPpgPoint(timestampMicros: t, value: y, isPeak: isPeak);

    if (_waveformHistory.length >= config.waveformHistoryCapacity) {
      _waveformHistory.removeFirst();
    }
    _waveformHistory.addLast(point);

    if (_waveformController.hasListener) {
      _waveformController.add(point);
    }
  }

  void _afterSample(int t) {
    final status = _publicStatus();
    final statusChanged = status != _lastStatus;
    final heartbeatDue =
        _phase != _Phase.noFinger && t - _lastPublishMicros >= _heartbeatMicros;
    if (_pendingPublish || statusChanged || heartbeatDue) {
      _publish(t);
    }
  }

  AcquisitionStatus _publicStatus() {
    switch (_phase) {
      case _Phase.noFinger:
        return AcquisitionStatus.noFinger;
      case _Phase.probing:
      case _Phase.settling:
        return AcquisitionStatus.settling;
      case _Phase.running:
        return _saturated
            ? AcquisitionStatus.saturated
            : AcquisitionStatus.measuring;
    }
  }

  void _publish(int t) {
    final metrics = _buildMetrics(t);
    _current = metrics;
    _lastStatus = metrics.status;
    _lastPublishMicros = t;
    _pendingPublish = false;
    if (!_metricsController.isClosed) {
      _metricsController.add(metrics);
    }
  }

  BiometricMetrics _buildMetrics(int t) {
    final status = _publicStatus();
    final count = _detector.ibiCount;
    final isVerified = _realFingerChecker.isVerified;

    if (status != AcquisitionStatus.measuring || !isVerified) {
      return BiometricMetrics(
        status: status,
        signalQuality: 0.0,
        beatCount: _detector.validBeats,
        ibiCount: count,
        timestampMicros: t,
        isRealFingerVerified: isVerified,
      );
    }

    final stale = _lastValidBeatMicros != 0 &&
        t - _lastValidBeatMicros > _staleMicros;
    if (stale) {
      return BiometricMetrics(
        status: status,
        signalQuality: 0.0,
        beatCount: _detector.validBeats,
        ibiCount: count,
        timestampMicros: t,
        isRealFingerVerified: isVerified,
      );
    }

    final double? bpm = count >= config.minBeatsForBpm ? _computeBpm(count) : null;
    final double? rmssd = _computeRmssd(count);
    final double? sdnn = _computeSdnn(count);
    final double? stress = rmssd == null
        ? null
        : stressFromRmssd(
            rmssd,
            referenceRmssd: _baselineRmssdMs ?? config.populationRmssdMs,
            steepness: config.stressSteepness,
          );

    return BiometricMetrics(
      status: status,
      isRealFingerVerified: isVerified,
      bpm: bpm,
      rmssd: rmssd,
      sdnn: sdnn,
      stressIndex: stress,
      signalQuality: _computeSqi(count),
      lastIbiMs: _detector.lastIbiMs > 0 ? _detector.lastIbiMs : null,
      beatCount: _detector.validBeats,
      ibiCount: count,
      timestampMicros: t,
    );
  }

  double _computeBpm(int count) {
    final n = math.min(config.hrWindowBeats, count);
    var sum = 0.0;
    for (var i = count - n; i < count; i++) {
      sum += _detector.ibiAt(i);
    }
    return 60000.0 / (sum / n);
  }

  double? _computeRmssd(int count) {
    final n = math.min(config.rmssdWindowBeats, count);
    var sumSquares = 0.0;
    var diffs = 0;
    for (var i = count - n + 1; i < count; i++) {
      if (!_detector.isContinuousWithPrevious(i)) continue;
      final d = _detector.ibiAt(i) - _detector.ibiAt(i - 1);
      sumSquares += d * d;
      diffs++;
    }
    if (diffs < config.minDiffsForRmssd) return null;
    return math.sqrt(sumSquares / diffs);
  }

  double? _computeSdnn(int count) {
    final n = math.min(config.rmssdWindowBeats, count);
    if (n < 3) return null;
    var sum = 0.0;
    for (var i = count - n; i < count; i++) {
      sum += _detector.ibiAt(i);
    }
    final mean = sum / n;
    var varSum = 0.0;
    for (var i = count - n; i < count; i++) {
      final d = _detector.ibiAt(i) - mean;
      varSum += d * d;
    }
    return math.sqrt(varSum / n);
  }

  double _computeSqi(int count) {
    if (count < 2) return 0.0;

    final completeness =
        math.min(1.0, count / config.targetBeatsForFullQuality);

    final n = math.min(config.rmssdWindowBeats, count);
    var sum = 0.0;
    for (var i = count - n; i < count; i++) {
      sum += _detector.ibiAt(i);
    }
    final mean = sum / n;
    var varianceSum = 0.0;
    for (var i = count - n; i < count; i++) {
      final d = _detector.ibiAt(i) - mean;
      varianceSum += d * d;
    }
    final cv = mean > 0 ? math.sqrt(varianceSum / n) / mean : 1.0;
    final rhythm = math.max(0.0, 1.0 - cv / config.rhythmCvLimit);

    final sqi =
        completeness * (0.5 * rhythm + 0.5 * _detector.acceptanceRatio);
    return math.min(1.0, math.max(0.0, sqi));
  }
}
