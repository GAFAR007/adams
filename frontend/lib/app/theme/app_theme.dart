/// WHAT: Defines the shared visual theme and semantic color tokens for the app.
/// WHY: Centralized color roles keep screens consistent and stop UI code from hard-coding one-off hex values.
/// HOW: Expose named light/dark surfaces, status tones, and a single Material theme built from those tokens.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

@immutable
class AppTone {
  const AppTone({
    required this.background,
    required this.foreground,
    this.border,
  });

  final Color background;
  final Color foreground;
  final Color? border;
}

class AppTheme {
  AppTheme._();

  // Brand anchors.
  static const Color ink = Color(0xFF1C2E32);
  static const Color cobalt = Color(0xFF2E6C70);
  static const Color sand = Color(0xFFF5F1E8);
  static const Color clay = Color(0xFFD5CCBD);
  static const Color ember = Color(0xFFB8743C);
  static const Color pine = Color(0xFF447A64);

  // Light surfaces.
  static const Color mist = Color(0xFFE6EFEC);
  static const Color shell = Color(0xFFFFFCF7);
  static const Color shellRaised = Color(0xFFFBF7EF);
  static const Color shellMuted = Color(0xFFF0E9DC);
  static const Color accentSoft = Color(0xFFD8E8E6);
  static const Color accentSurface = Color(0xFFEDF5F3);
  static const Color border = Color(0xFFD1C8B8);
  static const Color borderStrong = Color(0xFFB7AC98);
  static const Color textMuted = Color(0xFF5E6C6D);
  static const Color textSoft = Color(0xFF7B8889);

  // Status tones.
  static const Color info = Color(0xFF2F7784);
  static const Color infoSurface = Color(0xFFDCEFF2);
  static const Color successSurface = Color(0xFFDDEDE6);
  static const Color warningSurface = Color(0xFFF4E4D2);
  static const Color violet = Color(0xFF6A5C99);
  static const Color violetSurface = Color(0xFFE8E3F2);
  static const Color neutralSurface = Color(0xFFE7E3DA);
  static const Color danger = Color(0xFFB85757);
  static const Color dangerSurface = Color(0xFFF5DFDF);

  // Dark workspace surfaces.
  static const Color darkPage = Color(0xFF11181B);
  static const Color darkPageRaised = Color(0xFF172126);
  static const Color darkSurface = Color(0xFF1C252A);
  static const Color darkSurfaceRaised = Color(0xFF223037);
  static const Color darkSurfaceMuted = Color(0xFF27343C);
  static const Color darkBorder = Color(0xFF2F4047);
  static const Color darkBorderStrong = Color(0xFF3A4F58);
  static const Color darkText = Color(0xFFF1F6F4);
  static const Color darkTextMuted = Color(0xFFB3C1BD);
  static const Color darkTextSoft = Color(0xFF8D9B98);
  static const Color darkAccent = Color(0xFF74BBB4);
  static const Color darkAccentSurface = Color(0xFF244748);
  static const Color darkInfoSurface = Color(0xFF1F3740);
  static const Color darkSuccessSurface = Color(0xFF223A31);
  static const Color darkWarningSurface = Color(0xFF413023);

  static Color blendOn(Color overlay, {Color base = darkSurface}) {
    return Color.alphaBlend(overlay, base);
  }

  static Color readableForegroundFor(
    Color background, {
    Color light = darkText,
    Color dark = ink,
  }) {
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? light
        : dark;
  }

  static AppTone statusTone(String status) {
    return switch (status) {
      'submitted' => const AppTone(
        background: shellMuted,
        foreground: ink,
        border: border,
      ),
      'under_review' => const AppTone(
        background: warningSurface,
        foreground: ember,
        border: Color(0xFFE2C39E),
      ),
      'assigned' => const AppTone(
        background: mist,
        foreground: cobalt,
        border: Color(0xFFB5D0CF),
      ),
      'quoted' => const AppTone(
        background: warningSurface,
        foreground: ember,
        border: Color(0xFFE3B98E),
      ),
      'appointment_confirmed' => const AppTone(
        background: successSurface,
        foreground: pine,
        border: Color(0xFFB3D0C3),
      ),
      'pending_start' => const AppTone(
        background: violetSurface,
        foreground: violet,
        border: Color(0xFFC8BDE3),
      ),
      'project_started' => const AppTone(
        background: infoSurface,
        foreground: info,
        border: Color(0xFFB7D8E0),
      ),
      'work_done' => const AppTone(
        background: successSurface,
        foreground: pine,
        border: Color(0xFFAED0C1),
      ),
      'closed' => const AppTone(
        background: neutralSurface,
        foreground: textMuted,
        border: border,
      ),
      _ => const AppTone(
        background: shellMuted,
        foreground: ink,
        border: border,
      ),
    };
  }

  static ThemeData buildTheme() {
    final baseTextTheme = GoogleFonts.spaceGroteskTextTheme();
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: cobalt,
          brightness: Brightness.light,
        ).copyWith(
          primary: cobalt,
          onPrimary: Colors.white,
          secondary: pine,
          onSecondary: Colors.white,
          tertiary: ember,
          onTertiary: Colors.white,
          surface: shell,
          onSurface: ink,
          outline: border,
          outlineVariant: borderStrong,
          error: danger,
          onError: Colors.white,
        );

    final titleColor = ink;
    final bodyColor = ink;
    final mutedTextColor = textMuted;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: sand,
      canvasColor: sand,
      cardColor: shell,
      dividerColor: border.withValues(alpha: 0.78),
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: titleColor,
        ),
        displayMedium: baseTextTheme.displayMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: titleColor,
        ),
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: titleColor,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: titleColor,
        ),
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: titleColor,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: titleColor,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: titleColor,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(color: bodyColor),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(color: mutedTextColor),
        bodySmall: baseTextTheme.bodySmall?.copyWith(color: textSoft),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: bodyColor,
        ),
        labelMedium: baseTextTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: mutedTextColor,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: sand,
        foregroundColor: ink,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: shell,
        hintStyle: baseTextTheme.bodyMedium?.copyWith(color: textSoft),
        labelStyle: baseTextTheme.bodyMedium?.copyWith(color: textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: border.withValues(alpha: 0.9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: cobalt, width: 1.4),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: shell,
        margin: EdgeInsets.zero,
        shadowColor: ink.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: border.withValues(alpha: 0.72)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: shellRaised,
        side: BorderSide(color: border.withValues(alpha: 0.82)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: baseTextTheme.labelMedium?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: border.withValues(alpha: 0.72),
        thickness: 1,
        space: 1,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: border.withValues(alpha: 0.96)),
          backgroundColor: shell.withValues(alpha: 0.92),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cobalt,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: darkSurface,
        contentTextStyle: baseTextTheme.bodyMedium?.copyWith(color: darkText),
      ),
    );
  }
}
