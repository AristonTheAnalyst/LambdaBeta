import 'package:flutter/material.dart';
import '../theme/lambda_theme.dart';

abstract final class AppColors {
  static Color get bg           => themeNotifier.colors.bg;
  static Color get surface      => themeNotifier.colors.surface;
  static Color get surfaceHigh  => themeNotifier.colors.surfaceHigh;
  static Color get border       => themeNotifier.colors.border;
  static Color get primary      => themeNotifier.colors.primary;
  static Color get muted        => themeNotifier.colors.muted;
  static Color get accent       => themeNotifier.colors.accent;
  static Color get accentBg     => themeNotifier.colors.accentBg;
  static Color get accentText   => themeNotifier.colors.accentText;
  static Color get danger       => themeNotifier.colors.danger;
  static Color get dangerBg     => themeNotifier.colors.dangerBg;
  static Color get dangerBorder => themeNotifier.colors.dangerBorder;
  static Color get success      => themeNotifier.colors.success;
  static Color get successBg    => themeNotifier.colors.successBg;
  static Color get planned      => themeNotifier.colors.planned;
  static Color get plannedBg    => themeNotifier.colors.plannedBg;
  static Color get history      => themeNotifier.colors.history;
  static Color get historyBg    => themeNotifier.colors.historyBg;
}
