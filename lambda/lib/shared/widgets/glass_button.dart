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
  });

  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final IconData? icon;
  final bool loading;
  final bool disabled;
  final bool compact;
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

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.primary;
    // Solid fills use the page background as text: readable on cream
    // (primary) and bright green (success) alike.
    final fgColor = solid
        ? (effectiveColor == AppColors.danger
            ? AppColors.accentText
            : AppColors.bg)
        : effectiveColor;
    final isDisabled = disabled || loading;

    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: GestureDetector(
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
                color: solid ? effectiveColor : effectiveColor.withAlpha(77)),
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
                  Icon(icon, size: _iconOnlySize, color: fgColor)
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
      ),
    );
  }
}
