import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_text_styles.dart';

/// The pinned exercise note, read whole (2026-10-23).
///
/// The bar under the selector holds one ellipsized line — enough to remember
/// that a cue exists, not enough to read it. Tapping the bar opens this
/// reader with the complete message instead of jumping straight into the
/// notes sheet; `View all exercise notes` is the way on, and the caller
/// opens the sheet after this dialog has left.
///
/// Returns true only when that door was taken — Close, the barrier and the
/// back gesture all read as "just reading".
Future<bool> showPinnedNotePopup(
  BuildContext context, {
  required String text,

  /// False when the surface around the bar has no notes sheet to open (the
  /// reader still works; the door is simply not offered).
  bool canViewAll = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        'Exercise Note',
        style: AppFonts.ui(
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
      // Notes are uncapped prose: a long cue scrolls inside the dialog
      // rather than overflowing it.
      content: SingleChildScrollView(
        child: Text(
          text,
          style: AppFonts.ui(
            fontSize: AppTextStyles.body,
            height: 1.35,
            color: AppColors.primary,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'Close',
            style: AppFonts.ui(color: AppColors.inkSecondary),
          ),
        ),
        if (canViewAll)
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'View all exercise notes',
              style: AppFonts.ui(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    ),
  );
  return result ?? false;
}
