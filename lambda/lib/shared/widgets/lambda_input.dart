import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_text_styles.dart';

class LambdaInput extends StatelessWidget {
  const LambdaInput({
    super.key,
    required this.controller,
    this.focusNode,
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
    this.minLines,
    this.maxLines,
    this.maxLength,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
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

  /// Multiline sizing — pass both (e.g. 2 and 6) for a notes-style field.
  final int? minLines;
  final int? maxLines;

  /// Character cap, for fields taking an exercise or variation name
  /// ([kMaxExerciseNameLength]). Null — the default — leaves the field
  /// uncapped, which is every caller but those three.
  ///
  /// Material's own counter is suppressed in favour of [NameLimitCounter],
  /// which the screens render from their state listener; two counters under one
  /// field would be two spellings of the same number.
  final int? maxLength;

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
          focusNode: focusNode,
          obscureText: obscureText,
          enabled: enabled,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          minLines: minLines,
          maxLines: maxLines,
          maxLength: maxLength,
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
            // Material's counter only appears when a cap is set; the screens
            // draw NameLimitCounter instead.
            counterText: maxLength == null ? null : '',
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
