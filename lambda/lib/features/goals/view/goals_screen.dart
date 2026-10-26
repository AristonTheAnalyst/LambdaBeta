import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/date_range.dart';
import '../../../data/models/exercise_usage.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../shared/widgets/add_exercise_modal.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/date_range_selector.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_search_field.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/section_divider.dart';
import '../../../shared/widgets/segmented_control.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/sort_button.dart';
import '../../../shared/widgets/swipe_actions.dart';
import '../viewmodel/goals_viewmodel.dart';
import 'goal_dialogs.dart';
import 'goal_row.dart';
import 'goal_sheet.dart';

/// How a goal stands — the one status question the filter asks, answered in
/// one control (2026-10-20).
enum GoalStatus { all, complete, incomplete }

/// Everything the toolbar's filter narrows by (2026-10-20).
///
/// The filter used to be one status menu; it is now a sheet, because "which
/// goals" has more than one answer and they combine: the exercises the goals
/// sit on, how the goal stands, when its deadline falls, and when it was
/// completed. Each half is independent — an `all` range and an empty exercise
/// set are the unfiltered reading of that half — so [isActive] is simply "any
/// half is saying something", and the toolbar's button turns accent off it.
///
/// The two date ranges narrow by different clocks, which is why they are two
/// and not one: a goal can be due in June and completed in April, and a
/// reader may want either window. There is no written-date window — the sheet
/// asks what a goal is and how it stands, and "when it was written" was a
/// third answer nobody was asking for (2026-10-20).
@immutable
class GoalFilters {
  const GoalFilters({
    this.status = GoalStatus.all,
    this.targetDate = _allDates,
    this.completedDate = _allDates,
    this.exercises = const {},
  });

  static const _allDates = DateRangeSelection.preset(DateRangePreset.all);

  final GoalStatus status;

  /// The windows the goal's two dates are narrowed to. `all` = that clock
  /// does not narrow; any other selection excludes goals whose date on that
  /// clock is missing — a goal with no deadline cannot fall inside a window of
  /// deadlines.
  final DateRangeSelection targetDate;
  final DateRangeSelection completedDate;

  /// The exercise section keys in force (the same identity the list headers
  /// group by — an id, or the captured name of a goal written before goals
  /// named an exercise). Empty = every exercise.
  final Set<String> exercises;

  bool get isActive =>
      status != GoalStatus.all ||
      targetDate.preset != DateRangePreset.all ||
      completedDate.preset != DateRangePreset.all ||
      exercises.isNotEmpty;

  GoalFilters copyWith({
    GoalStatus? status,
    DateRangeSelection? targetDate,
    DateRangeSelection? completedDate,
    Set<String>? exercises,
  }) => GoalFilters(
    status: status ?? this.status,
    targetDate: targetDate ?? this.targetDate,
    completedDate: completedDate ?? this.completedDate,
    exercises: exercises ?? this.exercises,
  );
}

/// Whether [date] falls inside [window] — on the day a goal date is kept at,
/// so a deadline stored with a time still lands on its own day.
bool _inWindow(DateTime? date, ({DateTime from, DateTime to}) window) {
  if (date == null) return false;
  final day = dateOnly(date);
  return !day.isBefore(window.from) && day.isBefore(window.to);
}

/// What the Goals list is ordered by.
///
/// [exercise] is the default (2026-10-20). The shelf leads with the exercise
/// whose soonest **open** deadline is nearest — a completed goal's deadline
/// is history and never orders the shelf — then exercises whose open goals
/// carry no deadline, then exercises whose goals are all completed. Inside an
/// exercise the open goals lead and the completed ones follow, each side read
/// by its deadline, soonest first, with undated goals under the dated ones.
///
/// [added] is the repository's creation order — goals carry no created date
/// on the model, and the repository already read them oldest-first, so the
/// index IS the age. Its natural reading is newest first.
enum GoalSortCriterion { exercise, added, name, target }

const _sortOptions = [
  SortOption(label: 'By exercise', value: GoalSortCriterion.exercise),
  SortOption(
    label: 'Recently added',
    value: GoalSortCriterion.added,
    naturalDescending: true,
  ),
  SortOption(label: 'Name', value: GoalSortCriterion.name),
  SortOption(
    label: 'Heaviest target',
    value: GoalSortCriterion.target,
    naturalDescending: true,
  ),
];

/// The goals library: every target the user is chasing, and the + that adds
/// one.
///
/// Goals live by themselves (2026-10-08) — no program, no block — so this is
/// their own home beside Reviews.
///
/// The tab is a toolbar and a list (2026-10-19). Search, filter and sort act
/// on the loaded rows; adding moved off the list's foot and into a sheet the
/// + opens, so the list is only ever the goals themselves. The caption that
/// used to sit above them moved into the Library header's ⓘ — the place a
/// reader asks what this tab is (see `ExerciseHubScreen`).
///
/// **The list is sectioned by exercise, then by variation (2026-10-19).** The
/// exercise header pins to the top of the list while its section is on
/// screen, the variation subheader pins under it, and the next section pushes
/// them away — so the context a card is read in is always at the top rather
/// than scrolled off. Sections and subsections appear in the order their
/// first goal appears in the sort, so the toolbar's ordering reaches every
/// level of the list.
///
/// **The default order is by exercise, as a plan rather than a log
/// (2026-10-20).** Exercises lead by the soonest deadline among their **open**
/// goals; exercises whose open goals carry no deadline follow (by name), and
/// exercises whose goals are all completed trail everything. Inside an
/// exercise the open goals come first and the completed ones after, each side
/// read by its deadline. The other criteria order the goals only — the
/// sections follow them — so done work stays reachable without ever leading.
///
/// **Sections open on a tap (2026-10-20).** A library with goals on ten lifts
/// otherwise opens as ten cards of noise; collapsed, it opens as what it is —
/// a shelf of exercises — and the arrow on each header opens the one being
/// read. Collapsed is the default; the expanded set lives in the screen's
/// state, so a filter or a sort that rebuilds the list does not close what the
/// user opened.
///
/// **The filter is a sheet, not a menu (2026-10-20).** "Which goals" combines
/// status, three date windows and the exercises the goals sit on; [GoalFilters]
/// is the model behind it, and the funnel in the toolbar opens the sheet.
///
/// Deletion is a question, not a gesture (2026-10-19): the row swipes to a
/// drawer like Reviews' cards, and the drawer asks `confirmDeleteGoal` before
/// anything is written. The card carries no × — a delete that lives behind a
/// deliberate swipe can be taken back before the question is even asked.
///
/// [showHeader] false is the embedded form — the Library's Goals tab — where
/// the host owns the header and this screen contributes the toolbar's +. The
/// standalone form keeps the + in its own header, so the one verb sits in the
/// same corner in both.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({
    super.key,
    this.showHeader = true,
    this.viewModel,
    this.openWorkout,
  });

  final bool showHeader;

  /// The view model to render, when a caller already has one.
  ///
  /// Null = the screen loads its own. The seam exists for host tests: the
  /// repositories this screen reads through reach PowerSync, which a widget
  /// test has no way to stand up, so the only place to inject a fake is above
  /// them. A real caller never passes one — this screen owns its goals.
  final GoalsViewModel? viewModel;

  /// Opens the workout that beat a target being composed in the add sheet.
  ///
  /// Null = push its logs route, which is what the app does. The seam exists
  /// for host tests, which render under a bare `MaterialApp` with no router.
  final void Function(String sessionId)? openWorkout;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  late final GoalsViewModel _vm;

  /// Whether [_vm] is this screen's to dispose. An injected view model belongs
  /// to whoever passed it — and a host test that supplies one goes on asserting
  /// against it after the widget is gone.
  var _ownsVm = true;

  final _searchController = TextEditingController();
  String _query = '';
  GoalFilters _filters = const GoalFilters();
  GoalSortCriterion _sort = GoalSortCriterion.exercise;
  bool _sortDesc = false;

  /// The exercise sections the user has opened, by [_GoalSection.key]. Empty
  /// at first — collapsed is the default (2026-10-20) — and kept across
  /// filter, search and sort changes: what the user opened stays open, and
  /// what they never opened stays a header.
  final _expandedSections = <String>{};

  /// The New Goal form's contents, kept here rather than in the sheet
  /// (2026-10-19): a tap outside dismisses the sheet, and what the user typed
  /// must still be there when they come back. Only a written goal clears it.
  final _goalDraft = ExerciseTargetDraft();

  @override
  void initState() {
    super.initState();
    final injected = widget.viewModel;
    _ownsVm = injected == null;
    _vm = injected ?? GoalsViewModel();
    _vm.state.addListener(_onState);
    _searchController.addListener(() {
      if (mounted) setState(() => _query = _searchController.text);
    });
    // A caller that supplied the view model supplied its state too — loading
    // over it would replace what they set up.
    if (injected == null) _vm.load();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _goalDraft.dispose();
    _vm.state.removeListener(_onState);
    if (_ownsVm) _vm.dispose();
    super.dispose();
  }

  /// Deletes a goal — the swipe drawer's delete lands here, and it asks
  /// first. The question names the goal by the exercise it targets, because
  /// that is the row under the user's finger.
  Future<void> _delete(Goal goal) async {
    final name = goalExerciseNameFor(goal, _vm.state.value.exerciseDetailMap);
    if (!await confirmDeleteGoal(context, label: name)) return;
    if (!mounted) return;
    await _vm.deleteGoal(goal.goalId);
  }

  /// The focused view — the same form the New goal sheet composes, resting.
  ///
  /// The goal's own history is read fresh here rather than served from the
  /// list's load — a sheet opened after a workout is logged must see that
  /// workout (2026-10-19).
  Future<void> _open(Goal goal) {
    final state = _vm.state.value;
    return showGoalSheet(
      context,
      goal: goal,
      exerciseName: goalExerciseNameFor(goal, state.exerciseDetailMap),
      detailMap: state.exerciseDetailMap,
      variations: state.variations,
      loadPastSets: _vm.loadPastSets,
      onOpenWorkout: _openWorkout,
      // SAVE writes the whole row — the exercise and target included — and
      // mirrors what the read-back row says, budget history and all.
      onSave: (target) => _vm.updateGoal(
        goal.goalId,
        exerciseId: target.exerciseId,
        exerciseName: target.exerciseName,
        variationId: target.variationId,
        targetWeight: target.weight,
        targetReps: target.reps,
        description: target.notes,
        targetDate: target.targetDate,
      ),
    );
  }

  /// The door behind a green date — the creation form's "already beat this"
  /// caption and the stored goal's completion row both land here (2026-10-20):
  /// the past-session viewer on its **Details** tab, with the exercise that
  /// logged the set selected, so the set that achieved the goal is on screen
  /// wearing its green G.
  void _openWorkout(PastSetRow set) {
    final open = widget.openWorkout;
    if (open != null) {
      open(set.sessionId);
      return;
    }
    final exercise = set.exerciseId;
    final query = exercise == null
        ? 'tab=details'
        : 'tab=details&exercise=${Uri.encodeComponent(exercise)}';
    context.push('/logs/${set.sessionId}?$query');
  }

  /// + → the add sheet → the writes → Done.
  ///
  /// The sheet stays up after each write, so goals can be written in a run
  /// (2026-10-26): it clears its own form for the next target and confirms
  /// what it wrote, and the section each goal lands in opens behind it, so
  /// Done (or any dismissal) lands on the goals rather than on collapsed
  /// headers (2026-10-20). The draft outlives the sheet on purpose
  /// (2026-10-19): a tap outside, a back gesture or the trip to a logged
  /// workout all dismiss or cover the sheet, and reopening it must find the
  /// form as it was left. Only a written goal clears it.
  Future<void> _openAdd() async {
    final state = _vm.state.value;
    await showAddGoalSheet(
      context,
      detailMap: state.exerciseDetailMap,
      variations: state.variations,
      // The same timeline the list's outcomes read, read for recency: the
      // picker opens on what was trained last (2026-10-19).
      lastUsed: lastUsedByEntity(state.pastSets),
      // ...and read for the "already beat this" verdict, so the form can
      // name the day the target was met and open that workout.
      pastSets: state.pastSets,
      draft: _goalDraft,
      onOpenWorkout: _openWorkout,
      onAdd: (target) async {
        final ok = await _vm.addGoal(
          exerciseId: target.exerciseId,
          exerciseName: target.exerciseName,
          variationId: target.variationId,
          targetWeight: target.weight,
          targetReps: target.reps,
          description: target.notes,
          targetDate: target.targetDate,
        );
        if (ok && mounted) {
          // The sheet is still up: the list behind it opens the section the
          // goal landed in as the write's echo.
          setState(() => _expandedSections.add(target.exerciseId));
        }
        return ok;
      },
    );
  }

  /// Funnel → the filter sheet. The sheet works on a copy and answers on
  /// Done; a dismissal returns null and changes nothing.
  Future<void> _openFilters() async {
    final picked = await showLambdaModal<GoalFilters>(
      context,
      fitContent: true,
      child: _GoalFilterSheet(
        initial: _filters,
        exercises: _exerciseOptions(_vm.state.value),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _filters = picked);
  }

  /// Every exercise that holds a goal — the filter's tick list, in repository
  /// order (the picker it opens orders its own rows). Built from all goals
  /// rather than the visible ones: a list that shrinks under the filter it is
  /// editing would hide the tick it is showing, leaving no way to untick it.
  List<({String key, String name})> _exerciseOptions(GoalsState state) {
    final seen = <String>{};
    final options = <({String key, String name})>[];
    for (final goal in state.goals) {
      final name = goalExerciseNameFor(goal, state.exerciseDetailMap);
      final key = goal.exerciseId ?? name;
      if (seen.add(key)) options.add((key: key, name: name));
    }
    return options;
  }

  /// Opens or closes one exercise section. The arrow on its header is the
  /// control; the header itself is the target (2026-10-20).
  void _toggleSection(String key) {
    setState(() {
      if (!_expandedSections.add(key)) _expandedSections.remove(key);
    });
  }

  /// The rows the list draws: filter → search → sort, in that order, so the
  /// search box narrows what the filter already chose and the sort orders what
  /// survives. Names are resolved once per row; the goal's notes are searched
  /// too, though they are not on the row.
  ///
  /// The filter's date halves read the two clocks a goal has (2026-10-20):
  /// its deadline and the day its outcome was achieved. A goal missing the
  /// date a window narrows by cannot be in that window, so it is excluded —
  /// "no deadline" is not "any deadline".
  List<Goal> _visibleGoals(GoalsState state) {
    final query = _query.trim().toLowerCase();
    final detailMap = state.exerciseDetailMap;
    final today = DateTime.now();
    final targetWindow = _filters.targetDate.window(today);
    final completedWindow = _filters.completedDate.window(today);
    final narrowTarget = _filters.targetDate.preset != DateRangePreset.all;
    final narrowCompleted =
        _filters.completedDate.preset != DateRangePreset.all;
    final rows = <({Goal goal, int order, String name})>[];

    for (final (order, goal) in state.goals.indexed) {
      final outcome = state.outcomes[goal.goalId];
      final achieved = outcome?.achieved ?? false;
      if (_filters.status == GoalStatus.complete && !achieved) continue;
      if (_filters.status == GoalStatus.incomplete && achieved) continue;

      final name = goalExerciseNameFor(goal, detailMap);
      if (_filters.exercises.isNotEmpty &&
          !_filters.exercises.contains(goal.exerciseId ?? name)) {
        continue;
      }
      if (narrowTarget && !_inWindow(goal.targetDate, targetWindow)) continue;
      if (narrowCompleted &&
          !_inWindow(outcome?.evidenceDate, completedWindow)) {
        continue;
      }

      if (query.isNotEmpty) {
        final haystack = '$name ${goal.description ?? ''} ${goal.text ?? ''}'
            .toLowerCase();
        if (!haystack.contains(query)) continue;
      }
      rows.add((goal: goal, order: order, name: name));
    }

    if (_sort == GoalSortCriterion.exercise) {
      _sortByExercise(rows, state);
      return [for (final row in rows) row.goal];
    }

    rows.sort((a, b) {
      final primary = switch (_sort) {
        // Unreachable — the default order returned above; listed so the
        // switch stays exhaustive as criteria are added.
        GoalSortCriterion.exercise => 0,
        GoalSortCriterion.added => a.order.compareTo(b.order),
        GoalSortCriterion.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        GoalSortCriterion.target => (a.goal.targetWeight ?? -1).compareTo(
          b.goal.targetWeight ?? -1,
        ),
      };
      if (primary != 0) return _sortDesc ? -primary : primary;
      // Equal criteria keep the repository's order — a stable, readable tie
      // break rather than a sort that reshuffles on every rebuild.
      return a.order.compareTo(b.order);
    });
    return [for (final row in rows) row.goal];
  }

  /// The list's default order (2026-10-20): the shelf reads as a plan rather
  /// than a log.
  ///
  /// Exercises sort by the soonest deadline among their **open** goals — a
  /// completed goal's deadline is history, and letting it order the shelf
  /// would put done work first. Exercises whose open goals carry no deadline
  /// follow (by name), and exercises whose goals are all completed trail
  /// everything, so what is still being chased always leads.
  ///
  /// Inside an exercise the open goals come first and the completed ones
  /// after; each side reads by deadline, soonest first, and a goal with no
  /// deadline sits under the dated ones. Re-picking the criterion flips the
  /// deadline reading (latest first); the open-before-done rule does not
  /// flip, because completion is not a direction.
  ///
  /// The section order is computed from the rows on screen — the filtered and
  /// searched set — so a narrowed list is ordered as the reader sees it.
  void _sortByExercise(
    List<({Goal goal, int order, String name})> rows,
    GoalsState state,
  ) {
    DateTime? day(Goal goal) {
      final date = goal.targetDate;
      return date == null ? null : dateOnly(date);
    }

    bool achieved(Goal goal) => state.outcomes[goal.goalId]?.achieved ?? false;

    // One pass per section: does it still hold an open goal, and if so, when
    // is its soonest deadline?
    final ranks = <String, _SectionRank>{};
    for (final row in rows) {
      final rank = ranks.putIfAbsent(
        _sectionKey(row.goal, row.name),
        () => _SectionRank(row.name),
      );
      if (achieved(row.goal)) continue;
      rank.hasOpen = true;
      final date = day(row.goal);
      if (date == null) continue;
      final soonest = rank.soonest;
      if (soonest == null || date.isBefore(soonest)) rank.soonest = date;
    }

    // 0 = an open dated goal to work toward, 1 = open but undated, 2 = done.
    int tier(_SectionRank rank) =>
        rank.soonest != null ? 0 : (rank.hasOpen ? 1 : 2);

    final keys = ranks.keys.toList()
      ..sort((a, b) {
        final ra = ranks[a]!, rb = ranks[b]!;
        final ta = tier(ra), tb = tier(rb);
        if (ta != tb) return ta.compareTo(tb);
        if (ta == 0) {
          final cmp = ra.soonest!.compareTo(rb.soonest!);
          if (cmp != 0) return _sortDesc ? -cmp : cmp;
        }
        // Sections without a deadline read by name — the same A–Z the other
        // undated readings use — and the key keeps the order stable.
        final byName = ra.name.toLowerCase().compareTo(rb.name.toLowerCase());
        return byName != 0 ? byName : a.compareTo(b);
      });
    final place = {for (final (index, key) in keys.indexed) key: index};

    rows.sort((a, b) {
      final pa = place[_sectionKey(a.goal, a.name)]!;
      final pb = place[_sectionKey(b.goal, b.name)]!;
      if (pa != pb) return pa.compareTo(pb);

      final doneA = achieved(a.goal), doneB = achieved(b.goal);
      if (doneA != doneB) return doneA ? 1 : -1;

      final dateA = day(a.goal), dateB = day(b.goal);
      if (dateA != null && dateB != null) {
        final cmp = dateA.compareTo(dateB);
        if (cmp != 0) return _sortDesc ? -cmp : cmp;
      } else if (dateA != null) {
        return -1;
      } else if (dateB != null) {
        return 1;
      }
      // Equal placements keep the repository's order — a stable, readable tie
      // break rather than a sort that reshuffles on every rebuild.
      return a.order.compareTo(b.order);
    });
  }

  /// The identity a section, a filter tick and a goal's exercise share: the
  /// exercise's id, or the captured name of a goal written before goals named
  /// an exercise.
  String _sectionKey(Goal goal, String name) => goal.exerciseId ?? name;

  @override
  Widget build(BuildContext context) {
    final state = _vm.state.value;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          if (widget.showHeader)
            PageHeader(
              title: 'Goals',
              right: GlassButton(
                label: '',
                icon: Icons.add,
                semanticsLabel: 'Add goal',
                compact: true,
                onPressed: _openAdd,
              ),
            ),
          _toolbar(showAdd: !widget.showHeader),
          Expanded(child: _body(state)),
        ],
      ),
    );
  }

  /// The one toolbar every library tab wears: search first, then the verbs
  /// that narrow and order it, then the tab's own + where the host header has
  /// none.
  Widget _toolbar({required bool showAdd}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: LambdaSearchField(
              controller: _searchController,
              hint: 'Search goals…',
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GlassButton(
            label: '',
            icon: Icons.filter_list,
            semanticsLabel: 'Filter goals',
            compact: true,
            // A list quietly missing rows must say so somewhere, and the
            // button is where — accent while any half is narrowing.
            color: _filters.isActive ? AppColors.accent : null,
            onPressed: _openFilters,
          ),
          const SizedBox(width: AppSpacing.sm),
          SortButton<GoalSortCriterion>(
            options: _sortOptions,
            value: _sort,
            descending: _sortDesc,
            onChanged: (value, descending) => setState(() {
              _sort = value;
              _sortDesc = descending;
            }),
          ),
          if (showAdd) ...[
            const SizedBox(width: AppSpacing.sm),
            GlassButton(
              label: '',
              icon: Icons.add,
              semanticsLabel: 'Add goal',
              compact: true,
              onPressed: _openAdd,
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(GoalsState state) {
    // The list stays up through a refresh — only a cold open has nothing to
    // show while the read is in flight.
    if (state.isLoading && state.goals.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.goals.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.md,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              GlassButton(label: 'Retry', onPressed: _vm.load),
            ],
          ),
        ),
      );
    }

    final visible = _visibleGoals(state);
    if (state.goals.isEmpty || visible.isEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          // Zero unless the shell's bar is floating over this list, which is
          // where the Library's Goals tab lives.
          AppSpacing.lg + ScrollShrinkNavBar.contentInset(context),
        ),
        children: [
          // A failure with rows still on screen — a delete that did not go
          // through — says so above them rather than replacing them.
          if (state.error != null) ...[
            Text(
              state.error!,
              textAlign: TextAlign.center,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (state.goals.isEmpty)
            const _EmptyState(
              title: 'No goals yet',
              body: 'Tap + to set a weight × reps target.',
            )
          else
            _EmptyState(
              title: 'No goals match',
              body: _query.trim().isNotEmpty
                  ? 'Nothing for "$_query".'
                  : 'Nothing matches this filter.',
            ),
        ],
      );
    }

    final sections = _sections(state, visible);
    return CustomScrollView(
      slivers: [
        if (state.error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              child: Text(
                state.error!,
                textAlign: TextAlign.center,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.danger,
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        // One group per exercise: the group is what lets the exercise header
        // pin only while its own section is on screen (the next section's
        // header pushes it away), and the nested group does the same for each
        // variation subheader.
        for (final section in sections)
          SliverMainAxisGroup(
            slivers: [
              PinnedHeaderSliver(
                child: _ExerciseHeader(
                  section.exerciseName,
                  count: section.goalCount,
                  expanded: _expandedSections.contains(section.key),
                  onTap: () => _toggleSection(section.key),
                ),
              ),
              // Collapsed by default (2026-10-20): an unopened exercise is its
              // header alone — no variation subheaders, no cards. The header is
              // a pinned sliver either way, so it stays at the top while its
              // open section scrolls under it.
              if (_expandedSections.contains(section.key))
                for (final variation in section.variations)
                  SliverMainAxisGroup(
                    slivers: [
                      PinnedHeaderSliver(
                        child: _VariationHeader(variation.name),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        sliver: SliverList.builder(
                          itemCount: variation.goals.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.md,
                            ),
                            child: _goalCard(variation.goals[i], state),
                          ),
                        ),
                      ),
                    ],
                  ),
            ],
          ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: AppSpacing.lg + ScrollShrinkNavBar.contentInset(context),
          ),
        ),
      ],
    );
  }

  /// The rows grouped for drawing: an exercise section holding variation
  /// subsections, each holding goals.
  ///
  /// Groups appear in the order their first goal appears in the sorted list,
  /// so the toolbar's ordering reaches every level of the list rather than
  /// stopping at the top of it.
  List<_GoalSection> _sections(GoalsState state, List<Goal> visible) {
    final sections = <String, _GoalSection>{};
    for (final goal in visible) {
      final exerciseName = goalExerciseNameFor(goal, state.exerciseDetailMap);
      // A goal written before goals named an exercise has no id at all: its
      // captured name is the only identity it has, so that is the group — and
      // it is the key the filter's ticks, the expansion state and the default
      // ordering all speak.
      final key = _sectionKey(goal, exerciseName);
      final section = sections.putIfAbsent(
        key,
        () => _GoalSection(key: key, exerciseName: exerciseName),
      );
      // An archived variation keeps its own subsection — the goal was set on
      // it — and says what it is rather than folding into the plain lift.
      final name =
          goalVariationNameFor(goal, state.variations) ?? 'Archived variation';
      section.variation(name).goals.add(goal);
    }
    return [for (final section in sections.values) section];
  }

  /// One card, and the swipe drawer that hides its delete.
  ///
  /// The clip radius is the card's own (2026-10-20): [SwipeActions] clips at
  /// [AppRadius.md] so the drawer's buttons can never show through the card's
  /// corners — a larger radius shaved the card's border arcs off at every
  /// corner, which only became visible when the success chrome made the edge
  /// green.
  Widget _goalCard(Goal goal, GoalsState state) => SwipeActions(
    // Keyed by goal, so a delete never hands an open drawer's state to the
    // row that slides up into its place.
    key: ValueKey(goal.goalId),
    borderRadius: AppRadius.md,
    actions: [
      SwipeAction(
        icon: Icons.delete_outline,
        color: AppColors.danger,
        foreground: AppColors.dangerText,
        onTap: () => _delete(goal),
      ),
    ],
    child: GestureDetector(
      onTap: () => _open(goal),
      // The section headers name the exercise and variation, so the card
      // itself leads with the target (2026-10-19).
      child: GoalRow(
        target: goalTargetValue(goal.targetWeight, goal.targetReps),
        targetDate: goal.targetDate,
        outcome: state.outcomes[goal.goalId],
      ),
    ),
  );
}

/// One exercise's place in the default (By exercise) ordering: the soonest
/// deadline among its **open** goals, if it has one, and whether it holds any
/// open goal at all.
///
/// A completed goal's deadline never orders the shelf — it is history, and
/// letting it lead would put done work first. A section with no open goals
/// trails every section that has some.
class _SectionRank {
  _SectionRank(this.name);

  /// The exercise's display name — the A–Z tie-break between sections whose
  /// deadlines tie or that carry none.
  final String name;

  bool hasOpen = false;
  DateTime? soonest;
}

/// One exercise's slice of the list: its goals, split by variation.
///
/// Both maps keep insertion order — the order the sorted goals arrive in —
/// which is what makes the sort reach the sections and subsections.
class _GoalSection {
  _GoalSection({required this.key, required this.exerciseName});

  /// The section's identity — the exercise's id, or the captured name of a
  /// goal written before goals named an exercise. The filter's ticks and the
  /// expansion state are keyed by it, so the three can never disagree about
  /// which section is which.
  final String key;
  final String exerciseName;
  final _variations = <String, _VariationSection>{};

  _VariationSection variation(String name) =>
      _variations.putIfAbsent(name, () => _VariationSection(name));

  Iterable<_VariationSection> get variations => _variations.values;

  /// How many goals the section holds — what a collapsed header counts.
  int get goalCount =>
      variations.fold(0, (sum, variation) => sum + variation.goals.length);
}

/// One variation's goals within an exercise section.
class _VariationSection {
  _VariationSection(this.name);

  final String name;
  final goals = <Goal>[];
}

/// A section's sticky header: the exercise name, how many goals sit under it,
/// and the arrow that opens the section (2026-10-20), with a hairline under it
/// so the pinned bar reads as a bar when cards scroll beneath it.
///
/// The whole header is the tap target — the name says which section, the arrow
/// says which way the tap will turn it, and the count is what a collapsed
/// header can say that a name alone cannot.
class _ExerciseHeader extends StatelessWidget {
  const _ExerciseHeader(
    this.name, {
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final String name;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.ui(
                fontSize: AppTextStyles.lg,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$count',
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              color: AppColors.inkSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            size: 18,
            color: AppColors.muted,
          ),
        ],
      ),
    ),
  );
}

/// A variation's sticky subheader, pinned under the exercise's header.
class _VariationHeader extends StatelessWidget {
  const _VariationHeader(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.bg,
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.xs,
    ),
    child: Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppFonts.ui(
        fontSize: AppTextStyles.sm,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
    ),
  );
}

/// The two clocks a goal has, as the filter sheet names them.
enum _GoalDate { target, completed }

/// The filter sheet: the exercises the goals sit on, status, and the two
/// date windows (2026-10-20).
///
/// A sheet rather than a menu because the question has several halves that
/// combine, and because a range needs room to state itself ("1M · 24 Sep –
/// 24 Oct"). It works on a copy of the filters it was opened with — every
/// control edits [_filters], nothing touches the list — and answers it on
/// Done; dismissing the sheet answers nothing, the contract every picker in
/// the app keeps.
///
/// A date row opens the shared range selector over this sheet (the same
/// stacked-modal pattern the goal form's calendar uses). The target date's
/// calendar reaches five years ahead — a deadline can stand in the future —
/// while completed stops at today, because a completion cannot happen
/// tomorrow.
class _GoalFilterSheet extends StatefulWidget {
  const _GoalFilterSheet({required this.initial, required this.exercises});

  final GoalFilters initial;

  /// Every exercise holding a goal, in section order — the tick list. Empty
  /// only when there are no goals, in which case the section is omitted.
  final List<({String key, String name})> exercises;

  @override
  State<_GoalFilterSheet> createState() => _GoalFilterSheetState();
}

class _GoalFilterSheetState extends State<_GoalFilterSheet> {
  late GoalFilters _filters = widget.initial;

  /// Wakes the picker's rows when a tick changes: [showAddExerciseModal]
  /// rebuilds off this listenable rather than off the sheet's own setState,
  /// because the picker is a route of its own.
  final _exerciseTicks = ValueNotifier(0);

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _exerciseTicks.dispose();
    super.dispose();
  }

  DateRangeSelection _rangeFor(_GoalDate which) => switch (which) {
    _GoalDate.target => _filters.targetDate,
    _GoalDate.completed => _filters.completedDate,
  };

  Future<void> _pickRange(_GoalDate which) async {
    final picked = await showDateRangeSelector(
      context,
      initial: _rangeFor(which),
      // Deadlines run ahead of the clock; completions cannot.
      lastDate: which == _GoalDate.target
          ? DateTime(_today.year + 5, 12, 31)
          : null,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filters = switch (which) {
        _GoalDate.target => _filters.copyWith(targetDate: picked),
        _GoalDate.completed => _filters.copyWith(completedDate: picked),
      };
    });
  }

  void _toggleExercise(String key) {
    if (!mounted) return;
    setState(() {
      final next = {..._filters.exercises};
      if (!next.remove(key)) next.add(key);
      _filters = _filters.copyWith(exercises: next);
    });
    _exerciseTicks.value++;
  }

  /// The exercise half is the session's own picker, not a grid of ticks on
  /// this sheet (2026-10-20): a library of thirty lifts would push status and
  /// the dates below the fold, and every lift ever filtered would have to be
  /// scrolled past. The sheet's field states what is narrowed; the picker
  /// searches, ticks and unticks, and stays up across taps — the same
  /// [showAddExerciseModal] a session's selector opens.
  Future<void> _pickExercises() async {
    showAddExerciseModal(
      context,
      title: 'Select Exercises',
      // The sheet opens on the list, not the keyboard (2026-10-20): this
      // picker is opened to tick what is already there, and a keyboard would
      // cover the exercises it came to show. Typing waits for a tap on the
      // search field.
      autofocusSearch: false,
      listenable: _exerciseTicks,
      entries: () => [
        for (final e in widget.exercises)
          AddExerciseEntry(exerciseId: e.key, name: e.name),
      ],
      isAdded: (key) => _filters.exercises.contains(key),
      onAdd: (key) async => _toggleExercise(key),
      onRemoveRequest: (key) async => _toggleExercise(key),
    );
  }

  /// What the exercise field says: the whole library when nothing is ticked,
  /// the lift's name when one is, the count otherwise.
  String get _exerciseLabel {
    final chosen = _filters.exercises;
    if (chosen.isEmpty) return 'All exercises';
    if (chosen.length == 1) {
      for (final e in widget.exercises) {
        if (e.key == chosen.single) return e.name;
      }
    }
    return '${chosen.length} exercises';
  }

  /// One date window — the goal form's date field recipe (glass, a calendar
  /// glyph, the selection stated in place), narrowed rows turning accent.
  Widget _rangeRow(_GoalDate which) {
    final range = _rangeFor(which);
    final narrowed = range.preset != DateRangePreset.all;
    final fg = narrowed ? AppColors.accent : AppColors.inkSecondary;
    return GestureDetector(
      key: ValueKey('goal-filter-${which.name}-date'),
      onTap: () => _pickRange(which),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: glassBox(narrowed ? AppColors.accent : AppColors.primary),
        child: Row(
          children: [
            Icon(Icons.event_outlined, size: 16, color: fg),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                range.label(_today),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: narrowed ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: fg),
          ],
        ),
      ),
    );
  }

  /// The exercise field — the date rows' own recipe (glass, a glyph, the
  /// selection stated in place, narrowed turning accent), because it is the
  /// same kind of control: a row that opens a picker over this sheet.
  Widget _exerciseField() {
    final narrowed = _filters.exercises.isNotEmpty;
    final fg = narrowed ? AppColors.accent : AppColors.inkSecondary;
    return GestureDetector(
      key: const ValueKey('goal-filter-exercises'),
      onTap: _pickExercises,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: glassBox(narrowed ? AppColors.accent : AppColors.primary),
        child: Row(
          children: [
            Icon(Icons.fitness_center, size: 16, color: fg),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _exerciseLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: narrowed ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: fg),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Filter goals',
              style: AppFonts.ui(
                fontSize: AppTextStyles.lg,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Narrow the list by the lift a goal is on, how it stands, and '
              'when it was due or completed.',
              style: AppFonts.ui(
                fontSize: AppTextStyles.xs,
                color: AppColors.inkSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // ── Exercises ──
            if (widget.exercises.isNotEmpty) ...[
              const SectionDivider('EXERCISES'),
              const SizedBox(height: AppSpacing.md),
              _exerciseField(),
              const SizedBox(height: AppSpacing.lg),
            ],
            // ── Status ──
            const SectionDivider('STATUS'),
            const SizedBox(height: AppSpacing.md),
            SegmentedControl<GoalStatus>(
              options: const [
                SegmentOption(label: 'All', value: GoalStatus.all),
                SegmentOption(label: 'Complete', value: GoalStatus.complete),
                SegmentOption(
                  label: 'Not complete',
                  value: GoalStatus.incomplete,
                ),
              ],
              value: _filters.status,
              onChange: (status) =>
                  setState(() => _filters = _filters.copyWith(status: status)),
            ),
            // ── The two clocks ──
            const SizedBox(height: AppSpacing.lg),
            const SectionDivider('TARGET DATE'),
            const SizedBox(height: AppSpacing.md),
            _rangeRow(_GoalDate.target),
            const SizedBox(height: AppSpacing.lg),
            const SectionDivider('COMPLETED DATE'),
            const SizedBox(height: AppSpacing.md),
            _rangeRow(_GoalDate.completed),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Clear',
                    disabled: !_filters.isActive,
                    onPressed: () =>
                        setState(() => _filters = const GoalFilters()),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: GlassButton(
                    label: 'Done',
                    solid: true,
                    onPressed: () => Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pop(_filters),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Nothing here — or nothing matching the current search/filter.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppFonts.ui(
            fontSize: AppTextStyles.md,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          body,
          textAlign: TextAlign.center,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            color: AppColors.inkSecondary,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}
