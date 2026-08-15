import 'package:flutter/material.dart';

abstract final class ClawnsoleColors {
  static const deepPurple = Color(0xFF3B2A67);
  static const deepBlue = Color(0xFF173A69);
  static const cobalt = Color(0xFF3159C7);
  static const rail = Color(0xFF151329);
  static const railMuted = Color(0xFFC7C4E0);
  static const danger = Color(0xFFB4233A);
}

extension ClawnsoleThemeContext on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
}

ThemeData buildClawnsoleTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: ClawnsoleColors.deepPurple,
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFFC8B8FF) : ClawnsoleColors.deepPurple,
        onPrimary: dark ? const Color(0xFF211442) : Colors.white,
        secondary: dark ? const Color(0xFF93BDFF) : ClawnsoleColors.deepBlue,
        onSecondary: dark ? const Color(0xFF071D38) : Colors.white,
        tertiary: dark ? const Color(0xFFA8B9FF) : ClawnsoleColors.cobalt,
        onTertiary: dark ? const Color(0xFF0D1B4D) : Colors.white,
        surface: dark ? const Color(0xFF171827) : const Color(0xFFFCFCFF),
        onSurface: dark ? const Color(0xFFF0EFF8) : const Color(0xFF1E1E2B),
        surfaceContainerLowest: dark
            ? const Color(0xFF0D0E18)
            : const Color(0xFFF3F4FA),
        surfaceContainerLow: dark
            ? const Color(0xFF202235)
            : const Color(0xFFF0F1F8),
        surfaceContainer: dark
            ? const Color(0xFF282A40)
            : const Color(0xFFE8EAF4),
        surfaceContainerHigh: dark
            ? const Color(0xFF30334B)
            : const Color(0xFFE1E4F0),
        onSurfaceVariant: dark
            ? const Color(0xFFB9B9CA)
            : const Color(0xFF616174),
        outline: dark ? const Color(0xFF76768B) : const Color(0xFF777789),
        outlineVariant: dark
            ? const Color(0xFF393B52)
            : const Color(0xFFD9DBE7),
        error: dark ? const Color(0xFFFFB2BE) : ClawnsoleColors.danger,
        errorContainer: dark
            ? const Color(0xFF5C1725)
            : const Color(0xFFFFDADF),
      );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surfaceContainerLowest,
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 58,
        height: .96,
        letterSpacing: -2.2,
        fontWeight: FontWeight.w700,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 42,
        height: 1,
        letterSpacing: -1.3,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 27,
        height: 1.05,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      bodyLarge: TextStyle(fontSize: 15, height: 1.5),
      bodyMedium: TextStyle(fontSize: 13, height: 1.45),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    ),
  );

  return base.copyWith(
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    dividerColor: scheme.outlineVariant,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? const Color(0xFF292443) : ClawnsoleColors.rail,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
    ),
    dialogTheme: DialogThemeData(backgroundColor: scheme.surface),
  );
}
