import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_guard/services/signal_processor_service.dart';
import 'package:pulse_guard/widgets/ppg_waveform_painter.dart';
import 'package:pulse_guard/widgets/pulse_beat_indicator.dart';
import 'package:pulse_guard/widgets/signal_quality_meter.dart';

void main() {
  group('PpgWaveformView Widget Tests', () {
    late StreamController<FilteredPpgPoint> waveformController;
    late StreamController<BiometricMetrics> metricsController;

    setUp(() {
      waveformController = StreamController<FilteredPpgPoint>.broadcast();
      metricsController = StreamController<BiometricMetrics>.broadcast();
    });

    tearDown(() async {
      await waveformController.close();
      await metricsController.close();
    });

    testWidgets('renders flatline idle state without crashing', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PpgWaveformView(
              waveformStream: waveformController.stream,
              metricsStream: metricsController.stream,
              initialStatus: AcquisitionStatus.noFinger,
            ),
          ),
        ),
      );

      expect(find.byType(PpgWaveformView), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('supports both scroll and sweep display modes', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                PpgWaveformView(
                  waveformStream: waveformController.stream,
                  metricsStream: metricsController.stream,
                  displayMode: WaveformDisplayMode.scroll,
                ),
                PpgWaveformView(
                  waveformStream: waveformController.stream,
                  metricsStream: metricsController.stream,
                  displayMode: WaveformDisplayMode.sweep,
                ),
              ],
            ),
          ),
        ),
      );

      // Feed sample points to both
      waveformController.add(const FilteredPpgPoint(
        timestampMicros: 1000000,
        value: 12.5,
        isPeak: false,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(PpgWaveformView), findsNWidgets(2));
    });

    testWidgets('convenience factory fromProcessor instantiates correctly', (WidgetTester tester) async {
      final processor = SignalProcessorService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PpgWaveformView.fromProcessor(processor),
          ),
        ),
      );

      expect(find.byType(PpgWaveformView), findsOneWidget);
      await processor.dispose();
    });
  });

  group('PulseBeatIndicator Widget Tests', () {
    late StreamController<FilteredPpgPoint> waveformController;
    late StreamController<BiometricMetrics> metricsController;

    setUp(() {
      waveformController = StreamController<FilteredPpgPoint>.broadcast();
      metricsController = StreamController<BiometricMetrics>.broadcast();
    });

    tearDown(() async {
      await waveformController.close();
      await metricsController.close();
    });

    testWidgets('displays placeholder BPM when inactive', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PulseBeatIndicator(
              waveformStream: waveformController.stream,
              metricsStream: metricsController.stream,
              initialMetrics: BiometricMetrics.idle,
            ),
          ),
        ),
      );

      expect(find.text('--'), findsOneWidget);
      expect(find.text('BPM'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('updates BPM when live measuring metrics arrive', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PulseBeatIndicator(
              waveformStream: waveformController.stream,
              metricsStream: metricsController.stream,
            ),
          ),
        ),
      );

      metricsController.add(const BiometricMetrics(
        status: AcquisitionStatus.measuring,
        bpm: 74.0,
        rmssd: 38.0,
        stressIndex: 52.0,
        signalQuality: 0.85,
        beatCount: 12,
        ibiCount: 10,
        timestampMicros: 1000000,
      ));
      await tester.pumpAndSettle();

      expect(find.text('74'), findsOneWidget);
      expect(find.text('BPM'), findsOneWidget);
    });

    testWidgets('triggers beat animation on systolic peak event and invokes onBeat', (WidgetTester tester) async {
      var beatFired = false;
      final key = GlobalKey<PulseBeatIndicatorState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PulseBeatIndicator(
              key: key,
              waveformStream: waveformController.stream,
              metricsStream: metricsController.stream,
              onBeat: () => beatFired = true,
            ),
          ),
        ),
      );

      // Trigger programmatic beat
      key.currentState?.triggerBeat();
      expect(beatFired, isTrue);

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PulseBeatIndicator), findsOneWidget);
    });
  });

  group('SignalQualityMeter & SignalQualityPanel Tests', () {
    testWidgets('displays placeFinger guidance when no finger detected', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SignalQualityPanel(metrics: BiometricMetrics.idle),
          ),
        ),
      );

      expect(find.text('Place finger over camera'), findsOneWidget);
      expect(find.text('No signal'), findsOneWidget);
      expect(find.text('--%'), findsOneWidget);
    });

    testWidgets('displays calibrating guidance during settling phase', (WidgetTester tester) async {
      const settlingMetrics = BiometricMetrics(
        status: AcquisitionStatus.settling,
        signalQuality: 0.0,
        beatCount: 0,
        ibiCount: 0,
        timestampMicros: 1000,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SignalQualityPanel(metrics: settlingMetrics),
          ),
        ),
      );

      expect(find.text('Keep still - calibrating...'), findsOneWidget);
      expect(find.text('No signal'), findsOneWidget);
    });

    testWidgets('displays high noise guidance when signal quality drops under noise', (WidgetTester tester) async {
      const noisyMetrics = BiometricMetrics(
        status: AcquisitionStatus.measuring,
        signalQuality: 0.15,
        beatCount: 10,
        ibiCount: 9,
        timestampMicros: 2000,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SignalQualityPanel(metrics: noisyMetrics),
          ),
        ),
      );

      expect(find.text('High noise detected'), findsOneWidget);
      expect(find.text('Poor'), findsOneWidget);
    });

    testWidgets('displays optimal SQI and reading pulse when signal is clean', (WidgetTester tester) async {
      const cleanMetrics = BiometricMetrics(
        status: AcquisitionStatus.measuring,
        bpm: 72.0,
        rmssd: 45.0,
        stressIndex: 44.0,
        signalQuality: 0.92,
        beatCount: 16,
        ibiCount: 16,
        timestampMicros: 3000,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SignalQualityPanel(metrics: cleanMetrics),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Reading pulse...'), findsOneWidget);
      expect(find.text('Optimal'), findsOneWidget);
      expect(find.text('92%'), findsOneWidget);
    });

    testWidgets('displays sensor error when hasError is true', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SignalQualityPanel(
              metrics: BiometricMetrics.idle,
              hasError: true,
            ),
          ),
        ),
      );

      expect(find.text('Sensor error'), findsOneWidget);
    });
  });
}
