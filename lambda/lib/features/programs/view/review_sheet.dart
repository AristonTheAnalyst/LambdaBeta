import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/program_review.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/pr_event_row.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../model/program_achievements.dart';

/// What a review sheet decided.
///
/// The sheet does not touch the repository itself — the screen owns the
/// ViewModel, and a sheet that completed reviews behind its back would leave
/// the timeline showing a revision it never fetched.
class ReviewDecision {
  const ReviewDecision._(this.outcome, {this.wantsEditor = false});

  /// The outcome to complete with, or null to leave the review open.
  final String? outcome;

  /// The user chose to go make the change rather than call it done.
  final bool wantsEditor;

  /// "I did the thing." Completes with [kOutcomeApplied] when the review
  /// carried a proposal, [kOutcomeReviewed] otherwise — the same act, named by
  /// what it was about.
  factory ReviewDecision.apply({required bool hasProposal}) => ReviewDecision._(
        hasProposal ? kOutcomeApplied : kOutcomeReviewed,
      );

  /// "I looked at it." Cuts a revision without claiming anything was changed.
  static const ReviewDecision reviewed = ReviewDecision._(kOutcomeReviewed);

  /// "Not now." Records the dismissal and cuts nothing — see
  /// `ProgramHistoryRepository.checkpointFor` for why that matters.
  static const ReviewDecision dismissed = ReviewDecision._(kOutcomeDismissed);

  /// "Let me go edit the program first." Leaves the review open.
  static const ReviewDecision editFirst =
      ReviewDecision._(null, wantsEditor: true);
}

/// The checkpoint: what the program produced since the last one, what a
/// proposed change asks for, and the actions that close it out.
Future<ReviewDecision?> showReviewSheet(
  BuildContext context, {
  required ProgramReview review,

  /// Null when the window has nothing to show, or when this is a close record
  /// read back from the archive.
  ProgramAchievements? achievements,

  /// How many versions this review's window covers — 0 for the first review of
  /// a program that has never been captured.
  String? proposedSummary,
  VoidCallback? onViewProposal,
}) {
  return showLambdaModal<ReviewDecision>(
    context,
    child: SafeArea(
      child: _ReviewSheet(
        review: review,
        achievements: achievements,
        proposedSummary: proposedSummary,
        onViewProposal: onViewProposal,
      ),
    ),
  );
}

class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet({
    required this.review,
    required this.achievements,
    required this.proposedSummary,
    required this.onViewProposal,
  });

  final ProgramReview review;
  final ProgramAchievements? achievements;
  final String? proposedSummary;
  final VoidCallback? onViewProposal;

  @override
  Widget build(BuildContext context) {
    final hasProposal = review.hasProposal;
    final when = review.scheduledFor ?? review.createdDate;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            review.title?.trim().isNotEmpty == true
                ? review.title!.trim()
                : (hasProposal ? 'Proposed change' : 'Review'),
            style: AppFonts.ui(
              fontSize: AppTextStyles.lg,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Scheduled for ${DateFormat('EEE, d MMM yyyy').format(when)}',
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              color: AppColors.muted,
            ),
          ),
          if (review.notes?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              review.notes!.trim(),
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.primary,
              ),
            ),
          ],
          if (hasProposal) ...[
            const SizedBox(height: AppSpacing.lg),
            _SectionLabel('PROPOSED'),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      proposedSummary ?? 'An edit is attached to this review.',
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.sm,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  if (onViewProposal != null)
                    GlassButton(
                      label: 'Diff',
                      compact: true,
                      onPressed: onViewProposal!,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _SectionLabel('SINCE THE LAST CHECKPOINT'),
          const SizedBox(height: AppSpacing.sm),
          _AchievementsPanel(achievements: achievements),
          const SizedBox(height: AppSpacing.lg),
          _Actions(
            hasProposal: hasProposal,
            onDecision: (d) => Navigator.of(context).pop(d),
          ),
        ],
      ),
    );
  }
}

/// The achievements window. An empty window is stated plainly rather than
/// hidden: "nothing was logged" is itself the answer to "how did this block
/// go?", and a blank space would read as a loading failure.
class _AchievementsPanel extends StatelessWidget {
  const _AchievementsPanel({required this.achievements});

  final ProgramAchievements? achievements;

  @override
  Widget build(BuildContext context) {
    final a = achievements;
    if (a == null) {
      return Text(
        'Achievements are shown for the program that is currently running.',
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          color: AppColors.muted,
        ),
      );
    }
    if (a.isEmpty) {
      return Text(
        'Nothing logged in this window yet.',
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          color: AppColors.muted,
        ),
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
      if (g.goal.targetReps != null)
        '× ${formatPrNumber(g.goal.targetReps!)}',
    ];
    return parts.isEmpty ? 'Goal' : parts.join(' ');
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.hasProposal, required this.onDecision});

  final bool hasProposal;
  final ValueChanged<ReviewDecision> onDecision;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: GlassButton(
            label: hasProposal ? 'Apply change' : 'Done',
            solid: true,
            onPressed: () => onDecision(ReviewDecision.apply(
              hasProposal: hasProposal,
            )),
          ),
        ),
        if (hasProposal) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: GlassButton(
              label: 'Make changes',
              onPressed: () => onDecision(ReviewDecision.editFirst),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            if (hasProposal) ...[
              Expanded(
                child: GlassButton(
                  label: 'Reviewed',
                  compact: true,
                  onPressed: () => onDecision(ReviewDecision.reviewed),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: GlassButton(
                label: 'Dismiss',
                compact: true,
                color: AppColors.muted,
                onPressed: () => onDecision(ReviewDecision.dismissed),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppFonts.mono(
          fontSize: AppTextStyles.xs,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: AppColors.muted,
        ),
      );
}
