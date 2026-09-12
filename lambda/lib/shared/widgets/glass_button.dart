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
            borderRadius: BorderRadius.circular(AppRadius.md),
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
                  Icon(icon, size: 14, color: fgColor),
                  const SizedBox(width: 6),
                ],
                if (icon != null && label.isEmpty)
                  Icon(icon, size: 14, color: fgColor)
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
