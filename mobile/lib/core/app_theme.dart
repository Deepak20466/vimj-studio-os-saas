import 'package:flutter/material.dart';

class AppColors {
  // Matches CLAUDE.md's UI color spec (#FFA500 / #FFF500 / #F0F8FF) and the
  // web dashboard's theme.css, so the mobile app looks like the same product.
  static const Color brandOrange = Color(0xFFB35900);
  static const Color brandOrangeBright = Color(0xFFFFA500);
  static const Color brandOrangeDark = Color(0xFF7A3D00);
  static const Color brandYellow = Color(0xFFFFC400);
  static const Color brandYellowBright = Color(0xFFFFF500);
  static const Color brandYellowDark = Color(0xFFE6AC00);
  static const Color brandLight = Color(0xFFFBE8D3);
  static const Color aliceBlue = Color(0xFFF0F8FF);
  static const Color bg = Color(0xFFFDF1E2);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);
  // Matches theme.css's --text/--text-muted so body copy reads clearly
  // instead of Flutter's default pale gray.
  static const Color text = Color(0xFF1A1A2E);
  static const Color textMuted = Color(0xFF6B5A45);
}

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.brandOrange,
        brightness: Brightness.light,
        primary: AppColors.brandOrange,
        secondary: AppColors.brandYellowDark,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(color: AppColors.text),
        titleLarge: TextStyle(color: AppColors.text),
        titleMedium: TextStyle(color: AppColors.text),
        bodyLarge: TextStyle(color: AppColors.text),
        bodyMedium: TextStyle(color: AppColors.textMuted),
        labelLarge: TextStyle(color: AppColors.text),
      ).apply(bodyColor: AppColors.text, displayColor: AppColors.text),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandYellow,
          foregroundColor: AppColors.brandOrangeDark,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: const TextStyle(color: AppColors.textMuted),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIconColor: AppColors.brandOrange,
        suffixIconColor: AppColors.brandOrange,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.brandOrange,
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF201B12),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandYellow,
          foregroundColor: AppColors.brandOrangeDark,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
