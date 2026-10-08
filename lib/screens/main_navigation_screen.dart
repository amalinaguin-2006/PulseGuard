// lib/screens/main_navigation_screen.dart
//
// PulseGuard — Phase 6: Main navigation container with custom burgundy bottom bar
// and illuminated oval gradient highlight badge.

import 'package:flutter/material.dart';

import '../controllers/history_controller.dart';
import '../controllers/measurement_controller.dart';
import '../controllers/pulse_guard_scope.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;
  final HistoryController? historyController;
  final MeasurementController? measurementController;

  const MainNavigationScreen({
    super.key,
    this.initialIndex = 0,
    this.historyController,
    this.measurementController,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex;
  HistoryController? _localHistory;
  MeasurementController? _localMeasurement;

  HistoryController get _historyController =>
      widget.historyController ??
      _localHistory ??
      PulseGuardScope.of(context).historyController;

  MeasurementController get _measurementController =>
      widget.measurementController ??
      _localMeasurement ??
      PulseGuardScope.of(context).measurementController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    if (widget.historyController == null) {
      // Local fallback if no scope or constructor injection
      _localHistory = HistoryController();
      _localMeasurement = MeasurementController(
        onReadingSaved: (id, reading) {
          _localHistory?.registerSavedReading(reading);
        },
      );
      _localHistory!.load();
    } else {
      widget.historyController!.load();
    }
  }

  @override
  void dispose() {
    _localMeasurement?.dispose();
    _localHistory?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PulseColors.cream,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(
            historyController: _historyController,
            measurementController: _measurementController,
          ),
          HistoryScreen(
            historyController: _historyController,
          ),
          ProfileScreen(
            historyController: _historyController,
          ),
        ],
      ),
      bottomNavigationBar: _buildCustomBottomBar(),
    );
  }

  Widget _buildCustomBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: PulseColors.crimson,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(40),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _buildNavItem(
                  index: 0,
                  label: 'HOME',
                  icon: Icons.home_rounded,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  index: 1,
                  label: 'PulseLog',
                  icon: Icons.analytics_outlined,
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  index: 2,
                  label: 'Profile',
                  icon: Icons.person_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _currentIndex == index;

    return InkWell(
      onTap: () {
        if (_currentIndex != index) {
          setState(() => _currentIndex = index);
          if (index == 1) {
            _historyController.load();
          }
        }
      },
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFC44040),
                    Color(0xFF8B1E1E),
                  ],
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: isSelected
              ? Border.all(color: PulseColors.white.withAlpha(120), width: 1.2)
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withAlpha(50),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? PulseColors.white : PulseColors.white.withAlpha(160),
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? PulseColors.white : PulseColors.white.withAlpha(180),
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
