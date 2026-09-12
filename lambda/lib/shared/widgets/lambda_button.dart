import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_text_styles.dart';

enum ButtonVariant { primary, ghost, danger, success }

class LambdaButton extends StatelessWidget {
  const LambdaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.loading = false,
    this.disabled = false,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback onPressed;
  final ButtonVariant variant;
  final bool loading;
  final bool disabled;
  final bool fullWidth;

  /// The variant's semantic color — every button renders the glass recipe
  /// (translucent tint + soft hairline in this color), the same chrome as
  /// GlassButton and every other pressable.
  Color get _color => switch (variant) {
        ButtonVariant.primary => AppColors.primary,
        ButtonVariant.ghost   => AppColors.primary,
        ButtonVariant.danger  => AppColors.danger,
        ButtonVariant.success => AppColors.success,
      };

  @override
  Widget build(BuildContext context) {
    final isDisabled = disabled || loading;

    return Opacity(
      opacity: isDisabled ? 0.45 : 1.0,
      child: SizedBox(
        width: fullWidth ? double.infinity : null,
        height: 48,
        child: TextButton(
          onPressed: isDisabled ? null : onPressed,
          style: TextButton.styleFrom(
            backgroundColor: _color.withAlpha(26),
            foregroundColor: _color,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: _color.withAlpha(77)),
            ),
          ),
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _color,
                  ),
                )
              : Text(
                  label,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.md,
                    fontWeight: FontWeight.w600,
                    color: _color,
                  ),
                ),
        ),
      ),
    );
  }
}
