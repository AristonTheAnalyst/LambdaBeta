import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Font-family roles, mirroring the two-typeface system from the session
/// screen's Figma reference: a clean UI font for text/headings, JetBrains Mono
/// for numeric values and uppercase micro-labels.
///
/// On iOS the UI font is Apple's system typeface (SF Pro — resolved at runtime
/// by Flutter from `PlatformTextTheme`), so Material surfaces like the date
/// picker get the native look rather than a bundled webfont; every other
/// platform falls back to bundled Manrope.
abstract final class AppFonts {
  /// Resolved per platform: `.SF Pro` on iOS, Manrope elsewhere. The literal
  /// '.SF Pro' name is what Flutter's text theme resolves to the system SF Pro
  /// on iOS. Manrope stays bundled as the cross-platform default.
  static String get uiFamily =>
      defaultTargetPlatform == TargetPlatform.iOS ? '.SF Pro' : 'Manrope';

  static const monoFamily = 'JetBrainsMono';

  /// Disables google_fonts runtime fetching so a cold/offline start can never
  /// fall back to the platform default (Roboto). Call once before runApp.
  static void init() {
    GoogleFonts.config.allowRuntimeFetching = false;
  }

  static TextStyle ui({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      _text(uiFamily,
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          letterSpacing: letterSpacing,
          height: height);

  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      _text(monoFamily,
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          letterSpacing: letterSpacing,
          height: height);

  static TextStyle _text(
    String family, {
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      TextStyle(
        fontFamily: family,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// Applies the bundled Manrope family to a whole text theme, preserving
  /// each style's existing size/weight/color.
  static TextTheme uiTextTheme(TextTheme base) => TextTheme(
        displayLarge: _apply(base.displayLarge),
        displayMedium: _apply(base.displayMedium),
        displaySmall: _apply(base.displaySmall),
        headlineLarge: _apply(base.headlineLarge),
        headlineMedium: _apply(base.headlineMedium),
        headlineSmall: _apply(base.headlineSmall),
        titleLarge: _apply(base.titleLarge),
        titleMedium: _apply(base.titleMedium),
        titleSmall: _apply(base.titleSmall),
        bodyLarge: _apply(base.bodyLarge),
        bodyMedium: _apply(base.bodyMedium),
        bodySmall: _apply(base.bodySmall),
        labelLarge: _apply(base.labelLarge),
        labelMedium: _apply(base.labelMedium),
        labelSmall: _apply(base.labelSmall),
      );

  static TextStyle _apply(TextStyle? t) =>
      t == null ? TextStyle(fontFamily: uiFamily) : t.copyWith(fontFamily: uiFamily);
}
