import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import './container_styles.dart';

/// THE read-only text box — the display half of [LambdaInput].
///
/// Where an input is where text is written, a readout is where it is read
/// back: the same label above (a note reads under the header it was typed
/// under), the text in a ghost box that holds its shape for a short note and
/// scrolls inside for a long one. The past-session viewer's Summary tab is the
/// reference; the exercise review note's record state is the same box. Text
/// shown rather than written wears this — never a bare `Text` on a card.
///
/// The empty case is the caller's, in one of three shapes: the box is not
/// drawn (the review note on a snapshot), the surrounding section speaks
/// instead (the bookend), or [placeholder] answers inside the box — secondary
/// ink in the value's own place, so a record that left no note still shows
/// the box it would have filled (the review note while Compare is up, where
/// dropping the row mid-flip would move the card under the eye that just
/// tapped it).
class LambdaReadout extends StatelessWidget {
  const LambdaReadout({
    super.key,
    this.label,
    required this.value,
    this.placeholder,
    this.textSize = AppTextStyles.sm,
  });

  /// Same slot and styling as [LambdaInput.label]; null for a box the
  /// surrounding section already names.
  final String? label;

  final String value;

  /// What the box reads when [value] is blank — `inkSecondary`, like
  /// [LambdaInput]'s own placeholder: readable, but one step down from a
  /// real note. Null leaves a blank box blank.
  final String? placeholder;

  /// The value's size. The ladder's `sm` by default; a box that flips into a
  /// [LambdaInput] passes `md` so the pair's toggle never resizes the text
  /// (the input writes at `md`), leaving size out of the read/edit signal
  /// (2026-10-28).
  final double textSize;

  @override
  Widget build(BuildContext context) {
    final isBlank = value.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
          child: ConstrainedBox(
            // Roomier than one line so short notes still read as a box;
            // long notes scroll inside it instead of stretching the card.
            constraints: const BoxConstraints(minHeight: 64, maxHeight: 120),
            child: SingleChildScrollView(
              child: Text(
                isBlank ? (placeholder ?? value) : value,
                style: AppFonts.ui(
                  fontSize: textSize,
                  color: isBlank && placeholder != null
                      ? AppColors.inkSecondary
                      : AppColors.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
