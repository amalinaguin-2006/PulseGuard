// lib/screens/auth/forgot_password_screen.dart
//
// PulseGuard — Phase 6: Password reset flow with simulated OTP.

import 'package:flutter/material.dart';

import '../../controllers/pulse_guard_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_pill_button.dart';
import '../../widgets/pulsing_heart_logo.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }

    // Step 1: Simulate sending OTP
    setState(() => _isLoading = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _isLoading = false);

    // Step 2: Show simulated OTP dialog
    final otpVerified = await _showOtpDialog(email);
    if (!otpVerified || !mounted) return;

    // Step 3: Show new password dialog
    final newPassword = await _showNewPasswordDialog();
    if (newPassword == null || !mounted) return;

    final session = PulseGuardScope.of(context).sessionController;
    await session.resetPassword(email: email, newPassword: newPassword);

    // Success -> Forward to login
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password updated successfully! Please sign in.'),
        backgroundColor: PulseColors.optimal,
      ),
    );
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<bool> _showOtpDialog(String email) async {
    final otpController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: PulseColors.cream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: PulseColors.crimson, width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.mark_email_read_outlined,
                color: PulseColors.crimson, size: 28),
            const SizedBox(width: 10),
            Text(
              'Enter OTP Code',
              style: PulseTextStyles.heading3,
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A 4-digit reset code has been sent to:\n$email',
              style: PulseTextStyles.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: PulseColors.crimson,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '1234',
                hintStyle: TextStyle(
                  color: PulseColors.crimson.withAlpha(80),
                  letterSpacing: 8,
                ),
                filled: true,
                fillColor: PulseColors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: PulseColors.pillBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: PulseColors.crimson, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Demo Code: 1234',
                style: PulseTextStyles.caption.copyWith(
                  fontStyle: FontStyle.italic,
                  color: PulseColors.crimsonLight,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: PulseColors.crimson.withAlpha(180)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (otpController.text.trim() == '1234' ||
                  otpController.text.trim().length == 4) {
                Navigator.of(ctx).pop(true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Invalid OTP code. Try 1234.')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: PulseColors.crimson,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Verify', style: TextStyle(color: PulseColors.white)),
          ),
        ],
      ),
    );
    otpController.dispose();
    return result ?? false;
  }

  Future<String?> _showNewPasswordDialog() async {
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: PulseColors.cream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: PulseColors.crimson, width: 2),
        ),
        title: Text(
          'Set New Password',
          style: PulseTextStyles.heading3,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newPassController,
              obscureText: true,
              decoration: pillInputDecoration(
                hint: 'New Password',
                icon: Icons.lock_outline,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPassController,
              obscureText: true,
              decoration: pillInputDecoration(
                hint: 'Confirm Password',
                icon: Icons.lock_reset,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(
              'Cancel',
              style: TextStyle(color: PulseColors.crimson.withAlpha(180)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (newPassController.text.isNotEmpty &&
                  newPassController.text == confirmPassController.text) {
                Navigator.of(ctx).pop(newPassController.text.trim());
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Passwords must match and not be empty')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: PulseColors.crimson,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('Save & Login', style: TextStyle(color: PulseColors.white)),
          ),
        ],
      ),
    );

    newPassController.dispose();
    confirmPassController.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PulseColors.cream,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Back button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: PulseColors.crimson),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Back to Login',
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Lock Icon Container
                  Center(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2D5D5),
                        shape: BoxShape.circle,
                        border: Border.all(color: PulseColors.crimson, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: PulseColors.crimson.withAlpha(40),
                            blurRadius: 15,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        size: 50,
                        color: PulseColors.crimson,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Title & description
                  Text(
                    'Forgot Password?',
                    textAlign: TextAlign.center,
                    style: PulseTextStyles.heading2,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "No worries, we'll send you reset instructions to your registered email.",
                    textAlign: TextAlign.center,
                    style: PulseTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: 36),

                  // Email input field
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: pillInputDecoration(
                      hint: 'Enter your Email',
                      icon: Icons.email_outlined,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Reset password button
                  GradientPillButton(
                    text: 'Reset Password',
                    onPressed: _handleResetPassword,
                  ),
                  const SizedBox(height: 20),

                  // Back to Login link
                  Center(
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, size: 18, color: PulseColors.crimson),
                      label: Text(
                        'Back to Login',
                        style: PulseTextStyles.bodyMedium.copyWith(
                          color: PulseColors.crimson,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_isLoading)
            const TransitLoadingOverlay(message: 'Sending reset instructions...'),
        ],
      ),
    );
  }
}
