// lib/screens/onboarding/questionnaire_part1_screen.dart
//
// PulseGuard — Phase 6: Health & Baseline Questionnaire (Part 1).

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/gradient_pill_button.dart';
import 'questionnaire_part2_screen.dart';

class QuestionnairePart1Screen extends StatefulWidget {
  final String fullName;
  final String email;

  const QuestionnairePart1Screen({
    super.key,
    required this.fullName,
    required this.email,
  });

  @override
  State<QuestionnairePart1Screen> createState() =>
      _QuestionnairePart1ScreenState();
}

class _QuestionnairePart1ScreenState extends State<QuestionnairePart1Screen> {
  // Biological Sex
  String? _selectedSex = 'Male';

  // Date of Birth & Derived Age
  DateTime? _selectedDob;
  int? _derivedAge;

  // Height & Weight
  final _heightController = TextEditingController(text: "5' 9\"");
  final _weightController = TextEditingController(text: "70");

  // Cardiac Devices (Multi-select)
  final Set<String> _selectedCardiacDevices = {'None'};

  // Cardiac History Events (Multi-select)
  final Set<String> _selectedCardiacEvents = {'None'};

  static const List<String> _cardiacDeviceOptions = [
    'Pacemaker',
    'Implantable Cardioverter-Defibrillator (ICD)',
    'None',
  ];

  static const List<String> _cardiacEventOptions = [
    'Heart attack (Myocardial Infarction)',
    'Coronary stent placement or bypass surgery (CABG)',
    'Catheter ablation for arrhythmia',
    'Heart valve repair or replacement',
    'Diagnosed heart failure',
    'None',
  ];

  @override
  void initState() {
    super.initState();
    // Default DOB ~ 25 years ago
    final now = DateTime.now();
    _selectedDob = DateTime(now.year - 25, 5, 15);
    _derivedAge = 25;
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  void _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime(now.year - 25, 1, 1),
      firstDate: DateTime(1920),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: PulseColors.crimson,
              onPrimary: PulseColors.white,
              onSurface: PulseColors.textDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        int age = now.year - picked.year;
        if (now.month < picked.month ||
            (now.month == picked.month && now.day < picked.day)) {
          age--;
        }
        _derivedAge = age;
      });
    }
  }

  void _toggleDevice(String option) {
    setState(() {
      if (option == 'None') {
        _selectedCardiacDevices.clear();
        _selectedCardiacDevices.add('None');
      } else {
        _selectedCardiacDevices.remove('None');
        if (_selectedCardiacDevices.contains(option)) {
          _selectedCardiacDevices.remove(option);
          if (_selectedCardiacDevices.isEmpty) {
            _selectedCardiacDevices.add('None');
          }
        } else {
          _selectedCardiacDevices.add(option);
        }
      }
    });
  }

  void _toggleEvent(String option) {
    setState(() {
      if (option == 'None') {
        _selectedCardiacEvents.clear();
        _selectedCardiacEvents.add('None');
      } else {
        _selectedCardiacEvents.remove('None');
        if (_selectedCardiacEvents.contains(option)) {
          _selectedCardiacEvents.remove(option);
          if (_selectedCardiacEvents.isEmpty) {
            _selectedCardiacEvents.add('None');
          }
        } else {
          _selectedCardiacEvents.add(option);
        }
      }
    });
  }

  void _handleContinue() {
    if (_derivedAge == null || _derivedAge! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid date of birth')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuestionnairePart2Screen(
          fullName: widget.fullName,
          email: widget.email,
          sex: _selectedSex ?? 'Other',
          dob: _selectedDob!,
          age: _derivedAge!,
          height: _heightController.text.trim(),
          weight: _weightController.text.trim(),
          cardiacDevices: _selectedCardiacDevices.toList(),
          cardiacEvents: _selectedCardiacEvents.toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PulseColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            // Deep Red Curved Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                          "Let's Know Little more about YOU",
                          textAlign: TextAlign.center,
                          style: PulseTextStyles.heading3.copyWith(
                            color: PulseColors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48), // balance back button
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Step 1 of 2: Baseline Biometrics',
                    style: PulseTextStyles.caption.copyWith(
                      color: PulseColors.white.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),

            // Form Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Biological Sex
                    _buildSectionCard(
                      title: '1. What is your biological sex ?',
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildChoiceChip(
                              label: 'Female',
                              icon: Icons.female,
                              selected: _selectedSex == 'Female',
                              onTap: () => setState(() => _selectedSex = 'Female'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildChoiceChip(
                              label: 'Male',
                              icon: Icons.male,
                              selected: _selectedSex == 'Male',
                              onTap: () => setState(() => _selectedSex = 'Male'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2. Date of Birth
                    _buildSectionCard(
                      title: '2. What is your date of birth ?',
                      child: InkWell(
                        onTap: _pickDateOfBirth,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: PulseColors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: PulseColors.pillBorder, width: 1.2),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.calendar_month,
                                      color: PulseColors.crimson, size: 20),
                                  const SizedBox(width: 10),
                                  Text(
                                    _selectedDob != null
                                        ? '${_selectedDob!.day.toString().padLeft(2, '0')}/${_selectedDob!.month.toString().padLeft(2, '0')}/${_selectedDob!.year}'
                                        : 'Select Date of Birth',
                                    style: PulseTextStyles.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: PulseColors.textDark,
                                    ),
                                  ),
                                ],
                              ),
                              if (_derivedAge != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: PulseColors.crimson.withAlpha(20),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$_derivedAge yrs old',
                                    style: PulseTextStyles.caption.copyWith(
                                      color: PulseColors.crimson,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3 & 4. Height and Weight
                    Row(
                      children: [
                        Expanded(
                          child: _buildSectionCard(
                            title: '3. Height',
                            child: TextField(
                              controller: _heightController,
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                hintText: "5' 9\"",
                                filled: true,
                                fillColor: PulseColors.white,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: const BorderSide(
                                      color: PulseColors.pillBorder),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: const BorderSide(
                                      color: PulseColors.pillBorder),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSectionCard(
                            title: '4. Weight (kg)',
                            child: TextField(
                              controller: _weightController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                hintText: '70',
                                suffixText: 'kg',
                                filled: true,
                                fillColor: PulseColors.white,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: const BorderSide(
                                      color: PulseColors.pillBorder),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: const BorderSide(
                                      color: PulseColors.pillBorder),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 5. Implanted Cardiac Device
                    _buildSectionCard(
                      title: '5. Do you have an implanted cardiac device?',
                      child: Column(
                        children: _cardiacDeviceOptions.map((opt) {
                          final isSelected =
                              _selectedCardiacDevices.contains(opt);
                          return _buildCheckboxOption(
                            label: opt,
                            selected: isSelected,
                            onTap: () => _toggleDevice(opt),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 6. Personal History of Cardiac Events
                    _buildSectionCard(
                      title:
                          '6. Personal history of cardiac events or procedures?',
                      child: Column(
                        children: _cardiacEventOptions.map((opt) {
                          final isSelected =
                              _selectedCardiacEvents.contains(opt);
                          return _buildCheckboxOption(
                            label: opt,
                            selected: isSelected,
                            onTap: () => _toggleEvent(opt),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Continue button
                    GradientPillButton(
                      text: 'Continue',
                      onPressed: _handleContinue,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
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

  Widget _buildChoiceChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? PulseColors.crimson : PulseColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? PulseColors.crimson : PulseColors.pillBorder,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? PulseColors.white : PulseColors.crimson,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? PulseColors.white : PulseColors.textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
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
                  color: selected ? PulseColors.textDark : PulseColors.textMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
