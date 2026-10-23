import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_radius.dart';
import 'container_styles.dart';

/// Where a header glyph stands.
enum HeaderIconVariant {
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
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.semanticsLabel,
    required this.onPressed,
    this.color,
    this.glyphSize = 20,
    this.variant = HeaderIconVariant.bare,
    this.compact = false,
  });

  final IconData icon;

  /// The word the glyph stands for — `Back`, `Cancel`, `Edit`, `Done`. The
  /// only reading a screen reader gets, and the reason a glyph is allowed to
  /// replace a word at all.
  final String semanticsLabel;

  final VoidCallback? onPressed;
  final Color? color;
  final double glyphSize;
  final HeaderIconVariant variant;

  /// The boxed variant's target: 36, or 32 where the toolbar is tight.
  final bool compact;

  double get _boxSize => compact ? 32 : 36;

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
      HeaderIconVariant.bare => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(width: 44, height: 44, child: glyph),
      ),
      HeaderIconVariant.boxed => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: _boxSize,
          height: _boxSize,
          alignment: Alignment.center,
          decoration: enabled
              ? glassBox(effectiveColor, radius: AppRadius.md - 6)
              : BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md - 6),
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
