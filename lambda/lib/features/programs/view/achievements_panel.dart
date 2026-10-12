import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/pr_event_row.dart';
import '../model/program_achievements.dart';

/// What the program produced since the last checkpoint.
///
/// It lives on the review's **finish** sheet rather than on the review itself:
/// the notes a user writes there are the record of why they changed what they
/// changed, and this is the context that makes them writable. An empty window is
/// stated plainly rather than hidden — "nothing was logged" is itself an answer,
/// and a blank space would read as a loading failure.
class AchievementsPanel extends StatelessWidget {
  const AchievementsPanel({super.key, required this.achievements});

  /// Null when there is no window to show — no open review, or one with no run
  /// behind it and no previous checkpoint to date the window from.
  final ProgramAchievements? achievements;

  @override
  Widget build(BuildContext context) {
    final a = achievements;
    if (a == null) {
      return Text(
        'Achievements are shown for the program that is currently running.',
        style: AppFonts.ui(fontSize: AppTextStyles.sm, color: AppColors.muted),
      );
    }
    if (a.isEmpty) {
      return Text(
        'Nothing logged in this window yet.',
        style: AppFonts.ui(fontSize: AppTextStyles.sm, color: AppColors.muted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CountRow(achievements: a),
        if (a.prs.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          for (final pr in a.prs) PrEventRow(pr, showExercise: true),
        ],
        if (a.goals.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          for (final g in a.goals) _GoalRow(goal: g),
        ],
      ],
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.achievements});

  final ProgramAchievements achievements;

  @override
  Widget build(BuildContext context) {
    final a = achievements;
    final facts = <String>[
      if (a.sessions.isNotEmpty) '${a.sessions.length} sessions',
      '${a.prs.length} PRs',
      if (a.goals.isNotEmpty) '${a.achievedGoalCount}/${a.goals.length} goals',
    ];
    return Text(
      facts.join('   ·   '),
      style: AppFonts.mono(
        fontSize: AppTextStyles.xs,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.accent,
      ),
    );
  }
}

/// One goal's outcome. A miss reports how close it came — that is the whole
/// reason a goal is worth reviewing, and a bare "missed" says nothing.
class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal});

  final GoalAchievement goal;

  @override
  Widget build(BuildContext context) {
    final g = goal;
    final target = _targetLabel(g);
    final evidence = g.evidenceWeight == null
        ? null
        : '${formatPrNumber(g.evidenceWeight!)}kg'
              '${g.evidenceReps == null ? '' : ' × ${formatPrNumber(g.evidenceReps!)}'}';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
      child: Row(
        children: [
          Icon(
            g.achieved ? Icons.check_circle_outline : Icons.circle_outlined,
            size: 16,
            color: g.achieved ? AppColors.success : AppColors.muted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g.goal.text?.trim().isNotEmpty == true
                      ? g.goal.text!.trim()
                      : target,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                if (evidence != null)
                  Text(
                    g.achieved ? 'reached $evidence' : 'closest $evidence',
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.xs,
                      color: g.achieved ? AppColors.success : AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "100kg × 1", or just the reps when there is no weight target.
  static String _targetLabel(GoalAchievement g) {
    final parts = <String>[
      if (g.goal.targetWeight != null)
        '${formatPrNumber(g.goal.targetWeight!)}kg',
      if (g.goal.targetReps != null) '× ${formatPrNumber(g.goal.targetReps!)}',
    ];
    return parts.isEmpty ? 'Goal' : parts.join(' ');
  }
}
