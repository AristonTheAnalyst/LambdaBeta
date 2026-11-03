import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';

// The Goals list's destructive question.
//
// Both of the row's ways to delete — the × and the swipe drawer — land here,
// so a goal can never go on a single stray tap or an accidental drag. The
// question names the goal by its exercise, because the row under the finger is
// the one being deleted and "this goal" alone would leave the user checking.
//
// The dismissal never repeats the confirm's verb: "Keep goal" and "Delete
// goal" are different answers, and a dialog whose way out reads like its way
// through is one answered by reflex.

/// The "delete this goal?" warning — the row's × and its swipe both open it.
///
/// True only on the confirm; a dismissed dialog reads as "no".
Future<bool> confirmDeleteGoal(
  BuildContext context, {
  required String label,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Delete this goal?',
        style: AppFonts.ui(
          fontWeight: FontWeight.w800,
          color: AppColors.danger,
        ),
      ),
      content: Text(
        '"$label" is removed from your goals. Your logged sets stay in '
        'Training Logs. This can\'t be undone.',
        style: AppFonts.ui(color: AppColors.inkSecondary, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'Keep goal',
            style: AppFonts.ui(color: AppColors.inkSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'Delete goal',
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
