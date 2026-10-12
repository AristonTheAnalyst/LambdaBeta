import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../shared/widgets/filter_button.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_search_field.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/sort_button.dart';
import '../viewmodel/reviews_viewmodel.dart';
import 'review_picker_rows.dart';

/// Which half of the scope the sheet edits — the list whose tile was tapped
/// to open it.
///
/// The sheet shows that half and only that half: one tile, one job. The other
/// half is untouched by the visit — the write hands it back exactly as the
/// pass held it, order and all. (Noted when the split landed, 2026-10-08: the
/// goals tile lives on the goals list, which only exists once a pass has
/// goals, so a pass with none still has no way in to add its first.)
enum ReviewScopeSection { workouts, goals }

/// What the sheet leaves behind: the pass's scope as it now stands, in the
/// order the rows were shown.
///
/// Only ever answers for a sheet that edited something — null is a dismissal
/// that changed nothing, which the caller must not read as an empty scope.
class ReviewScopeEdit {
  const ReviewScopeEdit({required this.sessionIds, required this.goalIds});

  final List<String> sessionIds;
  final List<String> goalIds;
}

/// Edits what an **open** pass covers: tick a workout or a goal to add it to
/// the review, untick one to take it out.
///
/// The same tick-row interaction as the selection screen, on the same rows, for
/// the same reason: building the set is one gesture whether it is being built
/// for the first time or changed halfway through. Every tick writes through to
/// the row as it is made — the scope is what the pass *is*, and an edit that
/// lived only in a sheet would go with it — and the sheet stays open, so the
/// set is edited in one visit rather than one visit per tick.
///
/// [loadWorkouts] and [loadGoals] are seams for tests; the defaults read the
/// same lists the picker offers, so the sheet can never show a workout the
/// picker would not. Only the shown half is loaded — a visit costs what it
/// shows.
///
/// Each half can be narrowed as it is read — a search either side, a sort on
/// the workouts, a filter and a sort on the goals (2026-10-10). None of it
/// changes what the sheet is: a query hides rows without touching the scope,
/// and the sort is the order a tick writes in.
Future<ReviewScopeEdit?> showReviewScopeSheet(
  BuildContext context, {
  required String reviewId,
  required String userId,
  required List<String> sessionIds,
  required List<String> goalIds,
  ReviewScopeSection section = ReviewScopeSection.workouts,
  Future<List<ReviewableWorkout>> Function()? loadWorkouts,
  Future<List<ReviewableGoal>> Function()? loadGoals,
  ProgramHistoryRepository? repository,
}) {
  return showLambdaModal<ReviewScopeEdit>(
    context,
    fitContent: true,
    // Both halves carry a search box, so this sheet is the one that can meet
    // a keyboard — the sheet lifts over it instead of letting it cover the
    // rows (2026-10-10).
    keyboardAware: true,
    child: _ReviewScopeSheet(
      reviewId: reviewId,
      userId: userId,
      sessionIds: sessionIds,
      goalIds: goalIds,
      section: section,
      loadWorkouts: loadWorkouts,
      loadGoals: loadGoals,
      repository: repository,
    ),
  );
}

/// How the workouts half can be ordered. "Recently logged" is the order the
/// list arrives in — the loader's own recency rule — so the default reading
/// changes nothing until the user asks (2026-10-10).
enum _WorkoutSort { recent, finished, name }

const _workoutSortOptions = [
  SortOption(
    label: 'Recently logged',
    value: _WorkoutSort.recent,
    naturalDescending: true,
  ),
  SortOption(
    label: 'Most finished',
    value: _WorkoutSort.finished,
    naturalDescending: true,
  ),
  SortOption(label: 'A–Z', value: _WorkoutSort.name),
];

/// How the goals half can be ordered, and which of its rows it shows.
///
/// The filter reads the *live* ticks: "Not in this review" is the list of
/// goals still to add, and ticking one takes its row out of that list as the
/// tick is made (2026-10-10).
enum _GoalSort { name, target }

enum _GoalFilter { all, inReview, notInReview }

const _goalSortOptions = [
  SortOption(label: 'A–Z', value: _GoalSort.name),
  SortOption(
    label: 'Heaviest target',
    value: _GoalSort.target,
    naturalDescending: true,
  ),
];

const _goalFilterOptions = [
  FilterOption(label: 'All', value: _GoalFilter.all),
  FilterOption(label: 'In this review', value: _GoalFilter.inReview),
  FilterOption(label: 'Not in this review', value: _GoalFilter.notInReview),
];

class _ReviewScopeSheet extends StatefulWidget {
  const _ReviewScopeSheet({
    required this.reviewId,
    required this.userId,
    required this.sessionIds,
    required this.goalIds,
    required this.section,
    this.loadWorkouts,
    this.loadGoals,
    this.repository,
  });

  final String reviewId;
  final String userId;

  /// The scope the pass already has — what the ticks are seeded from, and the
  /// ids the sheet cannot show but must not drop.
  final List<String> sessionIds;
  final List<String> goalIds;

  /// Which half this visit edits.
  final ReviewScopeSection section;
  final Future<List<ReviewableWorkout>> Function()? loadWorkouts;
  final Future<List<ReviewableGoal>> Function()? loadGoals;
  final ProgramHistoryRepository? repository;

  @override
  State<_ReviewScopeSheet> createState() => _ReviewScopeSheetState();
}

class _ReviewScopeSheetState extends State<_ReviewScopeSheet> {
  /// What the pass covers, as it is being edited. Seeded from the pass itself:
  /// the sheet opens on the scope it is changing, not on an empty one.
  late final Set<String> _pickedWorkouts = {...widget.sessionIds};
  late final Set<String> _pickedGoals = {...widget.goalIds};

  late final _repository = widget.repository ?? ProgramHistoryRepository();

  List<ReviewableWorkout>? _workouts;
  List<ReviewableGoal>? _goals;

  /// Set when a tap was refused because it would have left the pass with no
  /// workouts. Cleared by the next tap that lands.
  bool _needsAWorkout = false;

  /// Each half's own search — a workout list and a goal list can both run
  /// long enough that finding one is the visit's real work (2026-10-10).
  String _workoutQuery = '';
  String _goalQuery = '';

  /// How each list is ordered, and which goals are shown. The defaults are
  /// the readings the rows already arrive in, so opening the sheet changes
  /// nothing until the user asks: workouts keep the loader's recency order,
  /// goals read A–Z (the library's own order), nothing filtered.
  _WorkoutSort _workoutSort = _WorkoutSort.recent;
  bool _workoutSortDesc = true;
  _GoalSort _goalSort = _GoalSort.name;
  bool _goalSortDesc = false;
  _GoalFilter _goalFilter = _GoalFilter.all;

  /// Set when a write failed. The ticks are rolled back with it — the row is
  /// what the pass is, and a tick it does not have is a lie the landing would
  /// keep showing — so the sheet says what went wrong instead of re-ticking.
  bool _failed = false;

  /// True once something has been written — what the sheet answers with.
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Which half this visit is here for; the other is not loaded, not drawn,
  /// and handed back untouched.
  bool get _showsWorkouts => widget.section == ReviewScopeSection.workouts;

  Future<void> _load() async {
    final workouts = _showsWorkouts
        ? await (widget.loadWorkouts ??
              () => fetchReviewableWorkouts(userId: widget.userId))()
        : null;
    final goals = _showsWorkouts
        ? null
        : await (widget.loadGoals ??
              () => fetchReviewableGoals(userId: widget.userId))();
    if (!mounted) return;
    setState(() {
      _workouts = workouts;
      _goals = goals;
    });
  }

  /// The one list this visit edits, as rows.
  List<Widget> get _rows => _showsWorkouts ? _workoutRows : _goalRows;

  /// [items] in [compare]'s order, ties keeping the order they arrived in —
  /// Dart's sort is not stable, and a row that moved under an equal row for no
  /// reason reads as a glitch.
  List<T> _sorted<T>(List<T> items, int Function(T, T) compare) {
    final indexed = [
      for (var i = 0; i < items.length; i++) (item: items[i], index: i),
    ];
    indexed.sort((a, b) {
      final byValue = compare(a.item, b.item);
      return byValue != 0 ? byValue : a.index.compareTo(b.index);
    });
    return [for (final entry in indexed) entry.item];
  }

  /// The workouts comparator the sort is set to. A workout that has never
  /// been logged sorts to the end whichever way the direction is flipped —
  /// nothing is not the most recent thing on either reading.
  int Function(ReviewableWorkout, ReviewableWorkout) get _workoutCompare {
    final direction = _workoutSortDesc ? -1 : 1;
    return switch (_workoutSort) {
      _WorkoutSort.recent => (a, b) {
        final x = a.lastLogged;
        final y = b.lastLogged;
        if (x == null && y == null) return 0;
        if (x == null) return 1;
        if (y == null) return -1;
        return x.compareTo(y) * direction;
      },
      _WorkoutSort.finished => (a, b) =>
          a.finished.compareTo(b.finished) * direction,
      _WorkoutSort.name => (a, b) =>
          a.label.toLowerCase().compareTo(b.label.toLowerCase()) * direction,
    };
  }

  /// The goals comparator the sort is set to. A goal that recorded no weight
  /// is never the heaviest — it stays at the end either way — and at equal
  /// weight more reps is the heavier ask.
  int Function(ReviewableGoal, ReviewableGoal) get _goalCompare {
    final direction = _goalSortDesc ? -1 : 1;
    return switch (_goalSort) {
      _GoalSort.name => (a, b) =>
          a.exerciseName.toLowerCase().compareTo(b.exerciseName.toLowerCase()) *
          direction,
      _GoalSort.target => (a, b) {
        final x = a.targetWeight;
        final y = b.targetWeight;
        if (x == null && y == null) return 0;
        if (x == null) return 1;
        if (y == null) return -1;
        final byWeight = x.compareTo(y) * direction;
        if (byWeight != 0) return byWeight;
        return (a.targetReps ?? 0).compareTo(b.targetReps ?? 0) * direction;
      },
    };
  }

  /// The whole workouts list in the sort's order — what a tick writes in.
  /// The *whole* list, whatever a query is hiding: a search narrows the view,
  /// it must not jump a ticked row to the front of the scope.
  List<ReviewableWorkout> get _workoutsInOrder =>
      _sorted(_workouts!, _workoutCompare);

  /// The whole goals list in the sort's order — see [_workoutsInOrder].
  List<ReviewableGoal> get _goalsInOrder => _sorted(_goals!, _goalCompare);

  /// Whether [goal] passes the filter in force. The filter reads the *live*
  /// ticks: "Not in this review" is the list of goals still to add, and a
  /// tick takes its row out of that list as the tick is made.
  bool _passesGoalFilter(ReviewableGoal goal) => switch (_goalFilter) {
    _GoalFilter.all => true,
    _GoalFilter.inReview => _pickedGoals.contains(goal.goalId),
    _GoalFilter.notInReview => !_pickedGoals.contains(goal.goalId),
  };

  List<Widget> get _workoutRows {
    final term = _workoutQuery.trim().toLowerCase();
    final shown = [
      for (final workout in _workoutsInOrder)
        if (term.isEmpty || workout.label.toLowerCase().contains(term))
          workout,
    ];
    return [
      if (shown.isEmpty && _workouts!.isNotEmpty)
        Text(
          'No workouts match “${_workoutQuery.trim()}”.',
          style: AppFonts.ui(
            fontSize: AppTextStyles.xs,
            color: AppColors.muted,
          ),
        )
      else
        for (final workout in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ReviewTickRow(
              title: workout.label,
              caption: [workout.sinceReviewLabel, workout.finishedLabel],
              ticked: _pickedWorkouts.contains(workout.sessionId),
              onTap: () => _toggleWorkout(workout.sessionId),
            ),
          ),
    ];
  }

  List<Widget> get _goalRows {
    final term = _goalQuery.trim().toLowerCase();
    final goals = [
      for (final goal in _goalsInOrder)
        if (_passesGoalFilter(goal) &&
            (term.isEmpty ||
                goal.exerciseName.toLowerCase().contains(term) ||
                goal.target.toLowerCase().contains(term)))
          goal,
    ];
    return [
      if (_goals!.isEmpty)
        Text(
          'No goals yet — add a PR target you\'d like to hit, and any of them '
          'can be reviewed here.',
          style: AppFonts.ui(
            fontSize: AppTextStyles.xs,
            color: AppColors.muted,
          ),
        )
      else if (goals.isEmpty)
        Text(
          term.isNotEmpty
              ? 'No goals match “${_goalQuery.trim()}”.'
              : 'No goals with this filter.',
          style: AppFonts.ui(
            fontSize: AppTextStyles.xs,
            color: AppColors.muted,
          ),
        )
      else
        for (final goal in goals)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ReviewTickRow(
              title: goal.exerciseName,
              target: goal.target,
              ticked: _pickedGoals.contains(goal.goalId),
              onTap: () => _toggleGoal(goal.goalId),
            ),
          ),
    ];
  }

  /// The scope as the row should now hold it: everything in [ordered], ticked
  /// rows kept in that order, then whatever the sheet could not show — a
  /// workout deleted since the pass began stays in the scope. The scope is
  /// edited, not rebuilt from today's picker, and the order it stores is the
  /// list's own, sort included.
  List<String> _ordered(List<String> ordered, Set<String> picked, List<String> original) {
    final ids = [for (final id in ordered) if (picked.contains(id)) id];
    ids.addAll([for (final id in original) if (!ordered.contains(id)) id]);
    return ids;
  }

  // The half this visit does not show is handed back exactly as the pass held
  // it, order and all: what the sheet does not show, it does not reorder.
  List<String> get _orderedWorkouts => _showsWorkouts
      ? _ordered(
          [for (final w in _workoutsInOrder) w.sessionId],
          _pickedWorkouts,
          widget.sessionIds,
        )
      : widget.sessionIds;

  List<String> get _orderedGoals => _showsWorkouts
      ? widget.goalIds
      : _ordered(
          [for (final g in _goalsInOrder) g.goalId],
          _pickedGoals,
          widget.goalIds,
        );

  Future<void> _toggleWorkout(String sessionId) async {
    // Removing the last workout would leave a pass with nothing to walk — the
    // one thing a review cannot be. Refused rather than silently ignored: the
    // sheet says why.
    if (_pickedWorkouts.contains(sessionId) && _pickedWorkouts.length == 1) {
      setState(() => _needsAWorkout = true);
      return;
    }
    final before = {..._pickedWorkouts};
    final beforeGoals = {..._pickedGoals};
    setState(() {
      _needsAWorkout = false;
      if (!_pickedWorkouts.remove(sessionId)) _pickedWorkouts.add(sessionId);
    });
    await _write(beforeWorkouts: before, beforeGoals: beforeGoals);
  }

  Future<void> _toggleGoal(String goalId) async {
    final before = {..._pickedWorkouts};
    final beforeGoals = {..._pickedGoals};
    setState(() {
      _needsAWorkout = false;
      if (!_pickedGoals.remove(goalId)) _pickedGoals.add(goalId);
    });
    await _write(beforeWorkouts: before, beforeGoals: beforeGoals);
  }

  /// Writes the scope as it now stands, and rolls the ticks back to
  /// [beforeWorkouts]/[beforeGoals] if the write fails — what the sheet showed
  /// before this tap, captured by the caller *before* it moved a tick. Nothing
  /// is re-read: the sheet knows exactly what it changed.
  Future<void> _write({
    required Set<String> beforeWorkouts,
    required Set<String> beforeGoals,
  }) async {
    try {
      await _repository.setReviewScope(
        widget.reviewId,
        sessionIds: _orderedWorkouts,
        goalIds: _orderedGoals,
      );
      if (!mounted) return;
      setState(() {
        _edited = true;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _pickedWorkouts
          ..clear()
          ..addAll(beforeWorkouts);
        _pickedGoals
          ..clear()
          ..addAll(beforeGoals);
      });
    }
  }

  void _done() {
    Navigator.of(context, rootNavigator: true).pop(
      _edited
          ? ReviewScopeEdit(
              sessionIds: _orderedWorkouts,
              goalIds: _orderedGoals,
            )
          : null,
    );
  }

  /// The workouts toolbar: search, then sort. No filter — every workout the
  /// pass could hold is worth seeing, and the list is short by nature.
  Widget _workoutToolbar() => Row(
    children: [
      Expanded(
        child: LambdaSearchField(
          hint: 'Search workouts…',
          showIcon: true,
          // The sheet's default background is a surface ground.
          elevated: true,
          onChanged: (value) => setState(() => _workoutQuery = value),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      SortButton<_WorkoutSort>(
        options: _workoutSortOptions,
        value: _workoutSort,
        descending: _workoutSortDesc,
        // The sheet's default background is a surface ground.
        elevated: true,
        onChanged: (value, descending) => setState(() {
          _workoutSort = value;
          _workoutSortDesc = descending;
        }),
      ),
    ],
  );

  /// The goals toolbar: search, filter, sort — a goal list can be long enough
  /// that "which ones" is asked as often as "which one".
  Widget _goalToolbar() => Row(
    children: [
      Expanded(
        child: LambdaSearchField(
          hint: 'Search goals…',
          showIcon: true,
          elevated: true,
          onChanged: (value) => setState(() => _goalQuery = value),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      FilterButton<_GoalFilter>(
        options: _goalFilterOptions,
        value: _goalFilter,
        active: _goalFilter != _GoalFilter.all,
        // The sheet's default background is a surface ground.
        elevated: true,
        onChanged: (value) => setState(() => _goalFilter = value),
      ),
      const SizedBox(width: AppSpacing.sm),
      SortButton<_GoalSort>(
        options: _goalSortOptions,
        value: _goalSort,
        descending: _goalSortDesc,
        // The sheet's default background is a surface ground.
        elevated: true,
        onChanged: (value, descending) => setState(() {
          _goalSort = value;
          _goalSortDesc = descending;
        }),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final loading = _showsWorkouts ? _workouts == null : _goals == null;
    final hasRows = _showsWorkouts
        ? _workouts?.isNotEmpty ?? false
        : _goals?.isNotEmpty ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // The sheet's heading is the section word itself — the same
                // label the list used to wear under its own title, promoted
                // (2026-10-10): "In this review" said nothing the tile that
                // opened the sheet had not, and the count line under it read
                // as a stat nobody asked for.
                Expanded(
                  child: ReviewSectionLabel(
                    _showsWorkouts ? 'WORKOUTS' : 'GOALS',
                  ),
                ),
                GlassButton(label: 'Done', compact: true, onPressed: _done),
              ],
            ),
            // Both refusals sit here, under the heading they explain, rather
            // than down beside the rows that caused them: the list scrolls
            // under a cap, and a reason the user has to go looking for is not
            // a reason the sheet gave.
            if (_needsAWorkout) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'A review needs at least one workout — add another before '
                'taking this one out.',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.xs,
                  color: AppColors.muted,
                ),
              ),
            ],
            if (_failed) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Could not update the review — the change was not saved.',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.xs,
                  color: AppColors.danger,
                ),
              ),
            ],
            // The toolbar rides above the rows it reads, and stays up while a
            // query or a filter empties the list below it — a search box that
            // disappeared the moment it matched nothing could never be
            // cleared.
            if (!loading && hasRows) ...[
              const SizedBox(height: AppSpacing.md),
              if (_showsWorkouts) _workoutToolbar() else _goalToolbar(),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  // 0.55 of the room that is actually left: with the keyboard
                  // up, the sheet is lifted by its height (keyboardAware), so
                  // a cap measured on the full screen would push the sheet
                  // past the top of it.
                  maxHeight:
                      (MediaQuery.sizeOf(context).height -
                          MediaQuery.viewInsetsOf(context).bottom) *
                      0.55,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: _rows,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
