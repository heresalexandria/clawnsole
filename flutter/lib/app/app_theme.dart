import 'package:flutter/material.dart';

abstract final class ClawnsoleColors {
  static const ink = Color(0xFF20241F);
  static const forest = Color(0xFF223C32);
  static const forestSoft = Color(0xFF3C5B4E);
  static const cream = Color(0xFFF5F0E7);
  static const paper = Color(0xFFFCF9F3);
  static const clay = Color(0xFFC66F4D);
  static const clayDark = Color(0xFF8C472F);
  static const mustard = Color(0xFFD3A449);
  static const sage = Color(0xFFABC0A5);
  static const muted = Color(0xFF746F65);
  static const line = Color(0xFFDCD3C5);
  static const danger = Color(0xFF9C3F36);
}

ThemeData buildClawnsoleTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: ClawnsoleColors.forest,
    brightness: Brightness.light,
    primary: ClawnsoleColors.forest,
    secondary: ClawnsoleColors.clay,
    surface: ClawnsoleColors.paper,
    error: ClawnsoleColors.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: ClawnsoleColors.cream,
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 58,
        height: .96,
        letterSpacing: -2.2,
        fontWeight: FontWeight.w700,
        color: ClawnsoleColors.ink,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 42,
        height: 1,
        letterSpacing: -1.3,
        fontWeight: FontWeight.w700,
        color: ClawnsoleColors.ink,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 27,
        height: 1.05,
        fontWeight: FontWeight.w700,
        color: ClawnsoleColors.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: ClawnsoleColors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: ClawnsoleColors.ink,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        height: 1.5,
        color: ClawnsoleColors.ink,
      ),
      bodyMedium: TextStyle(
        fontSize: 13,
        height: 1.45,
        color: ClawnsoleColors.muted,
      ),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ClawnsoleColors.paper,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: ClawnsoleColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: ClawnsoleColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: ClawnsoleColors.clay, width: 1.5),
      ),
      hintStyle: const TextStyle(color: Color(0xFFA09A90)),
    ),
    dividerColor: ClawnsoleColors.line,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ClawnsoleColors.clay,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ClawnsoleColors.forest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        side: const BorderSide(color: ClawnsoleColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: ClawnsoleColors.forest,
      contentTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
