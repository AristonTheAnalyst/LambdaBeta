import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_text_styles.dart';

enum ButtonVariant { primary, ghost, danger }

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

  Color get _bg => switch (variant) {
        ButtonVariant.primary => AppColors.accent,
        ButtonVariant.ghost   => Colors.transparent,
        ButtonVariant.danger  => AppColors.danger,
      };

  Color get _fg => switch (variant) {
        ButtonVariant.primary => AppColors.accentText,
        ButtonVariant.ghost   => AppColors.accent,
        ButtonVariant.danger  => AppColors.accentText,
      };

  BorderSide get _border => switch (variant) {
        ButtonVariant.ghost => BorderSide(color: AppColors.accent),
        _                   => BorderSide.none,
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
            backgroundColor: _bg,
            foregroundColor: _fg,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
              side: _border,
            ),
          ),
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _fg,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: AppTextStyles.md,
                    fontWeight: FontWeight.w600,
                    color: _fg,
                  ),
                ),
        ),
      ),
    );
  }
}
