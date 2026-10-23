import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';

// The Reviews list's two destructive questions: cancelling an open pass and
// deleting a completed record.
//
// Each names the pass by its list label, because the row being deleted is the
// one under the finger and "this review" alone would leave the user checking.
// Neither dismiss verb repeats its confirm's verb: a dialog whose dismissal
// reads the same as its destructive answer is one answered by reflex.
//
// Both return true only on the confirm; a dismissed dialog reads as "no".

/// The "cancel this review?" warning — the open card swipes into it, and it is
/// where the user is told what a cancel takes with it.
Future<bool> confirmCancelReview(
  BuildContext context, {
  required String label,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Cancel this review?',
        style: AppFonts.ui(
          fontWeight: FontWeight.w800,
          color: AppColors.danger,
        ),
      ),
      content: Text(
        '"$label" is deleted, with every tick and note made in it. '
        'This can\'t be undone.',
        style: AppFonts.ui(color: AppColors.inkSecondary, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'Keep reviewing',
            style: AppFonts.ui(color: AppColors.inkSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'Cancel review',
            style: AppFonts.ui(
              color: AppColors.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// The "delete this record?" warning — the completed card swipes into it.
///
/// A record is the finished thing a pass existed to make, so the body says
/// plainly that the record goes with the row, and the dismissal is a plain
/// "Keep it": "Cancel" belongs to the other question, and two destructive
/// verbs sharing one word would blur which one is being answered.
Future<bool> confirmDeleteCompletedReview(
  BuildContext context, {
  required String label,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Delete this review?',
        style: AppFonts.ui(
          fontWeight: FontWeight.w800,
          color: AppColors.danger,
        ),
      ),
      content: Text(
        '"$label" is deleted, with the record it kept. '
        'This can\'t be undone.',
        style: AppFonts.ui(color: AppColors.inkSecondary, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'Keep it',
            style: AppFonts.ui(color: AppColors.inkSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'Delete review',
            style: AppFonts.ui(
              color: AppColors.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
  return ok ?? false;
}
