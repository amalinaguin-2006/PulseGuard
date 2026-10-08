// lib/screens/main_navigation_screen.dart
//
// PulseGuard — Phase 6: Main navigation container with custom burgundy bottom bar
// and illuminated oval gradient highlight badge.

import 'package:flutter/material.dart';

import '../controllers/history_controller.dart';
import '../controllers/measurement_controller.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;

  const MainNavigationScreen({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex;
  late final HistoryController _historyController;
  late final MeasurementController _measurementController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _historyController = HistoryController();
    _measurementController = MeasurementController(
      onReadingSaved: (id, reading) {
        _historyController.registerSavedReading(reading);
      },
    );

    // Initial load of history and profile
    _historyController.load();
  }

  @override
  void dispose() {
    _measurementController.dispose();
    _historyController.dispose();
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                label: 'HOME',
                icon: Icons.home_rounded,
              ),
              _buildNavItem(
                index: 1,
                label: 'PulseLog',
                icon: Icons.analytics_outlined,
              ),
              _buildNavItem(
                index: 2,
                label: 'Profile',
                icon: Icons.person_rounded,
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? PulseColors.white : PulseColors.white.withAlpha(160),
              size: 22,
            ),
            const SizedBox(width: 8),
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
    );
  }
}
