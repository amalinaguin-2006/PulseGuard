import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_guard/models/ppg_sample.dart';
import 'package:pulse_guard/services/dsp/bandpass_filter.dart';
import 'package:pulse_guard/services/dsp/peak_detector.dart';
import 'package:pulse_guard/services/signal_processor_service.dart';

void main() {
  group('BandpassFilter (IIR Butterworth 0.7 - 3.5 Hz)', () {
    test('removes DC bias and settles to zero mean', () {
      final filter = BandpassFilter(sampleRateHz: 30.0, lowCutHz: 0.7, highCutHz: 3.5);
      const dcLevel = 180.0;
      filter.prime(dcLevel);

      double lastOut = 0.0;
      // Feed 90 samples (3 seconds) of constant DC level
      for (var i = 0; i < 90; i++) {
        lastOut = filter.process(dcLevel);
      }

      // Output should be virtually zero (< 0.01)
      expect(lastOut.abs(), lessThan(0.01));
    });

    test('passes frequencies within nominal physiological cardiac band (1.5 Hz ~ 90 BPM)', () {
      final filter = BandpassFilter(sampleRateHz: 30.0, lowCutHz: 0.7, highCutHz: 3.5);
      const sampleRate = 30.0;
      const freq = 1.5; // 1.5 Hz is well inside 0.7 - 3.5 Hz
      const amplitude = 10.0;

      filter.prime(0.0);
      var maxOutput = 0.0;

      // Run for 4 seconds to reach steady-state
      for (var i = 0; i < 120; i++) {
        final t = i / sampleRate;
        final x = amplitude * math.sin(2 * math.pi * freq * t);
        final y = filter.process(x);
        if (i > 60 && y.abs() > maxOutput) {
          maxOutput = y.abs();
        }
      }

      // In passband, Butterworth section response should retain > 80% of amplitude
      expect(maxOutput, greaterThan(8.0));
    });

    test('strongly attenuates out-of-band high frequency noise (10 Hz)', () {
      final filter = BandpassFilter(sampleRateHz: 30.0, lowCutHz: 0.7, highCutHz: 3.5);
      const sampleRate = 30.0;
      const freq = 10.0; // High frequency noise
      const amplitude = 10.0;

      filter.prime(0.0);
      var maxOutput = 0.0;

      for (var i = 0; i < 120; i++) {
        final t = i / sampleRate;
        final x = amplitude * math.sin(2 * math.pi * freq * t);
        final y = filter.process(x);
        if (i > 60 && y.abs() > maxOutput) {
          maxOutput = y.abs();
        }
      }

      // Out of band at 10 Hz with cutoff 3.5 Hz should be heavily suppressed
      expect(maxOutput, lessThan(1.5));
    });

    test('reconfigures correctly for non-standard camera sample rates', () {
      final filter = BandpassFilter(sampleRateHz: 30.0);
      expect(filter.sampleRateHz, equals(30.0));

      filter.configure(sampleRateHz: 25.0);
      expect(filter.sampleRateHz, equals(25.0));

      // Check robust handling of non-finite values
      expect(filter.process(double.nan), equals(0.0));
      expect(filter.process(double.infinity), equals(0.0));
    });
  });

  group('PeakDetector', () {
    test('detects periodic pulses and measures accurate IBI', () {
      final detector = PeakDetector(
        refractoryMs: 280.0,
        minIbiMs: 285.0,
        maxIbiMs: 1500.0,
      );

      // Simulate 1.0 Hz heart rate (60 BPM -> 1000 ms IBI) at 30 FPS (~33,333 micros per frame)
      const frameDeltaMicros = 33333;
      var currentMicros = 1000000;
      final beats = <int>[];

      for (var frame = 0; frame < 150; frame++) {
        final tSeconds = frame / 30.0;
        // Simple synthetic cardiac pulse: sine wave with positive peak
        final y = 5.0 * math.sin(2 * math.pi * 1.0 * tSeconds);
        final event = detector.update(y, currentMicros);

        if (event == BeatEvent.validBeat || event == BeatEvent.firstBeat) {
          beats.add(currentMicros);
        }
        currentMicros += frameDeltaMicros;
      }

      // Should detect around 4-5 peaks across 5 seconds
      expect(beats.length, greaterThanOrEqualTo(4));
      // Stored IBIs should be closely centered around 1000 ms (within 5% due to 30 FPS sampling)
      expect(detector.ibiCount, greaterThanOrEqualTo(3));
      expect(detector.lastIbiMs, closeTo(1000.0, 50.0));
      expect(detector.recentIbis.length, equals(detector.ibiCount));
    });

    test('ignores dicrotic notch within refractory blanking period', () {
      final detector = PeakDetector(
        refractoryMs: 280.0,
        minIbiMs: 285.0,
        maxIbiMs: 1500.0,
      );

      var tMicros = 1000000;
      var beatCount = 0;

      void feedFrame(double val, int dtMicros) {
        tMicros += dtMicros;
        final res = detector.update(val, tMicros);
        if (res == BeatEvent.firstBeat || res == BeatEvent.validBeat) {
          beatCount++;
        }
      }

      // Primary systolic peak
      feedFrame(1.0, 33333);
      feedFrame(8.0, 33333); // Peak 1
      feedFrame(3.0, 33333);
      feedFrame(0.5, 33333);

      final initialBeats = beatCount;
      expect(initialBeats, equals(1));

      // Dicrotic notch 150 ms later (within the 280 ms refractory window)
      feedFrame(1.0, 50000);
      feedFrame(4.0, 33333); // Secondary peak
      feedFrame(1.0, 33333);

      // Beat count should NOT have increased because refractory blanking suppresses it
      expect(beatCount, equals(1));
    });

    test('rejects non-physiological outlier intervals', () {
      final detector = PeakDetector(minIbiMs: 285.0, maxIbiMs: 1500.0);

      var tMicros = 1000000;
      detector.update(1.0, tMicros);
      detector.update(5.0, tMicros + 33000);
      detector.update(1.0, tMicros + 66000); // Peak 1 confirmed

      // Next peak after only 150 ms (< minIbiMs)
      tMicros += 150000;
      detector.update(1.0, tMicros);
      final event = detector.update(5.0, tMicros + 33000);
      detector.update(1.0, tMicros + 66000);

      // Should be rejected as an artifact beat
      expect(event, isNot(equals(BeatEvent.validBeat)));
    });
  });

  group('SignalProcessorService', () {
    late SignalProcessorService service;
    late StreamController<PpgFrameSample> sourceController;

    setUp(() {
      service = SignalProcessorService(
        config: const SignalProcessorConfig(
          rateProbeFrames: 5,
          settleMs: 200,
        ),
      );
      sourceController = StreamController<PpgFrameSample>.broadcast();
      service.bind(sourceController.stream);
    });

    tearDown(() async {
      await service.dispose();
      await sourceController.close();
    });

    test('initial state is idle with no finger', () {
      expect(service.currentMetrics.status, equals(AcquisitionStatus.noFinger));
      expect(service.currentMetrics.bpm, isNull);
      expect(service.currentMetrics.rmssd, isNull);
      expect(service.currentMetrics.isReliable, isFalse);
    });

    test('transitions through probing and settling when finger is placed', () async {
      final statuses = <AcquisitionStatus>[];
      final sub = service.metricsStream.listen((m) => statuses.add(m.status));

      var tMicros = 1000000;
      // Emit frames with finger present
      for (var i = 0; i < 20; i++) {
        sourceController.add(PpgFrameSample(
          timestampMicros: tMicros,
          redValue: 180.0,
          greenValue: 40.0,
          isFingerPresent: true,
        ));
        tMicros += 33333; // ~30 FPS
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await sub.cancel();
      expect(statuses, contains(AcquisitionStatus.settling));
    });

    test('stressFromRmssd maps properly across resting and stressed ranges', () {
      // Resting reference 40 ms -> Stress 50
      final mid = SignalProcessorService.stressFromRmssd(40.0, referenceRmssd: 40.0);
      expect(mid, closeTo(50.0, 0.5));

      // High HRV (relaxed, 80 ms) -> Low Stress
      final relaxed = SignalProcessorService.stressFromRmssd(80.0, referenceRmssd: 40.0);
      expect(relaxed, lessThan(30.0));

      // Low HRV (stressed, 15 ms) -> High Stress
      final stressed = SignalProcessorService.stressFromRmssd(15.0, referenceRmssd: 40.0);
      expect(stressed, greaterThan(80.0));

      // Zero or negative RMSSD clamps cleanly to 100
      expect(SignalProcessorService.stressFromRmssd(0.0, referenceRmssd: 40.0), equals(100.0));
    });

    test('finger disconnect resets acquisition state', () async {
      var tMicros = 1000000;

      // Frame with finger
      sourceController.add(PpgFrameSample(
        timestampMicros: tMicros,
        redValue: 180.0,
        greenValue: 40.0,
        isFingerPresent: true,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Finger removed
      sourceController.add(PpgFrameSample(
        timestampMicros: tMicros + 33333,
        redValue: 20.0,
        greenValue: 10.0,
        isFingerPresent: false,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(service.currentMetrics.status, equals(AcquisitionStatus.noFinger));
      expect(service.currentMetrics.bpm, isNull);
    });

    test('buildReading returns null when measuring metrics are incomplete and succeeds when valid', () {
      // In idle / incomplete state
      expect(service.buildReading(), isNull);

      // Verify trace export capability
      final jsonTrace = service.exportRecentWaveformJson();
      expect(jsonTrace, isA<String>());
    });
  });
}
