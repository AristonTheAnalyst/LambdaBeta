import 'package:flutter/material.dart';
import '../styles/app_fonts.dart';
import '../styles/app_radius.dart';
import '../styles/app_spacing.dart';
import '../styles/app_text_styles.dart';

enum LambdaThemeVariant { primary, monoLight }

class LambdaColors {
  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color surfaceLow;
  final Color border;
  final Color primary;
  final Color muted;
  final Color accent;
  final Color accentBg;
  final Color accentText;
  final Color danger;
  final Color dangerBg;
  final Color dangerBorder;
  final Color success;
  final Color successBg;
  final Color planned;
  final Color plannedBg;

  const LambdaColors({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceLow,
    required this.border,
    required this.primary,
    required this.muted,
    required this.accent,
    required this.accentBg,
    required this.accentText,
    required this.danger,
    required this.dangerBg,
    required this.dangerBorder,
    required this.success,
    required this.successBg,
    required this.planned,
    required this.plannedBg,
  });

  static const dark = LambdaColors(
    bg: Color(0xFF262626),
    surface: Color(0xFF2E2E2E),
    surfaceHigh: Color(0xFF363636),
    surfaceLow: Color(0xFF1E1E1E),
    border: Color(0xFF383838),
    primary: Color(0xFFDDCAB7),
    muted: Color(0xFF9E8470),
    accent: Color(0xFFEB912B),
    accentBg: Color(0xFF3A2810),
    accentText: Color(0xFFFFFFFF),
    danger: Color(0xFFC0392B),
    dangerBg: Color(0xFF3A1A1A),
    dangerBorder: Color(0xFF7A2020),
    success: Color(0xFF4ADE80),
    successBg: Color(0xFF16321F),
    planned: Color(0xFF60A5FA),
    plannedBg: Color(0xFF16253A),
  );

  static const monoLight = LambdaColors(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF4F4F4),
    surfaceHigh: Color(0xFFEBEBEB),
    surfaceLow: Color(0xFFE2E2E2),
    border: Color(0xFFD6D6D6),
    primary: Color(0xFF1A1A1A),
    muted: Color(0xFF6B6B6B),
    accent: Color(0xFF2D2D2D),
    accentBg: Color(0xFFEEEEEE),
    accentText: Color(0xFFFFFFFF),
    danger: Color(0xFFC0392B),
    dangerBg: Color(0xFFFFEEEE),
    dangerBorder: Color(0xFFE8A8A8),
    success: Color(0xFF2E7D46),
    successBg: Color(0xFFEAF6EE),
    planned: Color(0xFF2563EB),
    plannedBg: Color(0xFFDBEAFE),
  );

  ThemeData toThemeData() {
    final isDark = bg.computeLuminance() < 0.5;

    // The card recipe from `lambdaBox(ContainerTone.surface)`: the house fill,
    // a 1px hairline, radius 12. Every stock panel below reuses it, so a
    // dialog can never look like a different app from the sheet beside it.
    final panel = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(color: border),
    );
    // M3 tints a raised surface with the primary colour — accent orange on
    // this palette. Lambda's surfaces are flat, so raised stock panels say so
    // by turning the tint off and carrying the hairline instead.
    const noTint = Colors.transparent;
    // The two quiet styles the stock chrome needs, in the app's own voice:
    // the size is the body's, not Material's, and the tracking is off.
    TextStyle ui(double size, {FontWeight? weight, Color? color, double? height}) =>
        AppFonts.ui(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: 0,
          height: height,
        );

    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface: surface,
        surfaceContainerLowest: surfaceLow,
        surfaceContainerLow: surfaceLow,
        surfaceContainer: surface,
        surfaceContainerHigh: surfaceHigh,
        surfaceContainerHighest: surfaceHigh,
        primary: accent,
        onPrimary: accentText,
        secondary: muted,
        onSecondary: accentText,
        tertiary: muted,
        onTertiary: accentText,
        error: danger,
        onError: accentText,
        onSurface: primary,
        // Unset slots derive from the cream primary, which would draw cream
        // dividers and field underlines. The house hairline instead.
        outline: border,
        outlineVariant: border,
      ),
      textTheme: AppFonts.uiTextTheme(
        TextTheme(
          bodyMedium: TextStyle(
            fontSize: AppTextStyles.md,
            color: primary,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),

      // ── Stock chrome, themed once ────────────────────────────────────────
      // Everything below is Material's own widget with Lambda's dress on:
      // without it, an AlertDialog, a date picker or a snackbar arrives in
      // Google's default shape, type and elevation beside the house widgets.
      // New call sites inherit this, so the sweep only has to happen once.

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: noTint,
        elevation: 0,
        shape: panel,
        titleTextStyle: ui(AppTextStyles.lg,
            weight: FontWeight.w800, color: primary),
        contentTextStyle: ui(AppTextStyles.sm, color: muted, height: 1.45),
        actionsPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        insetPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
      ),

      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          // Accent, as Material's own default already was — a text button is
          // an action. Cancel-style buttons style themselves muted at their
          // call sites.
          foregroundColor: WidgetStatePropertyAll(accent),
          textStyle: WidgetStatePropertyAll(
              ui(AppTextStyles.sm, weight: FontWeight.w600)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          )),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          overlayColor: WidgetStatePropertyAll(accent.withValues(alpha: 0.12)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        // The family was missing here and Material's own body size took over,
        // which is what made notifications read as "not this app".
        contentTextStyle: ui(AppTextStyles.sm, color: primary),
        actionTextColor: accent,
        // Floating and rounded like every other Lambda panel, instead of
        // Material's square bar welded to the screen edge.
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: border),
        ),
        elevation: 0,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: surfaceHigh,
        surfaceTintColor: noTint,
        elevation: 0,
        shape: panel,
        textStyle: ui(AppTextStyles.sm, color: primary),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: noTint,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        dragHandleColor: border,
      ),

      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: border),
        ),
        textStyle: ui(AppTextStyles.xs, color: primary),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs + 2),
        waitDuration: const Duration(milliseconds: 400),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: surface,
        surfaceTintColor: noTint,
        elevation: 0,
        shape: panel,
        dividerColor: border,
        headerBackgroundColor: surfaceHigh,
        headerForegroundColor: primary,
        headerHeadlineStyle:
            ui(AppTextStyles.xl, weight: FontWeight.w800, color: primary),
        headerHelpStyle: ui(AppTextStyles.xs, color: muted),
        weekdayStyle: ui(AppTextStyles.xs, color: muted),
        dayStyle: ui(AppTextStyles.sm, color: primary),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return muted.withValues(alpha: 0.4);
          }
          // The selected day sits on an accent-filled circle.
          if (states.contains(WidgetState.selected)) return accentText;
          return primary;
        }),
        yearForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return muted.withValues(alpha: 0.4);
          }
          if (states.contains(WidgetState.selected)) return accentText;
          return primary;
        }),
        todayBorder: BorderSide(color: accent),
        // Cancel muted, OK in accent — the app's dialog language, where the
        // affirmative wears the accent and the way out stays quiet.
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: muted,
          textStyle: ui(AppTextStyles.sm, weight: FontWeight.w600),
        ),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: ui(AppTextStyles.sm, weight: FontWeight.w600),
        ),
      ),

      useMaterial3: true,
    );
  }
}

class LambdaThemeNotifier extends ValueNotifier<LambdaThemeVariant> {
  LambdaThemeNotifier() : super(LambdaThemeVariant.primary);

  LambdaColors get colors => value == LambdaThemeVariant.primary
      ? LambdaColors.dark
      : LambdaColors.monoLight;
}

final themeNotifier = LambdaThemeNotifier();
