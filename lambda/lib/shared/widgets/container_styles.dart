import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_radius.dart';

/// Container tones — the one place container chrome is defined. Fill, border
/// width (always 1), border color with its baked alpha, and radius all live
/// here so outlines can never drift again. Any new container should draw
/// through [lambdaBox] (or [LambdaContainer]) instead of hand-rolling a
/// BoxDecoration.
enum ContainerTone {
  /// Neutral card on the page background.
  surface,

  /// Slightly raised container — dropdown chips, search fields, disabled
  /// buttons. Same 1px border as [surface], lighter fill.
  ghost,

  /// Accent-tinted container — PR rows, summary cards, trophies. The thin
  /// 0.35 outline.
  accent,

  /// Danger-tinted container — warnings, delete states.
  danger,

  /// Planned-tinted container — planned-session cards.
  planned,

  /// Text-input field: surface fill, no border (the input's own decoration
  /// draws the chrome on top of the page background).
  field,

  /// Page-background fill with the standard border — cutout chips sitting on
  /// a surface card.
  bg,

  /// Transparent fill with the standard border — pure outline containers.
  outline,

  /// Transparent fill with the floating layer's brighter rim — [outline] for
  /// controls standing on the blurred floor (a review's add tile), where the
  /// house hairline is all but invisible. The same rim the glass wears.
  outlineBright,
}

/// The floating layer's rim — the edge every tone standing on (or made of)
/// the blurred floor shares: light cream, faint enough to read as an edge
/// rather than as a border.
///
/// A getter, not a stored value: the palette follows the theme, so the rim has
/// to be read where it is drawn.
Color get floatingRim => AppColors.primary.withValues(alpha: 0.30);

/// The floating layer's shadow — one recipe for anything hovering above the
/// page rather than sitting on it: the nav bar's pill, a review's bar, the
/// toolbar's anchored menus. Drawn on the outer decoration, outside whatever
/// clips the fill, or the blur gets cut off at the edges.
List<BoxShadow> get floatingShadow => [
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.28),
    blurRadius: 24,
    offset: const Offset(0, 8),
    spreadRadius: -6,
  ),
];

/// The box recipe for [tone]. Radius defaults to [AppRadius.lg]; pill
/// containers pass a larger radius (e.g. 999).
BoxDecoration lambdaBox(
  ContainerTone tone, {
  double radius = AppRadius.lg,
}) {
  final (Color fill, Color? border) = switch (tone) {
    ContainerTone.surface => (AppColors.surface, AppColors.border),
    ContainerTone.ghost => (AppColors.surfaceHigh, AppColors.border),
    ContainerTone.accent => (
        AppColors.accentBg,
        AppColors.accent.withValues(alpha: 0.35),
      ),
    ContainerTone.danger => (AppColors.dangerBg, AppColors.dangerBorder),
    ContainerTone.planned => (
        AppColors.plannedBg,
        AppColors.planned.withValues(alpha: 0.35),
      ),
    ContainerTone.field => (AppColors.surface, null),
    ContainerTone.bg => (AppColors.bg, AppColors.border),
    ContainerTone.outline => (Colors.transparent, AppColors.border),
    ContainerTone.outlineBright => (Colors.transparent, floatingRim),
  };
  return BoxDecoration(
    color: fill,
    borderRadius: BorderRadius.circular(radius),
    border: border == null ? null : Border.all(color: border),
  );
}

/// The glass recipe — translucent tint + soft hairline in [color]
/// (GlassButton's chrome, for pressables that aren't buttons: chips,
/// pills, arrows, trigger boxes). The one place those two alphas live.
BoxDecoration glassBox(Color color, {double radius = AppRadius.md}) =>
    BoxDecoration(
      color: color.withAlpha(26),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: color.withAlpha(77)),
    );

/// A tappable container with baked-in chrome — the replacement for ad-hoc
/// `Container(decoration: ...)` chrome everywhere.
class LambdaContainer extends StatelessWidget {
  const LambdaContainer({
    super.key,
    required this.child,
    this.tone = ContainerTone.surface,
    this.radius = AppRadius.lg,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final ContainerTone tone;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: lambdaBox(tone, radius: radius),
      padding: padding,
      child: child,
    );
    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}
