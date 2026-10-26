import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/menu_popover.dart';
import '../../../shared/widgets/sheet_filter_field.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/sort_button.dart';
import '../../../shared/widgets/user_name_text.dart';
import '../../programs/model/program_achievements.dart';

/// The exercise goals sheet (2026-10-26) — the floor's bullseye, the door
/// that replaced the set row's swipe drawer.
///
/// The PR History sheet's furniture (the exercise uppercased as an eyebrow
/// over the title, a count, a close) with the goals that belong to the
/// exercise on the card: what is still to be chased by default, everything
/// once the status filter says so, and a sort button for the order. A goal
/// reads met when [goalCompletionSet] finds the set that completed it — the
/// same engine that draws the `G` badge — so the sheet and the grid can never
/// disagree about whether a target stands.
///
/// The list is drawn from a [Listenable] and a getter rather than a snapshot
/// (the lessons modal's pattern): the New goal door opens the goals screen's
/// form over this sheet, and the goal it writes must appear here without the
/// sheet closing and reopening.
Future<void> showExerciseGoalsSheet(
  BuildContext context, {
  required String exerciseName,

  /// What re-reads the goals after a write — the live view model, or the
  /// past-session viewer's state.
  required Listenable listenable,

  /// [exerciseName]'s goals, read fresh on every rebuild.
  required List<Goal> Function() goalsFor,

  /// The timeline the badges are derived from (history plus any live rows),
  /// asked whether each goal stands.
  required List<PastSetRow> Function() setsFor,

  /// The New goal door — the floor builds the goals screen's form seeded with
  /// this exercise. Null draws no add button (a read-only surface).
  VoidCallback? onNewGoal,

  /// Variation id → name, for the badge a variated goal wears.
  Map<String, String> variationNames = const {},
}) {
  return showLambdaModal<void>(
    context,
    child: _ExerciseGoalsSheet(
      exerciseName: exerciseName,
      listenable: listenable,
      goalsFor: goalsFor,
      setsFor: setsFor,
      onNewGoal: onNewGoal,
      variationNames: variationNames,
    ),
  );
}

/// The status filter's answers. Null on the control is "all goals" — the
/// sheet opens on [open], because a sheet of answered questions is a report,
/// and this door is for what is left to do.
enum _GoalStatus { open, achieved }

/// The sort button's criteria. Each carries the reading a lifter wants when
/// they ask for it: date soonest first, weight and reps heaviest first,
/// newest first. The button flips any of them, and an undated goal always
/// trails the dated ones — "no deadline" is not a deadline.
enum _GoalSort { targetDate, weight, reps, newest }

/// The variation badge's ceiling — the PR History sheet's own bound, for the
/// same reason: a 20-character name at this mono size must not push the
/// target off the row.
const double _variationBadgeMaxWidth = 150;

class _ExerciseGoalsSheet extends StatefulWidget {
  const _ExerciseGoalsSheet({
    required this.exerciseName,
    required this.listenable,
    required this.goalsFor,
    required this.setsFor,
    this.onNewGoal,
    this.variationNames = const {},
  });

  final String exerciseName;
  final Listenable listenable;
  final List<Goal> Function() goalsFor;
  final List<PastSetRow> Function() setsFor;
  final VoidCallback? onNewGoal;
  final Map<String, String> variationNames;

  @override
  State<_ExerciseGoalsSheet> createState() => _ExerciseGoalsSheetState();
}

class _ExerciseGoalsSheetState extends State<_ExerciseGoalsSheet> {
  /// Null = every goal; [_GoalStatus.open] is the default (see the enum).
  _GoalStatus? _status = _GoalStatus.open;

  _GoalSort _sort = _GoalSort.targetDate;
  bool _descending = false;

  /// The highest weight a goal states — a multi-set goal reads by its top
  /// rung, which is the number that names the goal on a card.
  static num _topWeight(Goal goal) => goal.requirements.fold<num>(
    0,
    (best, target) => (target.weight ?? 0) > best ? target.weight! : best,
  );

  /// The highest rep count a goal states — the weight's twin.
  static num _topReps(Goal goal) => goal.requirements.fold<num>(
    0,
    (best, target) => (target.reps ?? 0) > best ? target.reps! : best,
  );

  /// The deadline comparison: dated goals in the chosen direction, undated
  /// ones after every dated one in both directions.
  int _byTargetDate(Goal a, Goal b) {
    final da = a.targetDate;
    final db = b.targetDate;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    final order = da.compareTo(db);
    return _descending ? -order : order;
  }

  int _compare(Goal a, Goal b) {
    final order = switch (_sort) {
      _GoalSort.targetDate => 0, // applied below, with its own null rule
      _GoalSort.weight => _topWeight(a).compareTo(_topWeight(b)),
      _GoalSort.reps => _topReps(a).compareTo(_topReps(b)),
      _GoalSort.newest => (a.createdDate ?? DateTime(0)).compareTo(
        b.createdDate ?? DateTime(0),
      ),
    };
    if (_sort == _GoalSort.targetDate) return _byTargetDate(a, b);
    final directed = _descending ? -order : order;
    if (directed != 0) return directed;
    // Equal on the criterion — the deadline still says which is more urgent,
    // and the id keeps the order stable across rebuilds.
    final dated = _byTargetDate(a, b);
    return dated != 0 ? dated : a.goalId.compareTo(b.goalId);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      key: const ValueKey('exercise-goals-sheet'),
      top: false,
      child: SizedBox(
        // The PR History sheet's settled height, for the same reason: the
        // room never resizes around its header and controls as the list
        // behind them changes.
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: ListenableBuilder(
            listenable: widget.listenable,
            builder: (context, _) => _content(context),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final goals = widget.goalsFor();
    // Met or not, read by the same engine that draws the G badge — one
    // verdict per goal, the set that completed it underneath.
    final sets = widget.setsFor();
    final completed = <String, PastSetRow?>{
      for (final goal in goals)
        goal.goalId: goalCompletionSet(goal: goal, sets: sets),
    };
    final filtered = [
      for (final goal in goals)
        if (_status == null ||
            (completed[goal.goalId] != null) ==
                (_status == _GoalStatus.achieved))
          goal,
    ]..sort(_compare);
    final total = goals.length;
    final countLabel = filtered.length == total
        ? (total == 1 ? '1 goal' : '$total goals')
        : '${filtered.length} of $total goals';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The Lessons and PR History sheets' own header recipe —
                  // the exercise uppercased as an eyebrow over the title —
                  // so every door opens onto the same furniture.
                  UserNameText(
                    widget.exerciseName.toUpperCase(),
                    tooltip: true,
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.caption,
                      fontWeight: FontWeight.w500,
                      color: AppColors.inkSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    'Goals',
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.lg,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onNewGoal != null)
              HeaderIconButton(
                key: const ValueKey('exercise-goals-add'),
                icon: Icons.add,
                semanticsLabel: 'New goal',
                color: AppColors.success,
                onPressed: widget.onNewGoal!,
              ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              countLabel,
              style: AppFonts.mono(
                fontSize: AppTextStyles.caption,
                fontWeight: FontWeight.w500,
                color: AppColors.inkSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            HeaderIconButton(
              key: const ValueKey('exercise-goals-close'),
              icon: Icons.close,
              semanticsLabel: 'Close',
              color: AppColors.muted,
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: SheetFilterField<_GoalStatus>(
                key: const ValueKey('exercise-goals-status-filter'),
                label: 'STATUS',
                anyLabel: 'All goals',
                anyShort: 'All',
                value: _status,
                options: const [_GoalStatus.open, _GoalStatus.achieved],
                optionLabel: (status) =>
                    status == _GoalStatus.open ? 'Open' : 'Achieved',
                align: MenuPopoverAlign.start,
                onChanged: (status) => setState(() => _status = status),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // The app's one sort control, at the sheet's ground: the icon
            // opens the criterion menu, and re-tapping the criterion in
            // force flips its direction (2026-10-10).
            SortButton<_GoalSort>(
              key: const ValueKey('exercise-goals-sort'),
              elevated: true,
              options: const [
                SortOption(label: 'Target date', value: _GoalSort.targetDate),
                SortOption(
                  label: 'Weight',
                  value: _GoalSort.weight,
                  naturalDescending: true,
                ),
                SortOption(
                  label: 'Reps',
                  value: _GoalSort.reps,
                  naturalDescending: true,
                ),
                SortOption(
                  label: 'Newest',
                  value: _GoalSort.newest,
                  naturalDescending: true,
                ),
              ],
              value: _sort,
              descending: _descending,
              onChanged: (sort, descending) => setState(() {
                _sort = sort;
                _descending = descending;
              }),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Flexible(
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text(
                    goals.isEmpty
                        ? 'No goals for this exercise yet'
                        : 'No goals match',
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.sm,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                )
              : ListView(
                  key: const ValueKey('exercise-goals-list'),
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (var i = 0; i < filtered.length; i++)
                      _GoalEntry(
                        goal: filtered[i],
                        completedSet: completed[filtered[i].goalId],
                        variationName:
                            widget.variationNames[filtered[i].variationId],
                        isLast: i == filtered.length - 1,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// One goal: the deadline over the target, the completion over both when it
/// was met. A met goal wears the success ink the `G` badge wears; an open one
/// the content ink, so the two read apart at a glance.
class _GoalEntry extends StatelessWidget {
  const _GoalEntry({
    required this.goal,
    required this.completedSet,
    required this.variationName,
    required this.isLast,
  });

  final Goal goal;

  /// The set that completed the goal — null while it stands.
  final PastSetRow? completedSet;

  final String? variationName;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final achieved = completedSet != null;
    final color = achieved ? AppColors.success : AppColors.primary;
    final target = goalRequirementsValue(goal.requirements);
    final targetDate = goal.targetDate;
    final completedDate = completedSet?.sessionCreatedDate;
    return Padding(
      key: ValueKey('exercise-goal-entry-${goal.goalId}'),
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The deadline and, over it, the day it was met — the PR entry's
          // rhythm, read across the top of each row.
          Row(
            children: [
              Text(
                targetDate == null
                    ? 'No deadline'
                    : DateFormat('d MMM yyyy').format(targetDate),
                style: AppFonts.mono(
                  fontSize: AppTextStyles.xs,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkSecondary,
                ),
              ),
              if (completedDate != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Completed ${DateFormat('d MMM yyyy').format(completedDate)}',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.xs,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              // A mark to hit while it stands, a tick once it was hit — the
              // goal card's own two glyphs.
              Icon(
                achieved ? Icons.check_circle : Icons.track_changes,
                size: 15,
                color: color,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    target.isEmpty ? 'No target' : target,
                    maxLines: 1,
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.body,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ),
              if (variationName != null && variationName!.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _variationBadgeMaxWidth,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: glassBox(color, radius: 999),
                    child: UserNameText(
                      toProperCase(variationName!),
                      style: AppFonts.mono(
                        fontSize: AppTextStyles.xs,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
