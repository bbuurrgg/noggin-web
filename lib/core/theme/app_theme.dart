import 'package:flutter/material.dart';

class AppTheme {
  static const background = Color(0xFFF5F5F7);
  static const ink = Color(0xFF1D1D1F);
  static const accent = Color(0xFF0A84FF);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: background,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'Roboto',
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        shape: CircleBorder(),
        elevation: 3,
      ),
    );
  }
}
