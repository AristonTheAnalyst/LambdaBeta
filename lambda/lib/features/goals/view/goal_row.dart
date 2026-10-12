import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/goal.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../programs/model/program_achievements.dart';

/// A goal's exercise name — the exercise's live name, falling back to the
/// text captured when the goal was written.
///
/// Live-first is the house rule (`20260826000000_snapshots_out_fks_in`) — a
/// renamed exercise renames it everywhere, goals included.
String goalExerciseNameFor(Goal goal, Map<String, ExerciseDetail> detailMap) =>
    toProperCase(detailMap[goal.exerciseId]?.name ?? goal.text ?? '');

/// One goal: what it is, and how it is going.
///
/// The name and the target are the two things a goal is, and the row draws
/// each as its own — the name left, the target right-aligned — so the targets
/// line up in a column down the list instead of trailing the names in a dash
/// string (2026-10-10). The same split the review sheets' rows make, so a
/// goal reads identically on the library, the landing and the scope sheet.
///
/// Goals carry no scope while they are unattached (2026-10-08): the chip that
/// named a program or block is retired from the UI, along with every way of
/// writing one. The `program_id`/`block_id` columns and the resolution around
/// them stay in the data layer, dormant, like day scheduling.
///
/// The outcome line is the reason the panel exists. A goal met shows the set
/// that met it — often heavier than the target, which is the interesting part.
/// A goal missed shows the best attempt, so a near miss reads as progress
/// rather than as a blank; a goal with no attempt at all says so in words,
/// because "0 kg × 0" is not a fact about anyone's training.
class GoalRow extends StatelessWidget {
  const GoalRow({
    super.key,
    required this.exerciseName,
    this.target = '',
    this.outcome,
    required this.onDelete,
  });

  /// Built by the caller with [goalExerciseNameFor], because the caller is
  /// the one holding the exercise detail map.
  final String exerciseName;

  /// The target, as its own right-aligned element ("100 kg × 5 reps"), built
  /// with `goalTargetValue`. Mono, because it is a numeric readout like the
  /// set grid's cells. Empty = there is no target to state.
  final String target;

  /// Null when this row has no verdict to show — the review's goal cards pass
  /// none, and the goals list derives a lifetime one. A goal with no verdict
  /// is not a failed one, and the row draws nothing rather than claiming
  /// otherwise.
  final GoalAchievement? outcome;

  /// Null when the row has nothing to delete — the review's read-only goal
  /// view, where the × would offer an action the pass does not have.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final o = outcome;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: lambdaBox(ContainerTone.surface, radius: AppRadius.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (o?.achieved ?? false) ...[
                      Icon(
                        Icons.check_circle,
                        size: 14,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        exerciseName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.sm,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    if (target.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        target,
                        style: AppFonts.mono(
                          fontSize: AppTextStyles.xs,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
                if (o != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    outcomeLabel(o),
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.xs,
                      color: o.achieved ? AppColors.success : AppColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onDelete != null)
            GestureDetector(
              onTap: onDelete,
              child: Icon(Icons.close, size: 16, color: AppColors.muted),
            ),
        ],
      ),
    );
  }
}

/// The verdict, in one line.
///
/// Evidence is optional even on a hit — a goal whose target recorded only one of
/// the two numbers has nothing to quantify — so every clause stands alone and
/// the line degrades to "Hit" rather than to a dangling separator.
String outcomeLabel(GoalAchievement o) {
  final w = o.evidenceWeight;
  final r = o.evidenceReps;
  final value = (w == null || r == null) ? null : '${_fmtNum(w)} kg × $r';
  final when = o.evidenceDate == null
      ? null
      : DateFormat('d MMM').format(o.evidenceDate!.toLocal());

  if (o.achieved) {
    final parts = [?value, ?when];
    return parts.isEmpty ? 'Hit' : 'Hit · ${parts.join(' · ')}';
  }
  if (value == null) return 'Not attempted yet';
  return 'Best ${[value, ?when].join(' · ')}';
}

String _fmtNum(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toString();
