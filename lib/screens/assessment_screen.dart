// lib/screens/assessment_screen.dart
//
// PulseGuard — Phase 6: Real-time biometric assessment screen with live camera,
// real-time PPG oscilloscope, and heart thumb progress track.

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../controllers/history_controller.dart';
import '../controllers/measurement_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/ppg_waveform_painter.dart';
import '../widgets/pulse_guard_header.dart';
import 'result_screen.dart';

class AssessmentScreen extends StatefulWidget {
  final MeasurementController measurementController;
  final HistoryController historyController;

  const AssessmentScreen({
    super.key,
    required this.measurementController,
    required this.historyController,
  });

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heartBeatController;
  late final Animation<double> _heartScale;
  bool _hasNavigatedToResult = false;

  @override
  void initState() {
    super.initState();
    _heartBeatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _heartScale = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _heartBeatController, curve: Curves.easeInOut),
    );

    widget.measurementController.addListener(_onMeasurementUpdate);

    // Auto-start measurement when screen mounts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.measurementController.canStart) {
        widget.measurementController.start(
          baselineRmssdMs: widget.historyController.preferredBaselineRmssd,
        );
      }
    });
  }

  @override
  void dispose() {
    widget.measurementController.removeListener(_onMeasurementUpdate);
    _heartBeatController.dispose();
    super.dispose();
  }

  void _onMeasurementUpdate() {
    if (!mounted || _hasNavigatedToResult) return;

    final phase = widget.measurementController.phase;
    if (phase == MeasurementPhase.completed || phase == MeasurementPhase.saved) {
      _hasNavigatedToResult = true;
      // Auto-save if not already saved
      if (widget.measurementController.canSave) {
        widget.measurementController.saveResult();
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResultScreen(
            measurementController: widget.measurementController,
            historyController: widget.historyController,
          ),
        ),
      );
    }
  }

  void _stopAssessment() async {
    await widget.measurementController.cancel();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.measurementController,
      builder: (context, _) {
        final ctrl = widget.measurementController;
        final profile = widget.historyController.profile;
        final userName = profile?.name ?? 'User';

        // Timer values
        final totalSeconds = ctrl.config.duration.inSeconds;
        final elapsedSeconds = (ctrl.progress * totalSeconds).clamp(0, totalSeconds).toInt();
        final progressFrac = ctrl.progress.clamp(0.0, 1.0);

        // Status text
        String promptText = 'Keep finger steady over the lens';
        if (ctrl.phase == MeasurementPhase.starting) {
          promptText = 'Initializing camera sensor & flash...';
        } else if (ctrl.phase == MeasurementPhase.detectingFinger) {
          promptText = 'Place finger over camera and flashlight';
        } else if (ctrl.phase == MeasurementPhase.calibrating) {
          promptText = 'Calibrating signal... Keep completely still';
        } else if (ctrl.warning == MeasurementWarning.fingerRemoved) {
          promptText = 'Finger lifted! Please reposition finger';
        } else if (ctrl.warning == MeasurementWarning.highNoise) {
          promptText = 'Motion detected. Rest hand on a flat surface';
        }

        // Live values
        final bpmVal = ctrl.bpm != null ? ctrl.bpm!.round().toString() : '--';
        final rmssdVal = ctrl.rmssd != null ? '${ctrl.rmssd!.round()} ms' : 'Calculating...';

        return Scaffold(
          backgroundColor: PulseColors.cream,
          body: SafeArea(
            child: Column(
              children: [
                // Top Header
                PulseGuardHeader(userName: userName),
                const Divider(color: Color(0xFFF2D5D5), thickness: 1, indent: 20, endIndent: 20),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Column(
                      children: [
                        // 1. Live Circular Camera Preview
                        _buildCircularCameraPreview(ctrl),
                        const SizedBox(height: 14),

                        // Status prompt pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: PulseColors.cardBackground,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: PulseColors.pillBorder, width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                ctrl.camera.isFingerDetected
                                    ? Icons.favorite
                                    : Icons.touch_app_outlined,
                                color: PulseColors.crimson,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  promptText,
                                  textAlign: TextAlign.center,
                                  style: PulseTextStyles.bodyMedium.copyWith(
                                    color: PulseColors.crimson,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // 2. Oscilloscope Container
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: PulseColors.cardBackground,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: PulseColors.pillBorder, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: PulseColors.crimson.withAlpha(20),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'LIVE PPG OSCILLOSCOPE',
                                      style: PulseTextStyles.metricLabel.copyWith(
                                        fontSize: 12,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: ctrl.sqi >= 0.7
                                            ? PulseColors.optimal.withAlpha(30)
                                            : PulseColors.moderate.withAlpha(30),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'SQI ${ctrl.sqiPercent}%',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: ctrl.sqi >= 0.7
                                              ? PulseColors.optimal
                                              : PulseColors.moderate,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(22),
                                  bottomRight: Radius.circular(22),
                                ),
                                child: SizedBox(
                                  height: 160,
                                  child: PpgWaveformView.fromProcessor(
                                    ctrl.processor,
                                    height: 160,
                                    style: const PpgWaveformStyle(
                                      lineColor: PulseColors.crimson,
                                      glowColor: PulseColors.crimsonLight,
                                      backgroundTop: PulseColors.cardBackground,
                                      backgroundBottom: PulseColors.cardBackground,
                                      gridColor: Color(0x1A8B1E1E),
                                      baselineColor: Color(0x338B1E1E),
                                      peakColor: PulseColors.crimson,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 3. Animated Time Progress Bar with Heart Thumb
                        _buildHeartProgressBar(progressFrac, elapsedSeconds, totalSeconds),
                        const SizedBox(height: 20),

                        // 4. Live Readouts (Pulse & Est. RMSSD)
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Pulse',
                                value: bpmVal,
                                unit: 'BPM',
                                icon: Icons.favorite_border,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Est. RMSSD',
                                value: rmssdVal,
                                unit: '',
                                icon: Icons.timeline,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // 5. STOP Assessment Button
                        InkWell(
                          onTap: _stopAssessment,
                          borderRadius: BorderRadius.circular(30),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: PulseColors.white,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: PulseColors.crimson, width: 2),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.stop_circle_outlined, color: PulseColors.crimson, size: 22),
                                const SizedBox(width: 8),
                                Text(
                                  'STOP assessment',
                                  style: PulseTextStyles.heading3.copyWith(
                                    fontSize: 16,
                                    color: PulseColors.crimson,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCircularCameraPreview(MeasurementController ctrl) {
    final cam = ctrl.camera.controller;
    final isReady = cam != null && cam.value.isInitialized;

    return Center(
      child: Container(
        width: 130,
        height: 130,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: PulseColors.crimson, width: 3.5),
          boxShadow: [
            BoxShadow(
              color: PulseColors.crimson.withAlpha(60),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipOval(
          child: isReady
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: cam.value.previewSize?.height ?? 130,
                    height: cam.value.previewSize?.width ?? 130,
                    child: CameraPreview(cam),
                  ),
                )
              : Container(
                  color: const Color(0xFFF2D5D5),
                  child: const Center(
                    child: Icon(
                      Icons.camera_alt_outlined,
                      size: 44,
                      color: PulseColors.crimson,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeartProgressBar(double progress, int elapsed, int total) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            const thumbSize = 28.0;
            final thumbLeft = (trackWidth - thumbSize) * progress;

            return SizedBox(
              height: 38,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Background Track
                  Container(
                    height: 8,
                    width: trackWidth,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8D0D0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  // Filled Track
                  Container(
                    height: 8,
                    width: (trackWidth * progress).clamp(0.0, trackWidth),
                    decoration: BoxDecoration(
                      gradient: PulseColors.buttonGradient,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  // Animated Heart Thumb
                  Positioned(
                    left: thumbLeft,
                    child: ScaleTransition(
                      scale: _heartScale,
                      child: Container(
                        width: thumbSize,
                        height: thumbSize,
                        decoration: BoxDecoration(
                          color: PulseColors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: PulseColors.crimson, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: PulseColors.crimson.withAlpha(80),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.favorite,
                          size: 16,
                          color: PulseColors.crimson,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress',
              style: PulseTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              '${elapsed}s / ${total}s',
              style: PulseTextStyles.caption.copyWith(
                fontWeight: FontWeight.bold,
                color: PulseColors.crimson,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: PulseColors.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PulseColors.pillBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: PulseColors.crimsonLight),
              const SizedBox(width: 6),
              Text(
                title,
                style: PulseTextStyles.metricLabel.copyWith(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: PulseTextStyles.metricValue.copyWith(fontSize: 24),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: PulseTextStyles.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: PulseColors.crimsonLight,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
