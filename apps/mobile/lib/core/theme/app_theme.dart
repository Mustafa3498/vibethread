import 'package:flutter/material.dart';

/// Brand palette: near-black canvas, warm off-white text, olive accent
/// (matches the Black / Olive products in the seed data).
class AppColors {
  static const background = Color(0xFF0D0D0D);
  static const surface = Color(0xFF161616);
  static const surfaceHigh = Color(0xFF202020);
  static const outline = Color(0xFF2E2E2E);
  static const text = Color(0xFFF2EFE8);
  static const textMuted = Color(0xFF9A978F);
  static const olive = Color(0xFF9BAA6B);
  static const onOlive = Color(0xFF11140A);
  static const amber = Color(0xFFE0A84B);
  static const danger = Color(0xFFE06C5B);
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.olive,
    onPrimary: AppColors.onOlive,
    secondary: AppColors.amber,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.danger,
    outline: AppColors.outline,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.outline, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.olive),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.olive.withValues(alpha: 0.22),
      disabledColor: AppColors.surface,
      side: const BorderSide(color: AppColors.outline),
      labelStyle: const TextStyle(color: AppColors.text, fontSize: 13),
      shape: const StadiumBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: TextStyle(color: AppColors.text),
    ),
  );
}
