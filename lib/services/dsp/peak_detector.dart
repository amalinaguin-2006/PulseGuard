// lib/services/dsp/peak_detector.dart
//
// Pulse Guard - Phase 4A: adaptive systolic peak detection and RR tracking.
//
// Works on the band-passed PPG waveform. A sample is a peak candidate when it
// is a local maximum (higher than its predecessor, not lower than its
// successor). A candidate becomes a beat when it:
//   1. exceeds an adaptive threshold: a fraction of a running peak-amplitude
//      level that decays exponentially while no beats arrive, so the
//      detector re-adapts when the signal gets weaker, and
//   2. falls outside the refractory (blanking) window after the previous
//      beat, which suppresses the dicrotic notch and other secondary bumps.
//
// Peak times are refined with parabolic interpolation. At 30 FPS one sample
// is 33 ms; without interpolation the timing quantisation alone would add
// large errors to HRV.
//
// Intervals between beats (IBI / RR, milliseconds) are validated and stored in
// a fixed-size ring buffer. Nothing is allocated per sample.

import 'dart:math' as math;
import 'dart:typed_data';

/// Result of feeding one sample to [PeakDetector.update].
enum BeatEvent {
  /// No beat at this sample.
  none,

  /// A beat was detected but there is no previous beat to measure from.
  firstBeat,

  /// A beat was detected and its interval passed validation (stored).
  validBeat,

  /// A beat was detected but its interval was rejected (missed or extra
  /// beat, or non-physiological). The interval is not stored.
  artifactBeat,
}

class PeakDetector {
  PeakDetector({
    this.refractoryMs = 280.0,
    this.minIbiMs = 285.0,
    this.maxIbiMs = 1500.0,
    this.thresholdRatio = 0.5,
    this.minAmplitude = 0.05,
    this.levelTauSeconds = 3.0,
    this.maxIbiDeviation = 0.30,
    this.maxConsecutiveRejects = 4,
  })  : assert(refractoryMs > 0),
        assert(minIbiMs > 0 && maxIbiMs > minIbiMs),
        assert(thresholdRatio > 0 && thresholdRatio < 1),
        assert(levelTauSeconds > 0),
        assert(maxIbiDeviation > 0),
        assert(maxConsecutiveRejects >= 1);

  /// Capacity of the IBI ring buffer (about 30 s of beats at 60 BPM).
  static const int capacity = 32;

  static const int _medianWindow = 8;

  /// Blanking time after a beat. 250-300 ms covers the dicrotic notch while
  /// still allowing heart rates up to about 210 BPM.
  final double refractoryMs;

  /// Shortest accepted interval (about 210 BPM).
  final double minIbiMs;

  /// Longest accepted interval (40 BPM).
  final double maxIbiMs;

  /// Threshold as a fraction of the running peak level.
  final double thresholdRatio;

  /// Absolute amplitude floor (same units as the filtered signal, i.e. 0-255
  /// pixel intensity). Peaks below this are treated as noise. Tune per
  /// device: it must sit above the sensor noise and below the real pulsatile
  /// amplitude of a good finger placement.
  final double minAmplitude;

  /// Time constant of the peak level's exponential decay.
  final double levelTauSeconds;

  /// An interval is rejected when it differs from the recent median by more
  /// than this fraction (0.30 = 30 %).
  final double maxIbiDeviation;

  /// After this many rejected intervals in a row the history is considered
  /// stale (the rhythm really changed, or the history was bad) and restarts.
  final int maxConsecutiveRejects;

  late final int _refractoryMicros = (refractoryMs * 1000.0).round();

  // Last two samples (for local-maximum detection).
  double _y0 = 0.0;
  double _y1 = 0.0;
  int _t0 = 0;
  int _t1 = 0;
  int _filled = 0;

  // Adaptive peak level.
  double _level = 0.0;

  // Beat tracking.
  bool _hasPeak = false;
  int _lastPeakMicros = 0;

  // IBI ring buffer. _cont[i] == 1 means the interval before this one was
  // also valid, i.e. the two are successive (needed for RMSSD).
  final Float64List _ibis = Float64List(capacity);
  final Uint8List _cont = Uint8List(capacity);
  final Float64List _scratch = Float64List(_medianWindow);
  int _head = 0;
  int _count = 0;
  bool _prevIntervalValid = false;
  int _consecutiveRejects = 0;

  int _validBeats = 0;
  int _artifactBeats = 0;
  double _lastIbiMs = 0.0;
  double _acceptanceEma = 1.0;
  bool _acceptanceInitialised = false;

  // -------------------------------------------------------------------------
  // Read-only state
  // -------------------------------------------------------------------------

  /// Number of intervals currently stored (0..[capacity]).
  int get ibiCount => _count;

  /// Most recent valid interval in ms (0 if none yet).
  double get lastIbiMs => _lastIbiMs;

  /// Interval at [index], where 0 is the oldest and [ibiCount] - 1 the newest.
  double ibiAt(int index) {
    assert(index >= 0 && index < _count);
    return _ibis[(_head - _count + index + capacity) % capacity];
  }

  /// True if the interval at [index] directly follows the one at [index] - 1
  /// with no rejected beat in between. Successive differences (RMSSD) must
  /// only use such pairs.
  bool isContinuousWithPrevious(int index) {
    assert(index >= 0 && index < _count);
    return _cont[(_head - _count + index + capacity) % capacity] == 1;
  }

  /// Chronological list snapshot of all currently stored intervals (ms).
  List<double> get recentIbis {
    final list = <double>[];
    for (var i = 0; i < _count; i++) {
      list.add(ibiAt(i));
    }
    return list;
  }

  /// Valid intervals accepted since the last [reset].
  int get validBeats => _validBeats;

  /// Intervals rejected since the last [reset].
  int get artifactBeats => _artifactBeats;

  /// Smoothed fraction (0-1) of recent intervals that were accepted.
  double get acceptanceRatio => _acceptanceEma;

  /// Current adaptive peak-amplitude level (0 until the first beat).
  double get signalLevel => _level;

  // -------------------------------------------------------------------------
  // Control
  // -------------------------------------------------------------------------

  /// Clears everything (finger removed, new session).
  void reset() {
    _y0 = 0.0;
    _y1 = 0.0;
    _t0 = 0;
    _t1 = 0;
    _filled = 0;
    _level = 0.0;
    _hasPeak = false;
    _lastPeakMicros = 0;
    _head = 0;
    _count = 0;
    _prevIntervalValid = false;
    _consecutiveRejects = 0;
    _validBeats = 0;
    _artifactBeats = 0;
    _lastIbiMs = 0.0;
    _acceptanceEma = 1.0;
    _acceptanceInitialised = false;
  }

  /// Declares that the signal was interrupted (dropped frames, motion
  /// artifact, saturation). Stored intervals are kept, but the next beat
  /// starts a fresh measurement (no interval is formed across the gap) and
  /// successive-difference pairs are not formed across it either.
  void markDiscontinuity() {
    _filled = 0;
    _hasPeak = false;
    _prevIntervalValid = false;
  }

  // -------------------------------------------------------------------------
  // Main entry point
  // -------------------------------------------------------------------------

  /// Feeds one filtered sample [y] taken at [timestampMicros]. Timestamps
  /// must be strictly increasing. Detection lags by one sample, because a
  /// peak is only known once the following sample has been seen.
  BeatEvent update(double y, int timestampMicros) {
    if (!y.isFinite) return BeatEvent.none;
    var event = BeatEvent.none;

    // Exponential decay of the peak level based on real elapsed time.
    if (_filled >= 1 && _level > 0.0) {
      final dtSeconds = (timestampMicros - _t1) * 1e-6;
      if (dtSeconds > 0.0) {
        _level *= math.exp(-dtSeconds / levelTauSeconds);
      }
    }

    // Local maximum at the middle sample?
    if (_filled >= 2 && _y1 > _y0 && _y1 >= y) {
      event = _evaluateCandidate(_y0, _y1, y, _t0, _t1, timestampMicros);
    }

    _y0 = _y1;
    _t0 = _t1;
    _y1 = y;
    _t1 = timestampMicros;
    if (_filled < 2) _filled++;

    return event;
  }

  BeatEvent _evaluateCandidate(
    double y0,
    double y1,
    double y2,
    int t0,
    int t1,
    int t2,
  ) {
    final threshold = math.max(minAmplitude, thresholdRatio * _level);
    if (y1 < threshold) return BeatEvent.none;

    // Parabolic interpolation through the three samples around the peak:
    // vertex offset in samples, in [-0.5, 0.5].
    var offset = 0.0;
    final denominator = y0 - 2.0 * y1 + y2;
    if (denominator < -1e-12) {
      offset = 0.5 * (y0 - y2) / denominator;
      if (offset > 0.5) offset = 0.5;
      if (offset < -0.5) offset = -0.5;
    }
    final peakMicros = t1 + (offset * (t2 - t0) * 0.5).round();

    // Refractory blanking: ignore bumps too close to the previous beat
    // (dicrotic notch, noise).
    if (_hasPeak && peakMicros - _lastPeakMicros < _refractoryMicros) {
      return BeatEvent.none;
    }

    _updateLevel(y1);

    if (!_hasPeak) {
      _hasPeak = true;
      _lastPeakMicros = peakMicros;
      _prevIntervalValid = false;
      return BeatEvent.firstBeat;
    }

    final ibiMs = (peakMicros - _lastPeakMicros) / 1000.0;
    _lastPeakMicros = peakMicros;
    return _handleInterval(ibiMs) ? BeatEvent.validBeat : BeatEvent.artifactBeat;
  }

  /// Moves the peak level toward the new peak, capping the influence of a
  /// single outlier spike.
  void _updateLevel(double amplitude) {
    var a = amplitude;
    if (_level > 1e-9 && a > 2.5 * _level) a = 2.5 * _level;
    _level = _level <= 1e-9 ? a : _level + 0.3 * (a - _level);
  }

  /// Validates an interval; returns true if it was stored.
  bool _handleInterval(double ibiMs) {
    var ok = ibiMs >= minIbiMs && ibiMs <= maxIbiMs;
    if (ok && _count >= 3) {
      final median = _recentMedian();
      if ((ibiMs - median).abs() > maxIbiDeviation * median) ok = false;
    }

    if (ok) {
      _consecutiveRejects = 0;
      _push(ibiMs, _prevIntervalValid);
      _prevIntervalValid = true;
      _validBeats++;
      _lastIbiMs = ibiMs;
      _updateAcceptance(true);
      return true;
    }

    _artifactBeats++;
    _prevIntervalValid = false;
    _consecutiveRejects++;
    _updateAcceptance(false);

    if (_consecutiveRejects >= maxConsecutiveRejects) {
      // Many rejections in a row: the stored history no longer matches the
      // signal. Start over, and keep this interval if it is physiological.
      _consecutiveRejects = 0;
      _count = 0;
      _head = 0;
      if (ibiMs >= minIbiMs && ibiMs <= maxIbiMs) {
        _push(ibiMs, false);
        _prevIntervalValid = true;
        _validBeats++;
        _lastIbiMs = ibiMs;
        return true;
      }
    }
    return false;
  }

  void _updateAcceptance(bool accepted) {
    final x = accepted ? 1.0 : 0.0;
    if (!_acceptanceInitialised) {
      _acceptanceEma = x;
      _acceptanceInitialised = true;
    } else {
      _acceptanceEma += 0.15 * (x - _acceptanceEma);
    }
  }

  void _push(double ibiMs, bool continuous) {
    _ibis[_head] = ibiMs;
    _cont[_head] = continuous ? 1 : 0;
    _head = (_head + 1) % capacity;
    if (_count < capacity) _count++;
  }

  /// Median of the most recent (up to 8) stored intervals. Uses a tiny
  /// insertion sort on a preallocated scratch buffer.
  double _recentMedian() {
    final n = math.min(_count, _medianWindow);
    for (var i = 0; i < n; i++) {
      _scratch[i] = ibiAt(_count - n + i);
    }
    for (var i = 1; i < n; i++) {
      final v = _scratch[i];
      var j = i - 1;
      while (j >= 0 && _scratch[j] > v) {
        _scratch[j + 1] = _scratch[j];
        j--;
      }
      _scratch[j + 1] = v;
    }
    final mid = n >> 1;
    return n.isOdd ? _scratch[mid] : 0.5 * (_scratch[mid - 1] + _scratch[mid]);
  }
}
