import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_text_styles.dart';

class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.icon,
    this.loading = false,
    this.disabled = false,
    this.compact = false,
    this.solid = false,
    this.radius = AppRadius.md,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final IconData? icon;
  final bool loading;
  final bool disabled;
  final bool compact;

  /// What the button *says*, when [label] is deliberately empty and [icon]
  /// carries the whole meaning.
  ///
  /// A glyph-only control is unreadable to a screen reader — `label: ''` and an
  /// `Icon` announce nothing — so every icon-only button names itself here.
  /// Ignored when [label] is non-empty: the visible word is already the reading.
  ///
  /// The same string becomes the glyph's tooltip, so the word is also available
  /// to a sighted user who does not recognise the shape: one param, two
  /// audiences (2026-10-20).
  final String? semanticsLabel;
  // Full-fill treatment for a primary CTA, instead of the default
  // translucent "glass" look.
  final bool solid;

  /// Corner radius. The default is the button's own; a button standing on a
  /// rounded container passes that container's radius so the two curves agree
  /// ([FloatingBar.cornerRadius], say — a tighter corner sitting inside a
  /// rounder one reads as a different object resting on it).
  final double radius;

  /// [icon]'s size beside a label: chrome for the word, and the word is the
  /// button.
  static const double _iconWithLabelSize = 14;

  /// [icon]'s size with no label under it. A glyph standing alone IS the
  /// button, so it takes the size the chrome alone has to carry — the same 14
  /// reads as decoration with nothing for it to decorate.
  static const double _iconOnlySize = 18;

  /// The box a lone glyph stands in: 18 wide (the glyph's own size) by 20
  /// tall. The extra two pixels of height are what lift a compact glyph-only
  /// button onto the 40px target floor (10 + 20 + 10 = 40; 12 + 20 + 12 = 44
  /// otherwise) without touching any labelled button's metrics.
  ///
  /// The floor is spent inside the CONTENT, never by stretching the container:
  /// a `Container` with an `alignment` fills whatever loose constraints it
  /// meets, and a stretched button would drag a `MenuPopover` panel off the
  /// screen with it (found 2026-10-20 — the sort/filter menus hung below the
  /// fold).
  static const double _iconOnlyHeight = 20;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.primary;
    final iconOnly = icon != null && label.isEmpty;
    // Solid fills use the page background as text: readable on cream
    // (primary) and bright green (success) alike. Danger keeps its own white:
    // with a red brand theme (ruby) the accent's ink is dark, and borrowing it
    // would put near-black text on the brick fill.
    final fgColor = solid
        ? (effectiveColor == AppColors.danger
              ? AppColors.dangerText
              : AppColors.bg)
        : effectiveColor;
    final isDisabled = disabled || loading;

    Widget button = GestureDetector(
      onTap: isDisabled ? null : onPressed,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 16,
          vertical: compact ? 10 : 12,
        ),
        decoration: BoxDecoration(
          color: solid ? effectiveColor : effectiveColor.withAlpha(26),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: solid ? effectiveColor : effectiveColor.withAlpha(77),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: fgColor,
                ),
              )
            else ...[
              if (icon != null && label.isNotEmpty) ...[
                Icon(icon, size: _iconWithLabelSize, color: fgColor),
                const SizedBox(width: 6),
              ],
              if (icon != null && label.isEmpty)
                SizedBox(
                  width: _iconOnlySize,
                  height: _iconOnlyHeight,
                  child: Center(
                    child: Icon(icon, size: _iconOnlySize, color: fgColor),
                  ),
                )
              else
                Text(
                  label,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: fgColor,
                  ),
                ),
            ],
          ],
        ),
      ),
    );

    if (iconOnly && semanticsLabel != null) {
      button = Tooltip(
        message: semanticsLabel!,
        // The `Semantics` below is the reading; the tooltip is the hint. With
        // both enabled the label would be announced twice.
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          enabled: !isDisabled,
          label: semanticsLabel,
          child: button,
        ),
      );
    }

    return Opacity(opacity: isDisabled ? 0.5 : 1.0, child: button);
  }
}
