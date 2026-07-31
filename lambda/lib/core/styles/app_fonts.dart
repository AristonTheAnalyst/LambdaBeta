import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Font-family roles, mirroring the two-typeface system from the session
/// screen's Figma reference: Manrope for UI text/headings, JetBrains Mono
/// for numeric values and uppercase micro-labels.
abstract final class AppFonts {
  static TextStyle ui({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.manrope(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextTheme uiTextTheme(TextTheme base) => GoogleFonts.manropeTextTheme(base);
}
