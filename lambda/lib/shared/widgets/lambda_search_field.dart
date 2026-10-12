import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_text_styles.dart';

/// THE search field — [LambdaInput]'s chrome at toolbar scale: same
/// ground-aware fill, hairline border, radius and accent focus, but denser
/// padding and a smaller text size, so it sits in a row beside a button.
///
/// Every search box in the app wears this — library toolbars, sheets,
/// popovers, pickers — rather than each hand-rolling its own
/// [InputDecoration]. [showIcon] adds the muted magnifier the sheets and
/// popovers lead with; [suffix] takes a trailing control (a picker's collapse
/// X) where one exists.
class LambdaSearchField extends StatelessWidget {
  const LambdaSearchField({
    super.key,
    this.controller,
    this.hint = 'Search…',
    this.autofocus = false,
    this.showIcon = false,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.suffix,
    this.elevated = false,
  });

  /// Null for a field nothing clears or re-seeds — the text lives in the
  /// field itself.
  final TextEditingController? controller;
  final String hint;
  final bool autofocus;
  final bool showIcon;

  /// Character cap, for a field whose text can BECOME a name (the add-exercise
  /// modal's create row). Material's counter stays suppressed — the screens
  /// draw their own name-limit counter from a state listener.
  final int? maxLength;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final Widget? suffix;

  /// Whether the box stands on a `surface` ground (a card, or a modal sheet
  /// on its default background) — see [LambdaInput.elevated]. The fill steps
  /// up to [AppColors.surfaceHigh] so the box always separates from what it
  /// stands on.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      maxLength: maxLength,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autocorrect: false,
      style: AppFonts.ui(fontSize: AppTextStyles.sm, color: AppColors.primary),
      cursorColor: AppColors.primary,
      decoration: InputDecoration(
        hintText: hint,
        counterText: maxLength == null ? null : '',
        hintStyle: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          color: AppColors.muted,
        ),
        prefixIcon:
            showIcon ? Icon(Icons.search, size: 18, color: AppColors.muted) : null,
        suffixIcon: suffix,
        filled: true,
        fillColor: elevated ? AppColors.surfaceHigh : AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }
}
