// lib/screens/home_screen.dart
//
// PulseGuard — Phase 6: Home dashboard with pre-measurement readiness checklist.

import 'package:flutter/material.dart';

import '../controllers/history_controller.dart';
import '../controllers/measurement_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/pulse_guard_header.dart';
import 'assessment_screen.dart';

class HomeScreen extends StatefulWidget {
  final HistoryController historyController;
  final MeasurementController measurementController;

  const HomeScreen({
    super.key,
    required this.historyController,
    required this.measurementController,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  // Pre-measurement answers
  bool _exercised = false;
  bool _caffeine = false;
  bool _stressed = false;
  bool _heavyMeal = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 0.97, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _startAssessment() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssessmentScreen(
          measurementController: widget.measurementController,
          historyController: widget.historyController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.historyController,
      builder: (context, _) {
        final profile = widget.historyController.profile;
        final userName = profile?.name ?? 'User';

        return Scaffold(
          backgroundColor: PulseColors.cream,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Branded Header
                  PulseGuardHeader(userName: userName),
                  const Divider(color: Color(0xFFF2D5D5), thickness: 1, indent: 20, endIndent: 20),
                  const SizedBox(height: 12),

                  // Section Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Before You Measure:',
                      style: PulseTextStyles.heading2.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4 Pre-measurement Check Cards
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        _buildCheckCard(
                          icon: Icons.directions_run_rounded,
                          title: 'Exercised in the last 15 mins?',
                          value: _exercised,
                          onChanged: (val) => setState(() => _exercised = val),
                        ),
                        const SizedBox(height: 12),
                        _buildCheckCard(
                          icon: Icons.coffee_rounded,
                          title: 'Caffeine or nicotine in the last hour?',
                          value: _caffeine,
                          onChanged: (val) => setState(() => _caffeine = val),
                        ),
                        const SizedBox(height: 12),
                        _buildCheckCard(
                          icon: Icons.psychology_alt_rounded,
                          title: 'Feeling anxious or stressed?',
                          value: _stressed,
                          onChanged: (val) => setState(() => _stressed = val),
                        ),
                        const SizedBox(height: 12),
                        _buildCheckCard(
                          icon: Icons.restaurant_rounded,
                          title: 'Heavy meal or dehydrated recently?',
                          value: _heavyMeal,
                          onChanged: (val) => setState(() => _heavyMeal = val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Sub-caption recommendation
                  Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: PulseColors.cardBackground,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: PulseColors.pillBorder.withAlpha(120)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: PulseColors.crimson),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Please sit quietly for 5 minutes before starting',
                              style: PulseTextStyles.caption.copyWith(
                                color: PulseColors.crimson,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Prominent Circular Gradient "START TEST" Button
                  Center(
                    child: ScaleTransition(
                      scale: _pulseScale,
                      child: InkWell(
                        onTap: _startAssessment,
                        borderRadius: BorderRadius.circular(90),
                        child: Container(
                          width: 170,
                          height: 170,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: PulseColors.startButtonGradient,
                            boxShadow: [
                              BoxShadow(
                                color: PulseColors.crimson.withAlpha(100),
                                blurRadius: 25,
                                spreadRadius: 4,
                                offset: const Offset(0, 8),
                              ),
                            ],
                            border: Border.all(
                              color: PulseColors.white.withAlpha(180),
                              width: 3.5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.fingerprint_rounded,
                                size: 54,
                                color: PulseColors.white,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'START TEST',
                                style: PulseTextStyles.heading3.copyWith(
                                  color: PulseColors.white,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Helper caption
                  Center(
                    child: Text(
                      'Place finger over rear camera lens & flash',
                      style: PulseTextStyles.caption.copyWith(
                        color: PulseColors.textMedium,
                        fontWeight: FontWeight.w500,
                      ),
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

  Widget _buildCheckCard({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: PulseColors.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PulseColors.pillBorder, width: 1.2),
      ),
      child: Row(
        children: [
          // Icon badge
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: PulseColors.crimson.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: PulseColors.crimson, size: 22),
          ),
          const SizedBox(width: 14),

          // Question Title
          Expanded(
            child: Text(
              title,
              style: PulseTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: PulseColors.textDark,
              ),
            ),
          ),

          // Yes / No Toggle Pill
          Container(
            decoration: BoxDecoration(
              color: PulseColors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: PulseColors.pillBorder, width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildToggleOption(
                  label: 'No',
                  selected: !value,
                  onTap: () => onChanged(false),
                ),
                _buildToggleOption(
                  label: 'Yes',
                  selected: value,
                  onTap: () => onChanged(true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? PulseColors.crimson : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? PulseColors.white : PulseColors.textMedium,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
