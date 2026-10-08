import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_guard/models/ppg_sample.dart';
import 'package:pulse_guard/services/ppg_camera_service.dart';

void main() {
  group('PpgFrameSample model tests', () {
    test('instantiates and provides correct timestamp and channels', () {
      final sample = PpgFrameSample(
        timestampMicros: 1700000000000000,
        redValue: 185.5,
        greenValue: 42.1,
        isFingerPresent: true,
      );

      expect(sample.timestampMicros, equals(1700000000000000));
      expect(sample.timestamp, equals(DateTime.fromMicrosecondsSinceEpoch(1700000000000000)));
      expect(sample.redValue, equals(185.5));
      expect(sample.greenValue, equals(42.1));
      expect(sample.isFingerPresent, isTrue);
    });

    test('serializes toMap and fromMap correctly', () {
      final sample = PpgFrameSample.now(
        redValue: 200.0,
        greenValue: 30.0,
        isFingerPresent: true,
      );

      final map = sample.toMap();
      final restored = PpgFrameSample.fromMap(map);

      expect(restored.timestampMicros, equals(sample.timestampMicros));
      expect(restored.redValue, equals(sample.redValue));
      expect(restored.greenValue, equals(sample.greenValue));
      expect(restored.isFingerPresent, equals(sample.isFingerPresent));
    });

    test('copyWith works as expected', () {
      final sample = PpgFrameSample(
        timestampMicros: 1000,
        redValue: 150.0,
        greenValue: 50.0,
        isFingerPresent: false,
      );

      final modified = sample.copyWith(isFingerPresent: true, redValue: 160.0);
      expect(modified.isFingerPresent, isTrue);
      expect(modified.redValue, equals(160.0));
      expect(modified.greenValue, equals(50.0));
      expect(modified.timestampMicros, equals(1000));
    });
  });

  group('PpgCameraService finger detection heuristics', () {
    test('detects finger when red is dominant and chroma V is elevated', () {
      final isFinger = PpgCameraService.isFingerDetectedFromMetrics(
        avgRed: 180.0,
        avgGreen: 40.0,
        avgLuminance: 90.0,
        avgChromaV: 165.0,
      );
      expect(isFinger, isTrue);
    });

    test('rejects frame when red channel is too dim', () {
      final isFinger = PpgCameraService.isFingerDetectedFromMetrics(
        avgRed: 45.0, // below kMinRedThreshold (60.0)
        avgGreen: 20.0,
        avgLuminance: 35.0,
        avgChromaV: 150.0,
      );
      expect(isFinger, isFalse);
    });

    test('rejects frame when red does not dominate green (e.g. white or daylight scene)', () {
      final isFinger = PpgCameraService.isFingerDetectedFromMetrics(
        avgRed: 150.0,
        avgGreen: 145.0, // not dominated by red
        avgLuminance: 140.0,
        avgChromaV: 130.0,
      );
      expect(isFinger, isFalse);
    });

    test('rejects frame when scene is pitch dark (torch blocked or unlit)', () {
      final isFinger = PpgCameraService.isFingerDetectedFromMetrics(
        avgRed: 20.0,
        avgGreen: 10.0,
        avgLuminance: 15.0, // below kMinLuminanceThreshold (30.0)
        avgChromaV: 140.0,
      );
      expect(isFinger, isFalse);
    });

    test('rejects frame when scene is completely blown out white reflection', () {
      final isFinger = PpgCameraService.isFingerDetectedFromMetrics(
        avgRed: 255.0,
        avgGreen: 254.0,
        avgLuminance: 254.0, // above kMaxLuminanceThreshold (252.0)
        avgChromaV: 128.0,
      );
      expect(isFinger, isFalse);
    });
  });
}
