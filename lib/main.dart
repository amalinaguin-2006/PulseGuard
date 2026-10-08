// lib/main.dart
//
// PulseGuard — Biometric PPG Pulse and Stress Monitoring Application
// Master entry point with InheritedWidget scope, portrait orientation lock,
// dynamic routing, and offline-first database bootstrap.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controllers/history_controller.dart';
import 'controllers/measurement_controller.dart';
import 'controllers/pulse_guard_scope.dart';
import 'controllers/session_controller.dart';
import 'screens/assessment_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/onboarding/questionnaire_part1_screen.dart';
import 'screens/onboarding/questionnaire_part2_screen.dart';
import 'screens/result_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/pulsing_heart_logo.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Strict portrait orientation only
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

class PulseGuardApp extends StatefulWidget {
  const PulseGuardApp({super.key});

  @override
  State<PulseGuardApp> createState() => _PulseGuardAppState();
}

class _PulseGuardAppState extends State<PulseGuardApp> {
  late final SessionController _sessionController;
  late final HistoryController _historyController;
  late final MeasurementController _measurementController;

  @override
  void initState() {
    super.initState();
    _sessionController = SessionController();
    _historyController = HistoryController();
    _measurementController = MeasurementController(
      onReadingSaved: (id, reading) {
        _historyController.registerSavedReading(reading);
      },
    );

    // Initial load of session & telemetry logs
    _sessionController.loadSession();
    _historyController.load();
  }

  @override
  void dispose() {
    _measurementController.dispose();
    _historyController.dispose();
    _sessionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PulseGuardScope(
      sessionController: _sessionController,
      historyController: _historyController,
      measurementController: _measurementController,
      child: MaterialApp(
        title: 'PulseGuard',
        debugShowCheckedModeBanner: false,
        theme: buildPulseGuardTheme(),
        initialRoute: '/',
        routes: {
          '/': (context) => const AppBootstrapScreen(),
          '/login': (context) => const LoginScreen(),
          '/signup': (context) => const SignUpScreen(),
          '/forgot': (context) => const ForgotPasswordScreen(),
          '/forgot_password': (context) => const ForgotPasswordScreen(),
          '/onboarding/1': (context) {
            final session = PulseGuardScope.of(context).sessionController;
            return QuestionnairePart1Screen(
              fullName: session.profile?.name ?? 'User',
              email: session.profile?.email ?? 'user@pulseguard.io',
            );
          },
          '/onboarding/2': (context) {
            final args =
                ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
            final session = PulseGuardScope.of(context).sessionController;
            return QuestionnairePart2Screen(
              fullName: args?['fullName'] ?? session.profile?.name ?? 'User',
              email: args?['email'] ?? session.profile?.email ?? 'user@pulseguard.io',
              sex: args?['sex'] ?? 'Male',
              dob: args?['dob'] ??
                  DateTime.now().subtract(const Duration(days: 365 * 25)),
              age: args?['age'] ?? 25,
              height: args?['height'] ?? "5' 9\"",
              weight: args?['weight'] ?? '70',
              cardiacDevices: (args?['cardiacDevices'] as List<String>?) ??
                  const ['None'],
              cardiacEvents: (args?['cardiacEvents'] as List<String>?) ??
                  const ['None'],
            );
          },
          '/main': (context) => const MainNavigationScreen(),
          '/assessment': (context) {
            final scope = PulseGuardScope.of(context);
            return AssessmentScreen(
              measurementController: scope.measurementController,
              historyController: scope.historyController,
            );
          },
          '/result': (context) {
            final scope = PulseGuardScope.of(context);
            return ResultScreen(
              measurementController: scope.measurementController,
              historyController: scope.historyController,
            );
          },
        },
      ),
    );
  }
}

/// Initial launch decider: checks SQLite session for existing profile.
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
      // Natural delay to showcase brand heartbeat logo
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      if (!mounted) return;
      final session = PulseGuardScope.of(context).sessionController;
      await session.loadSession();

      if (!mounted) return;

      if (session.isAuthenticated) {
        // Local profile found -> Go to dashboard
        Navigator.of(context).pushReplacementNamed('/main');
      } else {
        // First launch -> Authenticate
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (_) {
      if (!mounted) return;
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
            const PulsingHeartLogo(size: 150),
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
