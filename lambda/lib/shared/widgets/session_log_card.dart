import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import '../../core/utils/session_format.dart';
import '../../data/models/session.dart';
import '../../data/models/session_exercise_set.dart';
import './container_styles.dart';
import './feeling_rating.dart';
import './press_squash.dart';

/// THE session card — the all-sessions picker sheet's row, reused as the
/// Training Logs' workout card so the two surfaces share one
/// implementation. A 2×2 identity grid (DATE / PLANNED / PRE / POST) plus
/// centered per-exercise set summaries. [selected] marks the currently
/// shown session with the accent soft-highlight recipe.
class SessionLogCard extends StatelessWidget {
  const SessionLogCard({
    super.key,
    required this.workout,
    this.selected = false,
    required this.onTap,
  });

  final SessionWithSets workout;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = workout.session;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: PressSquash(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            // Recessed — darker than the page ground so the row cards
            // separate from it.
            color: AppColors.surfaceLow,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            // The soft-highlight recipe marks the selected session.
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _identityGrid(s),
              if (workout.sets.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: _exerciseSummaries(workout.sets),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The card's 2×2 identity grid — date, planned source, pre and post
  /// ratings — hairline-separated cells in the StatsRow style. Exercises
  /// live below it, centered.
  Widget _identityGrid(Session s) {
    return Container(
      decoration: lambdaBox(
        ContainerTone.outline,
        radius: AppRadius.md,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _gridCell(
                  'DATE',
                  Text(
                    DateFormat('MMM d, yyyy').format(s.createdDatetime),
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.sm,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              Container(width: 1, color: AppColors.border),
              Expanded(
                child: _gridCell(
                  'PLANNED',
                  s.plannedSessionName != null
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.plannedBg,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.planned.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            s.plannedSessionName!,
                            style: AppFonts.ui(
                              fontSize: AppTextStyles.sm,
                              fontWeight: FontWeight.w700,
                              color: AppColors.planned,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : Text(
                          '—',
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.sm,
                            color: AppColors.muted,
                          ),
                        ),
                ),
              ),
            ],
          ),
          Container(height: 1, color: AppColors.border),
          Row(
            children: [
              Expanded(
                child: _gridCell(
                  'PRE',
                  FeelingRating(value: s.preFeeling, size: 14, spacing: 3),
                ),
              ),
              Container(width: 1, color: AppColors.border),
              Expanded(
                child: _gridCell(
                  'POST',
                  FeelingRating(value: s.feeling, size: 14, spacing: 3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gridCell(String label, Widget content) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.sm,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: AppFonts.mono(
            fontSize: 13,
            letterSpacing: 0.8,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 3),
        content,
      ],
    ),
  );

  List<Widget> _exerciseSummaries(List<SessionExerciseSet> sets) {
    final order = <String>[];
    final counts = <String, int>{};
    final names = <String, String>{};
    for (final s in sets) {
      final exerciseId = s.exerciseId;
      if (exerciseId == null) continue;
      if (!names.containsKey(exerciseId)) {
        order.add(exerciseId);
        names[exerciseId] = s.exerciseName ?? exerciseId;
      }
      counts[exerciseId] = (counts[exerciseId] ?? 0) + 1;
    }
    return order.map((exId) {
      final count = counts[exId]!;
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                toProperCase(names[exId]!),
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$count ${count == 1 ? 'set' : 'sets'}',
              style: AppFonts.mono(
                fontSize: AppTextStyles.sm,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
