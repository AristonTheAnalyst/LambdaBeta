import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';

/// The one "delete this session?" warning — the Training Logs list and the
/// live session's all-sessions picker both delete through this, so the copy
/// and styling can never drift between the two surfaces. Returns true only
/// when the user confirms; a dismissed dialog reads as "no".
///
/// [setCount] is the session's logged-set count, folded into the warning so
/// the user sees exactly how much goes with the session.
Future<bool> confirmDeleteSession(
  BuildContext context, {
  required int setCount,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Delete Session',
          style: AppFonts.ui(
              fontWeight: FontWeight.w800, color: AppColors.danger)),
      content: Text(
          'Delete this session${setCount > 0 ? ' and its $setCount logged set${setCount == 1 ? '' : 's'}' : ''}? '
          'This can\'t be undone.',
          style: AppFonts.ui(color: AppColors.muted)),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete',
                style: AppFonts.ui(
                    color: AppColors.danger, fontWeight: FontWeight.w600))),
      ],
    ),
  );
  return ok ?? false;
}
