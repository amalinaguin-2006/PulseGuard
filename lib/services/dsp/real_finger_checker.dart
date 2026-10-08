/// PulseGuard — Real-Finger Biometric Verification Engine
///
/// Implements biometric anti-spoofing to reject red stickers, colored paper,
/// artificial screens, or static plastic objects placed over the camera lens.
///
/// Requirements (evaluated over a rolling 6-second window):
///   1. Perfusion Index (PI = AC/DC * 100%) between 0.05% and 8.0%.
///   2. Autocorrelation peak r(tau_1) >= 0.40 at fundamental lag in 42–210 BPM.
///   3. Harmonic peak r(2*tau_1) >= 0.20 one period later.
///   4. Rejection if RMSSD < 1.0 ms across 15+ detected beats (rejects synthetic pulse generators).
///   5. State machine: Verify after 2 consecutive passing checks (evaluated 1/sec),
///      revoke after 3 consecutive failing checks.
library;

import 'dart:math' as math;

/// Single point stored in the rolling 6-second window.
class _PpgWindowSample {
  final int timestampMicros;
  final double rawDc; // Unfiltered raw red channel intensity
  final double filteredAc; // Bandpass filtered pulsatile AC component

  const _PpgWindowSample({
    required this.timestampMicros,
    required this.rawDc,
    required this.filteredAc,
  });
}

/// Result of an individual real-finger verification evaluation.
class RealFingerCheckResult {
  final bool passed;
  final double perfusionIndex;
  final double maxAutocorr;
  final double harmonicAutocorr;
  final String? failureReason;

  const RealFingerCheckResult({
    required this.passed,
    required this.perfusionIndex,
    required this.maxAutocorr,
    required this.harmonicAutocorr,
    this.failureReason,
  });
}

/// Orchestrates real-finger biometric verification over a rolling 6-second window.
class RealFingerChecker {
  RealFingerChecker({
    this.windowDurationMs = 6000,
    this.minPerfusionPercent = 0.05,
    this.maxPerfusionPercent = 8.0,
    this.minAutocorrFundamental = 0.40,
    this.minAutocorrHarmonic = 0.20,
    this.minBpm = 42.0,
    this.maxBpm = 210.0,
    this.consecutivePassesRequired = 2,
    this.consecutiveFailsToRevoke = 3,
  });

  final int windowDurationMs;
  final double minPerfusionPercent;
  final double maxPerfusionPercent;
  final double minAutocorrFundamental;
  final double minAutocorrHarmonic;
  final double minBpm;
  final double maxBpm;
  final int consecutivePassesRequired;
  final int consecutiveFailsToRevoke;

  final List<_PpgWindowSample> _window = <_PpgWindowSample>[];

  int _consecutivePasses = 0;
  int _consecutiveFails = 0;
  bool _isVerified = false;

  int _lastEvaluationMicros = 0;

  /// True when anti-spoofing confirms the sensor is viewing living human tissue.
  bool get isVerified => _isVerified;

  int get consecutivePasses => _consecutivePasses;
  int get consecutiveFails => _consecutiveFails;

  /// Resets all window buffers and verification state.
  void reset() {
    _window.clear();
    _consecutivePasses = 0;
    _consecutiveFails = 0;
    _isVerified = false;
    _lastEvaluationMicros = 0;
  }

  /// Appends a new sample to the rolling 6-second window.
  void addSample({
    required int timestampMicros,
    required double rawRed,
    required double filteredRed,
  }) {
    _window.add(_PpgWindowSample(
      timestampMicros: timestampMicros,
      rawDc: rawRed,
      filteredAc: filteredRed,
    ));

    // Prune samples older than the 6-second window
    final cutoff = timestampMicros - (windowDurationMs * 1000);
    while (_window.isNotEmpty && _window.first.timestampMicros < cutoff) {
      _window.removeAt(0);
    }
  }

  /// Evaluates verification conditions. Should be called approximately once per second.
  RealFingerCheckResult evaluate({
    required double sampleRateHz,
    double? currentRmssdMs,
    int validBeatCount = 0,
  }) {
    if (_window.length < 30 || sampleRateHz < 10.0) {
      _recordFail();
      return const RealFingerCheckResult(
        passed: false,
        perfusionIndex: 0.0,
        maxAutocorr: 0.0,
        harmonicAutocorr: 0.0,
        failureReason: 'Insufficient window samples (< 30)',
      );
    }

    // 1. Calculate DC (mean of raw red) and AC (peak-to-peak of filtered)
    var sumDc = 0.0;
    var minAc = double.infinity;
    var maxAc = -double.infinity;

    for (final s in _window) {
      sumDc += s.rawDc;
      if (s.filteredAc < minAc) minAc = s.filteredAc;
      if (s.filteredAc > maxAc) maxAc = s.filteredAc;
    }

    final meanDc = sumDc / _window.length;
    final peakToPeakAc = maxAc > minAc ? (maxAc - minAc) : 0.0;

    // Perfusion Index (PI = (AC / DC) * 100%)
    final pi = meanDc > 1.0 ? (peakToPeakAc / meanDc) * 100.0 : 0.0;

    if (pi < minPerfusionPercent || pi > maxPerfusionPercent) {
      _recordFail();
      return RealFingerCheckResult(
        passed: false,
        perfusionIndex: pi,
        maxAutocorr: 0.0,
        harmonicAutocorr: 0.0,
        failureReason: 'Perfusion index ${pi.toStringAsFixed(3)}% outside '
            '[$minPerfusionPercent%, $maxPerfusionPercent%]',
      );
    }

    // 2. Reject artificial clock/generator: RMSSD < 1.0 ms over 15+ beats
    if (validBeatCount >= 15 && currentRmssdMs != null && currentRmssdMs < 1.0) {
      _recordFail();
      return RealFingerCheckResult(
        passed: false,
        perfusionIndex: pi,
        maxAutocorr: 0.0,
        harmonicAutocorr: 0.0,
        failureReason: 'RMSSD (${currentRmssdMs.toStringAsFixed(2)} ms) < 1.0 ms '
            'over $validBeatCount beats (artificial generator detected)',
      );
    }

    // 3. Autocorrelation analysis on filtered AC component
    final n = _window.length;
    var acSum = 0.0;
    for (var i = 0; i < n; i++) {
      acSum += _window[i].filteredAc;
    }
    final acMean = acSum / n;

    var varianceSum = 0.0;
    for (var i = 0; i < n; i++) {
      final diff = _window[i].filteredAc - acMean;
      varianceSum += diff * diff;
    }

    if (varianceSum <= 1e-6) {
      _recordFail();
      return RealFingerCheckResult(
        passed: false,
        perfusionIndex: pi,
        maxAutocorr: 0.0,
        harmonicAutocorr: 0.0,
        failureReason: 'Near-zero signal variance (flatline/sticker)',
      );
    }

    // Lag search bounds corresponding to 42 - 210 BPM
    final minLag = (sampleRateHz * 60.0 / maxBpm).round();
    final maxLag = (sampleRateHz * 60.0 / minBpm).round().clamp(minLag + 2, n - 2);

    var bestLag = minLag;
    var maxR = -1.0;

    for (var lag = minLag; lag <= maxLag; lag++) {
      var crossSum = 0.0;
      for (var i = 0; i < n - lag; i++) {
        crossSum += (_window[i].filteredAc - acMean) *
            (_window[i + lag].filteredAc - acMean);
      }
      final r = crossSum / varianceSum;
      if (r > maxR) {
        maxR = r;
        bestLag = lag;
      }
    }

    if (maxR < minAutocorrFundamental) {
      _recordFail();
      return RealFingerCheckResult(
        passed: false,
        perfusionIndex: pi,
        maxAutocorr: maxR,
        harmonicAutocorr: 0.0,
        failureReason: 'Fundamental autocorrelation ${maxR.toStringAsFixed(2)} < '
            '$minAutocorrFundamental',
      );
    }

    // 4. Check harmonic peak at one period later (2 * bestLag)
    final harmonicTargetLag = bestLag * 2;
    final searchDelta = math.max(2, (bestLag * 0.15).round());
    final hMin = (harmonicTargetLag - searchDelta).clamp(minLag, n - 2);
    final hMax = (harmonicTargetLag + searchDelta).clamp(minLag, n - 2);

    var maxHarmonicR = -1.0;
    for (var lag = hMin; lag <= hMax; lag++) {
      var crossSum = 0.0;
      for (var i = 0; i < n - lag; i++) {
        crossSum += (_window[i].filteredAc - acMean) *
            (_window[i + lag].filteredAc - acMean);
      }
      final r = crossSum / varianceSum;
      if (r > maxHarmonicR) {
        maxHarmonicR = r;
      }
    }

    if (maxHarmonicR < minAutocorrHarmonic) {
      _recordFail();
      return RealFingerCheckResult(
        passed: false,
        perfusionIndex: pi,
        maxAutocorr: maxR,
        harmonicAutocorr: maxHarmonicR,
        failureReason: 'Harmonic autocorrelation ${maxHarmonicR.toStringAsFixed(2)} < '
            '$minAutocorrHarmonic',
      );
    }

    // All conditions met: Pass!
    _recordPass();
    return RealFingerCheckResult(
      passed: true,
      perfusionIndex: pi,
      maxAutocorr: maxR,
      harmonicAutocorr: maxHarmonicR,
    );
  }

  void _recordPass() {
    _consecutivePasses++;
    _consecutiveFails = 0;
    if (_consecutivePasses >= consecutivePassesRequired) {
      _isVerified = true;
    }
  }

  void _recordFail() {
    _consecutiveFails++;
    _consecutivePasses = 0;
    if (_consecutiveFails >= consecutiveFailsToRevoke) {
      _isVerified = false;
    }
  }

  /// Helper to check if a periodic 1-second check is due.
  bool isCheckDue(int currentTimestampMicros) {
    if (_lastEvaluationMicros == 0 ||
        currentTimestampMicros - _lastEvaluationMicros >= 1000000) {
      _lastEvaluationMicros = currentTimestampMicros;
      return true;
    }
    return false;
  }
}
