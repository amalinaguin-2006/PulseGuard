// lib/services/signal_processor_service.dart
//
// Pulse Guard - Phase 4A: DSP pipeline and biometric metrics engine.
//
// Consumes Stream<PpgFrameSample> (from PpgCameraService) and produces:
//   * waveformStream : one filtered point per frame, for the oscilloscope UI
//   * metricsStream  : BiometricMetrics (BPM, RMSSD, Stress Index, SQI, status)
//                      on every beat, on status changes, and once per second
//   * buildReading() : converts the current metrics into a PpgReading for
//                      SQLite storage (Phase 2)
//
// Pipeline per frame (all O(1), no allocation except the emitted objects):
//   raw red -> bandpass (0.7-3.5 Hz) -> adaptive peak detector -> IBI ring
//   buffer -> BPM / RMSSD / Stress / SQI (recomputed on beats only).
//
// Typical use:
//   final processor = SignalProcessorService();
//   processor.bind(camera.sampleStream);
//   processor.metricsStream.listen((m) { ... });
//   final reading = processor.buildReading();   // when the session ends
//   if (reading != null) await DatabaseService.instance.insertPpgReading(reading);

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/ppg_reading.dart';
import '../models/ppg_sample.dart';
import 'dsp/bandpass_filter.dart';
import 'dsp/peak_detector.dart';

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

  /// Red channel is clipped (finger too bright / pressed too lightly with the
  /// torch); the pulsatile component is lost until the clipping stops.
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

  /// Band-passed signal (zero-mean, pixel-intensity units).
  final double value;

  /// True when a beat was detected at this sample (the detector confirms a
  /// peak one sample late).
  final bool isPeak;

  Map<String, dynamic> toMap() => {
        't': timestampMicros,
        'v': double.parse(value.toStringAsFixed(3)),
        'p': isPeak ? 1 : 0,
      };
}

/// Snapshot of all derived biometrics. Nullable values mean "not available
/// yet / not trustworthy right now".
class BiometricMetrics {
  const BiometricMetrics({
    required this.status,
    required this.signalQuality,
    required this.beatCount,
    required this.ibiCount,
    required this.timestampMicros,
    this.bpm,
    this.rmssd,
    this.stressIndex,
    this.lastIbiMs,
  });

  /// Pipeline state at [timestampMicros].
  final AcquisitionStatus status;

  /// Smoothed heart rate in beats per minute.
  final double? bpm;

  /// HRV: root mean square of successive IBI differences, in milliseconds.
  final double? rmssd;

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

  /// Time of the sample that triggered this snapshot (microseconds, same
  /// clock as [PpgFrameSample.timestampMicros]).
  final int timestampMicros;

  /// Minimum SQI considered reliable enough to store or show as a result.
  static const double reliableSqi = 0.6;

  /// True when BPM and HRV exist and the signal quality is acceptable.
  bool get isReliable =>
      status == AcquisitionStatus.measuring &&
      bpm != null &&
      rmssd != null &&
      signalQuality >= reliableSqi;

  static const BiometricMetrics idle = BiometricMetrics(
    status: AcquisitionStatus.noFinger,
    signalQuality: 0.0,
    beatCount: 0,
    ibiCount: 0,
    timestampMicros: 0,
  );

  @override
  String toString() =>
      'BiometricMetrics($status, bpm: ${bpm?.toStringAsFixed(1)}, '
      'rmssd: ${rmssd?.toStringAsFixed(1)}, '
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

  /// Sampling rate assumed before the real rate is measured.
  final double nominalSampleRateHz;

  /// Bandpass edges.
  final double lowCutHz;
  final double highCutHz;

  /// Frames used to measure the real frame rate when a finger appears. The
  /// filter is then designed for that rate rather than the nominal 30 Hz.
  final int rateProbeFrames;

  /// Time to let the filter settle after (re)starting, before detecting beats.
  final int settleMs;

  /// A gap between frames longer than this restarts filtering and breaks the
  /// beat chain (dropped frames would otherwise corrupt IBIs).
  final int maxGapMs;

  /// Red values at or above this count as clipped.
  final double saturationLevel;

  /// Consecutive clipped frames before the state becomes `saturated`.
  final int saturationFrameLimit;

  /// A filtered sample larger than this multiple of the peak level is a
  /// motion artifact (finger shifted).
  final double artifactAmplitudeRatio;

  /// Detection is paused this long after a motion artifact.
  final int artifactHoldMs;

  /// Intervals averaged for the smoothed BPM.
  final int hrWindowBeats;

  /// Most recent intervals used for RMSSD and rhythm statistics.
  final int rmssdWindowBeats;

  /// Intervals needed before BPM is reported.
  final int minBeatsForBpm;

  /// Successive differences needed before RMSSD is reported.
  final int minDiffsForRmssd;

  /// Reference RMSSD (ms) that maps to a stress score of 50 when the user has
  /// no personal baseline. A generic adult resting value; personal baselines
  /// are far better.
  final double populationRmssdMs;

  /// Steepness of the stress curve (higher = sharper transition around the
  /// reference).
  final double stressSteepness;

  /// Number of stored intervals at which the buffer counts as "complete" for
  /// the SQI.
  final int targetBeatsForFullQuality;

  /// Coefficient of variation of IBIs at which the rhythm score reaches 0.
  final double rhythmCvLimit;

  /// No valid beat for this long invalidates the metrics.
  final int staleAfterMs;

  /// Interval between periodic metric emissions while a finger is present.
  final int metricsHeartbeatMs;

  /// Peak amplitude floor passed to the detector (see [PeakDetector]).
  final double minPeakAmplitude;

  /// Number of recent filtered points kept in memory for waveform serialization.
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
        _detector = PeakDetector(minAmplitude: config.minPeakAmplitude);

  final SignalProcessorConfig config;

  final BandpassFilter _filter;
  final PeakDetector _detector;

  final StreamController<FilteredPpgPoint> _waveformController =
      StreamController<FilteredPpgPoint>.broadcast();
  final StreamController<BiometricMetrics> _metricsController =
      StreamController<BiometricMetrics>.broadcast();

  final Queue<FilteredPpgPoint> _waveformHistory = Queue<FilteredPpgPoint>();

  StreamSubscription<PpgFrameSample>? _subscription;
  bool _disposed = false;

  /// Personal resting RMSSD (ms) used to normalise the stress index.
  double? _baselineRmssdMs;

  // Cached config in microseconds.
  late final int _settleMicros = config.settleMs * 1000;
  late final int _maxGapMicros = config.maxGapMs * 1000;
  late final int _artifactHoldMicros = config.artifactHoldMs * 1000;
  late final int _staleMicros = config.staleAfterMs * 1000;
  late final int _heartbeatMicros = config.metricsHeartbeatMs * 1000;

  // Pipeline state.
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

  // Publishing state.
  BiometricMetrics _current = BiometricMetrics.idle;
  AcquisitionStatus _lastStatus = AcquisitionStatus.noFinger;
  int _lastPublishMicros = 0;
  bool _pendingPublish = false;
  bool _errorReported = false;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Filtered waveform points, one per frame once a finger is on the lens.
  Stream<FilteredPpgPoint> get waveformStream => _waveformController.stream;

  /// Metric snapshots (on each beat, on status change, and about once per
  /// second while a finger is present). Source errors are forwarded here.
  Stream<BiometricMetrics> get metricsStream => _metricsController.stream;

  /// The latest snapshot.
  BiometricMetrics get currentMetrics => _current;

  /// Frame rate measured when the finger was placed (0 before that).
  double get measuredSampleRateHz => _measuredSampleRateHz;

  /// Sets or clears the user's resting RMSSD (ms), e.g. from
  /// `UserProfile.baselineHrv`. Normalises the stress index to the person.
  void updateBaseline({double? rmssdMs}) {
    _baselineRmssdMs = (rmssdMs != null && rmssdMs > 0) ? rmssdMs : null;
  }

  /// Starts consuming [source]. Replaces any previous subscription.
  void bind(Stream<PpgFrameSample> source) {
    if (_disposed) {
      throw StateError('SignalProcessorService has been disposed.');
    }
    final previous = _subscription;
    if (previous != null) unawaited(previous.cancel());
    _resetPipeline();
    _subscription = source.listen(_onSample, onError: _onSourceError);
  }

  /// Stops consuming samples and clears the pipeline.
  Future<void> unbind() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    _resetPipeline();
    _publish(_lastSampleMicros);
  }

  /// Clears all measurement state without unsubscribing (new session).
  void reset() {
    _resetPipeline();
    _publish(_lastSampleMicros);
  }

  /// Unsubscribes and closes both streams. The service cannot be reused.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _waveformController.close();
    await _metricsController.close();
  }

  /// Converts the current metrics to a [PpgReading] for SQLite storage.
  ///
  /// Returns null unless the pipeline is measuring and BPM, RMSSD and stress
  /// are all available, guaranteeing all database constraints are met.
  /// If [rawPpgData] is omitted, automatically exports the recent filtered trace.
  PpgReading? buildReading({String? rawPpgData}) {
    final m = _current;
    final bpm = m.bpm;
    final rmssd = m.rmssd;
    final stress = m.stressIndex;
    if (m.status != AcquisitionStatus.measuring ||
        bpm == null ||
        rmssd == null ||
        stress == null) {
      return null;
    }
    final trace = rawPpgData ?? exportRecentWaveformJson();
    return PpgReading(
      timestamp: DateTime.now().toIso8601String(),
      bpm: bpm,
      rmssd: rmssd,
      stressIndex: stress,
      signalQuality: (m.signalQuality * 100.0).clamp(0.0, 100.0).toDouble(),
      rawPpgData: trace,
    );
  }

  /// Exports a compact JSON string representing the rolling waveform history.
  String exportRecentWaveformJson({int? maxPoints}) {
    final limit = maxPoints ?? config.waveformHistoryCapacity;
    final points = _waveformHistory.toList();
    final start = points.length > limit ? points.length - limit : 0;
    final slice = points.sublist(start).map((p) => p.toMap()).toList();
    return jsonEncode(slice);
  }

  /// Maps RMSSD to a 0-100 stress score, decreasing in RMSSD:
  /// `100 / (1 + (rmssd / reference) ^ steepness)`.
  ///
  /// RMSSD equal to [referenceRmssd] gives 50; half the reference gives about
  /// 80 (steepness 2); double gives about 20. Always within (0, 100).
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
      // Never let one bad frame kill the subscription. Start clean and report
      // once per session.
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
    if (!x.isFinite) return; // Non-finite value: ignore the frame.

    // Finger lifted: drop everything so stale beats cannot leak into the next
    // measurement.
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

  /// Measures the actual frame rate over the first frames, then designs the
  /// filter for it. The camera rarely delivers exactly 30 FPS and a filter
  /// designed for the wrong rate shifts its passband.
  void _stepProbing(int t, double x) {
    if (t - _lastSampleMicros > _maxGapMicros || t <= _lastSampleMicros) {
      // Unstable delivery: restart the probe.
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
    // The 3.5 Hz upper cutoff needs a rate well above 7 Hz.
    rate = math.min(120.0, math.max(15.0, rate));
    _measuredSampleRateHz = rate;
    _filter.configure(sampleRateHz: rate);
    _enterSettling(t, x);
  }

  void _stepFiltering(int t, double x) {
    final dt = t - _lastSampleMicros;
    if (dt <= 0) return; // Duplicate or out-of-order frame.
    if (dt > _maxGapMicros) {
      // Dropped frames: the IIR state and the beat chain are no longer valid.
      _enterSettling(t, x);
      return;
    }
    _lastSampleMicros = t;

    // Clipped red channel: no usable pulsatile component.
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

    if (_phase == _Phase.settling) {
      if (t >= _settleEndMicros) _phase = _Phase.running;
      _emitWaveform(t, y, false);
      return;
    }

    // Motion artifact: a swing far larger than the usual pulse amplitude.
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
    _emitWaveform(t, y, event != BeatEvent.none);

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

  /// (Re)starts filtering from a clean state at sample [x].
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

  // -------------------------------------------------------------------------
  // Publishing
  // -------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // Metric computation (runs on beats / heartbeats only, not per frame)
  // -------------------------------------------------------------------------

  BiometricMetrics _buildMetrics(int t) {
    final status = _publicStatus();
    final count = _detector.ibiCount;

    if (status != AcquisitionStatus.measuring) {
      return BiometricMetrics(
        status: status,
        signalQuality: 0.0,
        beatCount: _detector.validBeats,
        ibiCount: count,
        timestampMicros: t,
      );
    }

    // No valid beat for a while: whatever is buffered is out of date.
    final stale = _lastValidBeatMicros != 0 &&
        t - _lastValidBeatMicros > _staleMicros;
    if (stale) {
      return BiometricMetrics(
        status: status,
        signalQuality: 0.0,
        beatCount: _detector.validBeats,
        ibiCount: count,
        timestampMicros: t,
      );
    }

    final double? bpm = count >= config.minBeatsForBpm ? _computeBpm(count) : null;
    final double? rmssd = _computeRmssd(count);
    final double? stress = rmssd == null
        ? null
        : stressFromRmssd(
            rmssd,
            referenceRmssd: _baselineRmssdMs ?? config.populationRmssdMs,
            steepness: config.stressSteepness,
          );

    return BiometricMetrics(
      status: status,
      bpm: bpm,
      rmssd: rmssd,
      stressIndex: stress,
      signalQuality: _computeSqi(count),
      lastIbiMs: _detector.lastIbiMs > 0 ? _detector.lastIbiMs : null,
      beatCount: _detector.validBeats,
      ibiCount: count,
      timestampMicros: t,
    );
  }

  /// Heart rate from the mean of the most recent intervals.
  double _computeBpm(int count) {
    final n = math.min(config.hrWindowBeats, count);
    var sum = 0.0;
    for (var i = count - n; i < count; i++) {
      sum += _detector.ibiAt(i);
    }
    return 60000.0 / (sum / n);
  }

  /// RMSSD over successive valid interval pairs in the recent window. Pairs
  /// that straddle a rejected beat or a signal gap are skipped.
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

  /// Signal Quality Index in [0, 1]:
  ///   completeness (buffer fill)
  ///   x (0.5 x rhythmicity + 0.5 x fraction of beats accepted)
  /// Rhythmicity falls as the coefficient of variation of the IBIs grows,
  /// because erratic intervals usually mean noise rather than physiology.
  /// This is a heuristic confidence score, not a clinical measure.
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
