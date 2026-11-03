import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import 'container_styles.dart';

/// The session stage's chevron recipe (2026-10-22): a 40px target, a 24px
/// `chevron_*` glyph and the 6 corner. The exercise selector's flanks and the
/// date bar's two session arrows draw from it, so the two pairs never read as
/// two sizes of the same control — the PR Lab's one-chevron-species rule,
/// carried into production.
///
/// Live is the glass square; spent is the transparent hairline. The spent
/// arrow keeps its shape — a control that disappears shifts everything beside
/// it — and still claims its tap, so a dead end is a hole in neither the
/// layout nor the hit test.
class SessionChevronButton extends StatelessWidget {
  const SessionChevronButton({
    super.key,
    required this.icon,
    required this.semanticsLabel,
    required this.onPressed,
    this.enabled = true,
    this.size = kSessionChevronSize,
    this.iconSize = kSessionChevronIconSize,
  });

  /// The standard target — also the height the selector's field stands at
  /// between its arrows, and the row the date bar's phrase stands in.
  static const double kSessionChevronSize = 40;

  /// The standard glyph — the date bar's own `chevron_*` size.
  static const double kSessionChevronIconSize = 24;

  /// The chevron's corner; the selector's glass and the bar's glass share it.
  static const double kSessionChevronRadius = 6;

  final IconData icon;

  /// The word the arrow is for — screen readers and the tooltip-less bar
  /// both need it, and it is what lets the control be a bare glyph.
  final String semanticsLabel;

  /// The tap. Only fires while [enabled].
  final VoidCallback onPressed;

  final bool enabled;

  /// The full tap target; the selector's popover draws its smaller reorder
  /// arrows at 28 through the same recipe.
  final double size;

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final live = enabled;
    return Semantics(
      button: true,
      enabled: live,
      label: semanticsLabel,
      child: GestureDetector(
        onTap: live ? onPressed : () {},
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          // The glass recipe — the same chrome as every other pressable.
          decoration: live
              ? glassBox(
                  AppColors.primary,
                  radius: kSessionChevronRadius,
                )
              : BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(kSessionChevronRadius),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
          child: Icon(
            icon,
            size: iconSize,
            color: live ? AppColors.primary : AppColors.muted,
          ),
        ),
      ),
    );
  }
}
