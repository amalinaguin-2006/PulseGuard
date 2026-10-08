// lib/theme/app_theme.dart
//
// PulseGuard — Phase 6: Centralised design tokens and ThemeData.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Brand colours
// ─────────────────────────────────────────────────────────────────────────────

class PulseColors {
  PulseColors._();

  static const Color crimson = Color(0xFF8B1E1E);
  static const Color crimsonLight = Color(0xFFA62B2B);
  static const Color crimsonDark = Color(0xFF6B1515);
  static const Color cream = Color(0xFFFFF9F6);
  static const Color creamDark = Color(0xFFFBF0EA);
  static const Color cardBackground = Color(0xFFFFF5EF);
  static const Color pillBorder = Color(0xFF8B1E1E);
  static const Color textDark = Color(0xFF2D1810);
  static const Color textMedium = Color(0xFF5C3D2E);
  static const Color textLight = Color(0xFF9C7B6E);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF1A1A1A);

  // Status colours
  static const Color optimal = Color(0xFF2E8B57);
  static const Color moderate = Color(0xFFDAA520);
  static const Color fatigue = Color(0xFFCD5C5C);
  static const Color fatigueRed = Color(0xFFE04545);

  // Gradient stops
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF8B1E1E), Color(0xFFB33A3A)],
  );

  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFC44040), Color(0xFF8B1E1E)],
  );

  static const LinearGradient startButtonGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFCD5C5C), Color(0xFF8B1E1E)],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Text styles
// ─────────────────────────────────────────────────────────────────────────────

class PulseTextStyles {
  PulseTextStyles._();

  static TextStyle get brandTitle => GoogleFonts.playfairDisplay(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: PulseColors.crimson,
      );

  static TextStyle get brandSubtitle => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 3.0,
        color: PulseColors.crimsonLight,
      );

  static TextStyle get heading1 => GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: PulseColors.white,
      );

  static TextStyle get heading2 => GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: PulseColors.crimson,
      );

  static TextStyle get heading3 => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: PulseColors.crimson,
      );

  static TextStyle get body => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: PulseColors.textDark,
      );

  static TextStyle get bodyMedium => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: PulseColors.textMedium,
      );

  static TextStyle get caption => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: PulseColors.textLight,
      );

  static TextStyle get metricLarge => GoogleFonts.inter(
        fontSize: 42,
        fontWeight: FontWeight.w800,
        color: PulseColors.white,
      );

  static TextStyle get metricValue => GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: PulseColors.crimson,
      );

  static TextStyle get metricLabel => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: PulseColors.crimson,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Input decoration
// ─────────────────────────────────────────────────────────────────────────────

InputDecoration pillInputDecoration({
  required String hint,
  required IconData icon,
  bool obscure = false,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.inter(
      fontSize: 15,
      color: PulseColors.crimsonLight.withAlpha(140),
    ),
    prefixIcon: Icon(icon, color: PulseColors.crimson, size: 20),
    filled: true,
    fillColor: PulseColors.cream,
    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(30),
      borderSide: const BorderSide(color: PulseColors.pillBorder, width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(30),
      borderSide: const BorderSide(color: PulseColors.pillBorder, width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(30),
      borderSide: const BorderSide(color: PulseColors.crimsonLight, width: 2),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ThemeData
// ─────────────────────────────────────────────────────────────────────────────

ThemeData buildPulseGuardTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: PulseColors.cream,
    colorScheme: ColorScheme.fromSeed(
      seedColor: PulseColors.crimson,
      brightness: Brightness.light,
      surface: PulseColors.cream,
    ),
    textTheme: GoogleFonts.interTextTheme(),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: PulseColors.crimson,
        foregroundColor: PulseColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
        textStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
