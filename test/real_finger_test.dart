// test/real_finger_test.dart
//
// PulseGuard — Biometric Real-Finger Anti-Spoofing Unit Tests

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_guard/services/dsp/real_finger_checker.dart';

void main() {
  group('RealFingerChecker Biometric Anti-Spoofing Engine', () {
    late RealFingerChecker checker;

    setUp(() {
      checker = RealFingerChecker(
        windowDurationMs: 6000,
        minPerfusionPercent: 0.05,
        maxPerfusionPercent: 8.0,
        minAutocorrFundamental: 0.40,
        minAutocorrHarmonic: 0.20,
        minBpm: 42.0,
        maxBpm: 210.0,
        consecutivePassesRequired: 2,
        consecutiveFailsToRevoke: 3,
      );
    });

    test('Passes for synthetic 72 BPM pulsatile signal with physiological AC/DC ratio', () {
      const sampleRateHz = 30.0;
      const bpm = 72.0;
      const freqHz = bpm / 60.0; // 1.2 Hz
      const dcLevel = 180.0;
      const acAmplitude = 2.5; // PI ~ (5.0 / 180.0) * 100% ~ 2.77% (within [0.05%, 8.0%])

      final totalSamples = (sampleRateHz * 6.0).round(); // 180 samples (6 seconds)

      for (var i = 0; i < totalSamples; i++) {
        final t = i / sampleRateHz;
        // Heart pulse with fundamental + modest harmonic
        final ac = acAmplitude * math.sin(2 * math.pi * freqHz * t) +
            (acAmplitude * 0.25) * math.sin(4 * math.pi * freqHz * t);
        final rawRed = dcLevel + ac;

        checker.addSample(
          timestampMicros: (t * 1000000).round(),
          rawRed: rawRed,
          filteredRed: ac,
        );
      }

      // First evaluation
      final res1 = checker.evaluate(sampleRateHz: sampleRateHz);
      expect(res1.passed, isTrue, reason: 'First evaluation of 72 BPM should pass: ${res1.failureReason}');
      expect(checker.isVerified, isFalse, reason: 'Requires 2 consecutive passes');

      // Second evaluation
      final res2 = checker.evaluate(sampleRateHz: sampleRateHz);
      expect(res2.passed, isTrue, reason: 'Second evaluation of 72 BPM should pass: ${res2.failureReason}');
      expect(checker.isVerified, isTrue, reason: 'Should verify after 2 consecutive passes');
      expect(res2.perfusionIndex, greaterThanOrEqualTo(0.05));
      expect(res2.perfusionIndex, lessThanOrEqualTo(8.0));
      expect(res2.maxAutocorr, greaterThanOrEqualTo(0.40));
      expect(res2.harmonicAutocorr, greaterThanOrEqualTo(0.20));
    });

    test('Fails for static DC signal (red paper / red tape / static plastic spoof)', () {
      const sampleRateHz = 30.0;
      const dcLevel = 220.0;
      final totalSamples = (sampleRateHz * 6.0).round();

      for (var i = 0; i < totalSamples; i++) {
        final t = i / sampleRateHz;
        // Zero AC pulsatility
        checker.addSample(
          timestampMicros: (t * 1000000).round(),
          rawRed: dcLevel,
          filteredRed: 0.0,
        );
      }

      final res = checker.evaluate(sampleRateHz: sampleRateHz);
      expect(res.passed, isFalse);
      expect(checker.isVerified, isFalse);
    });

    test('Fails for purely random noise signal (no coherent cardiac autocorrelation)', () {
      const sampleRateHz = 30.0;
      final random = math.Random(42);
      final totalSamples = (sampleRateHz * 6.0).round();

      for (var i = 0; i < totalSamples; i++) {
        final t = i / sampleRateHz;
        final noiseAc = (random.nextDouble() - 0.5) * 4.0;
        final rawRed = 150.0 + noiseAc;

        checker.addSample(
          timestampMicros: (t * 1000000).round(),
          rawRed: rawRed,
          filteredRed: noiseAc,
        );
      }

      final res = checker.evaluate(sampleRateHz: sampleRateHz);
      expect(res.passed, isFalse);
      expect(checker.isVerified, isFalse);
      expect(res.maxAutocorr, lessThan(0.40));
    });

    test('Fails when window has insufficient samples (< 30 samples)', () {
      const sampleRateHz = 30.0;
      // Feed only 20 samples (< 30)
      for (var i = 0; i < 20; i++) {
        final t = i / sampleRateHz;
        checker.addSample(
          timestampMicros: (t * 1000000).round(),
          rawRed: 180.0,
          filteredRed: 1.0,
        );
      }

      final res = checker.evaluate(sampleRateHz: sampleRateHz);
      expect(res.passed, isFalse);
      expect(res.failureReason, contains('Insufficient window samples'));
      expect(checker.isVerified, isFalse);
    });

    test('Rejects artificial clock generator with RMSSD < 1.0 ms across 15+ beats', () {
      const sampleRateHz = 30.0;
      const bpm = 72.0;
      const freqHz = bpm / 60.0;
      const totalSamples = 180;

      for (var i = 0; i < totalSamples; i++) {
        final t = i / sampleRateHz;
        final ac = 2.0 * math.sin(2 * math.pi * freqHz * t);
        checker.addSample(
          timestampMicros: (t * 1000000).round(),
          rawRed: 180.0 + ac,
          filteredRed: ac,
        );
      }

      // Simulate a synthetic frequency generator with 0.1 ms jitter
      final res = checker.evaluate(
        sampleRateHz: sampleRateHz,
        currentRmssdMs: 0.2,
        validBeatCount: 16,
      );

      expect(res.passed, isFalse);
      expect(res.failureReason, contains('artificial generator detected'));
    });
  });
}
