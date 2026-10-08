// lib/widgets/signal_quality_meter.dart
//
// Pulse Guard - Phase 4B: signal quality meter and user guidance.
//
// Shows what the user should do right now ("Place finger over camera",
// "Keep still - calibrating...", "Reading pulse...", "High noise detected")
// together with the Signal Quality Index as a percentage, a four-segment bar
// and a Poor / Fair / Good / Optimal badge.
//
// BiometricMetrics.signalQuality is 0.0-1.0; this file converts it to 0-100 %.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/signal_processor_service.dart';

// ---------------------------------------------------------------------------
// Guidance and quality classification
// ---------------------------------------------------------------------------

/// What the user is being asked to do.
enum SignalGuidance {
  placeFinger(
    'Place finger over camera',
    'Cover the rear lens and flash completely, pressing lightly.',
    Icons.fingerprint,
    Color(0xFF60A5FA),
  ),
  calibrating(
    'Keep still - calibrating...',
    'Hold steady while the signal settles.',
    Icons.hourglass_top,
    Color(0xFFFBBF24),
  ),
  reading(
    'Reading pulse...',
    'Keep your finger still and relaxed.',
    Icons.graphic_eq,
    Color(0xFF34D399),
  ),
  highNoise(
    'High noise detected',
    'Keep still and press lightly; avoid moving your hand.',
    Icons.warning_amber_rounded,
    Color(0xFFF97316),
  ),
  saturated(
    'Signal saturated',
    'Shift your finger slightly or ease the pressure.',
    Icons.tune,
    Color(0xFFF97316),
  ),
  error(
    'Sensor error',
    'Stop and restart the measurement.',
    Icons.error_outline,
    Color(0xFFEF4444),
  );

  const SignalGuidance(this.title, this.hint, this.icon, this.color);

  final String title;
  final String hint;
  final IconData icon;
  final Color color;
}

/// Quality tier derived from the SQI.
enum SignalQualityLevel {
  none('No signal', Color(0xFF475569), 0),
  poor('Poor', Color(0xFFEF4444), 1),
  fair('Fair', Color(0xFFF59E0B), 2),
  good('Good', Color(0xFF84CC16), 3),
  optimal('Optimal', Color(0xFF22C55E), 4);

  const SignalQualityLevel(this.label, this.color, this.segments);

  final String label;
  final Color color;

  /// Number of filled bar segments (0-4).
  final int segments;

  /// Maps an SQI in [0, 1] to a tier: below 0.4 poor, below 0.6 fair, below
  /// 0.8 good, otherwise optimal. 0.6 is [BiometricMetrics.reliableSqi].
  static SignalQualityLevel fromSqi(double sqi) {
    if (sqi < 0.4) return SignalQualityLevel.poor;
    if (sqi < 0.6) return SignalQualityLevel.fair;
    if (sqi < 0.8) return SignalQualityLevel.good;
    return SignalQualityLevel.optimal;
  }
}

/// Chooses the guidance message for the current [metrics].
///
/// While measuring, "High noise detected" appears in two cases: beats were
/// being tracked but BPM has become unavailable (no valid beat for several
/// seconds), or enough beats are buffered yet the SQI is still very low.
SignalGuidance signalGuidanceFor(BiometricMetrics metrics) {
  switch (metrics.status) {
    case AcquisitionStatus.noFinger:
      return SignalGuidance.placeFinger;
    case AcquisitionStatus.settling:
      return SignalGuidance.calibrating;
    case AcquisitionStatus.saturated:
      return SignalGuidance.saturated;
    case AcquisitionStatus.measuring:
      final lostBeats = metrics.ibiCount >= 3 && metrics.bpm == null;
      final noisy = metrics.ibiCount >= 8 && metrics.signalQuality < 0.25;
      return (lostBeats || noisy)
          ? SignalGuidance.highNoise
          : SignalGuidance.reading;
  }
}

// ---------------------------------------------------------------------------
// Stream-driven widget
// ---------------------------------------------------------------------------

/// Quality meter fed by `SignalProcessorService.metricsStream`. Uses a
/// [StreamBuilder], so the subscription is managed automatically.
class SignalQualityMeter extends StatelessWidget {
  const SignalQualityMeter({
    super.key,
    required this.metricsStream,
    this.initialMetrics = BiometricMetrics.idle,
  });

  /// Convenience constructor that reads the stream and current state from a
  /// [SignalProcessorService].
  factory SignalQualityMeter.fromProcessor(
    SignalProcessorService processor, {
    Key? key,
  }) {
    return SignalQualityMeter(
      key: key,
      metricsStream: processor.metricsStream,
      initialMetrics: processor.currentMetrics,
    );
  }

  final Stream<BiometricMetrics> metricsStream;

  /// Shown until the first event arrives.
  final BiometricMetrics initialMetrics;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BiometricMetrics>(
      stream: metricsStream,
      initialData: initialMetrics,
      builder: (BuildContext context, AsyncSnapshot<BiometricMetrics> snapshot) {
        return SignalQualityPanel(
          metrics: snapshot.data ?? initialMetrics,
          hasError: snapshot.hasError,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Pure display widget
// ---------------------------------------------------------------------------

/// Stateless panel for a given [metrics] snapshot. Use directly if you
/// already hold the metrics in your own state management.
class SignalQualityPanel extends StatelessWidget {
  const SignalQualityPanel({
    super.key,
    required this.metrics,
    this.hasError = false,
    this.backgroundColor = const Color(0xFF0F172A),
    this.titleColor = const Color(0xFFF1F5F9),
    this.hintColor = const Color(0xFF94A3B8),
    this.inactiveSegmentColor = const Color(0xFF1E293B),
    this.padding = const EdgeInsets.all(16.0),
    this.borderRadius = 16.0,
  });

  final BiometricMetrics metrics;

  /// Shows the "Sensor error" guidance regardless of [metrics].
  final bool hasError;

  final Color backgroundColor;
  final Color titleColor;
  final Color hintColor;
  final Color inactiveSegmentColor;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final guidance = hasError ? SignalGuidance.error : signalGuidanceFor(metrics);

    final measuring = metrics.status == AcquisitionStatus.measuring && !hasError;
    final analyzing = measuring && metrics.ibiCount < 4;
    final level = (!measuring || analyzing)
        ? SignalQualityLevel.none
        : SignalQualityLevel.fromSqi(metrics.signalQuality);
    final percent = measuring
        ? math.max(0, math.min(100, (metrics.signalQuality * 100.0).round()))
        : 0;
    final badgeText = analyzing ? 'Analyzing' : level.label;

    return Semantics(
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: '${guidance.title}. Signal quality '
          '${measuring ? '$percent percent, $badgeText' : 'unavailable'}.',
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _GuidanceRow(
              guidance: guidance,
              titleColor: titleColor,
              hintColor: hintColor,
            ),
            const SizedBox(height: 14.0),
            _SegmentedBar(
              level: level,
              inactiveColor: inactiveSegmentColor,
            ),
            const SizedBox(height: 10.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _PercentText(
                  percent: percent.toDouble(),
                  visible: measuring && !analyzing,
                  color: titleColor,
                ),
                _QualityBadge(label: badgeText, color: level.color),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidanceRow extends StatelessWidget {
  const _GuidanceRow({
    required this.guidance,
    required this.titleColor,
    required this.hintColor,
  });

  final SignalGuidance guidance;
  final Color titleColor;
  final Color hintColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 44.0,
          height: 44.0,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: guidance.color.withAlpha(36),
            border: Border.all(color: guidance.color.withAlpha(120)),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Icon(
              guidance.icon,
              key: ValueKey<SignalGuidance>(guidance),
              color: guidance.color,
              size: 24.0,
            ),
          ),
        ),
        const SizedBox(width: 12.0),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            alignment: Alignment.centerLeft,
            child: Column(
              key: ValueKey<SignalGuidance>(guidance),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  guidance.title,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 16.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  guidance.hint,
                  style: TextStyle(color: hintColor, fontSize: 13.0, height: 1.3),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SegmentedBar extends StatelessWidget {
  const _SegmentedBar({required this.level, required this.inactiveColor});

  final SignalQualityLevel level;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(4, (int index) {
        final filled = index < level.segments;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index < 3 ? 6.0 : 0.0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 8.0,
              decoration: BoxDecoration(
                color: filled ? level.color : inactiveColor,
                borderRadius: BorderRadius.circular(4.0),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _PercentText extends StatelessWidget {
  const _PercentText({
    required this.percent,
    required this.visible,
    required this.color,
  });

  final double percent;
  final bool visible;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: color,
      fontSize: 22.0,
      fontWeight: FontWeight.w700,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    if (!visible) {
      return Text('--%', style: style);
    }
    // No `begin`: the value animates from wherever it currently is.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: percent),
      duration: const Duration(milliseconds: 300),
      builder: (BuildContext context, double value, Widget? child) {
        return Text('${value.round()}%', style: style);
      },
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 5.0),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(999.0),
        border: Border.all(color: color.withAlpha(140)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12.0,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
