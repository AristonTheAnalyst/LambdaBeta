import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/friendly_error.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../programs/model/program_achievements.dart';

const _uuid = Uuid();

class GoalsState {
  const GoalsState({
    this.isLoading = false,
    this.error,
    this.goals = const [],
    this.outcomes = const {},
    this.exerciseDetailMap = const {},
    this.variations = const [],
    this.pastSets = const [],
  });

  final bool isLoading;
  final String? error;

  /// Every goal the user has, in creation order — the repository's order,
  /// which is the order the library reads in.
  final List<Goal> goals;

  /// How each goal stands over the whole of the user's history, keyed by
  /// `goalId`. Keyed rather than positional because a list of rows and a list
  /// of verdicts are two orders that can drift.
  final Map<String, GoalAchievement> outcomes;

  /// Names, so a goal can read as its exercise — the same live-first rule
  /// every other surface applies.
  final Map<String, ExerciseDetail> exerciseDetailMap;
  final List<CustomVariation> variations;

  /// The timeline the lifetime outcomes were derived from. Kept because the
  /// goal sheet's add-target picker and the list's outcomes are two readings
  /// of one load.
  final List<PastSetRow> pastSets;

  GoalsState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    List<Goal>? goals,
    Map<String, GoalAchievement>? outcomes,
    Map<String, ExerciseDetail>? exerciseDetailMap,
    List<CustomVariation>? variations,
    List<PastSetRow>? pastSets,
  }) => GoalsState(
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : error ?? this.error,
    goals: goals ?? this.goals,
    outcomes: outcomes ?? this.outcomes,
    exerciseDetailMap: exerciseDetailMap ?? this.exerciseDetailMap,
    variations: variations ?? this.variations,
    pastSets: pastSets ?? this.pastSets,
  );
}

/// The Goals tab's view model: the whole library of goals, and the two writes
/// a screen makes on it — add and delete.
///
/// Goals live by themselves (2026-10-08): nothing here is scoped to a program
/// or a run, and the standing a row shows is **lifetime** — "has any set ever
/// met it" — because that is the question a goal nobody is currently chasing
/// asks. The same window-scoped derivation answers the in-run question on the
/// review side; both go through `evaluateGoals`, so the two can never
/// disagree about what a set means.
class GoalsViewModel {
  GoalsViewModel({
    ProgramRepository? programRepository,
    ExerciseRepository? exerciseRepository,
    SessionRepository? sessionRepository,
    String? userId,
  }) : _programRepo = programRepository ?? ProgramRepository(),
       _exerciseRepo = exerciseRepository ?? ExerciseRepository(),
       _sessionRepo = sessionRepository ?? SessionRepository(),
       _userIdOverride = userId;

  final ProgramRepository _programRepo;
  final ExerciseRepository _exerciseRepo;
  final SessionRepository _sessionRepo;
  final String? _userIdOverride;

  final state = ValueNotifier(const GoalsState());
  bool _disposed = false;

  /// The signed-in user. Overridable because host tests cannot construct
  /// `Supabase.instance` at all.
  String get _userId =>
      _userIdOverride ?? Supabase.instance.client.auth.currentUser!.id;

  /// One pass over everything the tab reads. All-or-nothing: a half-loaded
  /// tab that claimed "no sets at this weight" off a failed timeline read
  /// would be worse than saying it could not load.
  Future<void> load() async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final options = await _programRepo.fetchGoalOptions(_userId);
      final goals = [for (final option in options) option.goal];
      final details = await _exerciseRepo.fetchExerciseDetailMap(_userId);
      final variations = await _exerciseRepo.fetchVariations(_userId);
      final sets = await _sessionRepo.loadPastSetsTimeline(_userId);
      if (_disposed) return;

      // Lifetime: from before any training to midnight past today. The
      // achievement vocabulary already speaks this way — Hit, Best, Not
      // attempted yet — so an open window is the only sensible reading for a
      // goal with no run around it.
      final outcomes = <String, GoalAchievement>{
        for (final outcome in evaluateGoals(
          goals: goals,
          sets: sets,
          from: DateTime.utc(1970),
          to: DateTime.now().add(const Duration(days: 1)),
        ))
          outcome.goal.goalId: outcome,
      };

      state.value = GoalsState(
        goals: goals,
        outcomes: outcomes,
        exerciseDetailMap: details,
        variations: variations,
        pastSets: sets,
      );
    } catch (_) {
      if (_disposed) return;
      state.value = state.value.copyWith(
        isLoading: false,
        error: 'Could not load your goals.',
      );
    }
  }

  /// The goal sheet's own read — a fresh timeline, so the history it shows is
  /// as of the tap rather than as of the tab's last load. The sheet owns the
  /// failure: a read that throws there is one error line, not a blank list.
  Future<List<PastSetRow>> loadPastSets() =>
      _sessionRepo.loadPastSetsTimeline(_userId);

  /// Adds an exercise-target goal.
  ///
  /// Unattached (2026-10-08): the goal carries no program or block — the scope
  /// columns are dormant, and every goal added here is the user's own. A goal
  /// can be created with no run active; a target is a thing to chase, and
  /// nothing about an attempt at it decides whether it can exist.
  ///
  /// True when the row was written. The add sheet keeps its target up on a
  /// false so a failed write is not also a lost form (2026-10-19).
  Future<bool> addGoal({
    required String exerciseId,
    required String exerciseName,
    String? variationId,
    num? targetWeight,
    int? targetReps,
    String? description,
    DateTime? targetDate,
  }) async {
    // The add form's notes are the goal's description — blank is no notes,
    // never an empty string (the same normalization the in-place edit applies).
    final notes = description?.trim();
    final goal = Goal(
      goalId: _uuid.v4(),
      userId: _userId,
      // The name is captured as the label's fallback: a goal outlives the
      // exercise it names, and a deleted exercise must not leave it blank.
      text: exerciseName,
      description: (notes?.isEmpty ?? true) ? null : notes,
      exerciseId: exerciseId,
      variationId: variationId,
      targetWeight: targetWeight,
      targetReps: targetReps,
      targetDate: targetDate == null ? null : dateOnly(targetDate),
    );
    try {
      await _programRepo.createGoal(_userId, goal);
      // A full reload rather than a local append: the new goal has no verdict
      // yet intact, and its outcome has to be derived against the timeline
      // like every other row's.
      await load();
      return true;
    } catch (e) {
      if (_disposed) return false;
      state.value = state.value.copyWith(error: friendlyError(e));
      return false;
    }
  }

  Future<void> deleteGoal(String goalId) async {
    try {
      await _programRepo.deleteGoal(goalId);
      if (_disposed) return;
      state.value = state.value.copyWith(
        clearError: true,
        goals: [
          for (final g in state.value.goals)
            if (g.goalId != goalId) g,
        ],
        outcomes: {
          for (final e in state.value.outcomes.entries)
            if (e.key != goalId) e.key: e.value,
        },
      );
    } catch (e) {
      if (_disposed) return;
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  /// Rewrites a goal from the focused sheet's form — the exercise, variation,
  /// target, notes and deadline together (2026-10-19).
  ///
  /// Mirrors the row the repository read back (adjustment history included) and
  /// re-derives that goal's standing: the target may have moved, and the
  /// list's verdict is a reading of the numbers. Only the edited row is
  /// re-derived — the rest of the load is not affected by one goal's target.
  ///
  /// Rethrows: the write belongs to the sheet that asked for it, which keeps
  /// the form standing and says so, not to a state error somewhere else.
  /// Null = the goal no longer exists; state is left alone.
  Future<Goal?> updateGoal(
    String goalId, {
    required String? exerciseId,
    String? exerciseName,
    String? variationId,
    num? targetWeight,
    int? targetReps,
    String? description,
    DateTime? targetDate,
  }) async {
    final updated = await _programRepo.updateGoal(
      goalId,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      variationId: variationId,
      targetWeight: targetWeight,
      targetReps: targetReps,
      description: description,
      targetDate: targetDate,
    );
    if (_disposed || updated == null) return updated;

    final current = state.value;
    final outcomes = Map<String, GoalAchievement>.of(current.outcomes);
    // Lifetime, the same window the load derives every other row's standing
    // over — one rule, so an edited row cannot disagree with the list.
    final derived = evaluateGoals(
      goals: [updated],
      sets: current.pastSets,
      from: DateTime.utc(1970),
      to: DateTime.now().add(const Duration(days: 1)),
    );
    if (derived.isEmpty) {
      outcomes.remove(goalId);
    } else {
      outcomes[goalId] = derived.first;
    }

    state.value = current.copyWith(
      goals: [
        for (final g in current.goals)
          if (g.goalId == goalId) updated else g,
      ],
      outcomes: outcomes,
    );
    return updated;
  }

  void dispose() {
    _disposed = true;
    state.dispose();
  }
}
