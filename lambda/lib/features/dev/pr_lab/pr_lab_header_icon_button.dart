// LAB COPY — the /dev/pr-lab layout sandbox's own copy of a shared
// widget. Never import this from a production screen. Edit freely: nothing
// here can reach the real session, planner, logs or PR History demo
// (2026-10-21).

import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_radius.dart';
import '../../../shared/widgets/container_styles.dart';

/// Where a header glyph stands.
enum PrLabHeaderIconVariant {
  /// A bare glyph in a 44×44 target — the header's own controls (back, close,
  /// edit, done). The box would be a second frame around a glyph that already
  /// sits in one.
  bare,

  /// The glass square — a glyph in a toolbar, where the box is what tells the
  /// controls apart from the labels beside them.
  boxed,
}

/// THE icon-only header control (2026-10-20).
///
/// Before this, a header's back control was drawn three ways — a bare
/// `GestureDetector` + `Icon` at a dozen sites, a Material `IconButton` at
/// seven more, and a text `GlassButton` in the session wizard — and most of
/// them announced nothing to a screen reader. One widget, one target, one
/// label.
///
/// The bare variant is [InfoButton]'s recipe exactly: a 44×44 invisible target
/// around a small centred glyph, so the button is as easy to hit as the compact
/// pill it replaced even though it looks smaller.
///
/// [onPressed] null draws the button inert (muted glyph, no tap) rather than
/// removing it — a control that disappears shifts everything beside it.
class PrLabHeaderIconButton extends StatelessWidget {
  const PrLabHeaderIconButton({
    super.key,
    required this.icon,
    required this.semanticsLabel,
    required this.onPressed,
    this.color,
    this.glyphSize = 20,
    this.variant = PrLabHeaderIconVariant.bare,
    this.compact = false,
    this.boxSize,
    this.radius,
  });

  final IconData icon;

  /// The word the glyph stands for — `Back`, `Cancel`, `Edit`, `Done`. The
  /// only reading a screen reader gets, and the reason a glyph is allowed to
  /// replace a word at all.
  final String semanticsLabel;

  final VoidCallback? onPressed;
  final Color? color;
  final double glyphSize;
  final PrLabHeaderIconVariant variant;

  /// The boxed variant's target: 36, or 32 where the toolbar is tight.
  final bool compact;

  /// An explicit box edge for a caller whose bar speaks at its own scale —
  /// the PR Lab's date changer, whose arrows stand at the nav bar's size
  /// (2026-10-21). Null keeps [compact]'s 32/36.
  final double? boxSize;

  /// An explicit corner for the boxed variant — the date changer passes the
  /// selector's own 6 so its two chevron pairs draw one shape (2026-10-21).
  /// Null keeps the header control's near-square 2.
  final double? radius;

  double get _boxSize => boxSize ?? (compact ? 32 : 36);

  double get _radius => radius ?? AppRadius.md - 6;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final effectiveColor = color ?? AppColors.accent;

    final glyph = Icon(
      icon,
      size: glyphSize,
      color: enabled ? effectiveColor : AppColors.muted,
    );

    final button = switch (variant) {
      PrLabHeaderIconVariant.bare => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(width: 44, height: 44, child: glyph),
      ),
      PrLabHeaderIconVariant.boxed => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: _boxSize,
          height: _boxSize,
          alignment: Alignment.center,
          decoration: enabled
              ? glassBox(effectiveColor, radius: _radius)
              : BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(_radius),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
          child: glyph,
        ),
      ),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      child: button,
    );
  }
}
