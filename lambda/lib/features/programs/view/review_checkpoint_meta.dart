import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/program_review.dart';
import '../../../shared/widgets/container_styles.dart';

/// The line that heads a checkpoint: what it came to, the day it was taken, and
/// the fingerprint of what it froze.
///
/// One widget because the two places a completed checkpoint is read — the card
/// that opens it and the snapshot screen behind it — are answering the same
/// question with the same three facts ("which checkpoint is this, and is it the
/// document I read last time?"). The fingerprint is the part that earns its
/// keep: two checkpoints showing the same short hash are byte-identical, which
/// is how "I reviewed this and changed nothing" proves itself rather than
/// asking to be believed.
class ReviewCheckpointMeta extends StatelessWidget {
  const ReviewCheckpointMeta({super.key, required this.review});

  final ProgramReview review;

  @override
  Widget build(BuildContext context) {
    // Dropped rather than blanked when a row carries no hash: `#--------` under
    // a finished review would read as a broken fingerprint instead of an
    // absent one.
    final hash = review.snapshotHash ?? '';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 3,
          ),
          // The accent tone at the chip radius — the same chrome the timeline's
          // own status chip draws, so the two read as the same kind of thing.
          decoration: lambdaBox(ContainerTone.accent, radius: AppRadius.md),
          child: Text(
            reviewOutcomeLabel(review.outcome).toUpperCase(),
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              fontWeight: FontWeight.w700,
              color: AppColors.accentText,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            DateFormat('MMM d, yyyy').format(review.effectiveDate),
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              color: AppColors.muted,
            ),
          ),
        ),
        if (hash.isNotEmpty)
          Text(
            '#${hash.substring(0, hash.length < 8 ? hash.length : 8)}',
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              color: AppColors.muted,
            ),
          ),
      ],
    );
  }
}
