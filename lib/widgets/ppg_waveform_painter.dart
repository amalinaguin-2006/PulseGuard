// lib/widgets/ppg_waveform_painter.dart
//
// Pulse Guard - Phase 4B: real-time PPG oscilloscope.
//
// Contents:
//   * WaveformDisplayMode - scroll vs hospital-style sweep
//   * PpgWaveformStyle    - colours, geometry, and adaptive themes
//   * PpgWaveformModel    - fixed-size ring buffer + auto-scaling envelope
//   * PpgWaveformPainter  - CustomPainter (grid, glowing curve, beat markers, area fill)
//   * PpgWaveformView     - high-performance stateful widget driving the canvas
//
// Performance notes:
//   * Painting is driven by a Listenable passed to CustomPainter, so only the
//     canvas repaints; no widget rebuilds happen per frame.
//   * Paint objects, Path and shaders are reused across frames.
//   * Samples live in preallocated typed-data ring buffers.
//   * The right edge follows a smoothed clock, scrolling evenly at the display
//     refresh rate (60 Hz) even though frames arrive at ~30 FPS.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/signal_processor_service.dart';

// ---------------------------------------------------------------------------
// Display Mode
// ---------------------------------------------------------------------------

/// Visual animation style of the waveform oscilloscope.
enum WaveformDisplayMode {
  /// Continuously scrolls from right to left like a modern pulse monitor (default).
  scroll,

  /// Sweeps across the canvas from left to right with an erase head like a
  /// hospital cardiac monitor.
  sweep,
}

// ---------------------------------------------------------------------------
// Style
// ---------------------------------------------------------------------------

/// Colours and geometry of the oscilloscope. The defaults suit dark themes;
/// use [PpgWaveformStyle.light] on light backgrounds or [PpgWaveformStyle.adaptive].
class PpgWaveformStyle {
  const PpgWaveformStyle({
    this.lineColor = const Color(0xFF22F5C8),
    this.glowColor = const Color(0xFF22F5C8),
    this.flatlineColor = const Color(0xFF3B4A5A),
    this.gridColor = const Color(0x14FFFFFF),
    this.baselineColor = const Color(0x33FFFFFF),
    this.peakColor = const Color(0xFFFF4D6D),
    this.backgroundTop = const Color(0xFF0D1626),
    this.backgroundBottom = const Color(0xFF070B14),
    this.lineWidth = 2.5,
    this.glowOuterWidth = 10.0,
    this.glowInnerWidth = 5.0,
    this.verticalFill = 0.42,
    this.gridDivisionsY = 4,
    this.gridIntervalMs = 500,
    this.showAreaFill = true,
    this.areaFillOpacity = 0.12,
  })  : assert(lineWidth > 0),
        assert(verticalFill > 0 && verticalFill <= 0.5),
        assert(gridDivisionsY >= 2),
        assert(gridIntervalMs > 0),
        assert(areaFillOpacity >= 0.0 && areaFillOpacity <= 1.0);

  /// Preset for light backgrounds.
  static const PpgWaveformStyle light = PpgWaveformStyle(
    lineColor: Color(0xFF0E9F6E),
    glowColor: Color(0xFF0E9F6E),
    flatlineColor: Color(0xFF9CA3AF),
    gridColor: Color(0x14000000),
    baselineColor: Color(0x33000000),
    peakColor: Color(0xFFE11D48),
    backgroundTop: Color(0xFFF8FAFC),
    backgroundBottom: Color(0xFFE2E8F0),
    areaFillOpacity: 0.08,
  );

  /// Factory creating an adaptive style matching the ambient [ThemeData.brightness].
  factory PpgWaveformStyle.adaptive(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const PpgWaveformStyle() : PpgWaveformStyle.light;
  }

  /// Main curve colour (fades in from the left edge in scroll mode).
  final Color lineColor;

  /// Glow colour drawn behind the curve.
  final Color glowColor;

  /// Colour of the flat line shown with no signal.
  final Color flatlineColor;

  /// Grid line colour.
  final Color gridColor;

  /// Centre baseline colour.
  final Color baselineColor;

  /// Beat marker colour.
  final Color peakColor;

  /// Background gradient (top and bottom).
  final Color backgroundTop;
  final Color backgroundBottom;

  /// Stroke width of the curve in logical pixels.
  final double lineWidth;

  /// Stroke widths of the two glow layers.
  final double glowOuterWidth;
  final double glowInnerWidth;

  /// Fraction (0, 0.5] of the canvas height the wave may occupy above and
  /// below the baseline once auto-scaled.
  final double verticalFill;

  /// Number of horizontal grid bands.
  final int gridDivisionsY;

  /// Time between vertical grid lines, in milliseconds.
  final int gridIntervalMs;

  /// Whether to render a subtle translucent glow area fill beneath the curve.
  final bool showAreaFill;

  /// Maximum opacity of the area fill gradient.
  final double areaFillOpacity;
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// Rolling sample buffer plus the smoothing state used for drawing.
///
/// Mutated from the UI isolate only (stream callbacks and the frame driver).
class PpgWaveformModel {
  PpgWaveformModel({
    required this.windowMicros,
    this.minAmplitude = 0.02,
  }) : envelope = minAmplitude;

  /// Ring buffer size: 10 s at 60 samples per second.
  static const int capacity = 600;

  /// The right edge of the canvas lags the newest sample slightly so the
  /// newest point is always fully visible.
  static const int renderDelayMicros = 50000;

  /// Width of the visible time window.
  int windowMicros;

  /// Smallest amplitude the auto-scaler will magnify (signal units). Prevents
  /// pure noise from being stretched to full height.
  double minAmplitude;

  /// Pipeline state; drives the flatline/damping behaviour.
  AcquisitionStatus status = AcquisitionStatus.noFinger;

  /// 0 (flat line) to 1 (full waveform). Eases between the two so the wave
  /// collapses and re-emerges smoothly.
  double damping = 0.0;

  /// Smoothed amplitude bound used for vertical scaling.
  double envelope;

  final Float32List _values = Float32List(capacity);
  final Int64List _times = Int64List(capacity);
  final Uint8List _peaks = Uint8List(capacity);
  int _head = 0;
  int _count = 0;

  final Stopwatch _clock = Stopwatch()..start();
  bool _offsetReady = false;
  double _offsetMicros = 0.0;
  bool _dirty = true;

  /// Number of stored samples.
  int get count => _count;

  int _index(int i) => (_head - _count + i + capacity) % capacity;

  /// Timestamp (microseconds) of the i-th oldest sample.
  int timeAt(int i) => _times[_index(i)];

  /// Value of the i-th oldest sample.
  double valueAt(int i) => _values[_index(i)];

  /// Whether the i-th oldest sample was flagged as a beat.
  bool isPeakAt(int i) => _peaks[_index(i)] == 1;

  /// Adds a sample from the processor.
  void add(FilteredPpgPoint point) {
    // Track the offset between the sample clock and the local clock with a
    // slow average, so scrolling stays even despite delivery jitter.
    final measured =
        (point.timestampMicros - _clock.elapsedMicroseconds).toDouble();
    if (!_offsetReady || (measured - _offsetMicros).abs() > 500000.0) {
      _offsetMicros = measured;
      _offsetReady = true;
    } else {
      _offsetMicros += (measured - _offsetMicros) * 0.05;
    }

    _values[_head] = point.value;
    _times[_head] = point.timestampMicros;
    _peaks[_head] = point.isPeak ? 1 : 0;
    _head = (_head + 1) % capacity;
    if (_count < capacity) _count++;
    _dirty = true;
  }

  /// Drops all samples (finger removed).
  void clear() {
    _head = 0;
    _count = 0;
    _offsetReady = false;
    _dirty = true;
  }

  /// Requests a repaint on the next frame.
  void markDirty() => _dirty = true;

  /// Current display time in the sample clock domain (microseconds).
  int nowMicros() =>
      (_clock.elapsedMicroseconds + _offsetMicros).round() - renderDelayMicros;

  /// Advances smoothing by [dtSeconds]. Returns true when the canvas needs
  /// repainting.
  bool advance(double dtSeconds) {
    final targetDamping = status == AcquisitionStatus.measuring ? 1.0 : 0.0;
    final dampingTau = targetDamping > damping ? 0.4 : 0.25;
    damping += (targetDamping - damping) * (1.0 - math.exp(-dtSeconds / dampingTau));
    if ((damping - targetDamping).abs() < 0.002) damping = targetDamping;

    // Peak absolute value inside the visible window.
    final fromTime = nowMicros() - windowMicros;
    var peak = 0.0;
    for (var i = 0; i < _count; i++) {
      if (timeAt(i) < fromTime) continue;
      final v = valueAt(i).abs();
      if (v > peak) peak = v;
    }
    final target = math.max(peak, minAmplitude);

    // Fast attack so peaks never clip, slow release so the scale does not
    // pump with every beat.
    final envelopeTau = target > envelope ? 0.12 : 1.2;
    envelope += (target - envelope) * (1.0 - math.exp(-dtSeconds / envelopeTau));

    final active =
        _dirty || status != AcquisitionStatus.noFinger || damping > 0.0;
    _dirty = false;
    return active;
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

/// Draws the oscilloscope: gradient background, grid, centre baseline,
/// glowing waveform, beat markers and leading dot.
class PpgWaveformPainter extends CustomPainter {
  PpgWaveformPainter({
    required this.model,
    required this.style,
    this.displayMode = WaveformDisplayMode.scroll,
    this.showPeakMarkers = true,
    super.repaint,
  });

  final PpgWaveformModel model;
  final PpgWaveformStyle style;
  final WaveformDisplayMode displayMode;
  final bool showPeakMarkers;

  // Reused drawing objects (no allocation per frame).
  final Path _path = Path();
  final Path _areaPath = Path();
  final Paint _background = Paint();
  late final Paint _gridPaint = Paint()
    ..color = style.gridColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  late final Paint _baselinePaint = Paint()
    ..color = style.baselineColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  late final Paint _flatlinePaint = Paint()
    ..color = style.flatlineColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = style.lineWidth
    ..strokeCap = StrokeCap.round;
  late final Paint _glowOuter = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = style.glowOuterWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  late final Paint _glowInner = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = style.glowInnerWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  late final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = style.lineWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _areaFill = Paint()..style = PaintingStyle.fill;
  late final Paint _peakGlow = Paint()..color = style.peakColor.withAlpha(70);
  late final Paint _peakCore = Paint()..color = style.peakColor;
  late final Paint _dotGlow = Paint()..color = style.glowColor.withAlpha(90);
  late final Paint _dotCore = Paint()..color = style.lineColor;
  late final Paint _sweepCursor = Paint()
    ..color = style.lineColor.withAlpha(160)
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  Size? _shaderSize;

  void _ensureShaders(Size size) {
    if (_shaderSize == size) return;
    _shaderSize = size;

    _background.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(0.0, size.height),
      <Color>[style.backgroundTop, style.backgroundBottom],
    );

    final from = Offset.zero;
    final to = Offset(size.width, 0.0);
    const stops = <double>[0.0, 0.45];

    if (displayMode == WaveformDisplayMode.scroll) {
      // Horizontal fade: old samples (left) are transparent, new ones opaque.
      _line.shader = ui.Gradient.linear(
        from,
        to,
        <Color>[style.lineColor.withAlpha(0), style.lineColor],
        stops,
      );
      _glowInner.shader = ui.Gradient.linear(
        from,
        to,
        <Color>[style.glowColor.withAlpha(0), style.glowColor.withAlpha(80)],
        stops,
      );
      _glowOuter.shader = ui.Gradient.linear(
        from,
        to,
        <Color>[style.glowColor.withAlpha(0), style.glowColor.withAlpha(34)],
        stops,
      );
    } else {
      // Uniform neon for sweep mode.
      _line.shader = null;
      _line.color = style.lineColor;
      _glowInner.shader = null;
      _glowInner.color = style.glowColor.withAlpha(80);
      _glowOuter.shader = null;
      _glowOuter.color = style.glowColor.withAlpha(34);
    }

    if (style.showAreaFill) {
      final alphaVal = (style.areaFillOpacity * 255.0).round().clamp(0, 255);
      _areaFill.shader = ui.Gradient.linear(
        Offset(0.0, 0.0),
        Offset(0.0, size.height),
        <Color>[
          style.lineColor.withAlpha(alphaVal),
          style.lineColor.withAlpha(0),
        ],
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _ensureShaders(size);

    final rect = Offset.zero & size;
    canvas
      ..save()
      ..clipRect(rect)
      ..drawRect(rect, _background);

    _paintGrid(canvas, size);
    _paintWave(canvas, size);
    canvas.restore();
  }

  void _paintGrid(Canvas canvas, Size size) {
    // Horizontal bands.
    final rows = style.gridDivisionsY;
    for (var i = 1; i < rows; i++) {
      final y = size.height * i / rows;
      canvas.drawLine(Offset(0.0, y), Offset(size.width, y), _gridPaint);
    }

    // Vertical lines.
    final window = model.windowMicros;
    final interval = style.gridIntervalMs * 1000;
    final now = model.nowMicros();
    final pxPerMicro = size.width / window;

    if (displayMode == WaveformDisplayMode.scroll) {
      var t = ((now - window) ~/ interval + 1) * interval;
      for (; t <= now; t += interval) {
        final x = size.width - (now - t) * pxPerMicro;
        canvas.drawLine(Offset(x, 0.0), Offset(x, size.height), _gridPaint);
      }
    } else {
      for (var x = 0.0; x <= size.width; x += size.width * (interval / window)) {
        canvas.drawLine(Offset(x, 0.0), Offset(x, size.height), _gridPaint);
      }
    }

    // Centre baseline.
    final midY = size.height / 2.0;
    canvas.drawLine(Offset(0.0, midY), Offset(size.width, midY), _baselinePaint);
  }

  void _paintWave(Canvas canvas, Size size) {
    final midY = size.height / 2.0;
    final damping = model.damping;
    final count = model.count;

    // No finger / settling / saturated: flat line.
    if (damping < 0.01 || count < 2) {
      canvas.drawLine(Offset(0.0, midY), Offset(size.width, midY), _flatlinePaint);
      return;
    }

    final window = model.windowMicros;
    final now = model.nowMicros();
    final yScale = (size.height * style.verticalFill / model.envelope) * damping;
    final maxY = size.height - 2.0;

    if (displayMode == WaveformDisplayMode.scroll) {
      _paintScrollingWave(canvas, size, midY, yScale, maxY, now, window);
    } else {
      _paintSweepingWave(canvas, size, midY, yScale, maxY, now, window);
    }
  }

  void _paintScrollingWave(
    Canvas canvas,
    Size size,
    double midY,
    double yScale,
    double maxY,
    int now,
    int window,
  ) {
    final fromTime = now - window;
    final xScale = size.width / window;
    final count = model.count;

    var first = count - 1;
    while (first > 0 && model.timeAt(first) >= fromTime) {
      first--;
    }
    if (count - first < 2) {
      canvas.drawLine(Offset(0.0, midY), Offset(size.width, midY), _flatlinePaint);
      return;
    }

    _path.reset();
    _areaPath.reset();

    var prevX = 0.0;
    var prevY = 0.0;
    var startX = 0.0;

    for (var i = first; i < count; i++) {
      final x = size.width - (now - model.timeAt(i)) * xScale;
      final y = math.max(2.0, math.min(maxY, midY - model.valueAt(i) * yScale));
      if (i == first) {
        _path.moveTo(x, y);
        _areaPath.moveTo(x, midY);
        _areaPath.lineTo(x, y);
        startX = x;
      } else {
        final midX = (prevX + x) / 2.0;
        final midYPoint = (prevY + y) / 2.0;
        _path.quadraticBezierTo(prevX, prevY, midX, midYPoint);
        _areaPath.quadraticBezierTo(prevX, prevY, midX, midYPoint);
      }
      prevX = x;
      prevY = y;
    }
    _path.lineTo(prevX, prevY);
    _areaPath.lineTo(prevX, prevY);
    _areaPath.lineTo(prevX, midY);
    _areaPath.lineTo(startX, midY);
    _areaPath.close();

    if (style.showAreaFill) {
      canvas.drawPath(_areaPath, _areaFill);
    }

    canvas
      ..drawPath(_path, _glowOuter)
      ..drawPath(_path, _glowInner)
      ..drawPath(_path, _line);

    if (showPeakMarkers) {
      for (var i = first; i < count; i++) {
        if (!model.isPeakAt(i)) continue;
        final x = size.width - (now - model.timeAt(i)) * xScale;
        final y = math.max(2.0, math.min(maxY, midY - model.valueAt(i) * yScale));
        canvas
          ..drawCircle(Offset(x, y), 7.0, _peakGlow)
          ..drawCircle(Offset(x, y), 3.0, _peakCore);
      }
    }

    // Leading dot at the newest sample.
    canvas
      ..drawCircle(Offset(prevX, prevY), 6.0, _dotGlow)
      ..drawCircle(Offset(prevX, prevY), 3.0, _dotCore);
  }

  void _paintSweepingWave(
    Canvas canvas,
    Size size,
    double midY,
    double yScale,
    double maxY,
    int now,
    int window,
  ) {
    final count = model.count;
    final sweepFrac = ((now % window) / window);
    final sweepX = size.width * sweepFrac;
    final blankingPx = size.width * 0.08; // 8% blanking erase zone

    _path.reset();
    var lastPointDrawn = false;
    var prevX = 0.0;
    var prevY = 0.0;

    for (var i = 0; i < count; i++) {
      final t = model.timeAt(i);
      final age = now - t;
      if (age > window || age < 0) continue;

      final x = size.width * ((t % window) / window);
      final y = math.max(2.0, math.min(maxY, midY - model.valueAt(i) * yScale));

      // Skip drawing inside blanking erase head
      final distFromSweep = (x - sweepX);
      if (distFromSweep > 0 && distFromSweep < blankingPx) {
        lastPointDrawn = false;
        continue;
      }

      if (!lastPointDrawn || (x - prevX).abs() > 40.0) {
        _path.moveTo(x, y);
      } else {
        _path.quadraticBezierTo(
            prevX, prevY, (prevX + x) / 2.0, (prevY + y) / 2.0);
      }
      prevX = x;
      prevY = y;
      lastPointDrawn = true;
    }

    canvas
      ..drawPath(_path, _glowOuter)
      ..drawPath(_path, _glowInner)
      ..drawPath(_path, _line);

    // Draw sweep cursor line
    canvas.drawLine(
      Offset(sweepX, 0.0),
      Offset(sweepX, size.height),
      _sweepCursor,
    );
  }

  @override
  bool shouldRepaint(PpgWaveformPainter oldDelegate) {
    return oldDelegate.model != model ||
        !identical(oldDelegate.style, style) ||
        oldDelegate.displayMode != displayMode ||
        oldDelegate.showPeakMarkers != showPeakMarkers;
  }
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Live PPG oscilloscope fed by the signal processor streams.
///
/// Subscribes in `initState`, cancels in `dispose`, and resubscribes if the
/// streams change. Needs bounded width; the height defaults to [height].
class PpgWaveformView extends StatefulWidget {
  const PpgWaveformView({
    super.key,
    required this.waveformStream,
    required this.metricsStream,
    this.initialStatus = AcquisitionStatus.noFinger,
    this.window = const Duration(seconds: 4),
    this.style = const PpgWaveformStyle(),
    this.displayMode = WaveformDisplayMode.scroll,
    this.height = 180.0,
    this.borderRadius = 16.0,
    this.showPeakMarkers = true,
    this.minAmplitude = 0.02,
  });

  /// Convenience constructor reading streams directly from a [SignalProcessorService].
  factory PpgWaveformView.fromProcessor(
    SignalProcessorService processor, {
    Key? key,
    Duration window = const Duration(seconds: 4),
    PpgWaveformStyle style = const PpgWaveformStyle(),
    WaveformDisplayMode displayMode = WaveformDisplayMode.scroll,
    double height = 180.0,
    double borderRadius = 16.0,
    bool showPeakMarkers = true,
    double minAmplitude = 0.02,
  }) {
    return PpgWaveformView(
      key: key,
      waveformStream: processor.waveformStream,
      metricsStream: processor.metricsStream,
      initialStatus: processor.currentMetrics.status,
      window: window,
      style: style,
      displayMode: displayMode,
      height: height,
      borderRadius: borderRadius,
      showPeakMarkers: showPeakMarkers,
      minAmplitude: minAmplitude,
    );
  }

  final Stream<FilteredPpgPoint> waveformStream;
  final Stream<BiometricMetrics> metricsStream;

  /// Status to assume until the first metrics event arrives.
  final AcquisitionStatus initialStatus;

  /// Visible time span (3-5 s works well; at most about 8 s).
  final Duration window;

  final PpgWaveformStyle style;

  /// Scroll or sweep display animation.
  final WaveformDisplayMode displayMode;

  final double height;
  final double borderRadius;
  final bool showPeakMarkers;

  /// See [PpgWaveformModel.minAmplitude]. Raise it if noise looks magnified.
  final double minAmplitude;

  @override
  State<PpgWaveformView> createState() => _PpgWaveformViewState();
}

class _PpgWaveformViewState extends State<PpgWaveformView>
    with SingleTickerProviderStateMixin {
  late final PpgWaveformModel _model;
  late PpgWaveformPainter _painter;
  late final AnimationController _frameDriver;

  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  final Stopwatch _frameClock = Stopwatch()..start();
  int _lastFrameMicros = 0;

  StreamSubscription<FilteredPpgPoint>? _waveformSubscription;
  StreamSubscription<BiometricMetrics>? _metricsSubscription;

  @override
  void initState() {
    super.initState();
    _model = PpgWaveformModel(
      windowMicros: widget.window.inMicroseconds,
      minAmplitude: widget.minAmplitude,
    )..status = widget.initialStatus;
    _painter = _buildPainter();
    _subscribe();

    // The controller is only used as a vsync-aligned frame callback.
    _frameDriver = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onFrame);
    _frameDriver.repeat();
  }

  PpgWaveformPainter _buildPainter() {
    return PpgWaveformPainter(
      model: _model,
      style: widget.style,
      displayMode: widget.displayMode,
      showPeakMarkers: widget.showPeakMarkers,
      repaint: _repaint,
    );
  }

  void _subscribe() {
    _waveformSubscription = widget.waveformStream.listen(_model.add);
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

  // Errors are surfaced by the guidance widget; the oscilloscope ignores them.
  void _ignoreError(Object error, StackTrace stackTrace) {}

  void _onMetrics(BiometricMetrics metrics) {
    final previous = _model.status;
    _model.status = metrics.status;
    // Drop stale samples when the finger leaves so they cannot reappear.
    if (metrics.status == AcquisitionStatus.noFinger &&
        previous != AcquisitionStatus.noFinger) {
      _model.clear();
    }
    _model.markDirty();
  }

  void _onFrame() {
    final nowMicros = _frameClock.elapsedMicroseconds;
    final dt = math.min(0.1, (nowMicros - _lastFrameMicros) * 1e-6);
    _lastFrameMicros = nowMicros;
    if (_model.advance(dt)) {
      _repaint.value++;
    }
  }

  @override
  void didUpdateWidget(PpgWaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.waveformStream != widget.waveformStream ||
        oldWidget.metricsStream != widget.metricsStream) {
      unawaited(_unsubscribe());
      _subscribe();
    }
    _model.windowMicros = widget.window.inMicroseconds;
    _model.minAmplitude = widget.minAmplitude;
    if (!identical(oldWidget.style, widget.style) ||
        oldWidget.displayMode != widget.displayMode ||
        oldWidget.showPeakMarkers != widget.showPeakMarkers) {
      _painter = _buildPainter();
    }
    _model.markDirty();
  }

  @override
  void dispose() {
    unawaited(_unsubscribe());
    _frameDriver
      ..removeListener(_onFrame)
      ..dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Live pulse waveform',
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: CustomPaint(
              painter: _painter,
              isComplex: true,
              willChange: true,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}
