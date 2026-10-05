import 'package:flutter/material.dart';

import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';

/// Picks one option out of a list, by name. Returns its id, or null when the
/// sheet was dismissed.
///
/// The programs screens ask this question three ways — which library workout
/// to copy in, which of the program's own workouts to move into a block, which
/// block to file a workout into — and each one had its own copy of the sheet,
/// with the title and the empty case drifting apart. The rows are named by the
/// caller rather than derived here: a workout's name and a block's name are
/// spelled differently (`toProperCase` for one of them), and the picker has no
/// business knowing which it is holding.
Future<String?> showOptionPickerSheet(
  BuildContext context, {
  required String title,
  required List<({String id, String label})> options,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              title,
              style: AppFonts.ui(
                fontSize: AppTextStyles.lg,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
          for (final option in options)
            ListTile(
              title: Text(
                option.label,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.md,
                  color: AppColors.primary,
                ),
              ),
              onTap: () => Navigator.of(ctx).pop(option.id),
            ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    ),
  );
}
