import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../data/models/block_sequence.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/models/planned_session_program.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_block.dart';
import '../../../data/models/program_history.dart';
import '../../../data/models/program_progress.dart';
import '../../../data/models/program_run.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/planned_session_repository.dart';
import '../../../data/repositories/program_run_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../model/achievements_derivation.dart';
import '../model/block_grouping.dart';
import '../model/program_run_lifecycle.dart';
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
    this.programRuns = const [],
    this.exerciseDetailMap = const {},
    this.isCurrent = false,
    this.anotherProgramIsCurrent = false,
    this.currentProgramName,
    this.settingCurrent = false,
    this.activeRun,
    this.currentProgress,
    this.pausedRun,
    this.pausedProgress,
    this.historyWarning,
    // Program field drafts
    this.nameDraft = '',
    this.descriptionDraft = '',
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

  /// The program's active blocks, in `block_order`. Empty on a simple program,
  /// and — a different fact with the same list — on a blocked one that has no
  /// blocks yet. `program.usesBlocks` is what tells those apart.
  final List<ProgramBlock> blocks;

  /// Every run this program has had, newest first.
  ///
  /// The history half of [blockSequence]: which blocks have been run and ended
  /// is a fact about runs, not about the blocks, so the block rows on their own
  /// cannot say where the program is in its sequence.
  final List<ProgramRun> programRuns;

  /// Where the program is in its block sequence — which block has been run,
  /// which one is next, and whether one is open right now.
  ///
  /// Derived on read rather than stored, like every other thing here that is a
  /// function of its inputs: the sequence is only ever `blocks` × `programRuns`,
  /// and caching it would be one more field to invalidate when either changes.
  BlockSequence get blockSequence =>
      BlockSequence(blocks: blocks, runs: programRuns);
  final bool isCurrent;

  /// Whether some *other* program is the current one.
  ///
  /// Distinct from `!isCurrent`, which is also true when nothing is running at
  /// all — and beginning a run is only worth warning about in the first case.
  /// The block-start prompt lands here with nothing running, so without this
  /// the common path would be the one that says "this resets progress on any
  /// currently active program" to a user who has none.
  final bool anotherProgramIsCurrent;

  /// The name of that other program, when there is one — so the begin sheet can
  /// say what it is about to pause instead of "another program".
  ///
  /// The copy is the philosophy: a warning that names what you are leaving
  /// reads as "this is kept, pick it back up", which is exactly what happens
  /// now. Null while nothing else is running, and also when the name could not
  /// be read — the warning falls back to generic wording either way.
  final String? currentProgramName;
  final bool settingCurrent;

  /// The active run for this program (when it's the current program) — carries
  /// the run's progression mode and duration config, editable while running.
  final ProgramRun? activeRun;

  /// Progress of the active run (null unless this program is current).
  final ProgramProgress? currentProgress;

  /// This program's open-but-not-current run — stepped away from, resumable.
  ///
  /// A third state beside "running" and "not running", and deliberately its
  /// own field rather than a relaxation of [activeRun]: `activeRun` means
  /// "this program is the one being run" everywhere it is read, and the bug
  /// that made every later write miss its row was exactly a field that meant
  /// two things. Only ever set when [isCurrent] is false.
  final ProgramRun? pausedRun;

  /// How far the paused run got, so coming back to a paused program shows what
  /// it did rather than starting the story at "Paused". Null when there is no
  /// paused run, or when its numbers cannot be read.
  final ProgramProgress? pausedProgress;

  /// A run action that succeeded but left something unwritten — currently,
  /// only a close record that could not be saved.
  ///
  /// Deliberately not [error]: the run *is* over, and rejecting the action
  /// would be a lie. But the loss is real and invisible otherwise, so it is
  /// shown until the next run action clears it.
  final String? historyWarning;

  final String nameDraft;
  final String descriptionDraft;

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
    List<ProgramRun>? programRuns,
    bool? isCurrent,
    bool? anotherProgramIsCurrent,
    String? currentProgramName,
    bool clearCurrentProgramName = false,
    bool? settingCurrent,
    ProgramRun? activeRun,
    bool clearActiveRun = false,
    ProgramProgress? currentProgress,
    bool clearCurrentProgress = false,
    ProgramRun? pausedRun,
    bool clearPausedRun = false,
    ProgramProgress? pausedProgress,
    bool clearPausedProgress = false,
    String? historyWarning,
    bool clearHistoryWarning = false,
    String? nameDraft,
    String? descriptionDraft,
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
    programRuns: programRuns ?? this.programRuns,
    isCurrent: isCurrent ?? this.isCurrent,
    anotherProgramIsCurrent:
        anotherProgramIsCurrent ?? this.anotherProgramIsCurrent,
    currentProgramName: clearCurrentProgramName
        ? null
        : (currentProgramName ?? this.currentProgramName),
    settingCurrent: settingCurrent ?? this.settingCurrent,
    // `activeRun: null` cannot mean "clear" through a `??` copyWith — the
    // explicit `clearActiveRun` is what a caller ending a run must pass, or the
    // ended run's data lingers as if it were still going.
    activeRun: clearActiveRun ? null : (activeRun ?? this.activeRun),
    currentProgress:
        clearCurrentProgress ? null : (currentProgress ?? this.currentProgress),
    pausedRun: clearPausedRun ? null : (pausedRun ?? this.pausedRun),
    pausedProgress:
        clearPausedProgress ? null : (pausedProgress ?? this.pausedProgress),
    historyWarning:
        clearHistoryWarning ? null : (historyWarning ?? this.historyWarning),
    nameDraft: nameDraft ?? this.nameDraft,
    descriptionDraft: descriptionDraft ?? this.descriptionDraft,
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
    String? userId,
  }) : _repo = repo ?? ProgramRepository(),
       _runRepo = runRepo ?? ProgramRunRepository(),
       _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
       _plannedSessionRepo = workoutPlanRepo ?? PlannedSessionRepository(),
       _historyRepo = historyRepo ?? ProgramHistoryRepository(),
       _derivation = achievementsDerivation ?? AchievementsDerivation(),
       _userIdOverride = userId {
    // Built here rather than in the initializer list: the lifecycle shares the
    // injected repos, and the editor is handed `this` as its host — `this` does
    // not exist until the body.
    _lifecycle = ProgramRunLifecycle(
      runRepo: _runRepo,
      historyRepo: _historyRepo,
      derivation: _derivation,
      // The close record resolves a block run's scope to its workout set, so
      // the lifecycle needs the same planned-session repository this screen
      // reads through — without it a host test's run close reaches the real
      // database.
      plannedSessionRepository: _plannedSessionRepo,
    );
    editor = WorkoutEditorViewModel(
      host: this,
      exerciseRepo: exerciseRepo,
      lessonRepo: lessonRepo,
      workoutRepo: workoutRepo,
      workoutPlanRepo: workoutPlanRepo,
      // The override travels with the repo overrides: a caller who had to name
      // the user because there is no Supabase to ask (see [_userId]) would
      // otherwise be handed an editor that asks it anyway.
      userId: userId,
    );
  }

  /// The workout editor this screen pushes. Held rather than created at the
  /// push site so the two screens read one instance of what the other changed.
  late final WorkoutEditorViewModel editor;

  final ProgramRepository _repo;
  final ProgramRunRepository _runRepo;
  final ExerciseRepository _exerciseRepo;
  final PlannedSessionRepository _plannedSessionRepo;
  final ProgramHistoryRepository _historyRepo;
  final AchievementsDerivation _derivation;
  final String? _userIdOverride;
  late final ProgramRunLifecycle _lifecycle;

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

  /// The signed-in user. Overridable because host tests cannot construct
  /// `Supabase.instance` at all.
  String get _userId =>
      _userIdOverride ?? Supabase.instance.client.auth.currentUser!.id;

  /// Creates a new program and returns its id, ready for [load].
  ///
  /// The wizard names it here rather than renaming a placeholder afterwards:
  /// the name is the one thing the user typed before this call, so passing it
  /// through is what makes it stick. Goals are added later, from the detail
  /// screen. Progression mode is NOT a program property — it's chosen when a
  /// run starts.
  ///
  /// [usesBlocks] is the shape chosen on the wizard's first step. It is written
  /// once here and never changed: whether a program is a list of workouts or a
  /// sequence of blocks decides its tabs, where its workouts are made, what its
  /// begin sheet offers and what a goal can be scoped to, and those surfaces
  /// cannot be half-switched after real workouts exist.
  Future<String?> createNewProgram({
    String? name,
    String? description,
    bool usesBlocks = false,
  }) async {
    try {
      final created = await _repo.createProgram(
        _userId,
        name: name,
        description: description,
        usesBlocks: usesBlocks,
      );
      return created.programId;
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
      return null;
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
        _repo.fetchBlocks(programId).timeout(const Duration(seconds: 4)),
        _runRepo
            .fetchPausedRun(_userId, programId: programId)
            .timeout(const Duration(seconds: 4)),
        // Every run this program has had — the other half of where it is in
        // its block sequence.
        _runRepo
            .fetchRunsForProgram(programId)
            .timeout(const Duration(seconds: 4)),
      ]);
      final program = results[0] as Program?;
      final currentRun = results[4] as ProgramRun?;
      final isCurrent = currentRun != null && currentRun.programId == programId;
      ProgramProgress? progress;
      if (isCurrent) {
        try {
          progress = await _runRepo.getProgress(_userId);
        } catch (_) {}
      }

      // Name the program that would be paused by beginning this one. Read on
      // demand rather than held in a list: exactly one program can be current,
      // and this is the only screen that has to name it.
      String? currentProgramName;
      if (currentRun != null && !isCurrent) {
        try {
          currentProgramName = (await _repo
                  .fetchProgram(currentRun.programId)
                  .timeout(const Duration(seconds: 4)))
              ?.name;
        } catch (_) {
          // Only the warning's wording depends on this.
        }
      }

      // This program's paused run, when it is not the one being run. A program
      // cannot be both — pausing is what stepping away does — so the two are
      // read together and only one of them is ever set.
      final pausedRun =
          isCurrent ? null : results[6] as ProgramRun?;
      ProgramProgress? pausedProgress;
      if (pausedRun != null) {
        try {
          pausedProgress = await _runRepo.progressFor(pausedRun);
        } catch (_) {
          // The paused row is what matters; its numbers are a bonus.
        }
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

      // The screen can be gone by now — every fetch above is awaited, and
      // backing out mid-load is one tap. Writing to the disposed notifier
      // throws on the fetch's own stack, where nothing catches it.
      if (_disposed) return;
      state.value = state.value.copyWith(
        isLoading: false,
        program: program,
        plannedWorkouts: (results[1] as List<PlannedSession>),
        programLinks: results[2] as List<PlannedSessionProgram>,
        exerciseDetailMap: results[3] as Map<String, ExerciseDetail>,
        blocks: results[5] as List<ProgramBlock>,
        programRuns: results[7] as List<ProgramRun>,
        nameDraft: program?.name ?? '',
        descriptionDraft: program?.description ?? '',
        isCurrent: isCurrent,
        anotherProgramIsCurrent: currentRun != null && !isCurrent,
        currentProgramName: currentProgramName,
        clearCurrentProgramName: currentProgramName == null,
        activeRun: isCurrent ? currentRun : null,
        clearActiveRun: !isCurrent,
        currentProgress: progress,
        clearCurrentProgress: progress == null,
        pausedRun: pausedRun,
        clearPausedRun: pausedRun == null,
        pausedProgress: pausedProgress,
        clearPausedProgress: pausedProgress == null,
      );
      // The due prompt loads independently — it is not critical for
      // rendering, and a slow read must not blank the screen.
      _loadDueItems();
    } catch (e) {
      if (_disposed) return;
      state.value = state.value.copyWith(isLoading: false, error: friendlyError(e));
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
      if (_disposed) return;
      state.value = state.value.copyWith(
        isSaving: false,
        program: updated,
        saveSuccess: true,
      );
      // Auto-dismiss the success banner after a short delay. Guarded like
      // every other continuation here: the screen can be popped inside those
      // two seconds — a review finishing is exactly that — and writing to a
      // disposed notifier throws on the timer's own stack, where nothing can
      // catch it.
      Future.delayed(const Duration(seconds: 2), () {
        if (_disposed) return;
        state.value = state.value.copyWith(saveSuccess: false);
      });
    } catch (e) {
      // The screen can be gone by the time a failed write comes back, and a
      // throw from here would surface as an unhandled exception on a stack
      // with no screen left to catch it.
      if (_disposed) return;
      state.value = state.value.copyWith(isSaving: false, error: friendlyError(e));
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

    // Flip the UI immediately so it never blocks on the network; the write
    // itself is awaited. The run that replaces whatever was running — and the
    // closing of that run — are the lifecycle's job, so both entry points
    // behave identically.
    state.value = s.copyWith(
      settingCurrent: false,
      isCurrent: true,
      // Whatever was running is paused by the begin, so it is no longer the
      // current program — but it is still there, waiting on its own card.
      anotherProgramIsCurrent: false,
      clearCurrentProgramName: true,
      clearError: true,
      // This program cannot be paused and current at once.
      clearPausedRun: true,
      clearPausedProgress: true,
    );
    try {
      final result = await _lifecycle.begin(
        userId: _userId,
        programId: s.program!.programId,
        progressionMode: progressionMode,
        targetSessions: targetSessions,
        targetWeeks: targetWeeks,
        endDate: endDate,
        blockId: blockId,
      );
      // The repository's run, never one minted here: its id is what every
      // later write — config edits, the close record — must address.
      state.value = state.value.copyWith(activeRun: result.run);
      // A simple program remembers the length it was just begun with, so the
      // next begin opens on that number. Best-effort and guarded inside the
      // repository — the run is live either way.
      await _repo.rememberDefaultTargetSessions(
        s.program!.programId,
        blockId: blockId,
        targetSessions: targetSessions,
      );
      // Load progress immediately — the detail screen's progress row would
      // otherwise stay hidden until the next full reload.
      final progress = await _runRepo.getProgress(_userId);
      state.value = state.value.copyWith(
        currentProgress: progress,
        clearCurrentProgress: progress == null,
      );
      // The run just opened is the sequence's new answer: its block is no
      // longer beginnable, and the block rows have to say so.
      await _loadRuns();
    } catch (e) {
      // The write failed — roll the UI back to exactly what it was, so the
      // program is not left marked "current" when nothing was persisted.
      state.value = s.copyWith(error: friendlyError(e));
    }
    _loadDueItems();
  }

  /// Ends the current run for this program, marking it as no longer active.
  Future<void> endCurrentRun() async {
    final s = state.value;
    // Optimistic: clear immediately so the UI never blocks. The cleared run's
    // close record is cut by the lifecycle, from the row the repository names
    // as current — not from this screen's copy, which the next reload would
    // replace anyway.
    state.value = s.copyWith(
      isCurrent: false,
      anotherProgramIsCurrent: false,
      clearCurrentProgramName: true,
      clearActiveRun: true,
      clearCurrentProgress: true,
      clearError: true,
    );
    try {
      final warning = await _lifecycle.end(userId: _userId);
      if (warning != null && !_disposed) {
        state.value = state.value.copyWith(historyWarning: warning);
      }
      // Ending a run settles what was waiting on it: the "program finished"
      // prompt is derived from the run and disappears with it.
      await _loadDueItems();
      // An ended run is what advances the sequence — the block that just
      // closed stops being current, and the next one becomes beginnable.
      await _loadRuns();
    } catch (e) {
      // Roll back on failure.
      state.value = s.copyWith(error: friendlyError(e));
    }
  }

  /// Whether some *other* program has a run sitting paused.
  ///
  /// Read when the confirmation is about to be asked rather than held in
  /// [ProgramDetailState]: only that dialog's wording needs it, and every run
  /// action on this screen rewrites which runs are open — a field would have to
  /// be carried true through each of those patches to stay honest, and a stale
  /// "nothing else is paused" is exactly the kind of drift the D1 bug was. A
  /// local read at the moment of asking cannot go stale.
  ///
  /// False on failure: the sentence it feeds is a courtesy about paused runs,
  /// and the question is worth asking without it.
  Future<bool> anotherProgramIsPaused() async {
    try {
      final runs = await _runRepo.fetchPausedRuns(_userId);
      final mine = programId;
      return runs.any((run) => run.programId != mine);
    } catch (_) {
      return false;
    }
  }

  /// Puts this program's paused run back in charge.
  ///
  /// No config sheet: the run already exists, with its config, its block and
  /// its session cursor. Resuming is not beginning, and asking how long the
  /// run should be again would be asking a question that already has an
  /// answer. Whatever was current steps aside — that is [resume]'s write, and
  /// it is why resuming from here can pause another program.
  Future<void> resumeRun() async {
    final s = state.value;
    final run = s.pausedRun;
    if (run == null || _disposed) return;
    state.value = s.copyWith(settingCurrent: true, clearError: true);
    try {
      await _lifecycle.resume(run, userId: _userId);
      // Read the result rather than assuming it: the write is a local update,
      // and claiming "current" for a row that did not move would be the same
      // class of lie the old optimistic run id told.
      final current = await _runRepo.getCurrentRun(_userId);
      final isCurrent = current?.programRunId == run.programRunId;
      ProgramProgress? progress;
      if (isCurrent) {
        try {
          progress = await _runRepo.getProgress(_userId);
        } catch (_) {}
      }
      if (_disposed) return;
      state.value = state.value.copyWith(
        settingCurrent: false,
        isCurrent: isCurrent,
        anotherProgramIsCurrent: !isCurrent && current != null,
        // The row as it stands now, not the one that was read before the
        // write: `run` still describes itself as paused, and anything that
        // later reads its state would be told the run this screen calls
        // current is not running.
        activeRun: isCurrent ? current : null,
        clearActiveRun: !isCurrent,
        currentProgress: progress,
        clearCurrentProgress: progress == null,
        clearPausedRun: isCurrent,
        clearPausedProgress: isCurrent,
      );
      await _loadRuns();
    } catch (e) {
      state.value =
          state.value.copyWith(settingCurrent: false, error: friendlyError(e));
    }
    _loadDueItems();
  }

  /// Ends this program's paused run, formally, and cuts its record.
  ///
  /// The "End program" the paused state needs: the user may be done with an
  /// attempt without having finished it, and saying so is what freezes what it
  /// got to. Ending is the only thing that unstamps a run from the paused
  /// state — a restart ends it too, but then begins another.
  Future<void> endPausedRun() async {
    final run = state.value.pausedRun;
    if (run == null || _disposed) return;
    state.value = state.value.copyWith(
      clearPausedRun: true,
      clearPausedProgress: true,
      clearError: true,
    );
    try {
      final warning = await _lifecycle.endRun(run, userId: _userId);
      if (warning != null && !_disposed) {
        state.value = state.value.copyWith(historyWarning: warning);
      }
      await _loadDueItems();
      await _loadRuns();
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  /// Starts this attempt over.
  ///
  /// Works from either state: a run being restarted is ended with its record
  /// first — a formal end, so what it produced is frozen where every other
  /// end's is — and a fresh run begins. The old run's sessions stay attributed
  /// to it, and the program's goals stay in force (they belong to the program,
  /// not the attempt). [targetSessions] comes from the config sheet, which the
  /// caller opens prefilled with the old numbers.
  Future<void> restartRun({
    String? progressionMode,
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
  }) async {
    final s = state.value;
    final old = s.activeRun ?? s.pausedRun;
    if (old == null || _disposed) return;
    state.value = s.copyWith(settingCurrent: true, clearError: true);
    try {
      final result = await _lifecycle.restart(
        oldRun: old,
        userId: _userId,
        progressionMode: progressionMode,
        targetSessions: targetSessions,
        targetWeeks: targetWeeks,
        endDate: endDate,
      );
      ProgramProgress? progress;
      try {
        progress = await _runRepo.getProgress(_userId);
      } catch (_) {}
      if (_disposed) return;
      state.value = state.value.copyWith(
        settingCurrent: false,
        isCurrent: true,
        anotherProgramIsCurrent: false,
        activeRun: result.run,
        clearPausedRun: true,
        clearPausedProgress: true,
        currentProgress: progress,
        clearCurrentProgress: progress == null,
        historyWarning: result.warning,
        clearHistoryWarning: result.warning == null,
      );
    } catch (e) {
      state.value =
          state.value.copyWith(settingCurrent: false, error: friendlyError(e));
    }
    _loadDueItems();
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
      // The rebuild is [ProgramRunLifecycle.withConfig]'s — it preserves the
      // fields this method does not touch, `blockId` included. Rebuilding the
      // run here from the arguments alone used to silently drop a block run's
      // block, un-blocking it for goal scoping and mislabelling its close.
      final updated = await _lifecycle.updateConfig(
        run,
        progressionMode: progressionMode,
        targetSessions: targetSessions,
        targetWeeks: targetWeeks,
        endDate: endDate,
        clearSessions: clearSessions,
        clearWeeks: clearWeeks,
        clearEndDate: clearEndDate,
      );
      state.value = state.value.copyWith(activeRun: updated, clearError: true);
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  /// The workouts a program can copy in — the standalone ones, which are what
  /// the workout library holds.
  ///
  /// Read on demand rather than held in state: the list belongs to the
  /// library, which is another screen, and it changes there rather than here.
  Future<List<PlannedSession>> standaloneWorkouts() =>
      _plannedSessionRepo.fetchPlannedSessions(_userId);

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
      state.value = state.value.copyWith(error: friendlyError(e));
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

  /// Re-reads this program's runs.
  ///
  /// The half of the block sequence that no block edit touches, so it is loaded
  /// where runs change rather than where blocks do. Best-effort: a failed read
  /// leaves the previous sequence, and the block rows only lose their "next"
  /// marking until the next load.
  Future<void> _loadRuns() async {
    final programId = state.value.program?.programId;
    if (programId == null) return;
    try {
      final runs = await _runRepo.fetchRunsForProgram(programId);
      if (_disposed) return;
      state.value = state.value.copyWith(programRuns: runs);
    } catch (_) {}
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
      state.value = state.value.copyWith(error: friendlyError(e));
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
      state.value = state.value.copyWith(error: friendlyError(e));
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
      state.value = state.value.copyWith(error: friendlyError(e));
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
