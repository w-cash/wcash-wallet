import 'package:flutter/material.dart';

abstract final class WardenColors {
  static const background = Color(0xFF090E0B);
  static const surface = Color(0xFF101713);
  static const surfaceRaised = Color(0xFF151F18);
  static const border = Color(0xFF26342B);
  static const accent = Color(0xFF74F57C);
  static const accentMuted = Color(0xFF173B1D);
  static const text = Color(0xFFF0F5F1);
  static const textMuted = Color(0xFF9AAC9F);
  static const error = Color(0xFFFF8A80);
}

ThemeData buildWardenTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: WardenColors.accent,
    brightness: Brightness.dark,
    surface: WardenColors.surface,
  );

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: scheme.copyWith(
      primary: WardenColors.accent,
      surface: WardenColors.surface,
      error: WardenColors.error,
    ),
    scaffoldBackgroundColor: WardenColors.background,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        color: WardenColors.text,
        fontSize: 42,
        height: 1.08,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.4,
      ),
      headlineSmall: TextStyle(
        color: WardenColors.text,
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      titleMedium: TextStyle(
        color: WardenColors.text,
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: WardenColors.text,
        fontSize: 16,
        height: 1.55,
      ),
      bodyMedium: TextStyle(
        color: WardenColors.textMuted,
        fontSize: 14,
        height: 1.5,
      ),
      labelLarge: TextStyle(fontWeight: FontWeight.w600),
    ),
    dividerColor: WardenColors.border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: WardenColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: WardenColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: WardenColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: WardenColors.accent, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: WardenColors.background,
        backgroundColor: WardenColors.accent,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
