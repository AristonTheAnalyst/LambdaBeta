import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/custom_variation.dart';
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

/// The variation a goal was set on, by name — "No Variation" for the plain
/// lift, because the picker that wrote the goal says it the same way.
///
/// Null when the goal names a variation the active list no longer holds (an
/// archived one): the caller reads that as "can't name it", and the goal list
/// says "Archived variation" where its subsection would be.
String? goalVariationNameFor(Goal goal, List<CustomVariation> variations) {
  final id = goal.variationId;
  if (id == null) return 'No Variation';
  for (final v in variations) {
    if (v.variationId == id) return v.name;
  }
  return null;
}

/// One goal card: its target, and how it stands.
///
/// The library draws these under section headers that name the exercise and
/// the variation (2026-10-19), so those cards pass neither name and lead with
/// the target — a goal IS its weight × reps. The target is set at the set
/// grid's own scale (mono 17 w700; 2026-10-20), so the card speaks the
/// session's vocabulary and never shouts over the section header it hangs
/// under.
///
/// **The whole card reads on one line** (2026-10-20): the target at the left
/// and the dates it exists to answer at the right — "5 × 5 kg  ◎ 31 Oct 2026
/// ✓ 13 Oct 2026" — so a card is one row tall. The target alone takes the
/// squeeze (it scale-to-fits, never ellipsizes), which keeps the dates at a
/// steady right column across every card in the list.
///
/// **The card states one date, never both** (2026-10-20): a met goal answers
/// "when did I hit it" with the completion day, a standing one answers "when
/// is it due" with the deadline — the date that matters is the one it has
/// not settled yet. The date reads by symbol: a green tick before the
/// completion, a bullseye ([_targetIcon]) before the deadline; the glyph
/// carries what the words "Target date" and "Completed" said, and the date is
/// the only text left to read. A standing goal with no deadline says "None"
/// rather than leaving the slot blank. Each mark carries its meaning again as
/// a semantics label, because a glyph is nothing to a screen reader.
///
/// **A met goal wears the success chrome** (2026-10-20): [successBox], the
/// same green fill and green outline the New Goal form's set row turns when
/// the history already beats the target. The card itself says "done" — a
/// check in the corner said it twice.
///
/// A review's goal rows are their own list with no headers, so they pass the
/// exercise name and draw it above the target; they pass no [targetDate] and
/// no [outcome] — an open pass has nothing to say about either yet — and the
/// date line is omitted rather than guessed.
///
/// The row carries no delete control: deleting is the swipe drawer's alone
/// (2026-10-19), where a gesture can be taken back before the question is
/// even asked.
class GoalRow extends StatelessWidget {
  const GoalRow({
    super.key,
    this.exerciseName,
    this.variationName,
    this.target = '',
    this.targetDate,
    this.outcome,
  });

  /// Built by the caller with [goalExerciseNameFor], because the caller is
  /// the one holding the exercise detail map. Null = the section headers name
  /// the exercise (the library's cards), and the line is omitted.
  final String? exerciseName;

  /// The goal's variation, built with [goalVariationNameFor]. Null = the
  /// caller has none to draw (the library's headed cards, the review's
  /// compact rows), and the line is omitted rather than guessed.
  final String? variationName;

  /// The target — "100 kg × 5", built with `goalTargetValue`. Mono and
  /// large, because it is the number the goal is. Empty = there is no target
  /// to state.
  final String target;

  /// The day the goal should be hit by; null = no deadline. Drawn in the
  /// left half of the date line, so the card always answers the question.
  final DateTime? targetDate;

  /// Null when this row has no verdict to show — the review's goal cards pass
  /// none, and the goals list derives a lifetime one. A goal with no verdict
  /// is not a failed one, and the row draws no Completed line rather than
  /// claiming otherwise.
  final GoalAchievement? outcome;

  @override
  Widget build(BuildContext context) {
    final o = outcome;
    final achieved = o?.achieved ?? false;
    // One date, never two (2026-10-20): a met goal states the day it was hit;
    // a standing one states the day it is due. The open-ended goal still says
    // "None" where a standing card would carry its deadline.
    final targetDay = targetDate == null ? 'None' : _day(targetDate!);
    final completedDay = achieved
        ? (o!.evidenceDate == null ? 'Hit' : _day(o.evidenceDate!))
        : null;
    // A review's goal rows pass no outcome and no dates, and are owed no mark;
    // every other card states one of the two questions.
    final hasMark = achieved || targetDate != null || o != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: achieved
          ? successBox()
          : lambdaBox(ContainerTone.surface, radius: AppRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (exerciseName != null)
            Text(
              exerciseName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.ui(
                fontSize: AppTextStyles.md,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          if (exerciseName != null && variationName != null) ...[
            const SizedBox(height: 2),
            Text(
              variationName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.inkSecondary,
              ),
            ),
          ],
          if (exerciseName != null && target.isNotEmpty)
            const SizedBox(height: AppSpacing.md),
          if (target.isNotEmpty || hasMark)
            // One line (2026-10-20): the target — the goal itself — at the
            // left, its single date at the right, so a card is a single row.
            // The target alone takes the squeeze: it scale-to-fits inside
            // whatever the date leaves, so a long target never pushes the
            // date off the card.
            Row(
              children: [
                Expanded(
                  child: target.isEmpty
                      ? const SizedBox.shrink()
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            target,
                            maxLines: 1,
                            // The set grid's scale — a goal is one set to
                            // beat (2026-10-20).
                            style: AppFonts.mono(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                ),
                if (hasMark) ...[
                  const SizedBox(width: AppSpacing.sm),
                  // The settled question outranks the open one (2026-10-20):
                  // a hit goal states its completion, and its deadline — now
                  // answered — is not drawn at all.
                  if (achieved)
                    _dateMark(
                      'Completed $completedDay',
                      completedDay!,
                      icon: Icons.check,
                      success: true,
                    )
                  else
                    _dateMark(
                      'Target date $targetDay',
                      targetDay,
                      icon: _targetIcon,
                      muted: targetDate == null,
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

/// The deadline's mark: Material's bullseye ([Icons.track_changes]) — a mark
/// to hit, rather than the calendar the form's date field already wears.
const _targetIcon = Icons.track_changes;

/// One symbol and its date, read as one phrase — "◎ 31 Oct 2026".
///
/// The glyph says what the date is (deadline or completion) and the value says
/// which day. The pair never wraps: it sits in the card's one line at its
/// intrinsic width, and the target beside it is the part that gives.
///
/// [semanticsLabel] restates the pair in words for a screen reader, which
/// cannot see the glyph; the [Row] is excluded so the label is all assistive
/// tech hears.
Widget _dateMark(
  String semanticsLabel,
  String value, {
  required IconData icon,
  bool muted = false,
  bool success = false,
}) => Semantics(
  container: true,
  label: semanticsLabel,
  excludeSemantics: true,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 14,
        color: success ? AppColors.success : AppColors.muted,
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(
        value,
        maxLines: 1,
        style: AppFonts.mono(
          fontSize: AppTextStyles.xs,
          fontWeight: FontWeight.w700,
          color: success
              ? AppColors.success
              : muted
              ? AppColors.inkSecondary
              : AppColors.primary,
        ),
      ),
    ],
  ),
);

String _day(DateTime date) => DateFormat('d MMM yyyy').format(date.toLocal());
