// lib/widgets/pulse_guard_header.dart
//
// PulseGuard — Phase 6: Reusable branded header with dynamic greeting.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Returns a contextual greeting based on the current local time.
String _greeting() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return 'Good Morning!';
  if (hour >= 12 && hour < 17) return 'Good Afternoon!';
  if (hour >= 17 && hour < 21) return 'Good Evening!';
  return 'Good Night!';
}

/// Branded header row used on Home, Assessment, Result, History and Profile
/// screens:  "PulseGuard" (serif) on the left,  greeting + user name on right.
class PulseGuardHeader extends StatelessWidget {
  const PulseGuardHeader({super.key, required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('PulseGuard', style: PulseTextStyles.brandTitle),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _greeting(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PulseTextStyles.bodyMedium.copyWith(
                    color: PulseColors.crimsonLight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  userName.trim().split(RegExp(r'\s+')).first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PulseTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
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
}
