// lib/screens/result_screen.dart
//
// PulseGuard — Phase 6: Assessment results and readiness telemetry.

import 'package:flutter/material.dart';

import '../controllers/history_controller.dart';
import '../controllers/measurement_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_pill_button.dart';
import '../widgets/pulse_guard_header.dart';

/// Representation of a single calendar day within the current week's readiness card.
class _DayReadiness {
  final String label;
  final int? score;
  final bool isToday;
  final DateTime date;

  const _DayReadiness({
    required this.label,
    required this.score,
    required this.isToday,
    required this.date,
  });
}

class ResultScreen extends StatefulWidget {
  final MeasurementController measurementController;
  final HistoryController historyController;

  const ResultScreen({
    super.key,
    required this.measurementController,
    required this.historyController,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  @override
  void initState() {
    super.initState();
    // Ensure the latest persistent readings from SQLite are loaded into memory
    widget.historyController.load();
  }

  /// Calculates the 7 days of the current calendar week (Monday through Sunday).
  ///
  /// Only real, measured data from [widget.historyController.readings] or the
  /// current test result are included. Days without measurements have `score: null`.
  List<_DayReadiness> _deriveWeeklyReadiness(int todayScore) {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    // In Dart DateTime, Monday is 1, Sunday is 7
    final monday = todayMidnight.subtract(Duration(days: now.weekday - 1));

    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final result = <_DayReadiness>[];

    for (int i = 0; i < 7; i++) {
      final dayDate = monday.add(Duration(days: i));
      final isToday = dayDate.year == now.year &&
          dayDate.month == now.month &&
          dayDate.day == now.day;

      final label = isToday ? 'TODAY' : dayLabels[i];

      if (isToday) {
        // Today reflects the primary freshly completed measurement
        result.add(_DayReadiness(
          label: label,
          score: todayScore,
          isToday: true,
          date: dayDate,
        ));
      } else {
        // Look up originally measured readings from the persistent history
        final dayReadings = widget.historyController.readings.where((r) {
          final dt = r.dateTime.toLocal();
          return dt.year == dayDate.year &&
              dt.month == dayDate.month &&
              dt.day == dayDate.day;
        }).toList();

        if (dayReadings.isNotEmpty) {
          // Average stress index across that day's real sessions, converted to readiness (0-100)
          final avgStress = dayReadings
                  .map((r) => r.stressIndex)
                  .reduce((a, b) => a + b) /
              dayReadings.length;
          final score = (100 - avgStress).round().clamp(10, 99);
          result.add(_DayReadiness(
            label: label,
            score: score,
            isToday: false,
            date: dayDate,
          ));
        } else {
          // No fake data — explicitly mark unmeasured days as null
          result.add(_DayReadiness(
            label: label,
            score: null,
            isToday: false,
            date: dayDate,
          ));
        }
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.historyController,
      builder: (context, _) {
        final result = widget.measurementController.result;
        final reading = result?.reading;

        // Heart rate, RMSSD & Stress Index
        final bpm = reading?.bpm.round() ??
            widget.measurementController.bpm?.round() ??
            72;
        final rmssd = reading?.rmssd.round() ??
            widget.measurementController.rmssd?.round() ??
            42;
        final stressIndex = reading?.stressIndex.round() ??
            widget.measurementController.stressIndex?.round() ??
            28;

        // Readiness score calculation (inverse of stress index, clamped 10-99)
        final readinessScore = (100 - stressIndex).clamp(10, 99);

        // Dynamic recovery classification
        Color statusColor;
        String statusTitle;
        String statusSubtitle;

        if (readinessScore >= 70) {
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
        final hour = now.hour == 0
            ? 12
            : (now.hour > 12 ? now.hour - 12 : now.hour);
        final period = now.hour >= 12 ? 'PM' : 'AM';
        final min = now.minute.toString().padLeft(2, '0');
        final timeStr = 'Today, $hour:$min $period';
        final profile = widget.historyController.profile;
        final userName = profile?.name ?? 'User';

        // Derive weekly readiness using only original measurements
        final weeklyDays = _deriveWeeklyReadiness(readinessScore);

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
                  const Divider(
                    color: Color(0xFFF2D5D5),
                    thickness: 1,
                    indent: 20,
                    endIndent: 20,
                  ),
                  const SizedBox(height: 12),

                  // Status & Timestamp
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: PulseColors.optimal,
                              size: 20,
                            ),
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
                                : (bpm <= 100
                                    ? 'Normal resting'
                                    : 'Elevated rate'),
                            icon: Icons.favorite_rounded,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _buildMetricCard(
                            title: 'STRESS SCORE',
                            value: '$stressIndex',
                            subtitle:
                                'RMSSD: $rmssd ms • ${stressIndex <= 30 ? "Optimal" : (stressIndex <= 60 ? "Moderate" : "High")}',
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
                        border: Border.all(
                          color: PulseColors.pillBorder,
                          width: 1.2,
                        ),
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
                              const Icon(
                                Icons.date_range_rounded,
                                size: 18,
                                color: PulseColors.crimson,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // 7 Day Dots Row (Proportionally responsive, real data only)
                          _buildWeeklyDots(weeklyDays),
                          const SizedBox(height: 16),

                          // Legend Pill (Responsive FittedBox guarantees zero overflow)
                          _buildLegendPill(),
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
                        widget.measurementController.reset();
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: PulseTextStyles.metricLabel.copyWith(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: PulseTextStyles.heading2.copyWith(
                fontSize: 22,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: PulseTextStyles.caption.copyWith(
              color: PulseColors.textMedium,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyDots(List<_DayReadiness> days) {
    return Row(
      children: days.map((day) {
        final score = day.score;
        final isToday = day.isToday;

        Color dotColor;
        Color textColor;
        Widget content;

        if (score != null) {
          if (score >= 70) {
            dotColor = PulseColors.optimal;
          } else if (score >= 50) {
            dotColor = PulseColors.moderate;
          } else {
            dotColor = PulseColors.fatigueRed;
          }
          textColor = PulseColors.white;
          content = Text(
            '$score',
            style: TextStyle(
              fontSize: isToday ? 13 : 11,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          );
        } else {
          // Originally unmeasured day: Clean neutral styling without fake data
          dotColor = const Color(0xFFF3ECE6);
          textColor = PulseColors.textMedium.withAlpha(180);
          content = Text(
            '—',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          );
        }

        return Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: isToday ? 36 : 30,
                height: isToday ? 36 : 30,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: isToday
                      ? Border.all(color: PulseColors.crimson, width: 2.5)
                      : (score == null
                          ? Border.all(
                              color: PulseColors.pillBorder.withAlpha(120),
                              width: 1.0,
                            )
                          : null),
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
                child: Center(child: content),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  day.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                    color:
                        isToday ? PulseColors.crimson : PulseColors.textMedium,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLegendPill() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: PulseColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PulseColors.pillBorder.withAlpha(100)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLegendItem(PulseColors.fatigueRed, 'FATIGUE (<50)'),
            const SizedBox(width: 8),
            _buildLegendItem(PulseColors.moderate, 'MODERATE (50-69)'),
            const SizedBox(width: 8),
            _buildLegendItem(PulseColors.optimal, 'OPTIMAL (≥70)'),
            const SizedBox(width: 8),
            _buildLegendItem(const Color(0xFFD4C8C2), 'NO DATA (—)'),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: PulseColors.textDark,
          ),
        ),
      ],
    );
  }
}
