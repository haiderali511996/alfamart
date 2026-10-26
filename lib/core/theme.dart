import 'package:flutter/material.dart';

/// Brand colours taken from the Alfa Mart logo.
class AppColors {
  static const navy = Color(0xFF011E65);
  static const navyDark = Color(0xFF011D5E);
  static const orange = Color(0xFFFD6900);
  static const success = Color(0xFF1B8A4B);
  static const danger = Color(0xFFC62828);
  static const warning = Color(0xFFF9A825);
  static const surface = Color(0xFFF5F7FB);

  static const sales = Color(0xFF1565C0);
  static const purchase = Color(0xFF6A1B9A);
  static const expense = Color(0xFFC62828);
  static const handover = Color(0xFFEF6C00);
  static const net = Color(0xFF1B8A4B);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.navy,
    primary: AppColors.navy,
    secondary: AppColors.orange,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.orange,
      foregroundColor: Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: AppColors.orange.withValues(alpha: 0.18),
      backgroundColor: Colors.white,
    ),
  );
}
