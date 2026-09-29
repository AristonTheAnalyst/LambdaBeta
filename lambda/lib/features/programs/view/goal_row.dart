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
import '../../../shared/widgets/exercise_target_picker.dart';
import '../model/program_achievements.dart';

/// A goal's display name as it appears in a list: the exercise's live name,
/// falling back to the text captured when the goal was written.
///
/// Live-first is the house rule (`20260826000000_snapshots_out_fks_in`) — a
/// renamed exercise renames it everywhere, goals included. Shared so the
/// program's goal list and a block's read identically.
String goalLabelFor(Goal goal, Map<String, ExerciseDetail> detailMap) =>
    goalTargetLabel(
      toProperCase(detailMap[goal.exerciseId]?.name ?? goal.text ?? ''),
      goal.targetWeight,
      goal.targetReps,
    );

/// One goal: what it is, what it is scoped to, and how it is going.
///
/// The outcome line is the reason the panel exists. A goal met shows the set
/// that met it — often heavier than the target, which is the interesting part.
/// A goal missed shows the best attempt, so a near miss reads as progress
/// rather than as a blank; a goal with no attempt at all says so in words,
/// because "0 kg × 0" is not a fact about anyone's training.
class GoalRow extends StatelessWidget {
  const GoalRow({
    super.key,
    required this.label,
    required this.onDelete,
    this.outcome,
    this.scopeLabel,
  });

  /// Built by the caller with [goalLabelFor], because the caller is the one
  /// holding the exercise detail map.
  final String label;

  /// Null when this goal is not in force right now — see
  /// `ProgramDetailState.goalOutcomes`. A goal with no verdict is not a failed
  /// one, and the row draws nothing rather than claiming otherwise.
  final GoalAchievement? outcome;

  /// The block this goal belongs to, when that is worth saying — the program's
  /// list mixes both scopes, so it names them; a block's own list is all one
  /// scope and passes nothing.
  final String? scopeLabel;

  final VoidCallback onDelete;

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
                    Flexible(
                      child: Text(
                        label,
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.sm,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (scopeLabel != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  ScopeChip(label: scopeLabel!),
                ],
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

/// A small scope label — which block a goal belongs to.
class ScopeChip extends StatelessWidget {
  const ScopeChip({super.key, required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withAlpha(26),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.withAlpha(77)),
      ),
      child: Text(
        label,
        style: AppFonts.ui(
          fontSize: AppTextStyles.xs,
          fontWeight: FontWeight.w600,
          color: c,
        ),
      ),
    );
  }
}

String _fmtNum(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toString();
