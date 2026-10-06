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
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4),
        titleLarge:
            TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
        titleMedium:
            TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: AppColors.text, height: 1.35),
        bodyMedium: TextStyle(color: AppColors.textMuted, height: 1.35),
        labelLarge:
            TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
      ).apply(bodyColor: AppColors.text, displayColor: AppColors.text),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandYellow,
          foregroundColor: AppColors.brandOrangeDark,
          minimumSize: const Size(48, 46),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: AppColors.brandOrangeDark,
          side: const BorderSide(color: Color(0xFFD7B98F)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE4D6C4))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE4D6C4))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: AppColors.brandOrange, width: 1.6)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.danger)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.danger, width: 1.6)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: const TextStyle(color: AppColors.textMuted),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIconColor: AppColors.brandOrange,
        suffixIconColor: AppColors.brandOrange,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.brandLight,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? AppColors.brandOrangeDark
                  : AppColors.textMuted,
            )),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.brandOrange),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.brandOrange,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF15130E),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
            color: Color(0xFFF3EDE1),
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4),
        titleLarge:
            TextStyle(color: Color(0xFFF3EDE1), fontWeight: FontWeight.w700),
        titleMedium:
            TextStyle(color: Color(0xFFF3EDE1), fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: Color(0xFFF3EDE1), height: 1.35),
        bodyMedium: TextStyle(color: Color(0xFFB8AB92), height: 1.35),
        labelLarge:
            TextStyle(color: Color(0xFFF3EDE1), fontWeight: FontWeight.w600),
      ).apply(
          bodyColor: const Color(0xFFF3EDE1),
          displayColor: const Color(0xFFF3EDE1)),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF201B12),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandYellow,
          foregroundColor: AppColors.brandOrangeDark,
          minimumSize: const Size(48, 46),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF201B12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3D331F))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3D331F))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
                color: AppColors.brandOrangeBright, width: 1.6)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF201B12),
        elevation: 1.5,
        margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        backgroundColor: const Color(0xFF201B12),
        indicatorColor: const Color(0xFF3D331F),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.brandYellow),
    );
  }
}
