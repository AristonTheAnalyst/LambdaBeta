import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';

/// The one "cancel this review?" warning — the Reviews list's open card swipes
/// into it, and it is where the user is told what a cancel takes with it.
///
/// It names the pass by its list label, because the row being deleted is the
/// one under the finger and "this review" alone would leave the user checking.
/// The dismiss verb is "Keep reviewing", not "Cancel": the confirm's own verb
/// IS cancel, and a dialog whose dismissal reads the same as its destructive
/// answer is a dialog that gets answered by reflex.
///
/// Returns true only on the confirm; a dismissed dialog reads as "no".
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
        style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.danger),
      ),
      content: Text(
        '"$label" is deleted, with every tick and note made in it. '
        'This can\'t be undone.',
        style: AppFonts.ui(color: AppColors.muted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'Keep reviewing',
            style: AppFonts.ui(color: AppColors.muted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'Cancel review',
            style: AppFonts.ui(color: AppColors.danger, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  return ok ?? false;
}
