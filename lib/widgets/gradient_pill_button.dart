// lib/widgets/gradient_pill_button.dart
//
// PulseGuard — Phase 6: Reusable gradient pill / stadium button.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A pill-shaped button with a vertical crimson gradient and optional
/// shadow, matching the Figma design spec for Login / Sign Up / Start Test.
class GradientPillButton extends StatelessWidget {
  const GradientPillButton({
    super.key,
    String? label,
    String? text,
    required this.onPressed,
    this.gradient,
    this.width = double.infinity,
    this.height = 54,
    this.textStyle,
    this.outlined = false,
  }) : label = label ?? text ?? '';

  final String label;
  final VoidCallback? onPressed;
  final Gradient? gradient;
  final double width;
  final double height;
  final TextStyle? textStyle;

  /// If true, renders as a bordered outline pill instead of filled.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return SizedBox(
        width: width,
        height: height,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: PulseColors.crimson, width: 1.5),
            shape: const StadiumBorder(),
            foregroundColor: PulseColors.crimson,
          ),
          child: Text(
            label,
            style: textStyle ??
                PulseTextStyles.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: PulseColors.crimson,
                ),
          ),
        ),
      );
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: gradient ?? PulseColors.buttonGradient,
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: [
          BoxShadow(
            color: PulseColors.crimson.withAlpha(80),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(height / 2),
          child: Center(
            child: Text(
              label,
              style: textStyle ??
                  PulseTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: PulseColors.white,
                    fontSize: 16,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
