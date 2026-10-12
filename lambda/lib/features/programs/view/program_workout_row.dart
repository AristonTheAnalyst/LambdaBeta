import 'package:flutter/material.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/planned_session.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/swipe_actions.dart';

/// One workout inside a program, as a card: name, notes, an optional badge,
/// and — when [dragIndex] is given — a drag handle for the reorderable list it
/// lives in.
///
/// Shared by the program detail screen (where the badge is the session number
/// and the swipe drawer is Duplicate / Delete) and the block editor (where
/// there is no badge and the drawer is Duplicate / Remove). Null callbacks hide
/// their control, the same convention `SessionExerciseCard` follows.
class ProgramWorkoutRow extends StatelessWidget {
  const ProgramWorkoutRow({
    super.key,
    required this.workout,
    this.badge,
    this.onTap,
    this.dragIndex,
    this.swipeActions = const [],
  });

  final PlannedSession workout;

  /// A short mono chip on the right, e.g. `Session 3`.
  final String? badge;

  final VoidCallback? onTap;

  /// The row's index in its own reorderable list. Null = not draggable, which
  /// is what a nested list needs: the index is local to the list, never the
  /// program-global order.
  final int? dragIndex;

  final List<SwipeAction> swipeActions;

  @override
  Widget build(BuildContext context) {
    final card = AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  toProperCase(workout.name),
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.md,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                if (workout.notes?.isNotEmpty == true)
                  Text(
                    workout.notes!,
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.xs,
                      color: AppColors.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                badge!,
                style: AppFonts.mono(
                  fontSize: AppTextStyles.xs,
                  color: AppColors.accent,
                ),
              ),
            ),
          if (dragIndex != null)
            ReorderableDragStartListener(
              index: dragIndex!,
              child: Icon(
                Icons.drag_handle,
                size: 18,
                color: AppColors.muted,
              ),
            ),
        ],
      ),
    );

    if (swipeActions.isEmpty) return card;
    return SwipeActions(actions: swipeActions, child: card);
  }
}
