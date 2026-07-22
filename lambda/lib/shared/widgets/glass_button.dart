import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
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
  });

  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final IconData? icon;
  final bool loading;
  final bool disabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.accent;
    final isDisabled = disabled || loading;

    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: GestureDetector(
        onTap: isDisabled ? null : onPressed,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: effectiveColor.withAlpha(26),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: effectiveColor.withAlpha(77)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: effectiveColor,
                  ),
                )
              else ...[
                if (icon != null) ...[
                  Icon(icon, size: 14, color: effectiveColor),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: effectiveColor,
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
