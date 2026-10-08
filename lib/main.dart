// lib/main.dart
//
// PulseGuard — Biometric PPG Pulse and Stress Monitoring Application
// Phase 6: Application entry point with dynamic routing and local state bootstrap.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'services/database_service.dart';
import 'theme/app_theme.dart';
import 'widgets/pulsing_heart_logo.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations & status bar appearance
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const PulseGuardApp());
}

class PulseGuardApp extends StatelessWidget {
  const PulseGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PulseGuard',
      debugShowCheckedModeBanner: false,
      theme: buildPulseGuardTheme(),
      routes: {
        '/': (context) => const AppBootstrapScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/forgot_password': (context) => const ForgotPasswordScreen(),
        '/main': (context) => const MainNavigationScreen(),
      },
      initialRoute: '/',
    );
  }
}

/// Initial launch decider: checks SQLite for existing profile.
class AppBootstrapScreen extends StatefulWidget {
  const AppBootstrapScreen({super.key});

  @override
  State<AppBootstrapScreen> createState() => _AppBootstrapScreenState();
}

class _AppBootstrapScreenState extends State<AppBootstrapScreen> {
  @override
  void initState() {
    super.initState();
    _checkInitialRoute();
  }

  Future<void> _checkInitialRoute() async {
    try {
      // Add a slight natural delay to show the branded splash
      await Future<void>.delayed(const Duration(milliseconds: 900));

      final profile = await DatabaseService.instance.fetchCurrentProfile();
      if (!mounted) return;

      if (profile != null) {
        // Registered user exists -> Go directly to main app dashboard
        Navigator.of(context).pushReplacementNamed('/main');
      } else {
        // First launch -> Go to login & authentication flow
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      if (!mounted) return;
      // On error, fallback to login
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PulseColors.cream,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const PulsingHeartLogo(size: 130),
            const SizedBox(height: 24),
            Text('PulseGuard', style: PulseTextStyles.brandTitle),
            const SizedBox(height: 6),
            Text('STRESS TELEMETRY', style: PulseTextStyles.brandSubtitle),
          ],
        ),
      ),
    );
  }
}
