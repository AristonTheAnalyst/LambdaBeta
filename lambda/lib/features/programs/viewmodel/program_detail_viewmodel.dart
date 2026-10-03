import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/models/planned_session_program.dart';
import '../../../data/models/program.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/program_block.dart';
import '../../../data/models/program_history.dart';
import '../../../data/models/program_progress.dart';
import '../../../data/models/program_revision.dart';
import '../../../data/models/program_run.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/planned_session_repository.dart';
import '../../../data/repositories/program_run_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../model/achievements_derivation.dart';
import '../model/program_achievements.dart';
import '../model/block_grouping.dart';
import 'workout_editor_viewmodel.dart';

/// The program screen's state: the program itself, its workouts, its blocks,
/// its goals, and what it is waiting on.
///
/// The workout *editor* has its own state — [WorkoutEditorViewModel] — because
/// it is a screen of its own, and one that opens with or without a program
/// behind it. What stays here is what a program is regardless of which of its
/// workouts happens to be open.
class ProgramDetailState {
  const ProgramDetailState({
    this.isLoading = false,
    this.isSaving = false,
    this.saveSuccess = false,
    this.error,
    this.program,
    this.plannedWorkouts = const [],
    this.programLinks = const [],
    this.blocks = const [],
    this.exerciseDetailMap = const {},
    this.isCurrent = false,
    this.anotherProgramIsCurrent = false,
    this.settingCurrent = false,
    this.activeRun,
    this.currentProgress,
    // Program field drafts
    this.nameDraft = '',
    this.descriptionDraft = '',
    this.allVariations = const [],
    // Goals
    this.programGoals = const [],
    this.goalOutcomes = const {},
    this.goalsLoading = false,
    this.due,
  });

  final bool isLoading;
  final bool isSaving;
  final bool saveSuccess;
  final String? error;
  final Program? program;
  final List<PlannedSession> plannedWorkouts;

  /// The program's join rows — day_of_week / sequence_order / week_offset
  /// live here per (program, planned session) pair.
  final List<PlannedSessionProgram> programLinks;
  final Map<String, ExerciseDetail> exerciseDetailMap;

  /// The program's active blocks, in `block_order`. Empty = a blockless
  /// program, which renders as one flat list exactly as it always has.
  final List<ProgramBlock> blocks;
  final bool isCurrent;

  /// Whether some *other* program is the current one.
  ///
  /// Distinct from `!isCurrent`, which is also true when nothing is running at
  /// all — and beginning a run is only worth warning about in the first case.
  /// The block-start prompt lands here with nothing running, so without this
  /// the common path would be the one that says "this resets progress on any
  /// currently active program" to a user who has none.
  final bool anotherProgramIsCurrent;
  final bool settingCurrent;

  /// The active run for this program (when it's the current program) — carries
  /// the run's progression mode and duration config, editable while running.
  final ProgramRun? activeRun;

  /// Progress of the active run (null unless this program is current).
  final ProgramProgress? currentProgress;

  final String nameDraft;
  final String descriptionDraft;

  /// The exercise/variation catalog, for the goals panel's target picker. The
  /// workout editor keeps a copy of its own rather than reaching for this one
  /// — see [WorkoutEditorState].
  final List<CustomVariation> allVariations;

  /// Every goal the program owns, at both levels — the program's own and each
  /// block's. Listed whether or not a run is active, because a goal is part of
  /// what the program is: it is authored before the first run and still there
  /// between runs. Which of them are being chased right now is answered by
  /// [Goal.appliesDuring] against the active run's block, and which of them
  /// have an outcome by [goalOutcomes].
  final List<Goal> programGoals;

  /// How each goal currently in force is going, keyed by goal id.
  ///
  /// Only the in-force ones appear: a block goal of a block that is not running
  /// is not failed, it is simply not being chased, and an absent entry says
  /// exactly that. Keyed rather than positional so a reload that reorders or
  /// shortens the list cannot paint one goal's outcome onto another. Empty when
  /// nothing is running — with no run there is no window, and therefore nothing
  /// achieved. The outcome is derived (see [ProgramAchievements]) until the run
  /// closes, when it is frozen into the close review.
  final Map<String, GoalAchievement> goalOutcomes;

  final bool goalsLoading;

  /// Something this program is waiting on — a review that has come due, or a
  /// run that has finished but is still marked current. Only ever the item for
  /// THIS program: the detail screen shows one program, and a prompt about
  /// another one belongs on the library card that names it.
  final DueItem? due;

  /// True when the program name or description has been edited in the form
  /// but not yet persisted — used by [UnsavedChangesGuard] to warn on back.
  bool get hasUnsavedProgramFields {
    if (program == null) return false;
    return nameDraft.trim() != (program!.name) ||
        descriptionDraft.trim() != (program!.description ?? '');
  }

  ProgramDetailState copyWith({
    bool? isLoading,
    bool? isSaving,
    bool? saveSuccess,
    String? error,
    bool clearError = false,
    Program? program,
    List<PlannedSession>? plannedWorkouts,
    List<PlannedSessionProgram>? programLinks,
    Map<String, ExerciseDetail>? exerciseDetailMap,
    List<ProgramBlock>? blocks,
    bool? isCurrent,
    bool? anotherProgramIsCurrent,
    bool? settingCurrent,
    ProgramRun? activeRun,
    ProgramProgress? currentProgress,
    String? nameDraft,
    String? descriptionDraft,
    List<CustomVariation>? allVariations,
    List<Goal>? programGoals,
    Map<String, GoalAchievement>? goalOutcomes,
    bool? goalsLoading,
    DueItem? due,
    bool clearDue = false,
  }) => ProgramDetailState(
    isLoading: isLoading ?? this.isLoading,
    isSaving: isSaving ?? this.isSaving,
    saveSuccess: saveSuccess ?? false,
    error: clearError ? null : error ?? this.error,
    program: program ?? this.program,
    plannedWorkouts: plannedWorkouts ?? this.plannedWorkouts,
    programLinks: programLinks ?? this.programLinks,
    exerciseDetailMap: exerciseDetailMap ?? this.exerciseDetailMap,
    blocks: blocks ?? this.blocks,
    isCurrent: isCurrent ?? this.isCurrent,
    anotherProgramIsCurrent:
        anotherProgramIsCurrent ?? this.anotherProgramIsCurrent,
    settingCurrent: settingCurrent ?? this.settingCurrent,
    activeRun: activeRun ?? this.activeRun,
    currentProgress: currentProgress ?? this.currentProgress,
    nameDraft: nameDraft ?? this.nameDraft,
    descriptionDraft: descriptionDraft ?? this.descriptionDraft,
    allVariations: allVariations ?? this.allVariations,
    programGoals: programGoals ?? this.programGoals,
    goalOutcomes: goalOutcomes ?? this.goalOutcomes,
    goalsLoading: goalsLoading ?? this.goalsLoading,
    due: clearDue ? null : (due ?? this.due),
  );
}

/// The program screen: the program, its workouts, its blocks, its goals, its
/// runs, and what it is waiting on.
///
/// The workout editor is a separate view model — [editor] — which this one
/// hosts. The editor owns everything that serves `PlanSessionScreen` and
/// reaches back through [WorkoutEditorHost] for the program context it cannot
/// know on its own; the split follows the seam the state already had, so the
/// two share no fields.
class ProgramDetailViewModel implements WorkoutEditorHost {
  ProgramDetailViewModel({
    ProgramRepository? repo,
    ProgramRunRepository? runRepo,
    ExerciseRepository? exerciseRepo,
    LessonRepository? lessonRepo,
    SessionRepository? workoutRepo,
    PlannedSessionRepository? workoutPlanRepo,
    ProgramHistoryRepository? historyRepo,
    AchievementsDerivation? achievementsDerivation,
  }) : _repo = repo ?? ProgramRepository(),
       _runRepo = runRepo ?? ProgramRunRepository(),
       _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
       _plannedSessionRepo = workoutPlanRepo ?? PlannedSessionRepository(),
       _historyRepo = historyRepo ?? ProgramHistoryRepository(),
       _derivation = achievementsDerivation ?? AchievementsDerivation() {
    // Built here rather than in the initializer list: the editor is handed
    // `this` as its host, and `this` does not exist until the body.
    editor = WorkoutEditorViewModel(
      host: this,
      exerciseRepo: exerciseRepo,
      lessonRepo: lessonRepo,
      workoutRepo: workoutRepo,
      workoutPlanRepo: workoutPlanRepo,
    );
  }

  /// The workout editor this screen pushes. Held rather than created at the
  /// push site so the two screens read one instance of what the other changed.
  late final WorkoutEditorViewModel editor;

  final ProgramRepository _repo;
  final ProgramRunRepository _runRepo;
  final _uuid = const Uuid();
  final ExerciseRepository _exerciseRepo;
  final PlannedSessionRepository _plannedSessionRepo;
  final ProgramHistoryRepository _historyRepo;
  final AchievementsDerivation _derivation;

  final state = ValueNotifier(const ProgramDetailState());

  // ── WorkoutEditorHost ────────────────────────────────────────────────────

  @override
  String? get programId => state.value.program?.programId;

  List<PlannedSessionProgram> get programLinks => state.value.programLinks;

  @override
  int get workoutCount => state.value.plannedWorkouts.length;

  /// The editor changed the program's contents, so re-read everything that
  /// depends on them — a superset of the old workouts-only refresh, because a
  /// grouping shift is a contents change too.
  @override
  Future<void> onContentsChanged() => _reloadContents();

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  /// Creates a new program and returns its id, ready for [load].
  ///
  /// The wizard names it here rather than renaming a placeholder afterwards:
  /// the name is the one thing the user typed before this call, so passing it
  /// through is what makes it stick. Goals are added later, from the detail
  /// screen. Progression mode is NOT a program property — it's chosen when a
  /// run starts.
  Future<String?> createNewProgram({String? name, String? description}) async {
    try {
      final created = await _repo.createProgram(
        _userId,
        name: name,
        description: description,
      );
      return created.programId;
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
      return null;
    }
  }

  /// Adds an exercise-target goal (weight × reps for a specific exercise).
  ///
  /// [blockId] names the scope: null is a program-level goal, chased through
  /// every run; set is that phase's own. A goal can be created with no run
  /// active — planning a program's targets before starting it is the natural
  /// order, and a scope does not need an attempt at it to exist.
  Future<void> addGoal({
    required String exerciseId,
    required String exerciseName,
    String? variationId,
    num? targetWeight,
    int? targetReps,
    String? blockId,
  }) async {
    final programId = state.value.program?.programId;
    if (programId == null) return;
    final goal = Goal(
      goalId: Uuid().v4(),
      userId: _userId,
      programId: programId,
      blockId: blockId,
      // NOT linked to the run it happens to be created under: the scope is
      // what the goal belongs to, and it outlives every attempt at it.
      text: exerciseName,
      exerciseId: exerciseId,
      variationId: variationId,
      targetWeight: targetWeight,
      targetReps: targetReps,
    );
    try {
      await _repo.createGoal(_userId, goal);
      await _loadGoals();
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> deleteGoal(String goalId) async {
    try {
      await _repo.deleteGoal(goalId);
      state.value = state.value.copyWith(
        programGoals: state.value.programGoals
            .where((g) => g.goalId != goalId)
            .toList(),
        goalOutcomes: {
          for (final e in state.value.goalOutcomes.entries)
            if (e.key != goalId) e.key: e.value,
        },
      );
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  /// Loads the program's goals, and how the ones in force are going.
  ///
  /// [ProgramDetailState.programGoals] is **every** goal the program owns, not
  /// just the ones running: a goal is part of what the program is, authored
  /// before the first run and still there between runs. Only the in-force ones
  /// get an entry in [ProgramDetailState.goalOutcomes] — a block goal of a
  /// block that is not running has no verdict, which is not the same as having
  /// missed one, and the keyed map says so by simply having no entry.
  ///
  /// The outcome is the same derivation the review sheet and the close record
  /// use, narrowed to this run's window — one interpretation of what a goal
  /// achieved, so the panel and the archive cannot disagree. It costs a
  /// past-sets read, which is why it is skipped entirely when there is nothing
  /// to report on: no run, or no goals in force.
  Future<void> _loadGoals() async {
    final programId = state.value.program?.programId;
    if (programId == null) return;
    final run = state.value.activeRun;
    state.value = state.value.copyWith(goalsLoading: true);
    try {
      final all = await _repo
          .fetchGoals(_userId, programId: programId)
          .timeout(const Duration(seconds: 3));
      final inForce = all
          .where((g) => g.appliesDuring(run?.blockId))
          .toList(growable: false);

      var outcomes = const <String, GoalAchievement>{};
      if (run != null && inForce.isNotEmpty) {
        final from = await _historyRepo.checkpointFor(programId);
        final achievements = await _derivation.derive(
          userId: _userId,
          from: from,
          programId: programId,
          blockId: run.blockId,
          runId: run.programRunId,
        );
        outcomes = {
          for (final g in achievements.goals) g.goal.goalId: g,
        };
      }

      state.value = state.value.copyWith(
        programGoals: all,
        goalOutcomes: outcomes,
        goalsLoading: false,
      );
    } catch (_) {
      state.value = state.value.copyWith(goalsLoading: false);
    }
  }

  /// What this program is waiting on, if anything.
  ///
  /// The repo's due query is user-wide (a review can be due on a program the
  /// user is not looking at), so the result is narrowed to the program on
  /// screen. Failing quietly is deliberate: a prompt is an addition to the
  /// screen, and a due check that throws must not blank one that loaded fine.
  Future<void> _loadDueItems() async {
    final programId = state.value.program?.programId;
    if (programId == null) return;
    try {
      final items = await _historyRepo
          .fetchDueItems(_userId)
          .timeout(const Duration(seconds: 3));
      DueItem? mine;
      for (final item in items) {
        if (item.programId == programId) {
          mine = item;
          break;
        }
      }
      if (_disposed) return;
      state.value = mine == null
          ? state.value.copyWith(clearDue: true)
          : state.value.copyWith(due: mine);
    } catch (_) {}
  }

  Future<void> load(String programId) async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      // Each fetch is individually timed out so a stuck PowerSync checkpoint
      // (which can block ALL local DB ops, reads included) doesn't freeze the
      // screen forever.
      final results = await Future.wait([
        _repo.fetchProgram(programId).timeout(const Duration(seconds: 4)),
        _plannedSessionRepo
            .fetchPlannedSessions(_userId, programId: programId)
            .timeout(const Duration(seconds: 4)),
        _plannedSessionRepo
            .fetchProgramLinks(programId)
            .timeout(const Duration(seconds: 4)),
        _exerciseRepo
            .fetchExerciseDetailMap(_userId)
            .timeout(const Duration(seconds: 4)),
        _runRepo.getCurrentRun(_userId).timeout(const Duration(seconds: 4)),
        _exerciseRepo
            .fetchVariations(_userId)
            .timeout(const Duration(seconds: 4)),
        _repo.fetchBlocks(programId).timeout(const Duration(seconds: 4)),
      ]);
      final program = results[0] as Program?;
      final currentRun = results[4] as ProgramRun?;
      var isCurrent = currentRun != null && currentRun.programId == programId;
      ProgramProgress? progress;
      if (isCurrent) {
        try {
          progress = await _runRepo.getProgress(_userId);
        } catch (_) {}
      }

      // Nothing ends the run here, and nothing should.
      //
      // It used to: a run that had met its target was closed out the moment a
      // screen noticed, which meant a block ended because someone opened it.
      // A block now ends when the user says it does — `_loadDueItems` puts the
      // question on the banner (`kDueRunFinished`), and the three paths that
      // answer it are all deliberate: the banner's action, "End program" in the
      // header, and a new run superseding the old one. Every closing revision
      // therefore has an honest reason attached, which is what the history
      // screen reads back.

      state.value = state.value.copyWith(
        isLoading: false,
        program: program,
        plannedWorkouts: (results[1] as List<PlannedSession>),
        programLinks: results[2] as List<PlannedSessionProgram>,
        exerciseDetailMap: results[3] as Map<String, ExerciseDetail>,
        blocks: results[6] as List<ProgramBlock>,
        nameDraft: program?.name ?? '',
        descriptionDraft: program?.description ?? '',
        isCurrent: isCurrent,
        anotherProgramIsCurrent: currentRun != null && !isCurrent,
        activeRun: isCurrent ? currentRun : null,
        currentProgress: progress,
        allVariations: results[5] as List<CustomVariation>,
      );
      // Goals and the due prompt load independently — neither is critical for
      // rendering, and a slow one must not blank the screen.
      _loadGoals();
      _loadDueItems();
    } catch (e) {
      state.value = state.value.copyWith(isLoading: false, error: e.toString());
    }
  }

  // ── Program fields ───────────────────────────────────────────────────────

  void setNameDraft(String v) =>
      state.value = state.value.copyWith(nameDraft: v);
  void setDescriptionDraft(String v) =>
      state.value = state.value.copyWith(descriptionDraft: v);

  Future<void> saveProgramDetails() async {
    final s = state.value;
    if (s.program == null || s.nameDraft.trim().isEmpty) return;
    state.value = s.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.updateProgram(
        s.program!.programId,
        name: s.nameDraft.trim(),
        description: s.descriptionDraft.trim(),
        userId: _userId,
      );
      final updated = await _repo.fetchProgram(s.program!.programId);
      state.value = state.value.copyWith(
        isSaving: false,
        program: updated,
        saveSuccess: true,
      );
      // Auto-dismiss the success banner after a short delay.
      Future.delayed(const Duration(seconds: 2), () {
        state.value = state.value.copyWith(saveSuccess: false);
      });
    } catch (e) {
      state.value = state.value.copyWith(isSaving: false, error: e.toString());
    }
  }

  /// Starts a run of this program. The mode lives on the run, not the
  /// program.
  ///
  /// The UI only starts order runs — day scheduling is retired, so nothing
  /// assigns sessions to weekdays and [progressionMode] keeps its default. The
  /// parameters stay because the column, the model and the repository still
  /// carry a frequency run's shape for when scheduling comes back.
  Future<void> setAsCurrent({
    String progressionMode = 'order',
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
    String? blockId,
  }) async {
    final s = state.value;
    if (s.program == null || _disposed) return;

    // Read the run being replaced BEFORE starting: `startProgramRun` clears
    // `is_current` server-side, and afterwards there is nothing left to name.
    // It is read here rather than taken from state because the previous run can
    // belong to a different program — this screen only ever shows one.
    ProgramRun? previous;
    try {
      previous = await _runRepo.getCurrentRun(_userId);
    } catch (_) {}

    // Optimistic: build the run locally and flip state immediately so the UI
    // never blocks on the network.  The server write happens in the background
    // (bounded by short timeouts inside the repository) and the run is picked
    // up by PowerSync on the next successful sync.
    final run = ProgramRun(
      programRunId: _uuid.v4(),
      programId: s.program!.programId,
      userId: _userId,
      startedDate: DateTime.now().toUtc(),
      isCurrent: true,
      progressionMode: progressionMode,
      targetSessions: targetSessions,
      targetWeeks: targetWeeks,
      endDate: endDate?.toUtc(),
      blockId: blockId,
    );
    state.value = s.copyWith(
      settingCurrent: false,
      isCurrent: true,
      // Whatever was running is about to be closed by `startProgramRun`, so
      // the warning that names it stops applying the moment this succeeds.
      anotherProgramIsCurrent: false,
      activeRun: run,
      clearError: true,
    );
    try {
      // Write through PowerSync (queued offline, synced later). Await so a
      // real failure surfaces instead of leaving optimistic state that a
      // restart would not reproduce.
      await _runRepo.startProgramRun(
        _userId,
        s.program!.programId,
        progressionMode: progressionMode,
        targetSessions: targetSessions,
        targetWeeks: targetWeeks,
        endDate: endDate,
        blockId: blockId,
      );
      // Load progress immediately — the detail screen's progress row would
      // otherwise stay hidden until the next full reload.
      final progress = await _runRepo.getProgress(_userId);
      state.value = state.value.copyWith(currentProgress: progress);
      // The replaced run gets its final checkpoint. It is over — starting a
      // run ended it — and the plan's rule is that a revision is cut just
      // before a program stops running. Its own program's history, not this
      // one's, which is why the run carries the program id.
      if (previous != null) await _closeRun(previous);
    } catch (e) {
      // The write failed — roll the optimistic UI back so the program is not
      // left marked "current" when nothing was actually persisted.
      state.value = state.value.copyWith(
        isCurrent: false,
        activeRun: null,
        error: e.toString(),
      );
    }
    _loadGoals();
    _loadDueItems();
  }

  /// Ends the current run for this program, marking it as no longer active.
  Future<void> endCurrentRun() async {
    final s = state.value;
    final run = s.activeRun;
    // Optimistic: clear immediately so the UI never blocks.
    state.value = s.copyWith(
      isCurrent: false,
      anotherProgramIsCurrent: false,
      activeRun: null,
      clearError: true,
    );
    try {
      await _runRepo.endCurrentRun(_userId);
      // The checkpoint is cut AFTER the run is over, so the revision records a
      // finished run rather than one that is still going.
      if (run != null) await _closeRun(run);
      // Ending a run settles what was waiting on it: the "program finished"
      // prompt is derived from the run and disappears with it.
      await _loadDueItems();
    } catch (e) {
      // Roll back on failure.
      state.value = state.value.copyWith(
        isCurrent: s.isCurrent,
        activeRun: s.activeRun,
        error: e.toString(),
      );
    }
  }

  /// Cuts a run's final revision and freezes what it produced.
  ///
  /// The achievements are derived ONCE, here, and the UI reads the same
  /// document the record keeps — a panel that says one thing and an archive
  /// that says another is the failure this avoids.
  ///
  /// Failures are swallowed: the run is over either way, and an error that
  /// left it looking active would be worse than a missing checkpoint.
  Future<void> _closeRun(ProgramRun run) async {
    try {
      final from = await _historyRepo.checkpointFor(run.programId);
      final achievements = await _derivation.derive(
        userId: _userId,
        from: from,
        programId: run.programId,
        // The block that was running, so the frozen record names the goals
        // that were actually in force for it.
        blockId: run.blockId,
        runId: run.programRunId,
      );
      await _historyRepo.closeRun(
        userId: _userId,
        programId: run.programId,
        runId: run.programRunId,
        // A block ending is not the program ending: the record says which
        // stopped running, which is what makes the history readable later.
        blockId: run.blockId,
        reason: run.blockId == null ? kRevisionProgramEnd : kRevisionBlockEnd,
        achievementsJson: achievements.encode(),
      );
    } catch (_) {}
  }

  /// Updates the active run's config (mutable while running) — progression
  /// mode and/or the duration targets.
  Future<void> updateRunConfig({
    String? progressionMode,
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
    bool clearSessions = false,
    bool clearWeeks = false,
    bool clearEndDate = false,
  }) async {
    final run = state.value.activeRun;
    if (run == null) return;
    try {
      await _runRepo.updateRunConfig(
        run.programRunId,
        progressionMode: progressionMode,
        targetSessions: targetSessions,
        targetWeeks: targetWeeks,
        endDate: endDate,
        clearSessions: clearSessions,
        clearWeeks: clearWeeks,
        clearEndDate: clearEndDate,
      );
      // Rebuild the run so the duration label and the edit dialog show the
      // new config without a full reload.
      final updated = ProgramRun(
        programRunId: run.programRunId,
        programId: run.programId,
        userId: run.userId,
        startedDate: run.startedDate,
        isCurrent: run.isCurrent,
        endedDate: run.endedDate,
        progressionMode: progressionMode ?? run.progressionMode,
        targetSessions: clearSessions
            ? null
            : (targetSessions ?? run.targetSessions),
        targetWeeks: clearWeeks ? null : (targetWeeks ?? run.targetWeeks),
        endDate: clearEndDate ? null : (endDate ?? run.endDate),
      );
      state.value = state.value.copyWith(activeRun: updated, clearError: true);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  /// Imports a library workout into the current program as a private copy.
  /// Returns the new program-local workout.
  Future<PlannedSession?> copyWorkoutIntoProgram(String sessionId) async {
    final programId = state.value.program?.programId;
    if (programId == null) return null;
    try {
      final newId = await _repo.importWorkoutIntoProgram(
        _userId,
        programId: programId,
        sourceSessionId: sessionId,
        sequenceOrder: state.value.plannedWorkouts.length + 1,
      );
      final wps = await _plannedSessionRepo.fetchPlannedSessions(
        _userId,
        programId: programId,
      );
      state.value = state.value.copyWith(plannedWorkouts: wps);
      return wps.where((w) => w.sessionId == newId).firstOrNull;
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
      return null;
    }
  }

  /// Returns the new workout's id, so a caller that wants to file the copy
  /// somewhere — a block, say — does not have to guess which row appeared.
  Future<String?> duplicatePlannedSession(PlannedSession source) async {
    final programId = state.value.program?.programId;
    if (programId == null) return null;
    // Duplicate via the planned repo, which copies groups + sets and — when
    // the source link is provided — links the copy into the same program
    // right after the source slot.
    final sourceLink = state.value.programLinks.firstWhereOrNull(
      (l) => l.plannedSessionId == source.sessionId,
    );
    final newId = await _plannedSessionRepo.duplicatePlannedSession(
      _userId,
      source,
      sourceLink: sourceLink,
    );
    await _reloadContents();
    return newId;
  }

  /// Removes a planned workout from the current program (from the detail
  /// list). The template itself survives — only the join row goes, so the
  /// session becomes standalone (usable from the workout library).
  Future<void> removePlannedSession(PlannedSession w) async {
    final link = state.value.programLinks.firstWhereOrNull(
      (l) => l.plannedSessionId == w.sessionId,
    );
    if (link != null) {
      await _plannedSessionRepo.deleteProgramLink(
        link.plannedSessionProgramId,
      );
    }
    final updated = state.value.plannedWorkouts
        .where((pw) => pw.sessionId != w.sessionId)
        .toList();
    state.value = state.value.copyWith(plannedWorkouts: updated);
  }

  Future<void> reorderWorkouts(
    List<PlannedSession> reordered,
    List<String> ids,
  ) async {
    // In-memory order updates immediately — the list IS the order.
    state.value = state.value.copyWith(plannedWorkouts: reordered);
    // Persist sequence_order on each join row to match the new order.
    for (var i = 0; i < ids.length; i++) {
      final link = state.value.programLinks.firstWhereOrNull(
        (l) => l.plannedSessionId == ids[i],
      );
      if (link == null) continue;
      await _plannedSessionRepo.updateProgramLink(
        link.plannedSessionProgramId,
        sequenceOrder: i + 1,
      );
    }
  }

  // ── Blocks ───────────────────────────────────────────────────────────────

  /// The program's workouts as ordered sections: one per block, then the
  /// unassigned ones. Pure — it joins ids, it does not re-read the database.
  List<ProgramBlockGroup> get blockGroups => groupWorkoutsByBlock(
    blocks: state.value.blocks,
    workouts: state.value.plannedWorkouts,
    links: state.value.programLinks,
  );

  Future<void> loadBlocks() async {
    final programId = state.value.program?.programId;
    if (programId == null) return;
    final blocks = await _repo.fetchBlocks(programId);
    state.value = state.value.copyWith(blocks: blocks);
  }

  /// Creates a block, appended to the program's order.
  ///
  /// Requires network — the repo writes it to Supabase first, so the block
  /// exists server-side before a membership or a run can reference it.
  Future<ProgramBlock?> createBlock({
    String? name,
    String? notes,
    int? targetWeeks,
    int? targetDays,
    int? targetSessions,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final programId = state.value.program?.programId;
    if (programId == null) return null;
    try {
      final block = await _repo.createProgramBlock(
        _userId,
        programId: programId,
        name: name,
        notes: notes,
        targetWeeks: targetWeeks,
        targetDays: targetDays,
        targetSessions: targetSessions,
        startDate: startDate,
        endDate: endDate,
      );
      state.value = state.value.copyWith(
        blocks: [...state.value.blocks, block],
        clearError: true,
      );
      return block;
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
      return null;
    }
  }

  Future<bool> updateBlock(
    String blockId, {
    String? name,
    String? notes,
    bool clearNotes = false,
    int? targetWeeks,
    int? targetDays,
    bool clearTargetDays = false,
    bool clearWeeks = false,
    int? targetSessions,
    bool clearSessions = false,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? endDate,
    bool clearEndDate = false,
  }) async {
    try {
      await _repo.updateBlock(
        blockId,
        name: name,
        notes: notes,
        clearNotes: clearNotes,
        targetWeeks: targetWeeks,
        targetDays: targetDays,
        clearTargetDays: clearTargetDays,
        clearWeeks: clearWeeks,
        targetSessions: targetSessions,
        clearSessions: clearSessions,
        startDate: startDate,
        clearStartDate: clearStartDate,
        endDate: endDate,
        clearEndDate: clearEndDate,
      );
      await loadBlocks();
      return true;
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
      return false;
    }
  }

  /// In-memory order updates immediately — the list IS the order — then each
  /// block's `block_order` is rewritten to match.
  Future<void> reorderBlocks(List<ProgramBlock> reordered) async {
    final programId = state.value.program?.programId;
    if (programId == null) return;
    state.value = state.value.copyWith(blocks: reordered);
    await _repo.reorderBlocks(
      programId,
      reordered.map((b) => b.blockId).toList(),
    );
  }

  /// Archives a block. Its workouts stay in the program, unassigned — a block
  /// is a grouping, not a container.
  Future<void> archiveBlock(String blockId) async {
    await _repo.archiveBlock(blockId);
    await _reloadContents();
  }

  Future<void> reactivateBlock(String blockId) async {
    await _repo.reactivateBlock(blockId);
    await loadBlocks();
  }

  /// Copies a block and its workouts. The copies are fresh rows, so editing
  /// one block never changes the other.
  Future<String?> duplicateBlock(String blockId) async {
    try {
      final newId = await _repo.duplicateBlock(_userId, blockId);
      await _reloadContents();
      return newId;
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
      return null;
    }
  }

  /// Moves a workout into a block, or out of every block when [blockId] is
  /// null. Membership lives on the join row, so this is one UPDATE.
  Future<void> assignWorkoutToBlock(String sessionId, String? blockId) async {
    final programId = state.value.program?.programId;
    if (programId == null) return;
    final link = state.value.programLinks.firstWhereOrNull(
      (l) => l.plannedSessionId == sessionId,
    );
    if (link == null) return;
    await _plannedSessionRepo.assignLinksToBlock(
      programId,
      [link.plannedSessionProgramId],
      blockId,
    );
    await _reloadContents();
  }

  /// Reorders the workouts of one block (or of the unassigned group), leaving
  /// every other workout where it is.
  ///
  /// `sequence_order` is program-global, so the block's members swap among the
  /// positions they already occupy rather than being renumbered from 1 — which
  /// is what keeps block membership from cascading a renumber through the
  /// workouts it doesn't touch.
  Future<void> reorderBlockWorkouts(
    String? blockId,
    List<String> orderedSessionIds,
  ) async {
    final s = state.value;
    final global = s.plannedWorkouts.map((w) => w.sessionId).toList();
    final slotIds = <String>{
      for (final group in blockGroups)
        if (group.block?.blockId == blockId)
          for (final w in group.workouts) w.sessionId,
    };
    final permuted = permuteWithinSlots(
      globalOrder: global,
      orderedSessionIds: orderedSessionIds,
      slotSessionIds: slotIds,
    );
    final byId = {for (final w in s.plannedWorkouts) w.sessionId: w};
    await reorderWorkouts(
      [for (final id in permuted) byId[id]!],
      permuted,
    );
  }

  /// Re-reads the workouts, join rows and blocks after a change that moves
  /// rows between them.
  Future<void> _reloadContents() async {
    final programId = state.value.program?.programId;
    if (programId == null) return;
    final results = await Future.wait([
      _plannedSessionRepo.fetchPlannedSessions(_userId, programId: programId),
      _plannedSessionRepo.fetchProgramLinks(programId),
      _repo.fetchBlocks(programId),
    ]);
    state.value = state.value.copyWith(
      plannedWorkouts: results[0] as List<PlannedSession>,
      programLinks: results[1] as List<PlannedSessionProgram>,
      blocks: results[2] as List<ProgramBlock>,
    );
  }

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    editor.dispose();
    state.dispose();
  }
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
