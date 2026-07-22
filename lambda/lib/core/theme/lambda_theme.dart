import 'package:flutter/material.dart';
import '../styles/app_text_styles.dart';

enum LambdaThemeVariant { primary, monoLight }

class LambdaColors {
  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color primary;
  final Color muted;
  final Color accent;
  final Color accentBg;
  final Color accentText;
  final Color danger;
  final Color dangerBg;
  final Color dangerBorder;

  const LambdaColors({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.primary,
    required this.muted,
    required this.accent,
    required this.accentBg,
    required this.accentText,
    required this.danger,
    required this.dangerBg,
    required this.dangerBorder,
  });

  static const dark = LambdaColors(
    bg:           Color(0xFF262626),
    surface:      Color(0xFF2E2E2E),
    surfaceHigh:  Color(0xFF363636),
    border:       Color(0xFF383838),
    primary:      Color(0xFFDDCAB7),
    muted:        Color(0xFF9E8470),
    accent:       Color(0xFFEB912B),
    accentBg:     Color(0xFF3A2810),
    accentText:   Color(0xFFFFFFFF),
    danger:       Color(0xFFC0392B),
    dangerBg:     Color(0xFF3A1A1A),
    dangerBorder: Color(0xFF7A2020),
  );

  static const monoLight = LambdaColors(
    bg:           Color(0xFFFFFFFF),
    surface:      Color(0xFFF4F4F4),
    surfaceHigh:  Color(0xFFEBEBEB),
    border:       Color(0xFFD6D6D6),
    primary:      Color(0xFF1A1A1A),
    muted:        Color(0xFF6B6B6B),
    accent:       Color(0xFF2D2D2D),
    accentBg:     Color(0xFFEEEEEE),
    accentText:   Color(0xFFFFFFFF),
    danger:       Color(0xFFC0392B),
    dangerBg:     Color(0xFFFFEEEE),
    dangerBorder: Color(0xFFE8A8A8),
  );

  ThemeData toThemeData() {
    final isDark = bg.computeLuminance() < 0.5;
    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface:     surface,
        primary:     accent,
        onPrimary:   accentText,
        secondary:   muted,
        onSecondary: accentText,
        tertiary:    muted,
        onTertiary:  accentText,
        error:       danger,
        onError:     accentText,
        onSurface:   primary,
      ),
      textTheme: TextTheme(
        bodyMedium: TextStyle(
          fontSize: AppTextStyles.md,
          color: primary,
          fontWeight: FontWeight.w400,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: TextStyle(color: primary),
      ),
      useMaterial3: true,
    );
  }
}

class LambdaThemeNotifier extends ValueNotifier<LambdaThemeVariant> {
  LambdaThemeNotifier() : super(LambdaThemeVariant.primary);

  LambdaColors get colors =>
      value == LambdaThemeVariant.primary ? LambdaColors.dark : LambdaColors.monoLight;
}

final themeNotifier = LambdaThemeNotifier();
