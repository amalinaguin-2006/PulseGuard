// lib/screens/onboarding/questionnaire_part2_screen.dart
//
// PulseGuard — Phase 6: Health & Baseline Questionnaire (Part 2).

import 'package:flutter/material.dart';

import '../../controllers/pulse_guard_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_pill_button.dart';
import '../../widgets/pulsing_heart_logo.dart';
import '../main_navigation_screen.dart';

class QuestionnairePart2Screen extends StatefulWidget {
  final String fullName;
  final String email;
  final String sex;
  final DateTime dob;
  final int age;
  final String height;
  final String weight;
  final List<String> cardiacDevices;
  final List<String> cardiacEvents;

  const QuestionnairePart2Screen({
    super.key,
    required this.fullName,
    required this.email,
    required this.sex,
    required this.dob,
    required this.age,
    required this.height,
    required this.weight,
    required this.cardiacDevices,
    required this.cardiacEvents,
  });

  @override
  State<QuestionnairePart2Screen> createState() =>
      _QuestionnairePart2ScreenState();
}

class _QuestionnairePart2ScreenState extends State<QuestionnairePart2Screen> {
  // Arrhythmia options
  final Set<String> _selectedArrhythmia = {'None'};
  static const List<String> _arrhythmiaOptions = [
    'Atrial Fibrillation (AFib) or Atrial Flutter',
    'Supraventricular Tachycardia (SVT)',
    'Frequent PVCs or PACs (premature extra beats)',
    'Other diagnosed rhythm disorder',
    'None',
  ];

  // Chronic conditions
  final Set<String> _selectedConditions = {'None'};
  static const List<String> _conditionOptions = [
    'High blood pressure (Hypertension)',
    'Low blood pressure (Hypotension)',
    'Type 1 or Type 2 Diabetes',
    'Chronic Kidney Disease (CKD)',
    'Thyroid disorder (Hyperthyroidism / Hypothyroidism)',
    'None',
  ];

  // Prescription medications
  final Set<String> _selectedMedications = {'None'};
  static const List<String> _medicationOptions = [
    'Beta-blockers / Calcium Channel Blockers',
    'Antiarrhythmics',
    'ADHD / stimulant medications / regular bronchodilators',
    'Thyroid hormone medication',
    'None',
  ];

  // Nicotine / Tobacco usage
  String _selectedNicotine = 'Non-user';
  static const List<String> _nicotineOptions = [
    'Non-user',
    'Former user',
    'Active cigarette/tobacco smoker',
    'Active vape/nicotine pouch user',
  ];

  bool _isSaving = false;

  void _toggleOption(Set<String> set, String option) {
    setState(() {
      if (option == 'None') {
        set.clear();
        set.add('None');
      } else {
        set.remove('None');
        if (set.contains(option)) {
          set.remove(option);
          if (set.isEmpty) {
            set.add('None');
          }
        } else {
          set.add(option);
        }
      }
    });
  }

  Future<void> _handleSubmit() async {
    setState(() => _isSaving = true);

    try {
      // 1. Build and save questionnaire data into SQLite via SessionController
      final session = PulseGuardScope.of(context).sessionController;
      await session.saveQuestionnaireData(
        sex: widget.sex,
        dob: widget.dob,
        age: widget.age,
        height: widget.height,
        weight: widget.weight,
        cardiacDevices: widget.cardiacDevices,
        cardiacEvents: widget.cardiacEvents,
        arrhythmia: _selectedArrhythmia.toList(),
        conditions: _selectedConditions.toList(),
        medications: _selectedMedications.toList(),
        nicotine: _selectedNicotine,
      );

      if (!mounted) return;
      setState(() => _isSaving = false);

      // 2. Show success dialog
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: PulseColors.cream,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: PulseColors.crimson, width: 2),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  color: Color(0xFFD8F3DC),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: PulseColors.optimal,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Success!',
                style: PulseTextStyles.heading2.copyWith(color: PulseColors.optimal),
              ),
              const SizedBox(height: 8),
              Text(
                'Your account is successfully created and baseline profile registered.',
                textAlign: TextAlign.center,
                style: PulseTextStyles.bodyMedium,
              ),
              const SizedBox(height: 20),
              GradientPillButton(
                text: 'Go to Dashboard',
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      );

      if (!mounted) return;

      // 3. Navigate to MainNavigationScreen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const MainNavigationScreen(),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving profile: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PulseColors.cream,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Deep Red Curved Header
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  decoration: const BoxDecoration(
                    gradient: PulseColors.headerGradient,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(30),
                      bottomRight: Radius.circular(30),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new,
                                color: PulseColors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          Expanded(
                            child: Text(
                              "be patient! Little bit more about YOU.......",
                              textAlign: TextAlign.center,
                              style: PulseTextStyles.heading3.copyWith(
                                color: PulseColors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Step 2 of 2: Health Background',
                        style: PulseTextStyles.caption.copyWith(
                          color: PulseColors.white.withAlpha(200),
                        ),
                      ),
                    ],
                  ),
                ),

                // Form Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Arrhythmia
                        _buildSectionCard(
                          title:
                              '1. Have you ever been clinically diagnosed with arrhythmia?',
                          child: Column(
                            children: _arrhythmiaOptions.map((opt) {
                              final isSelected =
                                  _selectedArrhythmia.contains(opt);
                              return _buildCheckboxOption(
                                label: opt,
                                selected: isSelected,
                                onTap: () =>
                                    _toggleOption(_selectedArrhythmia, opt),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 2. Chronic Conditions
                        _buildSectionCard(
                          title:
                              '2. Do you have any of the following active chronic conditions?',
                          child: Column(
                            children: _conditionOptions.map((opt) {
                              final isSelected =
                                  _selectedConditions.contains(opt);
                              return _buildCheckboxOption(
                                label: opt,
                                selected: isSelected,
                                onTap: () =>
                                    _toggleOption(_selectedConditions, opt),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 3. Prescription Medications
                        _buildSectionCard(
                          title:
                              '3. Are you actively taking any prescription medications?',
                          child: Column(
                            children: _medicationOptions.map((opt) {
                              final isSelected =
                                  _selectedMedications.contains(opt);
                              return _buildCheckboxOption(
                                label: opt,
                                selected: isSelected,
                                onTap: () =>
                                    _toggleOption(_selectedMedications, opt),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 4. Nicotine / Tobacco
                        _buildSectionCard(
                          title:
                              '4. What is your current tobacco and nicotine usage?',
                          child: Column(
                            children: _nicotineOptions.map((opt) {
                              final isSelected = _selectedNicotine == opt;
                              return InkWell(
                                onTap: () =>
                                    setState(() => _selectedNicotine = opt),
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 4),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_unchecked,
                                        color: isSelected
                                            ? PulseColors.crimson
                                            : PulseColors.textLight,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          opt,
                                          style: PulseTextStyles.bodyMedium
                                              .copyWith(
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: isSelected
                                                ? PulseColors.textDark
                                                : PulseColors.textMedium,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Submit Button
                        GradientPillButton(
                          text: 'Submit Profile',
                          onPressed: _handleSubmit,
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isSaving)
            const TransitLoadingOverlay(
              message: 'Configuring biometric baseline profile...',
            ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
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
          Text(
            title,
            style: PulseTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: PulseColors.crimson,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildCheckboxOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? PulseColors.crimson : PulseColors.textLight,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: PulseTextStyles.bodyMedium.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color:
                      selected ? PulseColors.textDark : PulseColors.textMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
