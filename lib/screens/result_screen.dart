// lib/screens/result_screen.dart
//
// PulseGuard — Phase 6: Assessment results and readiness telemetry.

import 'package:flutter/material.dart';

import '../controllers/history_controller.dart';
import '../controllers/measurement_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_pill_button.dart';
import '../widgets/pulse_guard_header.dart';

class ResultScreen extends StatelessWidget {
  final MeasurementController measurementController;
  final HistoryController historyController;

  const ResultScreen({
    super.key,
    required this.measurementController,
    required this.historyController,
  });

  @override
  Widget build(BuildContext context) {
    final result = measurementController.result;
    final reading = result?.reading;

    // Heart rate & RMSSD & Stress
    final bpm = reading?.bpm.round() ?? measurementController.bpm?.round() ?? 72;
    final rmssd = reading?.rmssd.round() ?? measurementController.rmssd?.round() ?? 42;
    final stressIndex = reading?.stressIndex.round() ?? measurementController.stressIndex?.round() ?? 28;

    // Readiness score calculation (inverse of stress index or calibrated 0-100)
    // Higher readiness = lower stress
    final readinessScore = (100 - stressIndex).clamp(10, 99);

    // Dynamic recovery classification
    Color statusColor;
    String statusTitle;
    String statusSubtitle;

    if (readinessScore >= 75) {
      statusColor = PulseColors.optimal;
      statusTitle = 'RECOVERED';
      statusSubtitle = 'Low Stress & High Readiness';
    } else if (readinessScore >= 50) {
      statusColor = PulseColors.moderate;
      statusTitle = 'MODERATE';
      statusSubtitle = 'Balanced Sympathetic Activity';
    } else {
      statusColor = PulseColors.fatigueRed;
      statusTitle = 'FATIGUE';
      statusSubtitle = 'Elevated Biometric Stress';
    }

    final now = DateTime.now();
    final hour = now.hour == 0 ? 12 : (now.hour > 12 ? now.hour - 12 : now.hour);
    final period = now.hour >= 12 ? 'PM' : 'AM';
    final min = now.minute.toString().padLeft(2, '0');
    final timeStr = 'Today, $hour:$min $period';
    final profile = historyController.profile;
    final userName = profile?.name ?? 'User';

    return Scaffold(
      backgroundColor: PulseColors.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              PulseGuardHeader(userName: userName),
              const Divider(color: Color(0xFFF2D5D5), thickness: 1, indent: 20, endIndent: 20),
              const SizedBox(height: 12),

              // Status & Timestamp
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: PulseColors.optimal, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'TEST COMPLETE',
                          style: PulseTextStyles.heading3.copyWith(
                            fontSize: 16,
                            color: PulseColors.crimson,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      timeStr,
                      style: PulseTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: PulseColors.textMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Large Circular Recovery Badge
              Center(
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withAlpha(90),
                        blurRadius: 24,
                        spreadRadius: 4,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(color: PulseColors.white, width: 4),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$readinessScore',
                        style: PulseTextStyles.metricLarge.copyWith(
                          fontSize: 56,
                          height: 1.0,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        statusTitle,
                        style: const TextStyle(
                          color: PulseColors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          statusSubtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: PulseColors.white.withAlpha(220),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Two Metric Cards (Heart Rate & Stress Score)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        title: 'HEART RATE',
                        value: '$bpm BPM',
                        subtitle: bpm < 60
                            ? 'Bradycardia / Athletic'
                            : (bpm <= 100 ? 'Normal resting' : 'Elevated rate'),
                        icon: Icons.favorite_rounded,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'STRESS SCORE',
                        value: '$stressIndex',
                        subtitle: 'RMSSD: $rmssd ms • ${stressIndex <= 30 ? "Optimal" : (stressIndex <= 60 ? "Moderate" : "High")}',
                        icon: Icons.speed_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // THIS WEEK'S READINESS Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: PulseColors.cardBackground,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: PulseColors.pillBorder, width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "THIS WEEK'S READINESS",
                            style: PulseTextStyles.metricLabel.copyWith(
                              letterSpacing: 1.0,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Icon(Icons.date_range_rounded, size: 18, color: PulseColors.crimson),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 7 Day Dots Row
                      _buildWeeklyDots(readinessScore),
                      const SizedBox(height: 16),

                      // Legend Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: PulseColors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: PulseColors.pillBorder.withAlpha(100)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildLegendItem(PulseColors.fatigueRed, 'FATIGUE (<50)'),
                            _buildLegendItem(PulseColors.moderate, 'MODERATE (50-74)'),
                            _buildLegendItem(PulseColors.optimal, 'OPTIMAL (≥75)'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Done Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GradientPillButton(
                  text: 'Back to Dashboard',
                  onPressed: () {
                    measurementController.reset();
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PulseColors.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PulseColors.pillBorder, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: PulseColors.crimson),
              const SizedBox(width: 6),
              Text(
                title,
                style: PulseTextStyles.metricLabel.copyWith(fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: PulseTextStyles.heading2.copyWith(fontSize: 22, height: 1.1),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: PulseTextStyles.caption.copyWith(
              color: PulseColors.textMedium,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyDots(int currentScore) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'TODAY'];
    // Mock history with today's score
    final scores = [78, 65, 82, 59, 74, 88, currentScore];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (index) {
        final score = scores[index];
        final day = days[index];
        final isToday = index == 6;

        Color dotColor;
        if (score >= 75) {
          dotColor = PulseColors.optimal;
        } else if (score >= 50) {
          dotColor = PulseColors.moderate;
        } else {
          dotColor = PulseColors.fatigueRed;
        }

        return Column(
          children: [
            Container(
              width: isToday ? 36 : 30,
              height: isToday ? 36 : 30,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: isToday
                    ? Border.all(color: PulseColors.crimson, width: 2.5)
                    : null,
                boxShadow: isToday
                    ? [
                        BoxShadow(
                          color: PulseColors.crimson.withAlpha(60),
                          blurRadius: 6,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  '$score',
                  style: TextStyle(
                    fontSize: isToday ? 13 : 11,
                    fontWeight: FontWeight.bold,
                    color: PulseColors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              day,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                color: isToday ? PulseColors.crimson : PulseColors.textMedium,
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
