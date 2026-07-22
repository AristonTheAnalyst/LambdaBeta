import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

abstract final class AppTheme {
  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.dark(
        surface: AppColors.surface,
        primary: AppColors.accent,
        onPrimary: AppColors.accentText,
        secondary: AppColors.muted,
        onSecondary: AppColors.accentText,
        tertiary: AppColors.muted,
        onTertiary: AppColors.accentText,
        error: AppColors.danger,
        onError: AppColors.accentText,
      ),
      textTheme: TextTheme(
        bodyMedium: TextStyle(
          fontSize: AppTextStyles.md,
          color: AppColors.primary,
          fontWeight: FontWeight.w400,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: TextStyle(color: AppColors.primary),
      ),
      useMaterial3: true,
    );
  }
}
