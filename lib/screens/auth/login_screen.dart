// lib/screens/auth/login_screen.dart
//
// PulseGuard — Phase 6: Login screen with pulsing heart-shield logo.

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/gradient_pill_button.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() {
    // Mock authentication — navigate to main app.
    Navigator.of(context).pushReplacementNamed('/main');
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

              // ── Pulsing heart-shield logo ──
              ScaleTransition(
                scale: _pulseAnimation,
                child: _HeartShieldLogo(),
              ),
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
                    GradientPillButton(
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

// ─────────────────────────────────────────────────────────────────────────────
// Heart-Shield Logo (drawn with Flutter primitives)
// ─────────────────────────────────────────────────────────────────────────────

class _HeartShieldLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 200,
      child: CustomPaint(painter: _ShieldHeartPainter()),
    );
  }
}

class _ShieldHeartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Shield background
    final shieldPath = Path()
      ..moveTo(cx, size.height * 0.05)
      ..cubicTo(cx - size.width * 0.55, size.height * 0.0,
          cx - size.width * 0.5, size.height * 0.45,
          cx, size.height * 0.95)
      ..cubicTo(cx + size.width * 0.5, size.height * 0.45,
          cx + size.width * 0.55, size.height * 0.0,
          cx, size.height * 0.05);
    shieldPath.close();

    final shieldFill = Paint()
      ..color = const Color(0xFFF2D5D5)
      ..style = PaintingStyle.fill;
    final shieldBorder = Paint()
      ..color = PulseColors.crimson
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawPath(shieldPath, shieldFill);
    canvas.drawPath(shieldPath, shieldBorder);

    // Heart icon inside the shield
    final heartSize = size.width * 0.38;
    final heartX = cx;
    final heartY = cy + size.height * 0.02;

    final heartPath = Path();
    heartPath.moveTo(heartX, heartY + heartSize * 0.25);

    // Left lobe
    heartPath.cubicTo(
      heartX - heartSize * 0.5, heartY - heartSize * 0.15,
      heartX - heartSize * 0.7, heartY - heartSize * 0.5,
      heartX - heartSize * 0.2, heartY - heartSize * 0.5,
    );
    heartPath.cubicTo(
      heartX - heartSize * 0.0, heartY - heartSize * 0.5,
      heartX, heartY - heartSize * 0.25,
      heartX, heartY - heartSize * 0.1,
    );

    // Right lobe
    heartPath.cubicTo(
      heartX, heartY - heartSize * 0.25,
      heartX + heartSize * 0.0, heartY - heartSize * 0.5,
      heartX + heartSize * 0.2, heartY - heartSize * 0.5,
    );
    heartPath.cubicTo(
      heartX + heartSize * 0.7, heartY - heartSize * 0.5,
      heartX + heartSize * 0.5, heartY - heartSize * 0.15,
      heartX, heartY + heartSize * 0.25,
    );
    heartPath.close();

    final heartPaint = Paint()
      ..color = PulseColors.crimson
      ..style = PaintingStyle.fill;
    canvas.drawPath(heartPath, heartPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
