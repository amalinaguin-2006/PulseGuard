// lib/screens/profile_screen.dart
//
// PulseGuard — Phase 6: User profile view with biometric data and edit modal.

import 'package:flutter/material.dart';

import '../controllers/history_controller.dart';
import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/pulse_guard_header.dart';

class ProfileScreen extends StatefulWidget {
  final HistoryController historyController;

  const ProfileScreen({
    super.key,
    required this.historyController,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  void _editProfile(UserProfile? currentProfile) async {
    final nameCtrl = TextEditingController(text: currentProfile?.name ?? '');
    final ageCtrl = TextEditingController(text: currentProfile?.age.toString() ?? '25');
    String selectedGender = currentProfile?.gender.toLowerCase() == 'female' ? 'Female' : 'Male';

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: PulseColors.cream,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: PulseColors.crimson, width: 2),
          ),
          title: Text('Edit Profile', style: PulseTextStyles.heading3),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: pillInputDecoration(
                    hint: 'Full Name',
                    icon: Icons.person_outline,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ageCtrl,
                  keyboardType: TextInputType.number,
                  decoration: pillInputDecoration(
                    hint: 'Age',
                    icon: Icons.cake_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setModalState(() => selectedGender = 'Male'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedGender == 'Male' ? PulseColors.crimson : PulseColors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: PulseColors.pillBorder),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Male',
                            style: TextStyle(
                              color: selectedGender == 'Male' ? PulseColors.white : PulseColors.textDark,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => setModalState(() => selectedGender = 'Female'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedGender == 'Female' ? PulseColors.crimson : PulseColors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: PulseColors.pillBorder),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Female',
                            style: TextStyle(
                              color: selectedGender == 'Female' ? PulseColors.white : PulseColors.textDark,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: PulseColors.crimson)),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  Navigator.of(ctx).pop(true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: PulseColors.crimson,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: const Text('Save', style: TextStyle(color: PulseColors.white)),
            ),
          ],
        ),
      ),
    );

    if (updated == true && mounted) {
      final newAge = int.tryParse(ageCtrl.text.trim()) ?? (currentProfile?.age ?? 25);
      final newProfile = currentProfile != null
          ? currentProfile.copyWith(
              name: nameCtrl.text.trim(),
              age: newAge,
              gender: selectedGender.toLowerCase(),
            )
          : UserProfile(
              name: nameCtrl.text.trim(),
              age: newAge,
              gender: selectedGender.toLowerCase(),
              createdAt: DateTime.now().toIso8601String(),
            );

      await widget.historyController.saveProfile(newProfile);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: PulseColors.optimal,
        ),
      );
    }
  }

  void _showAvatarPicker() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Avatar image selection opened')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.historyController,
      builder: (context, _) {
        final profile = widget.historyController.profile;
        final userName = profile?.name ?? 'Alex Mercer';
        final userAge = profile?.age ?? 26;
        final userGender = (profile?.gender ?? 'Male').toUpperCase();

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

                  // Avatar & Edit Icon
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: PulseColors.headerGradient,
                            border: Border.all(color: PulseColors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: PulseColors.crimson.withAlpha(50),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.person_rounded,
                              size: 64,
                              color: PulseColors.white,
                            ),
                          ),
                        ),
                        // Camera overlay badge
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: InkWell(
                            onTap: _showAvatarPicker,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: PulseColors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 18,
                                color: PulseColors.crimson,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // User Full Name and Edit button row
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          userName,
                          style: PulseTextStyles.heading2.copyWith(fontSize: 22),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20, color: PulseColors.crimson),
                          onPressed: () => _editProfile(profile),
                          tooltip: 'Edit Profile',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Profile Pills Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        // Email Pill
                        _buildProfilePill(
                          icon: Icons.email_outlined,
                          title: 'EMAIL ADDRESS',
                          value: 'alex.mercer@pulseguard.io',
                        ),
                        const SizedBox(height: 10),

                        // Dual Metric Pill: Age & Sex
                        _buildDualPill(
                          icon1: Icons.cake_outlined,
                          title1: 'AGE',
                          value1: '$userAge',
                          icon2: Icons.wc_outlined,
                          title2: 'SEX',
                          value2: userGender,
                        ),
                        const SizedBox(height: 10),

                        // Dual Metric Pill: Height & Weight
                        _buildDualPill(
                          icon1: Icons.straighten_outlined,
                          title1: 'HEIGHT',
                          value1: "5' 9\"",
                          icon2: Icons.monitor_weight_outlined,
                          title2: 'WEIGHT',
                          value2: '72 kg',
                        ),
                        const SizedBox(height: 10),

                        // DOB and Smoker Badge
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildProfilePill(
                                icon: Icons.calendar_today_outlined,
                                title: 'DOB',
                                value: '15.05.1998',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: PulseColors.optimal.withAlpha(20),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: PulseColors.optimal, width: 1.2),
                                ),
                                alignment: Alignment.center,
                                child: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(
                                      'NON-SMOKER',
                                      style: TextStyle(
                                        color: PulseColors.optimal,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Medical History Header
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Medical Telemetry Baseline',
                            style: PulseTextStyles.heading3.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Medical History Pills
                        _buildProfilePill(
                          icon: Icons.monitor_heart_outlined,
                          title: 'CARDIAC DEVICE',
                          value: 'NONE',
                        ),
                        const SizedBox(height: 10),
                        _buildProfilePill(
                          icon: Icons.history_edu_outlined,
                          title: 'CARDIAC EVENTS',
                          value: 'NONE RECORDED',
                        ),
                        const SizedBox(height: 10),
                        _buildProfilePill(
                          icon: Icons.waves_outlined,
                          title: 'ARRHYTHMIA',
                          value: 'NONE REPORTED',
                        ),
                        const SizedBox(height: 10),
                        _buildProfilePill(
                          icon: Icons.healing_outlined,
                          title: 'ACTIVE CHRONIC CONDITIONS',
                          value: 'NONE',
                        ),
                        const SizedBox(height: 10),
                        _buildProfilePill(
                          icon: Icons.medication_outlined,
                          title: 'ACTIVE MEDICATION',
                          value: 'NONE',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Log Out Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                      },
                      icon: const Icon(Icons.logout, color: PulseColors.crimson),
                      label: const Text(
                        'Log Out',
                        style: TextStyle(
                          color: PulseColors.crimson,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: PulseColors.crimson, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
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

  Widget _buildProfilePill({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: PulseColors.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PulseColors.pillBorder, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(icon, color: PulseColors.crimson, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: PulseTextStyles.metricLabel.copyWith(
                    fontSize: 10,
                    letterSpacing: 0.8,
                    color: PulseColors.crimsonLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: PulseTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: PulseColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDualPill({
    required IconData icon1,
    required String title1,
    required String value1,
    required IconData icon2,
    required String title2,
    required String value2,
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
          Expanded(
            child: Row(
              children: [
                Icon(icon1, color: PulseColors.crimson, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title1,
                        style: PulseTextStyles.metricLabel.copyWith(
                          fontSize: 10,
                          color: PulseColors.crimsonLight,
                        ),
                      ),
                      Text(
                        value1,
                        overflow: TextOverflow.ellipsis,
                        style: PulseTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 30,
            width: 1,
            color: PulseColors.pillBorder.withAlpha(120),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Icon(icon2, color: PulseColors.crimson, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title2,
                        style: PulseTextStyles.metricLabel.copyWith(
                          fontSize: 10,
                          color: PulseColors.crimsonLight,
                        ),
                      ),
                      Text(
                        value2,
                        overflow: TextOverflow.ellipsis,
                        style: PulseTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
