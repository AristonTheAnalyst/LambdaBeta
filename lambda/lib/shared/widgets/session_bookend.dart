import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import 'feeling_rating.dart';

/// One pre/post bookend section — the session questionnaire read back with
/// the same wording/styling as the live form: [question] above the rating
/// and [notesLabel] above the notes. Rating and notes always render: an
/// unrated session shows empty squares, and empty notes show [emptyNotes]
/// in the reflection sections' empty-note style. Notes sit in a lesson-row
/// container and scroll inside it when long.
///
/// Shared between the prep page's LAST SESSION card and the past-session
/// viewer's Summary tab so the two can never drift.
class SessionBookend extends StatelessWidget {
  const SessionBookend({
    super.key,
    required this.label,
    required this.feeling,
    required this.notes,
    required this.emptyNotes,
    required this.question,
    required this.notesLabel,
  });

  final String label;
  final int? feeling;
  final String? notes;
  final String emptyNotes;
  final String question;
  final String notesLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppFonts.mono(
            fontSize: 9,
            letterSpacing: 0.8,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          question,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Full-size squares — the usual rating size, centered like the
        // prep page's THIS SESSION input.
        FeelingRating(value: feeling),
        const SizedBox(height: AppSpacing.sm),
        Text(
          notesLabel,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 6),
        if (notes != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: ConstrainedBox(
              // Roomier than one line so short notes still read as a box;
              // long notes scroll inside it instead of stretching the card.
              constraints: const BoxConstraints(minHeight: 64, maxHeight: 120),
              child: SingleChildScrollView(
                child: Text(
                  notes!,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          )
        else
          Text(
            emptyNotes,
            style: AppFonts.ui(
              fontSize: AppTextStyles.xs,
              color: AppColors.muted,
            ),
          ),
      ],
    );
  }
}
