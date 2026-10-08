// lib/screens/auth/login_screen.dart
//
// PulseGuard — Login screen with pulsing heart-shield logo and local authentication.

import 'package:flutter/material.dart';

import '../../controllers/pulse_guard_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_pill_button.dart';
import '../../widgets/pulsing_heart_logo.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() => _isLoading = true);
    final session = PulseGuardScope.of(context).sessionController;

    if (email.isEmpty && password.isEmpty) {
      // If user presses login directly without typing, check if profile exists
      await session.loadSession();
      if (!mounted) return;
      if (session.isAuthenticated) {
        setState(() => _isLoading = false);
        Navigator.of(context).pushReplacementNamed('/main');
        return;
      }
    }

    if (email.isEmpty || password.isEmpty) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email and password')),
      );
      return;
    }

    final success = await session.signIn(email, password);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      Navigator.of(context).pushReplacementNamed('/main');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(session.errorMessage ?? 'Authentication failed. Please check credentials.'),
          backgroundColor: PulseColors.crimson,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PulseColors.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Three-dot menu ──
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 8),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Icon(Icons.more_horiz,
                      color: PulseColors.crimson, size: 28),
                ),
              ),
              const SizedBox(height: 16),

              // ── Pulsing heart-shield logo with authentic heartbeat animation ──
              const PulsingHeartLogo(size: 150),
              const SizedBox(height: 16),

              // ── Brand title ──
              Text('PulseGuard', style: PulseTextStyles.brandTitle.copyWith(
                fontSize: 34,
              )),
              const SizedBox(height: 4),
              Text('STRESS TELEMETRY', style: PulseTextStyles.brandSubtitle),
              const SizedBox(height: 32),

              // ── Input fields ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    TextField(
                      controller: _emailController,
                      decoration: pillInputDecoration(
                        hint: 'Email or Phone',
                        icon: Icons.person_outline,
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: pillInputDecoration(
                        hint: 'Password',
                        icon: Icons.lock_outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Bottom curved sheet ──
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF8F4F0),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
                ),
                padding: const EdgeInsets.fromLTRB(32, 12, 32, 40),
                child: Column(
                  children: [
                    // Forgot Password
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const ForgotPasswordScreen(),
                        ));
                      },
                      child: Text(
                        'Forgot Password?',
                        style: PulseTextStyles.bodyMedium.copyWith(
                          color: PulseColors.crimsonLight,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Login button
                    _isLoading
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(color: PulseColors.crimson),
                            ),
                          )
                        : GradientPillButton(
                            label: 'Login',
                            onPressed: _handleLogin,
                          ),
                    const SizedBox(height: 12),

                    Text('or', style: PulseTextStyles.caption),
                    const SizedBox(height: 12),

                    // Create account
                    GradientPillButton(
                      label: 'Create an account',
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const SignUpScreen(),
                        ));
                      },
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          PulseColors.crimsonLight.withAlpha(180),
                          PulseColors.crimson.withAlpha(200),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
