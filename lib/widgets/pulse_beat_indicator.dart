// lib/widgets/pulse_beat_indicator.dart
//
// Pulse Guard - Phase 4B: heartbeat indicator.
//
// A heart icon that contracts and expands, with a soft glow and two radial
// ripples, each time the signal processor flags a systolic peak. It is idle
// (no animation, no repaints) between beats, and greyed out unless the
// pipeline is actually measuring.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/signal_processor_service.dart';

/// Beat-synchronised heart animation with an optional BPM read-out.
class PulseBeatIndicator extends StatefulWidget {
  const PulseBeatIndicator({
    super.key,
    required this.waveformStream,
    required this.metricsStream,
    this.initialMetrics = BiometricMetrics.idle,
    this.size = 140.0,
    this.activeColor = const Color(0xFFFF4D6D),
    this.inactiveColor = const Color(0xFF475569),
    this.showBpm = true,
    this.bpmTextColor = const Color(0xFFF1F5F9),
    this.labelColor = const Color(0xFF94A3B8),
    this.onBeat,
  }) : assert(size > 0);

  /// Convenience constructor that reads streams directly from a [SignalProcessorService].
  factory PulseBeatIndicator.fromProcessor(
    SignalProcessorService processor, {
    Key? key,
    double size = 140.0,
    Color activeColor = const Color(0xFFFF4D6D),
    Color inactiveColor = const Color(0xFF475569),
    bool showBpm = true,
    VoidCallback? onBeat,
  }) {
    return PulseBeatIndicator(
      key: key,
      waveformStream: processor.waveformStream,
      metricsStream: processor.metricsStream,
      initialMetrics: processor.currentMetrics,
      size: size,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
      showBpm: showBpm,
      onBeat: onBeat,
    );
  }

  /// Source of beat events ([FilteredPpgPoint.isPeak]).
  final Stream<FilteredPpgPoint> waveformStream;

  /// Source of pipeline status and BPM.
  final Stream<BiometricMetrics> metricsStream;

  /// State to show until the first metrics event arrives.
  final BiometricMetrics initialMetrics;

  /// Width and height of the indicator area (ripples use all of it).
  final double size;

  /// Heart and ripple colour while measuring.
  final Color activeColor;

  /// Heart colour when there is no live signal.
  final Color inactiveColor;

  /// Show the BPM number under the heart.
  final bool showBpm;

  final Color bpmTextColor;
  final Color labelColor;

  /// Optional callback invoked when a valid systolic beat is animated.
  final VoidCallback? onBeat;

  @override
  State<PulseBeatIndicator> createState() => PulseBeatIndicatorState();
}

class PulseBeatIndicatorState extends State<PulseBeatIndicator>
    with SingleTickerProviderStateMixin {
  /// Heart occupies this fraction of the indicator's width.
  static const double _heartFraction = 0.34;

  late final AnimationController _controller;
  late final Animation<double> _scale;

  StreamSubscription<FilteredPpgPoint>? _waveformSubscription;
  StreamSubscription<BiometricMetrics>? _metricsSubscription;

  late AcquisitionStatus _status;
  double? _bpm;

  /// Manually triggers a heartbeat pulse animation (useful for testing and feedback).
  void triggerBeat() {
    if (mounted) {
      _controller.forward(from: 0.0);
      widget.onBeat?.call();
    }
  }

  @override
  void initState() {
    super.initState();
    _status = widget.initialMetrics.status;
    _bpm = _status == AcquisitionStatus.measuring
        ? widget.initialMetrics.bpm
        : null;

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Quick contraction-expansion (systole), then a slower relaxation.
    _scale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 1.28)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 18.0,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.28, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 82.0,
      ),
    ]).animate(_controller);

    _subscribe();
  }

  void _subscribe() {
    _waveformSubscription = widget.waveformStream.listen(_onPoint);
    _metricsSubscription = widget.metricsStream.listen(
      _onMetrics,
      onError: _ignoreError,
    );
  }

  Future<void> _unsubscribe() async {
    final waveform = _waveformSubscription;
    final metrics = _metricsSubscription;
    _waveformSubscription = null;
    _metricsSubscription = null;
    await waveform?.cancel();
    await metrics?.cancel();
  }

  void _ignoreError(Object error, StackTrace stackTrace) {}

  void _onPoint(FilteredPpgPoint point) {
    if (point.isPeak && _status == AcquisitionStatus.measuring) {
      triggerBeat();
    }
  }

  void _onMetrics(BiometricMetrics metrics) {
    final status = metrics.status;
    final bpm = status == AcquisitionStatus.measuring ? metrics.bpm : null;
    if (status != _status || bpm != _bpm) {
      setState(() {
        _status = status;
        _bpm = bpm;
      });
    }
  }

  @override
  void didUpdateWidget(PulseBeatIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.waveformStream != widget.waveformStream ||
        oldWidget.metricsStream != widget.metricsStream) {
      unawaited(_unsubscribe());
      _subscribe();
    }
  }

  @override
  void dispose() {
    unawaited(_unsubscribe());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _status == AcquisitionStatus.measuring;

    final heart = TweenAnimationBuilder<Color?>(
      tween: ColorTween(
        end: active ? widget.activeColor : widget.inactiveColor,
      ),
      duration: const Duration(milliseconds: 300),
      builder: (BuildContext context, Color? color, Widget? child) {
        return ScaleTransition(
          scale: _scale,
          child: Icon(
            Icons.favorite,
            size: widget.size * _heartFraction,
            color: color,
          ),
        );
      },
    );

    final indicator = SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _BeatRipplePainter(
                animation: _controller,
                color: widget.activeColor,
                heartFraction: _heartFraction,
              ),
            ),
          ),
          heart,
        ],
      ),
    );

    final bpmText = _bpm == null ? '--' : _bpm!.round().toString();

    return Semantics(
      label: active && _bpm != null
          ? 'Heart rate ${_bpm!.round()} beats per minute'
          : 'Heart rate not available',
      excludeSemantics: true,
      child: widget.showBpm
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                indicator,
                Text(
                  bpmText,
                  style: TextStyle(
                    color: widget.bpmTextColor,
                    fontSize: 36.0,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                Text(
                  'BPM',
                  style: TextStyle(
                    color: widget.labelColor,
                    fontSize: 12.0,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : indicator,
    );
  }
}

/// Glow and expanding rings, driven directly by the animation value (no
/// widget rebuilds). Paints nothing while the animation is idle.
class _BeatRipplePainter extends CustomPainter {
  _BeatRipplePainter({
    required this.animation,
    required this.color,
    required this.heartFraction,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final double heartFraction;

  final Paint _glow = Paint();
  final Paint _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  static int _alpha(double fraction) =>
      math.max(0, math.min(255, (fraction * 255.0).round()));

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t <= 0.0 || t >= 1.0) return;

    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2.0;
    final minRadius = maxRadius * heartFraction;
    final fade = 1.0 - t;

    _glow.shader = ui.Gradient.radial(
      center,
      maxRadius,
      <Color>[color.withAlpha(_alpha(0.45 * fade)), color.withAlpha(0)],
    );
    canvas.drawCircle(center, maxRadius, _glow);

    _drawRing(canvas, center, minRadius, maxRadius, t);
    if (t > 0.2) {
      _drawRing(canvas, center, minRadius, maxRadius, (t - 0.2) / 0.8);
    }
  }

  void _drawRing(
    Canvas canvas,
    Offset center,
    double minRadius,
    double maxRadius,
    double progress,
  ) {
    final eased = Curves.easeOut.transform(progress);
    _ring.color = color.withAlpha(_alpha(0.6 * (1.0 - progress)));
    canvas.drawCircle(center, minRadius + (maxRadius - minRadius) * eased, _ring);
  }

  @override
  bool shouldRepaint(_BeatRipplePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.heartFraction != heartFraction ||
        oldDelegate.animation != animation;
  }
}
