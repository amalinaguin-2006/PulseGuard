// lib/screens/auth/signup_screen.dart
//
// PulseGuard — Phase 6: Account creation screen with OTP simulation.

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/gradient_pill_button.dart';
import '../onboarding/questionnaire_part1_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to Terms & Privacy')),
      );
      return;
    }
    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    // Simulate OTP verification dialog
    final verified = await _showOtpDialog();
    if (!verified || !mounted) return;

    // Navigate to onboarding questionnaire
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => QuestionnairePart1Screen(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
      ),
    ));
  }

  Future<bool> _showOtpDialog() async {
    final otpController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: PulseColors.cream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Email Verification',
            style: PulseTextStyles.heading3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the 6-digit OTP sent to\n${_emailController.text.trim()}',
              textAlign: TextAlign.center,
              style: PulseTextStyles.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: PulseTextStyles.heading2.copyWith(letterSpacing: 8),
              decoration: InputDecoration(
                counterText: '',
                hintText: '------',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: PulseColors.crimson, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                Text('Cancel', style: TextStyle(color: PulseColors.textLight)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: PulseColors.crimson,
              shape: const StadiumBorder(),
            ),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    otpController.dispose();
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PulseColors.cream,
      body: Column(
        children: [
          // ── Curved burgundy header ──
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              left: 20,
              right: 20,
              bottom: 28,
            ),
            decoration: const BoxDecoration(
              gradient: PulseColors.headerGradient,
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(Icons.more_horiz, color: PulseColors.white, size: 28),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(Icons.close,
                          color: PulseColors.white, size: 24),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text("Let's",
                    style: PulseTextStyles.heading1
                        .copyWith(fontStyle: FontStyle.italic, fontSize: 22)),
                Text('Create\nYour\nAccount',
                    style: PulseTextStyles.heading1.copyWith(fontSize: 30)),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // ── Form fields ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    decoration: pillInputDecoration(
                      hint: 'Full Name',
                      icon: Icons.person_outline,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: pillInputDecoration(
                      hint: 'Email Address',
                      icon: Icons.mail_outline,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: pillInputDecoration(
                      hint: 'Password',
                      icon: Icons.lock_outline,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Terms checkbox
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _agreedToTerms,
                          activeColor: PulseColors.crimson,
                          onChanged: (v) =>
                              setState(() => _agreedToTerms = v ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: 'I agree to the ',
                            style: PulseTextStyles.caption,
                            children: [
                              TextSpan(
                                text: 'Terms & Privacy',
                                style: PulseTextStyles.caption.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: PulseColors.textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Sign Up button
                  GradientPillButton(
                    label: 'Sign Up',
                    onPressed: _handleSignUp,
                  ),
                  const SizedBox(height: 16),

                  // Sign In link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Have an account? ',
                          style: PulseTextStyles.caption),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Text(
                          'Sign In',
                          style: PulseTextStyles.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: PulseColors.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
