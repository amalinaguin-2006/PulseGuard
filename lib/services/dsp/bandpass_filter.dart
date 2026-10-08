// lib/services/dsp/bandpass_filter.dart
//
// Pulse Guard - Phase 4A: pure-Dart IIR Butterworth bandpass filter.
//
// Passband 0.7-3.5 Hz (about 42-210 BPM). Built as a cascade of two
// second-order Butterworth sections:
//   * high-pass at the low cutoff  -> removes DC level and slow baseline drift
//   * low-pass at the high cutoff  -> removes sensor jitter / high-frequency noise
// Each section is a biquad in Direct Form II Transposed, designed with the
// bilinear transform (with frequency pre-warping). Processing one sample is
// about 10 multiply-adds and allocates nothing.
//
// Note: an IIR filter delays the waveform by a roughly constant group delay.
// Absolute peak times are therefore shifted slightly, but inter-beat
// intervals (differences between peak times) are unaffected.

import 'dart:math' as math;

/// Second-order IIR section (biquad), Direct Form II Transposed.
class Biquad {
  // Butterworth quality factor for a 2nd-order section: 1 / sqrt(2).
  static final double _butterworthQ = 1.0 / math.sqrt2;

  double _b0 = 1.0;
  double _b1 = 0.0;
  double _b2 = 0.0;
  double _a1 = 0.0;
  double _a2 = 0.0;

  double _z1 = 0.0;
  double _z2 = 0.0;

  /// Designs a Butterworth low-pass at [cutoffHz] and clears the state.
  void designLowpass(double sampleRateHz, double cutoffHz) {
    final k = _prewarp(sampleRateHz, cutoffHz);
    final norm = 1.0 / (1.0 + k / _butterworthQ + k * k);
    _b0 = k * k * norm;
    _b1 = 2.0 * _b0;
    _b2 = _b0;
    _a1 = 2.0 * (k * k - 1.0) * norm;
    _a2 = (1.0 - k / _butterworthQ + k * k) * norm;
    reset();
  }

  /// Designs a Butterworth high-pass at [cutoffHz] and clears the state.
  void designHighpass(double sampleRateHz, double cutoffHz) {
    final k = _prewarp(sampleRateHz, cutoffHz);
    final norm = 1.0 / (1.0 + k / _butterworthQ + k * k);
    _b0 = norm;
    _b1 = -2.0 * norm;
    _b2 = norm;
    _a1 = 2.0 * (k * k - 1.0) * norm;
    _a2 = (1.0 - k / _butterworthQ + k * k) * norm;
    reset();
  }

  static double _prewarp(double sampleRateHz, double cutoffHz) {
    if (!(sampleRateHz > 0) || !(cutoffHz > 0) || cutoffHz >= sampleRateHz / 2) {
      throw ArgumentError(
        'Cutoff ($cutoffHz Hz) must be in (0, ${sampleRateHz / 2}) Hz '
        'for a sample rate of $sampleRateHz Hz.',
      );
    }
    return math.tan(math.pi * cutoffHz / sampleRateHz);
  }

  /// Filters one sample.
  double process(double x) {
    if (!x.isFinite) return 0.0;
    final y = _b0 * x + _z1;
    _z1 = _b1 * x - _a1 * y + _z2;
    _z2 = _b2 * x - _a2 * y;
    return y;
  }

  /// Clears the internal state (output restarts from zero).
  void reset() {
    _z1 = 0.0;
    _z2 = 0.0;
  }

  /// Sets the state to the steady state for a constant input [x] and returns
  /// the corresponding output. Avoids the large start-up transient you would
  /// otherwise get when the first sample is far from zero (camera values sit
  /// around 100-255, not 0).
  double prime(double x) {
    if (!x.isFinite) return 0.0;
    final dcGain = (_b0 + _b1 + _b2) / (1.0 + _a1 + _a2);
    final y = dcGain * x;
    _z2 = _b2 * x - _a2 * y;
    _z1 = _b1 * x - _a1 * y + _z2;
    return y;
  }
}

/// Butterworth-style bandpass: 2nd-order high-pass followed by 2nd-order
/// low-pass (4th order overall).
class BandpassFilter {
  BandpassFilter({
    double sampleRateHz = 30.0,
    this.lowCutHz = 0.7,
    this.highCutHz = 3.5,
  }) : _sampleRateHz = sampleRateHz {
    configure(sampleRateHz: sampleRateHz);
  }

  final Biquad _highpass = Biquad();
  final Biquad _lowpass = Biquad();

  double _sampleRateHz;

  /// Lower cutoff in Hz.
  final double lowCutHz;

  /// Upper cutoff in Hz.
  final double highCutHz;

  /// Sample rate the filter is currently designed for.
  double get sampleRateHz => _sampleRateHz;

  /// Re-designs both sections for [sampleRateHz] (e.g. the measured camera
  /// frame rate) and clears the state. Throws [ArgumentError] when the
  /// cutoffs are not valid for that rate (the high cutoff must be below
  /// Nyquist, so the rate must exceed 7 Hz for a 3.5 Hz cutoff).
  void configure({required double sampleRateHz}) {
    if (lowCutHz >= highCutHz) {
      throw ArgumentError('lowCutHz must be below highCutHz.');
    }
    _highpass.designHighpass(sampleRateHz, lowCutHz);
    _lowpass.designLowpass(sampleRateHz, highCutHz);
    _sampleRateHz = sampleRateHz;
  }

  /// Filters one sample. The output is zero-mean pulsatile signal.
  double process(double x) {
    if (!x.isFinite) return 0.0;
    return _lowpass.process(_highpass.process(x));
  }

  /// Clears all state.
  void reset() {
    _highpass.reset();
    _lowpass.reset();
  }

  /// Initialises the filter as if it had been fed the constant value [x]
  /// forever. Call with the first raw sample so the output starts near zero
  /// instead of ringing for several seconds.
  void prime(double x) {
    if (!x.isFinite) return;
    final highpassOut = _highpass.prime(x);
    _lowpass.prime(highpassOut);
  }
}
