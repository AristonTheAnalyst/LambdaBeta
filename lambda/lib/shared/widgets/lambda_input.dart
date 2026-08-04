import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_text_styles.dart';

class LambdaInput extends StatelessWidget {
  const LambdaInput({
    super.key,
    required this.controller,
    this.label,
    this.placeholder,
    this.error,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.required = false,
  });

  final TextEditingController controller;
  final String? label;
  final String? placeholder;
  final String? error;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Renders a small accent `*` after the label to mark the field required.
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label!,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              if (required) ...[
                const SizedBox(width: 2),
                Text('*',
                    style: AppFonts.ui(
                        fontSize: AppTextStyles.sm,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent)),
              ],
            ],
          ),
          const SizedBox(height: 6),
        ],
        TextField(
          controller: controller,
          obscureText: obscureText,
          enabled: enabled,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          autocorrect: false,
          enableSuggestions: !obscureText,
          style: AppFonts.ui(
            fontSize: AppTextStyles.md,
            color: AppColors.primary,
            fontWeight: FontWeight.w400,
          ),
          cursorColor: AppColors.primary,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: AppFonts.ui(
              color: AppColors.muted,
              fontSize: AppTextStyles.md,
            ),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? AppColors.dangerBorder : AppColors.border,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? AppColors.danger : AppColors.accent,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.border),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: AppFonts.ui(
              fontSize: AppTextStyles.xs,
              color: AppColors.danger,
            ),
          ),
        ],
      ],
    );
  }
}
