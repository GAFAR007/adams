/// WHAT: Defines the shared visual theme for the public, customer, admin, and staff experiences.
/// WHY: A strong theme makes the app feel intentional and keeps component styling consistent.
/// HOW: Build a warm-neutral palette with bold navy surfaces and an expressive text theme.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  static const Color ink = Color(0xFF11243B);
  static const Color cobalt = Color(0xFF1B4D8C);
  static const Color sand = Color(0xFFF6F0E6);
  static const Color clay = Color(0xFFE5D2BD);
  static const Color ember = Color(0xFFCE7B37);
  static const Color pine = Color(0xFF2C715B);

  static ThemeData buildTheme() {
    final baseTextTheme = GoogleFonts.spaceGroteskTextTheme();
    final colorScheme = ColorScheme.fromSeed(
      seedColor: cobalt,
      brightness: Brightness.light,
      primary: cobalt,
      secondary: ember,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: sand,
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(fontWeight: FontWeight.w700, color: ink),
        displayMedium: baseTextTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700, color: ink),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: ink),
        titleLarge: baseTextTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: ink),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(color: ink),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(color: ink.withValues(alpha: 0.85)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: sand,
        foregroundColor: ink,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: clay.withValues(alpha: 0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: clay.withValues(alpha: 0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: cobalt, width: 1.4),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: baseTextTheme.bodyMedium?.copyWith(color: Colors.white),
      ),
    );
  }
}
