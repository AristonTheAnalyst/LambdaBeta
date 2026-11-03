import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../styles/app_fonts.dart';
import '../styles/app_radius.dart';
import '../styles/app_spacing.dart';
import '../styles/app_text_styles.dart';

/// The ten palettes, in picker order: the six dark ones first, then the four
/// light ones.
///
/// The enum name is the persisted value (`shared_preferences`), so renaming a
/// variant silently retires it and every device falls back to [primary].
enum LambdaThemeVariant {
  primary,
  midnight,
  deepSea,
  plum,
  graphite,
  ruby,
  monoLight,
  porcelain,
  sand,
  blush,
}

class LambdaColors {
  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color surfaceLow;
  final Color border;
  final Color primary;

  /// The secondary ink — text that must still be *read*, one step below
  /// [primary]. Distinct from [muted], which is decoration: on the dark
  /// theme `muted` measures 3.87:1 on `surface`, 3.45 on `surfaceHigh` and
  /// 3.04 on a primary glass, all below WCAG AA for text. This token clears
  /// 4.5:1 on every ground the theme produces (6.03 / 5.37 / 4.73 / 5.10 on
  /// the dark palette), so it is safe anywhere. Owned and measured by the
  /// **accessibility** skill; the role split is stated in **typography**
  /// (2026-10-21).
  final Color inkSecondary;

  final Color muted;
  final Color accent;
  final Color accentBg;
  final Color accentText;
  final Color danger;
  final Color dangerBg;
  final Color dangerBorder;

  /// Ink on a **solid** [danger] fill. White everywhere, because [danger] is
  /// the same dark brick in every palette. Distinct from [accentText], which
  /// is ink on a solid accent fill and turns dark wherever the accent is
  /// bright (2026-10-22).
  final Color dangerText;
  final Color success;
  final Color successBg;
  final Color planned;
  final Color plannedBg;

  /// The solid fill a planned value wears when the logged value IS the plan
  /// (2026-10-23) — the "white text on blue" chip. Deeper than [planned] in
  /// the palettes whose [planned] is a light blue, so [plannedText] clears AA
  /// on it; the light palettes use their own [planned], already deep enough.
  /// The dark palettes' blue is a muted navy a step off [plannedBg]: on a
  /// near-black ground a saturated blue chip read as a glowing box
  /// (2026-10-23), so the chip's boundary is drawn by its full-[planned]
  /// edge, not by the fill.
  final Color plannedFill;

  /// Ink on a solid [plannedFill] chip. White everywhere, because every
  /// [plannedFill] is deep enough to carry it — the [dangerText] role.
  final Color plannedText;

  const LambdaColors({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceLow,
    required this.border,
    required this.primary,
    required this.inkSecondary,
    required this.muted,
    required this.accent,
    required this.accentBg,
    required this.accentText,
    required this.danger,
    required this.dangerBg,
    required this.dangerBorder,
    required this.dangerText,
    required this.success,
    required this.successBg,
    required this.planned,
    required this.plannedBg,
    required this.plannedFill,
    required this.plannedText,
  });

  static const dark = LambdaColors(
    bg: Color(0xFF262626),
    surface: Color(0xFF2E2E2E),
    surfaceHigh: Color(0xFF363636),
    surfaceLow: Color(0xFF1E1E1E),
    border: Color(0xFF383838),
    primary: Color(0xFFDDCAB7),
    inkSecondary: Color(0xFFC0A992),
    muted: Color(0xFF9E8470),
    accent: Color(0xFFEB912B),
    accentBg: Color(0xFF3A2810),
    accentText: Color(0xFFFFFFFF),
    danger: Color(0xFFC0392B),
    dangerBg: Color(0xFF3A1A1A),
    dangerBorder: Color(0xFF7A2020),
    dangerText: Color(0xFFFFFFFF),
    success: Color(0xFF4ADE80),
    successBg: Color(0xFF16321F),
    planned: Color(0xFF60A5FA),
    plannedBg: Color(0xFF16253A),
    plannedFill: Color(0xFF1E3A5F),
    plannedText: Color(0xFFFFFFFF),
  );

  // ── The palette family (2026-10-22) ────────────────────────────────────────
  // Every dark palette keeps the same brick `danger` and green `success`; only
  // the brand accent moves. `ruby` is the test of that split: its accent is a
  // bright rose (L* 65 against the brick's 45, ΔE ≈ 31), so brand red never
  // reads as a warning, and destructive chrome always carries `dangerBg` plus
  // its own icon or word.
  static const midnight = LambdaColors(
    bg: Color(0xFF141821),
    surface: Color(0xFF1C212C),
    surfaceHigh: Color(0xFF242A37),
    surfaceLow: Color(0xFF10131A),
    border: Color(0xFF2E3543),
    primary: Color(0xFFD8DFEC),
    inkSecondary: Color(0xFFAFBBD0),
    muted: Color(0xFF7C8798),
    accent: Color(0xFF6AA7FF),
    accentBg: Color(0xFF18263B),
    accentText: Color(0xFF0B1220),
    danger: Color(0xFFC0392B),
    dangerBg: Color(0xFF3A1A1A),
    dangerBorder: Color(0xFF7A2020),
    dangerText: Color(0xFFFFFFFF),
    success: Color(0xFF4ADE80),
    successBg: Color(0xFF16321F),
    // Blue is the accent here, so planned moves to violet to stay legible as
    // its own signal.
    planned: Color(0xFFC084FC),
    plannedBg: Color(0xFF2A1B3D),
    plannedFill: Color(0xFF7C3AED),
    plannedText: Color(0xFFFFFFFF),
  );

  static const deepSea = LambdaColors(
    bg: Color(0xFF101A1B),
    surface: Color(0xFF172324),
    surfaceHigh: Color(0xFF1F2D2E),
    surfaceLow: Color(0xFF0B1314),
    border: Color(0xFF29393A),
    primary: Color(0xFFD6E4E3),
    inkSecondary: Color(0xFFA6BBB9),
    muted: Color(0xFF728A88),
    accent: Color(0xFF2DD4BF),
    accentBg: Color(0xFF0E2E2B),
    accentText: Color(0xFF04211F),
    danger: Color(0xFFC0392B),
    dangerBg: Color(0xFF3A1A1A),
    dangerBorder: Color(0xFF7A2020),
    dangerText: Color(0xFFFFFFFF),
    success: Color(0xFF4ADE80),
    successBg: Color(0xFF16321F),
    planned: Color(0xFF60A5FA),
    plannedBg: Color(0xFF16253A),
    plannedFill: Color(0xFF1E3A5F),
    plannedText: Color(0xFFFFFFFF),
  );

  static const plum = LambdaColors(
    bg: Color(0xFF1A141F),
    surface: Color(0xFF221A29),
    surfaceHigh: Color(0xFF2B2134),
    surfaceLow: Color(0xFF130E17),
    border: Color(0xFF372A42),
    primary: Color(0xFFE7DDEC),
    inkSecondary: Color(0xFFC2B0CF),
    muted: Color(0xFF8C7899),
    accent: Color(0xFFC084FC),
    accentBg: Color(0xFF311E42),
    accentText: Color(0xFF1B0B2A),
    danger: Color(0xFFC0392B),
    dangerBg: Color(0xFF3A1A1A),
    dangerBorder: Color(0xFF7A2020),
    dangerText: Color(0xFFFFFFFF),
    success: Color(0xFF4ADE80),
    successBg: Color(0xFF16321F),
    planned: Color(0xFF60A5FA),
    plannedBg: Color(0xFF16253A),
    plannedFill: Color(0xFF1E3A5F),
    plannedText: Color(0xFFFFFFFF),
  );

  static const graphite = LambdaColors(
    bg: Color(0xFF141414),
    surface: Color(0xFF1C1C1C),
    surfaceHigh: Color(0xFF242424),
    surfaceLow: Color(0xFF0E0E0E),
    border: Color(0xFF2F2F2F),
    primary: Color(0xFFE6E6E6),
    inkSecondary: Color(0xFFB4B4B4),
    muted: Color(0xFF808080),
    accent: Color(0xFFF2F2F2),
    accentBg: Color(0xFF2A2A2A),
    accentText: Color(0xFF121212),
    danger: Color(0xFFC0392B),
    dangerBg: Color(0xFF3A1A1A),
    dangerBorder: Color(0xFF7A2020),
    dangerText: Color(0xFFFFFFFF),
    success: Color(0xFF4ADE80),
    successBg: Color(0xFF16321F),
    planned: Color(0xFF60A5FA),
    plannedBg: Color(0xFF16253A),
    plannedFill: Color(0xFF1E3A5F),
    plannedText: Color(0xFFFFFFFF),
  );

  /// Red is the brand, not the alarm: a bright rose accent over a wine-tinted
  /// ground, while `danger` stays the brick every palette shares.
  static const ruby = LambdaColors(
    bg: Color(0xFF1A1315),
    surface: Color(0xFF221A1D),
    surfaceHigh: Color(0xFF2B2125),
    surfaceLow: Color(0xFF140E10),
    border: Color(0xFF3A2B30),
    primary: Color(0xFFEDDFE2),
    inkSecondary: Color(0xFFC9B2B8),
    muted: Color(0xFF937980),
    accent: Color(0xFFFB7185),
    accentBg: Color(0xFF3B1A22),
    accentText: Color(0xFF2A070D),
    danger: Color(0xFFC0392B),
    dangerBg: Color(0xFF3A1A1A),
    dangerBorder: Color(0xFF7A2020),
    dangerText: Color(0xFFFFFFFF),
    success: Color(0xFF4ADE80),
    successBg: Color(0xFF16321F),
    planned: Color(0xFF60A5FA),
    plannedBg: Color(0xFF16253A),
    plannedFill: Color(0xFF1E3A5F),
    plannedText: Color(0xFFFFFFFF),
  );

  static const monoLight = LambdaColors(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF4F4F4),
    surfaceHigh: Color(0xFFEBEBEB),
    surfaceLow: Color(0xFFE2E2E2),
    border: Color(0xFFD6D6D6),
    primary: Color(0xFF1A1A1A),
    inkSecondary: Color(0xFF5A5A5A),
    muted: Color(0xFF6B6B6B),
    accent: Color(0xFF2D2D2D),
    accentBg: Color(0xFFEEEEEE),
    accentText: Color(0xFFFFFFFF),
    danger: Color(0xFFC0392B),
    dangerBg: Color(0xFFFFEEEE),
    dangerBorder: Color(0xFFE8A8A8),
    dangerText: Color(0xFFFFFFFF),
    success: Color(0xFF2E7D46),
    successBg: Color(0xFFEAF6EE),
    planned: Color(0xFF2563EB),
    plannedBg: Color(0xFFDBEAFE),
    plannedFill: Color(0xFF2563EB),
    plannedText: Color(0xFFFFFFFF),
  );

  // ── Light palettes ─────────────────────────────────────────────────────────
  // The plain white one is `monoLight`; these tint the paper. Each accent is
  // deep enough to carry white ink, and where the accent is blue the planned
  // signal shifts hue (violet or teal) so the two never blur.
  static const porcelain = LambdaColors(
    bg: Color(0xFFF7F9FC),
    surface: Color(0xFFEDF1F7),
    surfaceHigh: Color(0xFFE2E8F1),
    surfaceLow: Color(0xFFD9E1EC),
    border: Color(0xFFD2DAE5),
    primary: Color(0xFF16202C),
    inkSecondary: Color(0xFF4C5B6E),
    muted: Color(0xFF64748B),
    accent: Color(0xFF1D4ED8),
    accentBg: Color(0xFFDCE7FF),
    accentText: Color(0xFFFFFFFF),
    danger: Color(0xFFC0392B),
    dangerBg: Color(0xFFFFEEEE),
    dangerBorder: Color(0xFFE8A8A8),
    dangerText: Color(0xFFFFFFFF),
    success: Color(0xFF2E7D46),
    successBg: Color(0xFFEAF6EE),
    planned: Color(0xFF7E22CE),
    plannedBg: Color(0xFFF3E8FF),
    plannedFill: Color(0xFF7E22CE),
    plannedText: Color(0xFFFFFFFF),
  );

  static const sand = LambdaColors(
    bg: Color(0xFFFAF6EF),
    surface: Color(0xFFF2ECE1),
    surfaceHigh: Color(0xFFE9E1D2),
    surfaceLow: Color(0xFFE0D6C4),
    border: Color(0xFFD6CAB5),
    primary: Color(0xFF2B241B),
    inkSecondary: Color(0xFF5E5243),
    muted: Color(0xFF7D6F5D),
    accent: Color(0xFF4338CA),
    accentBg: Color(0xFFE3E1FA),
    accentText: Color(0xFFFFFFFF),
    danger: Color(0xFFC0392B),
    dangerBg: Color(0xFFFFEEEE),
    dangerBorder: Color(0xFFE8A8A8),
    dangerText: Color(0xFFFFFFFF),
    success: Color(0xFF2E7D46),
    successBg: Color(0xFFEAF6EE),
    planned: Color(0xFF0F766E),
    plannedBg: Color(0xFFD5F2EE),
    plannedFill: Color(0xFF0F766E),
    plannedText: Color(0xFFFFFFFF),
  );

  static const blush = LambdaColors(
    bg: Color(0xFFFDF7F8),
    surface: Color(0xFFF7ECEF),
    surfaceHigh: Color(0xFFEFE0E4),
    surfaceLow: Color(0xFFE7D4D9),
    border: Color(0xFFE3CFD5),
    primary: Color(0xFF2D2024),
    inkSecondary: Color(0xFF5F4B52),
    muted: Color(0xFF7E6970),
    accent: Color(0xFF86198F),
    accentBg: Color(0xFFFAE8F7),
    accentText: Color(0xFFFFFFFF),
    danger: Color(0xFFC0392B),
    dangerBg: Color(0xFFFFEEEE),
    dangerBorder: Color(0xFFE8A8A8),
    dangerText: Color(0xFFFFFFFF),
    success: Color(0xFF2E7D46),
    successBg: Color(0xFFEAF6EE),
    planned: Color(0xFF2563EB),
    plannedBg: Color(0xFFDBEAFE),
    plannedFill: Color(0xFF2563EB),
    plannedText: Color(0xFFFFFFFF),
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
    TextStyle ui(
      double size, {
      FontWeight? weight,
      Color? color,
      double? height,
    }) => AppFonts.ui(
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
        // Secondary/tertiary are latent text slots in Material's stock
        // chrome; they carry the readable secondary ink, never `muted`
        // (2026-10-22).
        secondary: inkSecondary,
        onSecondary: accentText,
        tertiary: inkSecondary,
        onTertiary: accentText,
        error: danger,
        onError: dangerText,
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
        titleTextStyle: ui(
          AppTextStyles.lg,
          weight: FontWeight.w800,
          color: primary,
        ),
        contentTextStyle: ui(
          AppTextStyles.sm,
          color: inkSecondary,
          height: 1.4,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xl,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          // Accent, as Material's own default already was — a text button is
          // an action. Cancel-style dismissals take `inkSecondary` at their
          // call sites: quiet, but readable (2026-10-22).
          foregroundColor: WidgetStatePropertyAll(accent),
          textStyle: WidgetStatePropertyAll(
            ui(AppTextStyles.sm, weight: FontWeight.w600),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),
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
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
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
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs + 2,
        ),
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
        headerHeadlineStyle: ui(
          AppTextStyles.xl,
          weight: FontWeight.w800,
          color: primary,
        ),
        headerHelpStyle: ui(AppTextStyles.xs, color: inkSecondary),
        weekdayStyle: ui(AppTextStyles.xs, color: inkSecondary),
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
        // Cancel in the secondary ink, OK in accent — the app's dialog
        // language, where the affirmative wears the accent and the way out
        // stays quiet but readable (2026-10-22).
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: inkSecondary,
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

/// The catalog behind the picker: one place that says what each variant looks
/// like and what it is called.
///
/// Profile → Appearance and the dev Experimental screen both read this, so a
/// new palette cannot appear in one and be missing from the other.
extension LambdaThemeVariantInfo on LambdaThemeVariant {
  LambdaColors get colors => switch (this) {
    LambdaThemeVariant.primary => LambdaColors.dark,
    LambdaThemeVariant.midnight => LambdaColors.midnight,
    LambdaThemeVariant.deepSea => LambdaColors.deepSea,
    LambdaThemeVariant.plum => LambdaColors.plum,
    LambdaThemeVariant.graphite => LambdaColors.graphite,
    LambdaThemeVariant.ruby => LambdaColors.ruby,
    LambdaThemeVariant.monoLight => LambdaColors.monoLight,
    LambdaThemeVariant.porcelain => LambdaColors.porcelain,
    LambdaThemeVariant.sand => LambdaColors.sand,
    LambdaThemeVariant.blush => LambdaColors.blush,
  };

  /// Which heading the picker files this under. Read from the ground itself,
  /// never a hand-kept list, so a palette cannot be filed under the wrong one.
  bool get isLight => colors.bg.computeLuminance() >= 0.5;

  String get label => switch (this) {
    LambdaThemeVariant.primary => 'Primary Theme',
    LambdaThemeVariant.midnight => 'Midnight',
    LambdaThemeVariant.deepSea => 'Deep Sea',
    LambdaThemeVariant.plum => 'Plum',
    LambdaThemeVariant.graphite => 'Graphite',
    LambdaThemeVariant.ruby => 'Ruby',
    LambdaThemeVariant.monoLight => 'Mono Light',
    LambdaThemeVariant.porcelain => 'Porcelain',
    LambdaThemeVariant.sand => 'Sand',
    LambdaThemeVariant.blush => 'Blush',
  };

  String get description => switch (this) {
    LambdaThemeVariant.primary => 'Dark warm palette with an amber accent',
    LambdaThemeVariant.midnight => 'Blue-black night with an azure accent',
    LambdaThemeVariant.deepSea => 'Deep teal ground with an aqua accent',
    LambdaThemeVariant.plum => 'Dark violet ground with a lilac accent',
    LambdaThemeVariant.graphite => 'Neutral charcoal with a white accent',
    LambdaThemeVariant.ruby => 'Dark wine ground with a rose accent',
    LambdaThemeVariant.monoLight =>
      'Clean white background with dark grey text',
    LambdaThemeVariant.porcelain => 'Cool white ground with a cobalt accent',
    LambdaThemeVariant.sand => 'Warm paper ground with an indigo accent',
    LambdaThemeVariant.blush => 'Soft pink-white ground with a magenta accent',
  };
}

/// The app's palette switch, chosen in Profile → Appearance (2026-10-22).
///
/// The choice is a preference, not state: every change is written to local
/// preferences, and [restore] applies it before `runApp` so the first frame is
/// already in the chosen theme. It stays device-local on purpose — two devices
/// on one account may look different.
class LambdaThemeNotifier extends ValueNotifier<LambdaThemeVariant> {
  LambdaThemeNotifier() : super(LambdaThemeVariant.primary);

  static const _prefsKey = 'lambda_theme_variant';

  LambdaColors get colors => value.colors;

  /// Applies the stored variant, if there is one.
  ///
  /// Missing, unknown and unreadable values all mean "keep the default": the
  /// name is matched against the enum, so a retired variant cannot wedge the
  /// app on a palette that no longer exists.
  Future<void> restore() async {
    try {
      final stored = (await SharedPreferences.getInstance()).getString(
        _prefsKey,
      );
      for (final variant in LambdaThemeVariant.values) {
        if (variant.name == stored) {
          // Straight to the field: restoring is not a choice, so it must not
          // write the preference back.
          super.value = variant;
          return;
        }
      }
    } catch (_) {
      // No plugin (a test host) or a wiped store — the default stands.
    }
  }

  @override
  set value(LambdaThemeVariant next) {
    if (next == value) return;
    super.value = next;
    unawaited(_store(next));
  }

  Future<void> _store(LambdaThemeVariant variant) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, variant.name);
    } catch (_) {
      // The theme still applies for this run; only the memory of it is lost.
    }
  }
}

final themeNotifier = LambdaThemeNotifier();
