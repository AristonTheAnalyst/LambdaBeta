import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/planned_session_set.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/models/program.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/program_progress.dart';
import '../../../data/models/program_run.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/planned_session_repository.dart';
import '../../../data/repositories/program_run_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../core/powersync/database.dart' as ps;
import '../../session/model/session_local_state.dart'
    show ExerciseHistorySession, groupHistoryByExercise, isSimilarVariationName;

/// One tab in the plan-workout screen — a single exercise within the
/// workout being planned. Unlike the session screen there's no superset
/// concept here (no schema support for grouping multiple exercises under
/// one planned "round"), so this is deliberately simpler than
/// `SessionExerciseSlot`: one exercise per slot, always.
class PlanExerciseSlot {
  const PlanExerciseSlot({
    required this.exerciseSequenceOrder,
    required this.exerciseId,
  });
  final int exerciseSequenceOrder;
  final String exerciseId;
}

class ProgramDetailState {
  const ProgramDetailState({
    this.isLoading = false,
    this.isSaving = false,
    this.saveSuccess = false,
    this.error,
    this.program,
    this.plannedWorkouts = const [],
    this.exerciseDetailMap = const {},
    this.isCurrent = false,
    this.settingCurrent = false,
    this.activeRun,
    this.currentProgress,
    // Program field drafts
    this.nameDraft = '',
    this.descriptionDraft = '',
    this.lengthWeeksDraft = '',
    this.progressionModeDraft = 'sequential',
    // Planned workout editor (full screen)
    this.editingWorkout,
    this.workoutNameDraft = '',
    this.workoutNotesDraft = '',
    this.workoutDayOfWeekDraft,
    this.workoutPlannedSessionSets = const [],
    this.workoutExerciseSlots = const [],
    this.activeSlotIndex = 0,
    this.workoutSetDrafts = const {},
    this.workoutSetsLoading = false,
    this.workoutUnsavedChanges = false,
    // Catalog / create-new (mirrors SessionViewModel)
    this.allVariations = const [],
    this.variationExerciseCounts = const {},
    this.newExCreating = false,
    this.newVarCreating = false,
    // Goals
    this.programGoals = const [],
    this.goalsLoading = false,
    // Lessons (per-exercise, cross-session — reuses fact_lesson as-is)
    this.lessonsByExercise = const {},
    // History (read-only past-sets, reuses the session's read path as-is)
    this.historyByExercise = const {},
    this.pastSetsLoaded = false,
  });

  final bool isLoading;
  final bool isSaving;
  final bool saveSuccess;
  final String? error;
  final Program? program;
  final List<PlannedSession> plannedWorkouts;
  final Map<String, ExerciseDetail> exerciseDetailMap;
  final bool isCurrent;
  final bool settingCurrent;

  /// The active run for this program (when it's the current program) — carries
  /// the run's duration config, editable while running.
  final ProgramRun? activeRun;

  /// Progress of the active run (null unless this program is current).
  final ProgramProgress? currentProgress;

  final String nameDraft;
  final String descriptionDraft;
  final String lengthWeeksDraft;
  final String progressionModeDraft;

  final PlannedSession? editingWorkout;
  final String workoutNameDraft;
  final String workoutNotesDraft;
  final int? workoutDayOfWeekDraft;
  final List<PlannedSessionSet> workoutPlannedSessionSets;
  final List<PlanExerciseSlot> workoutExerciseSlots;
  final int activeSlotIndex;
  final Map<int, List<int>> workoutSetDrafts;
  final bool workoutSetsLoading;
  final bool workoutUnsavedChanges;

  final List<CustomVariation> allVariations;
  final Map<String, int> variationExerciseCounts;
  final bool newExCreating;
  final bool newVarCreating;

  final Map<String, List<Lesson>> lessonsByExercise;
  final Map<String, List<ExerciseHistorySession>> historyByExercise;
  final bool pastSetsLoaded;

  final List<Goal> programGoals;
  final bool goalsLoading;

  bool get isCalendarMode => progressionModeDraft == 'calendar';

  /// True when the program name or description has been edited in the form
  /// but not yet persisted — used by [UnsavedChangesGuard] to warn on back.
  bool get hasUnsavedProgramFields {
    if (program == null) return false;
    return nameDraft.trim() != (program!.name) ||
        descriptionDraft.trim() != (program!.description ?? '');
  }

  PlanExerciseSlot? get activeSlot => workoutExerciseSlots.isEmpty
      ? null
      : workoutExerciseSlots[activeSlotIndex.clamp(
          0,
          workoutExerciseSlots.length - 1,
        )];

  List<PlannedSessionSet> plannedSetsFor(int exerciseSequenceOrder) =>
      workoutPlannedSessionSets
          .where((ps) => ps.exerciseSequenceOrder == exerciseSequenceOrder)
          .toList()
        ..sort((a, b) => a.setNumber.compareTo(b.setNumber));

  ProgramDetailState copyWith({
    bool? isLoading,
    bool? isSaving,
    bool? saveSuccess,
    String? error,
    bool clearError = false,
    Program? program,
    List<PlannedSession>? plannedWorkouts,
    Map<String, ExerciseDetail>? exerciseDetailMap,
    bool? isCurrent,
    bool? settingCurrent,
    ProgramRun? activeRun,
    ProgramProgress? currentProgress,
    String? nameDraft,
    String? descriptionDraft,
    String? lengthWeeksDraft,
    String? progressionModeDraft,
    PlannedSession? editingWorkout,
    bool clearEditingWorkout = false,
    String? workoutNameDraft,
    String? workoutNotesDraft,
    int? workoutDayOfWeekDraft,
    bool clearWorkoutDayOfWeekDraft = false,
    List<PlannedSessionSet>? workoutPlannedSessionSets,
    List<PlanExerciseSlot>? workoutExerciseSlots,
    int? activeSlotIndex,
    Map<int, List<int>>? workoutSetDrafts,
    bool? workoutSetsLoading,
    bool? workoutUnsavedChanges,
    List<CustomVariation>? allVariations,
    Map<String, int>? variationExerciseCounts,
    bool? newExCreating,
    bool? newVarCreating,
    Map<String, List<Lesson>>? lessonsByExercise,
    Map<String, List<ExerciseHistorySession>>? historyByExercise,
    bool? pastSetsLoaded,
    List<Goal>? programGoals,
    bool? goalsLoading,
  }) => ProgramDetailState(
    isLoading: isLoading ?? this.isLoading,
    isSaving: isSaving ?? this.isSaving,
    saveSuccess: saveSuccess ?? false,
    error: clearError ? null : error ?? this.error,
    program: program ?? this.program,
    plannedWorkouts: plannedWorkouts ?? this.plannedWorkouts,
    exerciseDetailMap: exerciseDetailMap ?? this.exerciseDetailMap,
    isCurrent: isCurrent ?? this.isCurrent,
    settingCurrent: settingCurrent ?? this.settingCurrent,
    activeRun: activeRun ?? this.activeRun,
    currentProgress: currentProgress ?? this.currentProgress,
    nameDraft: nameDraft ?? this.nameDraft,
    descriptionDraft: descriptionDraft ?? this.descriptionDraft,
    lengthWeeksDraft: lengthWeeksDraft ?? this.lengthWeeksDraft,
    progressionModeDraft: progressionModeDraft ?? this.progressionModeDraft,
    editingWorkout: clearEditingWorkout
        ? null
        : (editingWorkout ?? this.editingWorkout),
    workoutNameDraft: clearEditingWorkout
        ? ''
        : (workoutNameDraft ?? this.workoutNameDraft),
    workoutNotesDraft: clearEditingWorkout
        ? ''
        : (workoutNotesDraft ?? this.workoutNotesDraft),
    workoutDayOfWeekDraft: clearEditingWorkout || clearWorkoutDayOfWeekDraft
        ? null
        : (workoutDayOfWeekDraft ?? this.workoutDayOfWeekDraft),
    workoutPlannedSessionSets: clearEditingWorkout
        ? const []
        : (workoutPlannedSessionSets ?? this.workoutPlannedSessionSets),
    workoutExerciseSlots: clearEditingWorkout
        ? const []
        : (workoutExerciseSlots ?? this.workoutExerciseSlots),
    activeSlotIndex: clearEditingWorkout
        ? 0
        : (activeSlotIndex ?? this.activeSlotIndex),
    workoutSetDrafts: clearEditingWorkout
        ? const {}
        : (workoutSetDrafts ?? this.workoutSetDrafts),
    workoutSetsLoading: clearEditingWorkout
        ? false
        : (workoutSetsLoading ?? this.workoutSetsLoading),
    workoutUnsavedChanges: clearEditingWorkout
        ? false
        : (workoutUnsavedChanges ?? this.workoutUnsavedChanges),
    allVariations: allVariations ?? this.allVariations,
    variationExerciseCounts:
        variationExerciseCounts ?? this.variationExerciseCounts,
    newExCreating: newExCreating ?? this.newExCreating,
    newVarCreating: newVarCreating ?? this.newVarCreating,
    lessonsByExercise: lessonsByExercise ?? this.lessonsByExercise,
    historyByExercise: historyByExercise ?? this.historyByExercise,
    pastSetsLoaded: pastSetsLoaded ?? this.pastSetsLoaded,
    programGoals: programGoals ?? this.programGoals,
    goalsLoading: goalsLoading ?? this.goalsLoading,
  );
}

class ProgramDetailViewModel {
  ProgramDetailViewModel({
    ProgramRepository? repo,
    ProgramRunRepository? runRepo,
    ExerciseRepository? exerciseRepo,
    LessonRepository? lessonRepo,
    SessionRepository? workoutRepo,
    PlannedSessionRepository? workoutPlanRepo,
  }) : _repo = repo ?? ProgramRepository(),
       _runRepo = runRepo ?? ProgramRunRepository(),
       _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
       _lessonRepo = lessonRepo ?? LessonRepository(),
       _sessionRepo = workoutRepo ?? SessionRepository(),
       _plannedSessionRepo = workoutPlanRepo ?? PlannedSessionRepository();

  final ProgramRepository _repo;
  final ProgramRunRepository _runRepo;
  final _uuid = const Uuid();
  final ExerciseRepository _exerciseRepo;
  final LessonRepository _lessonRepo;
  final SessionRepository _sessionRepo;
  final PlannedSessionRepository _plannedSessionRepo;

  /// When set, the editor operates on a standalone workout (no program)
  /// instead of a program's planned workout.
  String? _standaloneWorkoutId;
  bool get isStandaloneMode => _standaloneWorkoutId != null;

  /// Virtual draft row ids for the workout editor — "+ ADD SET" and new
  /// exercise groups add drafts that materialize on input or explicit Save.
  int _nextDraftId = 1;

  // ── Discard rollback snapshot ─────────────────────────────────────────────
  /// The workout's state at open (or last Save) — sets + header fields.
  /// Discard restores exactly this: sets auto-commit as they're edited,
  /// so without a snapshot "Discard" could never undo them.
  List<PlannedSessionSet> _openedSetsSnapshot = const [];
  String? _openedName;
  String? _openedNotes;
  int? _openedDayOfWeek;
  bool _openedExisting = false;
  final state = ValueNotifier(const ProgramDetailState());

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  /// Creates a new program with only a progression mode (name/goals are set
  /// by the wizard's later steps) and returns its id, ready for [load].
  Future<String?> createNewProgram(String progressionMode) async {
    try {
      final created = await _repo.createProgram(
        _userId,
        progressionMode: progressionMode,
      );
      return created.programId;
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
      return null;
    }
  }

  /// Adds an exercise-target goal (weight × reps for a specific exercise).
  Future<void> addGoal({
    required String exerciseId,
    required String exerciseName,
    num? targetWeight,
    int? targetReps,
  }) async {
    final runId = state.value.activeRun?.programRunId;
    if (runId == null) return;
    final goal = Goal(
      goalId: Uuid().v4(),
      programRunId: runId,
      userId: _userId,
      text: exerciseName,
      exerciseId: exerciseId,
      targetWeight: targetWeight,
      targetReps: targetReps,
    );
    try {
      await _repo.createGoal(_userId, runId, goal);
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
      );
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> _loadGoals() async {
    final runId = state.value.activeRun?.programRunId;
    if (runId == null) return;
    state.value = state.value.copyWith(goalsLoading: true);
    try {
      final goals = await _repo
          .fetchGoals(runId)
          .timeout(const Duration(seconds: 3));
      state.value = state.value.copyWith(
        programGoals: goals,
        goalsLoading: false,
      );
    } catch (_) {
      state.value = state.value.copyWith(goalsLoading: false);
    }
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
        _exerciseRepo
            .fetchExerciseDetailMap(_userId)
            .timeout(const Duration(seconds: 4)),
        _runRepo.getCurrentRun(_userId).timeout(const Duration(seconds: 4)),
        _exerciseRepo
            .fetchVariations(_userId)
            .timeout(const Duration(seconds: 4)),
        _exerciseRepo.fetchBridges(_userId).timeout(const Duration(seconds: 4)),
      ]);
      final program = results[0] as Program?;
      final currentRun = results[3] as ProgramRun?;
      final variations = results[4] as List<CustomVariation>;
      final bridges = results[5] as List<Map<String, dynamic>>;
      final counts = <String, int>{};
      for (final b in bridges) {
        final varId = b['custom_variation_id'] as String;
        counts[varId] = (counts[varId] ?? 0) + 1;
      }
      final isCurrent = currentRun != null && currentRun.programId == programId;
      ProgramProgress? progress;
      if (isCurrent) {
        try {
          progress = await _runRepo.getProgress(_userId);
        } catch (_) {}
      }
      state.value = state.value.copyWith(
        isLoading: false,
        program: program,
        plannedWorkouts: (results[1] as List<PlannedSession>),
        exerciseDetailMap: results[2] as Map<String, ExerciseDetail>,
        nameDraft: program?.name ?? '',
        descriptionDraft: program?.description ?? '',
        lengthWeeksDraft: program?.lengthWeeks?.toString() ?? '',
        progressionModeDraft: program?.progressionMode ?? 'sequential',
        isCurrent: isCurrent,
        activeRun: isCurrent ? currentRun : null,
        currentProgress: progress,
        allVariations: variations,
        variationExerciseCounts: counts,
      );
      // Goals load independently — they aren't critical for rendering.
      _loadGoals();
    } catch (e) {
      state.value = state.value.copyWith(isLoading: false, error: e.toString());
    }
  }

  // ── Program fields ───────────────────────────────────────────────────────

  void setNameDraft(String v) =>
      state.value = state.value.copyWith(nameDraft: v);
  void setDescriptionDraft(String v) =>
      state.value = state.value.copyWith(descriptionDraft: v);
  void setLengthWeeksDraft(String v) =>
      state.value = state.value.copyWith(lengthWeeksDraft: v);
  void setProgressionModeDraft(String v) =>
      state.value = state.value.copyWith(progressionModeDraft: v);

  Future<void> saveProgramDetails() async {
    final s = state.value;
    if (s.program == null || s.nameDraft.trim().isEmpty) return;
    state.value = s.copyWith(isSaving: true, clearError: true);
    try {
      await _repo.updateProgram(
        s.program!.programId,
        name: s.nameDraft.trim(),
        description: s.descriptionDraft.trim(),
        lengthWeeks: int.tryParse(s.lengthWeeksDraft.trim()),
        progressionMode: s.progressionModeDraft,
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

  Future<void> setAsCurrent({
    int? targetSessions,
    int? targetWeeks,
    DateTime? endDate,
  }) async {
    final s = state.value;
    if (s.program == null || _disposed) return;

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
      targetSessions: targetSessions,
      targetWeeks: targetWeeks,
      endDate: endDate?.toUtc(),
    );
    state.value = s.copyWith(
      settingCurrent: false,
      isCurrent: true,
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
        targetSessions: targetSessions,
        targetWeeks: targetWeeks,
        endDate: endDate,
      );
      // Load progress immediately — the detail screen's progress row would
      // otherwise stay hidden until the next full reload.
      final progress = await _runRepo.getProgress(_userId);
      state.value = state.value.copyWith(currentProgress: progress);
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
  }

  /// Ends the current run for this program, marking it as no longer active.
  Future<void> endCurrentRun() async {
    final s = state.value;
    // Optimistic: clear immediately so the UI never blocks.
    state.value = s.copyWith(
      isCurrent: false,
      activeRun: null,
      clearError: true,
    );
    try {
      await _runRepo.endCurrentRun(_userId);
    } catch (e) {
      // Roll back on failure.
      state.value = state.value.copyWith(
        isCurrent: s.isCurrent,
        activeRun: s.activeRun,
        error: e.toString(),
      );
    }
  }

  /// Updates the active run's duration config (mutable while running).
  Future<void> updateRunConfig({
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

  // ── Planned workout editor (full screen) ─────────────────────────────────

  List<PlannedSessionSet> _setsFromSessionSets(List<PlannedSessionSet> sets) =>
      [
        for (final s in sets)
          PlannedSessionSet(
            setId: s.setId,
            sessionId: s.sessionId,
            userId: s.userId,
            exerciseId: s.exerciseId,
            variationId: s.variationId,
            exerciseSequenceOrder: s.exerciseSequenceOrder,
            setNumber: s.setNumber,
            targetWeight: s.targetWeight,
            targetReps: s.targetReps,
            targetNotes: s.targetNotes,
            exerciseName: s.exerciseName,
            variationName: s.variationName,
            isArchived: true,
          ),
      ];

  List<PlanExerciseSlot> _slotsFromSessionSets(List<PlannedSessionSet> sets) {
    final seen = <int>{};
    final slots = <PlanExerciseSlot>[];
    for (final s in sets) {
      if (seen.add(s.exerciseSequenceOrder)) {
        slots.add(
          PlanExerciseSlot(
            exerciseSequenceOrder: s.exerciseSequenceOrder,
            exerciseId: s.exerciseId,
          ),
        );
      }
    }
    return slots;
  }

  /// Creates a brand-new planned workout immediately (placeholder name) and
  /// opens it for editing — mirrors how starting a session is a definite
  /// action; there's no separate "draft, unsaved workout" state to manage.
  Future<void> createWorkoutAndOpen() async {
    final programId = state.value.program?.programId;
    if (programId == null) return;
    state.value = state.value.copyWith(clearError: true);
    try {
      final seqOrder = state.value.plannedWorkouts.length + 1;
      final wp = await _plannedSessionRepo.createPlannedSession(
        _userId,
        programId: programId,
        sequenceOrder: seqOrder,
      );
      final created = PlannedSession(
        sessionId: wp.sessionId,
        programId: programId,
        userId: wp.userId,
        name: wp.name,
        notes: wp.notes,
        sequenceOrder: seqOrder,
        isArchived: true,
      );
      // Created this editing session — Discard rolls back its existence.
      _openedExisting = false;
      _openedSetsSnapshot = const [];
      // Fetch from the standalone table (dim_workout) which is the source of
      // truth for all workouts now.
      final workouts = await _plannedSessionRepo.fetchPlannedSessions(
        _userId,
        programId: programId,
      );
      final plannedWorkouts = workouts;
      state.value = state.value.copyWith(
        plannedWorkouts: plannedWorkouts,
        editingWorkout: created,
        workoutNameDraft: created.name,
        workoutNotesDraft: created.notes ?? '',
        clearWorkoutDayOfWeekDraft: true,
        workoutPlannedSessionSets: const [],
        workoutExerciseSlots: const [],
        activeSlotIndex: 0,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> openEditWorkout(PlannedSession w) async {
    state.value = state.value.copyWith(
      editingWorkout: w,
      workoutNameDraft: w.name,
      workoutNotesDraft: w.notes ?? '',
      workoutDayOfWeekDraft: w.dayOfWeek,
      clearWorkoutDayOfWeekDraft: w.dayOfWeek == null,
      workoutSetsLoading: true,
    );
    try {
      // Consolidation enforces "exercises are unique per session" on legacy
      // data — duplicate exercise groups merge into one and no-target
      // keep-alive stubs archive — so the planner shows the same view the
      // session preview shows.
      final sets = await _plannedSessionRepo.consolidateDuplicateExerciseGroups(
        w.sessionId,
      );
      _openedSetsSnapshot = sets;
      _openedName = w.name;
      _openedNotes = w.notes;
      _openedDayOfWeek = w.dayOfWeek;
      _openedExisting = true;
      final plannedSets = _setsFromSessionSets(sets);
      state.value = state.value.copyWith(
        workoutPlannedSessionSets: plannedSets,
        workoutExerciseSlots: _slotsFromSessionSets(sets),
        activeSlotIndex: 0,
        workoutSetsLoading: false,
      );
      for (final slot in state.value.workoutExerciseSlots) {
        loadLessonsFor(slot.exerciseId);
      }
    } catch (e) {
      state.value = state.value.copyWith(
        workoutSetsLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Opens a standalone workout for editing (no program). Loads its name,
  /// notes, and planned sets into the editor.
  Future<void> openStandaloneWorkout(String sessionId) async {
    _standaloneWorkoutId = sessionId;
    await _ensureCatalog();
    final workouts = await _plannedSessionRepo.fetchPlannedSessions(_userId);
    final w = workouts.where((x) => x.sessionId == sessionId).firstOrNull;
    if (w == null) {
      // Surfacing the failure keeps the editor from hanging on its loading
      // spinner when a just-created row hasn't synced back yet.
      state.value = state.value.copyWith(
        workoutSetsLoading: false,
        error: 'Could not open workout.',
      );
      return;
    }
    state.value = state.value.copyWith(
      editingWorkout: PlannedSession(
        sessionId: w.sessionId,
        programId: '',
        userId: w.userId,
        name: w.name,
        notes: w.notes,
        sequenceOrder: 0,
        isArchived: true,
      ),
      workoutNameDraft: w.name,
      workoutNotesDraft: w.notes ?? '',
      workoutSetsLoading: true,
    );
    try {
      // Same legacy-data consolidation as openEditWorkout — one group per
      // exercise, no-target stubs archived, so the planner and the session
      // preview agree.
      final sets = await _plannedSessionRepo.consolidateDuplicateExerciseGroups(
        sessionId,
      );
      _openedSetsSnapshot = sets;
      _openedName = w.name;
      _openedNotes = w.notes;
      _openedDayOfWeek = w.dayOfWeek;
      _openedExisting = true;
      state.value = state.value.copyWith(
        workoutPlannedSessionSets: _setsFromSessionSets(sets),
        workoutExerciseSlots: _slotsFromSessionSets(sets),
        activeSlotIndex: 0,
        workoutSetsLoading: false,
      );
      for (final slot in state.value.workoutExerciseSlots) {
        loadLessonsFor(slot.exerciseId);
      }
    } catch (e) {
      state.value = state.value.copyWith(
        workoutSetsLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Creates a brand-new standalone workout and opens it for editing.
  Future<void> createStandaloneWorkoutAndOpen() async {
    _standaloneWorkoutId = null;
    state.value = state.value.copyWith(clearError: true);
    await _ensureCatalog();
    try {
      final created = await _plannedSessionRepo.createPlannedSession(_userId);
      // Open the editor against the row we just created. Building state from
      // the returned object (rather than re-fetching) avoids a race where the
      // insert hasn't reflected into a follow-up SELECT yet — previously that
      // left editingWorkout null and the screen on an eternal spinner.
      state.value = state.value.copyWith(
        editingWorkout: PlannedSession(
          sessionId: created.sessionId,
          programId: '',
          userId: created.userId,
          name: created.name,
          notes: created.notes,
          sequenceOrder: 0,
          isArchived: true,
        ),
        workoutNameDraft: created.name,
        workoutNotesDraft: created.notes ?? '',
        workoutSetsLoading: true,
      );
      try {
        final sets = await _plannedSessionRepo.fetchPlannedSets(
          created.sessionId,
        );
        state.value = state.value.copyWith(
          workoutPlannedSessionSets: _setsFromSessionSets(sets),
          workoutExerciseSlots: _slotsFromSessionSets(sets),
          activeSlotIndex: 0,
          workoutSetsLoading: false,
        );
        for (final slot in state.value.workoutExerciseSlots) {
          loadLessonsFor(slot.exerciseId);
        }
      } catch (e) {
        state.value = state.value.copyWith(
          workoutSetsLoading: false,
          error: e.toString(),
        );
      }
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  /// Loads the exercise/variation catalog if not already loaded — the
  /// standalone workout editor needs it to populate the add-exercise picker.
  Future<void> _ensureCatalog() async {
    if (state.value.exerciseDetailMap.isNotEmpty) return;
    try {
      await _reloadCatalog();
    } catch (_) {}
  }

  /// Copies a standalone workout into the current program as a planned
  /// workout, including its exercise sets. Returns the new planned workout.
  Future<PlannedSession?> copyWorkoutIntoProgram(String sessionId) async {
    final programId = state.value.program?.programId;
    if (programId == null) return null;
    try {
      final src = (await _plannedSessionRepo.fetchPlannedSessions(
        _userId,
      )).where((w) => w.sessionId == sessionId).firstOrNull;
      if (src == null) return null;
      final srcSets = await _plannedSessionRepo.fetchPlannedSets(sessionId);
      final created = await _plannedSessionRepo.createPlannedSession(
        _userId,
        name: src.name,
        notes: src.notes,
        programId: programId,
        sequenceOrder: state.value.plannedWorkouts.length + 1,
      );
      for (final s in srcSets) {
        await _plannedSessionRepo.createPlannedSet(
          _userId,
          created.sessionId,
          exerciseId: s.exerciseId,
          exerciseName: s.exerciseName,
          variationId: s.variationId,
          variationName: s.variationName,
          exerciseSequenceOrder: s.exerciseSequenceOrder,
          setNumber: s.setNumber,
          targetWeight: s.targetWeight,
          targetReps: s.targetReps,
          targetNotes: s.targetNotes,
        );
      }
      final wps = await _plannedSessionRepo.fetchPlannedSessions(
        _userId,
        programId: programId,
      );
      state.value = state.value.copyWith(plannedWorkouts: wps);
      return created;
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
      return null;
    }
  }

  void markWorkoutDirty() =>
      state.value = state.value.copyWith(workoutUnsavedChanges: true);

  Future<void> saveWorkout() async {
    final s = state.value;
    if (!s.workoutUnsavedChanges) return;
    // A planned workout must contain at least one exercise — never save an
    // empty one.
    if (s.workoutExerciseSlots.isEmpty) {
      state.value = state.value.copyWith(
        error: 'Add at least one exercise to this workout before saving.',
      );
      return;
    }
    await Future.wait([commitWorkoutName(), commitWorkoutNotes()]);
    // Persist any remaining draft rows as (possibly empty) planned sets —
    // empty sets are valid and an explicit Save is intent.
    final workout = s.editingWorkout;
    if (workout != null) {
      var anyDrafts = false;
      for (final entry in state.value.workoutSetDrafts.entries) {
        final slot = state.value.workoutExerciseSlots
            .where((sl) => sl.exerciseSequenceOrder == entry.key)
            .firstOrNull;
        if (slot == null) continue;
        for (final _ in entry.value) {
          await _persistEmptyPlannedSessionSet(slot.exerciseId, entry.key);
          anyDrafts = true;
        }
      }
      if (anyDrafts) {
        state.value = state.value.copyWith(workoutSetDrafts: const {});
      }
      // Refresh the rollback snapshot — a later Discard rolls back to this
      // Save, not to open.
      _openedSetsSnapshot = await _plannedSessionRepo.fetchPlannedSets(
        workout.sessionId,
      );
      final savedName = state.value.workoutNameDraft.trim();
      final savedNotes = state.value.workoutNotesDraft.trim();
      _openedName = savedName.isEmpty ? null : savedName;
      _openedNotes = savedNotes.isEmpty ? null : savedNotes;
      _openedDayOfWeek = state.value.workoutDayOfWeekDraft;
      _openedExisting = true;
    }
    if (isStandaloneMode) {
      state.value = state.value.copyWith(workoutUnsavedChanges: false);
      return;
    }
    // Refresh the workout list so the parent screen picks up name / order
    // changes when the user presses back.
    final programId = s.program?.programId ?? '';
    final wps = await _plannedSessionRepo.fetchPlannedSessions(
      _userId,
      programId: programId,
    );
    state.value = state.value.copyWith(
      plannedWorkouts: wps,
      workoutUnsavedChanges: false,
    );
  }

  /// Rolls the workout back to its open-time state (or last Save) — header
  /// fields and sets. Sets auto-commit as they're edited, so without this
  /// pass "Discard" could never undo them. A workout created in this
  /// editing session rolls back to nonexistence.
  Future<void> discardWorkoutChanges() async {
    final w = state.value.editingWorkout;
    if (w == null) return;
    if (!_openedExisting) {
      await deletePlannedSession();
      return;
    }
    try {
      await _plannedSessionRepo.updatePlannedSession(
        w.sessionId,
        name: _openedName,
        notes: _openedNotes,
        clearNotes: _openedNotes == null,
        dayOfWeek: _openedDayOfWeek,
        clearDayOfWeek: _openedDayOfWeek == null,
        userId: _userId,
      );
      final current = await _plannedSessionRepo.fetchPlannedSets(w.sessionId);
      final snapshotIds = {for (final s in _openedSetsSnapshot) s.setId};
      // Rows added since open are discarded.
      for (final s in current) {
        if (!snapshotIds.contains(s.setId)) {
          await _plannedSessionRepo.deletePlannedSet(s.setId);
        }
      }
      // Snapshot rows return to their open-time values (any archived during
      // editing come back).
      for (final s in _openedSetsSnapshot) {
        await _plannedSessionRepo.updatePlannedSet(
          s.setId,
          targetWeight: s.targetWeight,
          clearWeight: s.targetWeight == null,
          targetReps: s.targetReps,
          clearReps: s.targetReps == null,
          variationId: s.variationId,
          clearVariation: s.variationId == null,
          variationName: s.variationName,
          targetNotes: s.targetNotes,
          clearNotes: s.targetNotes == null,
        );
        await ps.db.execute(
          'UPDATE dim_planned_session_set SET is_archived = 0, exercise_sequence_order = ?, set_number = ? WHERE set_id = ?',
          [s.exerciseSequenceOrder, s.setNumber, s.setId],
        );
      }
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
    closeWorkoutEditor();
  }

  void closeWorkoutEditor() {
    // Clear editing state SYNCHRONOUSLY — dispose() commits pending
    // name/notes drafts, and a delayed clear would let a discarded draft
    // get written after the guard pops.
    final programId = state.value.program?.programId;
    state.value = state.value.copyWith(clearEditingWorkout: true);
    // When closing without saving (discard), still refresh the workout list
    // so that a newly-created-then-discarded workout shows its name correctly
    // and exercises added/removed during editing are reflected.
    if (!isStandaloneMode && programId != null) {
      _plannedSessionRepo
          .fetchPlannedSessions(_userId, programId: programId)
          .then((wps) {
            state.value = state.value.copyWith(plannedWorkouts: wps);
          });
    }
  }

  Future<void> deletePlannedSession() async {
    final w = state.value.editingWorkout;
    if (w == null) return;
    // Archive BEFORE clearing the editor — closeWorkoutEditor's list refetch
    // would otherwise race ahead and keep the deleted workout listed.
    await _plannedSessionRepo.deletePlannedSession(w.sessionId);
    closeWorkoutEditor();
    if (isStandaloneMode) {
      _standaloneWorkoutId = null;
    }
  }

  Future<void> duplicatePlannedSession(PlannedSession source) async {
    final programId = state.value.program?.programId;
    if (programId == null) return;
    // Duplicate via the standalone repo (which copies sets), then patch in the
    // program linkage columns.
    final newId = await _plannedSessionRepo.duplicatePlannedSession(
      _userId,
      source,
    );
    await ps.db.execute(
      'UPDATE dim_planned_session SET program_id = ?, sequence_order = ?, day_of_week = ? WHERE session_id = ?',
      [programId, (source.sequenceOrder ?? 0) + 1, source.dayOfWeek, newId],
    );
    final wps = await _plannedSessionRepo.fetchPlannedSessions(
      _userId,
      programId: programId,
    );
    state.value = state.value.copyWith(plannedWorkouts: wps);
  }

  /// Removes a planned workout from the current program (from the detail list).
  Future<void> removePlannedSession(PlannedSession w) async {
    await _plannedSessionRepo.deletePlannedSession(w.sessionId);
    final updated = state.value.plannedWorkouts
        .where((pw) => pw.sessionId != w.sessionId)
        .toList();
    state.value = state.value.copyWith(plannedWorkouts: updated);
  }

  Future<void> reorderWorkouts(
    List<PlannedSession> reordered,
    List<String> ids,
  ) async {
    // Update in-memory sequenceOrder so labels refresh immediately.
    for (var i = 0; i < reordered.length; i++) {
      reordered[i] = PlannedSession(
        sessionId: reordered[i].sessionId,
        programId: reordered[i].programId,
        userId: reordered[i].userId,
        name: reordered[i].name,
        notes: reordered[i].notes,
        sequenceOrder: i + 1,
        dayOfWeek: reordered[i].dayOfWeek,
        isArchived: reordered[i].isArchived,
      );
    }
    state.value = state.value.copyWith(plannedWorkouts: reordered);
    // Persist sequence_order on each workout to match the new order.
    for (var i = 0; i < ids.length; i++) {
      await ps.db.execute(
        'UPDATE dim_planned_session SET sequence_order = ? WHERE session_id = ?',
        [i + 1, ids[i]],
      );
    }
  }

  // ── Session name/notes/day-of-week — auto-commit on blur/change ─────────

  void setWorkoutNameDraft(String v) => state.value = state.value.copyWith(
    workoutNameDraft: v,
    workoutUnsavedChanges: true,
  );
  void setWorkoutNotesDraft(String v) => state.value = state.value.copyWith(
    workoutNotesDraft: v,
    workoutUnsavedChanges: true,
  );

  /// Whether anything is still unsaved after an auto-commit — pending set
  /// drafts, or name/notes/day-of-week drafts that differ from the persisted
  /// workout. Auto-committed fields must clear the dirty flag or the back
  /// guard prompts "Discard/Save" for already-saved data.
  bool _workoutStillDirty(PlannedSession w) {
    if (state.value.workoutSetDrafts.values.any((l) => l.isNotEmpty)) {
      return true;
    }
    if (state.value.workoutNameDraft.trim() != w.name) return true;
    if (state.value.workoutNotesDraft.trim() != (w.notes ?? '')) return true;
    if (state.value.workoutDayOfWeekDraft != w.dayOfWeek) return true;
    return false;
  }

  PlannedSession _withEditedWorkout(
    PlannedSession w, {
    String? name,
    String? notes,
  }) => PlannedSession(
    sessionId: w.sessionId,
    userId: w.userId,
    name: name ?? w.name,
    notes: notes ?? w.notes,
    isArchived: w.isArchived,
    programId: w.programId,
    sequenceOrder: w.sequenceOrder,
    dayOfWeek: w.dayOfWeek,
    createdDate: w.createdDate,
  );

  Future<void> commitWorkoutName() async {
    final w = state.value.editingWorkout;
    final name = state.value.workoutNameDraft.trim();
    if (w == null || name.isEmpty || name == w.name) return;
    await _plannedSessionRepo.updatePlannedSession(
      w.sessionId,
      name: name,
      userId: _userId,
    );
    final updated = _withEditedWorkout(w, name: name);
    state.value = state.value.copyWith(
      editingWorkout: updated,
      workoutUnsavedChanges: _workoutStillDirty(updated),
    );
    if (!isStandaloneMode) {
      final programId = state.value.program?.programId;
      if (programId != null) {
        final wps = await _plannedSessionRepo.fetchPlannedSessions(
          _userId,
          programId: programId,
        );
        state.value = state.value.copyWith(plannedWorkouts: wps);
      }
    }
  }

  Future<void> commitWorkoutNotes() async {
    final w = state.value.editingWorkout;
    if (w == null) return;
    final notes = state.value.workoutNotesDraft.trim();
    if (notes == (w.notes ?? '')) return;
    await _plannedSessionRepo.updatePlannedSession(
      w.sessionId,
      notes: notes.isEmpty ? null : notes,
    );
    final updated = _withEditedWorkout(w, notes: notes.isEmpty ? null : notes);
    state.value = state.value.copyWith(
      editingWorkout: updated,
      workoutUnsavedChanges: _workoutStillDirty(updated),
    );
  }

  Future<void> commitWorkoutDayOfWeek(int? v) async {
    final w = state.value.editingWorkout;
    if (w == null || isStandaloneMode) {
      return; // standalone workouts have no weekday
    }
    state.value = v == null
        ? state.value.copyWith(clearWorkoutDayOfWeekDraft: true)
        : state.value.copyWith(workoutDayOfWeekDraft: v);
    await _plannedSessionRepo.updatePlannedSession(
      w.sessionId,
      dayOfWeek: v,
      clearDayOfWeek: v == null,
    );
  }

  // ── Exercise tabs ─────────────────────────────────────────────────────────

  /// If [exerciseId] already has a tab, just switches to it — mirrors
  /// `SessionViewModel.addExerciseSlot`'s duplicate-prevention.
  void addPlannedExerciseGroup(String exerciseId) {
    final s = state.value;
    final existingIndex = s.workoutExerciseSlots.indexWhere(
      (slot) => slot.exerciseId == exerciseId,
    );
    if (existingIndex != -1) {
      state.value = s.copyWith(activeSlotIndex: existingIndex);
      return;
    }
    final nextOrder = s.workoutExerciseSlots.isEmpty
        ? 1
        : s.workoutExerciseSlots
                  .map((sl) => sl.exerciseSequenceOrder)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    final slots = [
      ...s.workoutExerciseSlots,
      PlanExerciseSlot(
        exerciseSequenceOrder: nextOrder,
        exerciseId: exerciseId,
      ),
    ];
    // The new group gets one virtual draft row — its entry row, persisted on
    // input or on explicit Save (never as a silent keep-alive stub).
    final drafts = Map<int, List<int>>.from(s.workoutSetDrafts);
    drafts.putIfAbsent(nextOrder, () => []).add(_nextDraftId++);
    state.value = s.copyWith(
      workoutExerciseSlots: slots,
      workoutSetDrafts: drafts,
      activeSlotIndex: slots.length - 1,
      workoutUnsavedChanges: true,
    );
    loadLessonsFor(exerciseId);
  }

  /// Removes the exercise slot at [index] from the editing workout and deletes
  /// all of its planned sets from the DB.  Active-index is clamped so the tab
  /// bar never points past the new end.
  Future<void> removePlannedExerciseGroup(int index) async {
    final s = state.value;
    final workout = s.editingWorkout;
    if (workout == null ||
        index < 0 ||
        index >= s.workoutExerciseSlots.length) {
      return;
    }
    final slot = s.workoutExerciseSlots[index];
    final order = slot.exerciseSequenceOrder;

    // Delete every planned set with this exercise's sequence order
    final setsToDelete = s.workoutPlannedSessionSets
        .where((ps) => ps.exerciseSequenceOrder == order)
        .toList();
    for (final ps in setsToDelete) {
      await _plannedSessionRepo.deletePlannedSet(ps.setId);
    }

    // Remove the slot and clamp active index
    final slots = [...s.workoutExerciseSlots]..removeAt(index);
    int newActive = s.activeSlotIndex;
    if (newActive >= slots.length) {
      newActive = (slots.length - 1).clamp(0, slots.length);
    }

    // Re-fetch sets so the UI reflects the deletion
    final plannedSets = _setsFromSessionSets(
      await _plannedSessionRepo.fetchPlannedSets(workout.sessionId),
    );

    state.value = s.copyWith(
      workoutExerciseSlots: slots,
      activeSlotIndex: newActive,
      workoutPlannedSessionSets: plannedSets,
      workoutUnsavedChanges: true,
    );
  }

  void tapTab(int index) =>
      state.value = state.value.copyWith(activeSlotIndex: index);

  Future<void> reorderExercises(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex || state.value.editingWorkout == null) return;
    final s = state.value;
    final slots = [...s.workoutExerciseSlots];
    final slot = slots.removeAt(oldIndex);
    slots.insert(newIndex, slot);
    int newActive = s.activeSlotIndex;
    if (s.activeSlotIndex == oldIndex) {
      newActive = newIndex;
    } else if (oldIndex < s.activeSlotIndex && newIndex >= s.activeSlotIndex) {
      newActive = s.activeSlotIndex - 1;
    } else if (oldIndex > s.activeSlotIndex && newIndex <= s.activeSlotIndex) {
      newActive = s.activeSlotIndex + 1;
    }
    // Renumber every slot's sequence order 1..N in the new list order —
    // pair-swapping only survives adjacent moves, and a non-adjacent drag
    // would otherwise persist a different order than the one shown.
    final renumbered = [
      for (var i = 0; i < slots.length; i++)
        PlanExerciseSlot(
          exerciseSequenceOrder: i + 1,
          exerciseId: slots[i].exerciseId,
        ),
    ];
    state.value = s.copyWith(
      workoutExerciseSlots: renumbered,
      activeSlotIndex: newActive,
    );
    final wid = s.editingWorkout!.sessionId;
    await _plannedSessionRepo.renumberSetExerciseOrders(wid, [
      for (var i = 0; i < slots.length; i++)
        (slots[i].exerciseSequenceOrder, i),
    ]);
    final sets = await _plannedSessionRepo.fetchPlannedSets(wid);
    state.value = state.value.copyWith(
      workoutPlannedSessionSets: _setsFromSessionSets(sets),
    );
  }

  // ── Draft (unsaved) planned-set rows ──────────────────────────────────────

  /// Persists an empty planned set row so an exercise added to a planned
  /// workout survives a save/reopen even before any target is entered.
  Future<void> _persistEmptyPlannedSessionSet(
    String exerciseId,
    int exerciseSequenceOrder,
  ) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    final existing = state.value.plannedSetsFor(exerciseSequenceOrder);
    final setNumber = existing.isEmpty
        ? 1
        : existing.map((ps) => ps.setNumber).reduce((a, b) => a > b ? a : b) +
              1;
    try {
      await _plannedSessionRepo.createPlannedSet(
        _userId,
        workout.sessionId,
        exerciseId: exerciseId,
        exerciseName: state.value.exerciseDetailMap[exerciseId]?.name,
        exerciseSequenceOrder: exerciseSequenceOrder,
        setNumber: setNumber,
      );
      final sets = await _plannedSessionRepo.fetchPlannedSets(
        workout.sessionId,
      );
      state.value = state.value.copyWith(
        workoutPlannedSessionSets: _setsFromSessionSets(sets),
      );
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  void addDraftPlannedSessionSet(int exerciseSequenceOrder) {
    // "+ ADD SET" adds a virtual draft row — visible immediately and a REAL
    // change (marks the editor dirty, so the guard prompts on back and the
    // Save button appears). The draft materializes as a row on input, or as
    // an empty row on explicit Save (empty sets are valid).
    final slot = state.value.workoutExerciseSlots
        .where((s) => s.exerciseSequenceOrder == exerciseSequenceOrder)
        .firstOrNull;
    if (slot == null) return;
    final drafts = Map<int, List<int>>.from(state.value.workoutSetDrafts);
    drafts.putIfAbsent(exerciseSequenceOrder, () => []).add(_nextDraftId++);
    state.value = state.value.copyWith(
      workoutSetDrafts: drafts,
      workoutUnsavedChanges: true,
    );
  }

  void removeDraftPlannedSessionSet(int exerciseSequenceOrder, int draftId) {
    final drafts = Map<int, List<int>>.from(state.value.workoutSetDrafts);
    drafts[exerciseSequenceOrder]?.remove(draftId);
    state.value = state.value.copyWith(
      workoutSetDrafts: drafts,
      workoutUnsavedChanges: true,
    );
  }

  Future<bool> quickCreatePlannedSessionSet({
    required String exerciseId,
    required int exerciseSequenceOrder,
    required int draftId,
    String? variationId,
    String? weight,
    String? reps,
    String? notes,
  }) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return false;
    // Empty planned sets are valid — a planned workout may list sets with no
    // target weight/reps yet (they show as blank rows, filled during the
    // session).
    final existing = state.value.plannedSetsFor(exerciseSequenceOrder);
    final setNumber = existing.isEmpty
        ? 1
        : existing.map((ps) => ps.setNumber).reduce((a, b) => a > b ? a : b) +
              1;
    try {
      await _plannedSessionRepo.createPlannedSet(
        _userId,
        workout.sessionId,
        exerciseId: exerciseId,
        exerciseName: state.value.exerciseDetailMap[exerciseId]?.name,
        variationId: variationId,
        variationName: _variationName(exerciseId, variationId),
        exerciseSequenceOrder: exerciseSequenceOrder,
        setNumber: setNumber,
        targetWeight: weight,
        targetReps: reps,
        targetNotes: notes,
      );
      removeDraftPlannedSessionSet(exerciseSequenceOrder, draftId);
      final sets = await _plannedSessionRepo.fetchPlannedSets(
        workout.sessionId,
      );
      state.value = state.value.copyWith(
        workoutPlannedSessionSets: _setsFromSessionSets(sets),
      );
      return true;
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
      return false;
    }
  }

  Future<void> quickUpdatePlannedSessionSet(
    PlannedSessionSet ps, {
    String? weight,
    bool clearWeight = false,
    String? reps,
    bool clearReps = false,
    String? variationId,
    bool clearVariation = false,
    String? notes,
    bool clearNotes = false,
  }) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    try {
      // variationId was previously accepted but never passed through —
      // assigning a variation to a planned set silently did nothing.
      await _plannedSessionRepo.updatePlannedSet(
        ps.setId,
        targetWeight: weight,
        clearWeight: clearWeight,
        targetReps: reps,
        clearReps: clearReps,
        variationId: variationId,
        clearVariation: clearVariation,
        variationName: variationId != null && !clearVariation
            ? _variationName(ps.exerciseId, variationId)
            : null,
        targetNotes: notes,
        clearNotes: clearNotes,
      );
      final sets = await _plannedSessionRepo.fetchPlannedSets(
        workout.sessionId,
      );
      state.value = state.value.copyWith(
        workoutPlannedSessionSets: _setsFromSessionSets(sets),
        workoutUnsavedChanges: true,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> duplicatePlannedSessionSet(PlannedSessionSet ps) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    final existing = state.value.plannedSetsFor(ps.exerciseSequenceOrder);
    final setNumber =
        existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    try {
      await _plannedSessionRepo.createPlannedSet(
        _userId,
        workout.sessionId,
        exerciseId: ps.exerciseId,
        exerciseName:
            ps.exerciseName ??
            state.value.exerciseDetailMap[ps.exerciseId]?.name,
        variationId: ps.variationId,
        variationName:
            ps.variationName ?? _variationName(ps.exerciseId, ps.variationId),
        exerciseSequenceOrder: ps.exerciseSequenceOrder,
        setNumber: setNumber,
        targetWeight: ps.targetWeight,
        targetReps: ps.targetReps,
        targetNotes: ps.targetNotes,
      );
      final sets = await _plannedSessionRepo.fetchPlannedSets(
        workout.sessionId,
      );
      state.value = state.value.copyWith(
        workoutPlannedSessionSets: _setsFromSessionSets(sets),
        workoutUnsavedChanges: true,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> deletePlannedSessionSet(String setId) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    await _plannedSessionRepo.deletePlannedSet(setId);
    final sets = await _plannedSessionRepo.fetchPlannedSets(workout.sessionId);
    state.value = state.value.copyWith(
      workoutPlannedSessionSets: _setsFromSessionSets(sets),
      workoutUnsavedChanges: true,
    );
  }

  // ── New exercise / variation (mirrors SessionViewModel) ───────────────────

  List<({String id, String name, int exerciseCount})> findSimilarVariations(
    String name,
  ) {
    final results = <({String id, String name, int exerciseCount})>[];
    for (final v in state.value.allVariations) {
      if (isSimilarVariationName(name, v.name)) {
        results.add((
          id: v.variationId,
          name: v.name,
          exerciseCount:
              state.value.variationExerciseCounts[v.variationId] ?? 0,
        ));
      }
    }
    return results;
  }

  Future<void> _reloadCatalog() async {
    final map = await _exerciseRepo.fetchExerciseDetailMap(_userId);
    final variations = await _exerciseRepo.fetchVariations(_userId);
    final bridges = await _exerciseRepo.fetchBridges(_userId);
    final counts = <String, int>{};
    for (final b in bridges) {
      final varId = b['custom_variation_id'] as String;
      counts[varId] = (counts[varId] ?? 0) + 1;
    }
    state.value = state.value.copyWith(
      exerciseDetailMap: map,
      allVariations: variations,
      variationExerciseCounts: counts,
    );
  }

  Future<String?> submitNewExercise(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    state.value = state.value.copyWith(newExCreating: true);
    try {
      final existing = await _exerciseRepo.findExerciseByName(_userId, trimmed);
      String id;
      if (existing != null) {
        // Creating a name that matches an archived exercise restores it —
        // exercises are per-user, and a soft-deleted name must not block
        // re-creation (reactivating an active row is a no-op).
        await _exerciseRepo.reactivateExercise(existing.exerciseId);
        id = existing.exerciseId;
      } else {
        final exercise = await _exerciseRepo.createExercise(_userId, trimmed);
        id = exercise.exerciseId;
      }
      await _reloadCatalog();
      state.value = state.value.copyWith(newExCreating: false);
      return id;
    } catch (e) {
      state.value = state.value.copyWith(
        newExCreating: false,
        error: e.toString(),
      );
      return null;
    }
  }

  Future<String?> submitNewVariation(
    String name, {
    required String exerciseId,
    String? useExistingId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty && useExistingId == null) return null;
    state.value = state.value.copyWith(newVarCreating: true);
    try {
      String id;
      if (useExistingId != null) {
        id = useExistingId;
        final existing = state.value.allVariations
            .where((v) => v.variationId == useExistingId)
            .firstOrNull;
        if (existing != null) {
          // Reusing an archived variation must bring it back — the bridge
          // alone would point at a variation nothing displays.
          await _exerciseRepo.reactivateVariation(id);
        }
      } else {
        final existing = await _exerciseRepo.findVariationByName(
          _userId,
          trimmed,
        );
        if (existing != null) {
          // Creating a name that matches an archived variation restores it.
          await _exerciseRepo.reactivateVariation(existing.variationId);
          id = existing.variationId;
        } else {
          final variation = await _exerciseRepo.createVariation(
            _userId,
            trimmed,
          );
          id = variation.variationId;
        }
      }
      await _exerciseRepo.addBridge(_userId, exerciseId, id);
      await _reloadCatalog();
      state.value = state.value.copyWith(newVarCreating: false);
      return id;
    } catch (e) {
      state.value = state.value.copyWith(
        newVarCreating: false,
        error: e.toString(),
      );
      return null;
    }
  }

  // ── Lessons (per-exercise, cross-session — same fact_lesson data session uses) ──

  String? _variationName(String exerciseId, String? variationId) {
    if (variationId == null) return null;
    return state.value.exerciseDetailMap[exerciseId]?.assignedVariations
        .where((v) => v.variationId == variationId)
        .map((v) => v.name)
        .firstOrNull;
  }

  /// All active variations, most recently used first — the set-row picker
  /// order. Variations are shared across ALL of a user's exercises now.
  List<CustomVariation> get variationsByRecency {
    final last = <String, DateTime>{};
    for (final sessions in state.value.historyByExercise.values) {
      for (final session in sessions) {
        for (final s in session.sets) {
          final vid = s.variationId;
          if (vid != null &&
              (last[vid] == null || session.date.isAfter(last[vid]!))) {
            last[vid] = session.date;
          }
        }
      }
    }
    return CustomVariation.sortByLastUsed(state.value.allVariations, last);
  }

  List<Lesson> lessonsFor(String exerciseId) =>
      state.value.lessonsByExercise[exerciseId] ?? const [];

  Future<void> loadLessonsFor(String exerciseId) async {
    try {
      final lessons = await _lessonRepo.fetchLessons(_userId, exerciseId);
      debugPrint('lessons loadLessonsFor($exerciseId) → ${lessons.length}');
      final map = Map<String, List<Lesson>>.from(state.value.lessonsByExercise);
      map[exerciseId] = lessons;
      state.value = state.value.copyWith(lessonsByExercise: map);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> addLesson(String exerciseId, String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _lessonRepo.createLesson(_userId, exerciseId, text.trim());
      await loadLessonsFor(exerciseId);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> toggleLessonPin(String exerciseId, String lessonId) async {
    final lesson = lessonsFor(
      exerciseId,
    ).firstWhereOrNull((l) => l.lessonId == lessonId);
    if (lesson == null) return;
    try {
      await _lessonRepo.setPinned(
        _userId,
        exerciseId,
        lessonId,
        !lesson.pinned,
      );
      await loadLessonsFor(exerciseId);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> deleteLesson(String exerciseId, String lessonId) async {
    try {
      await _lessonRepo.deleteLesson(lessonId);
      await loadLessonsFor(exerciseId);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> updateLessonText(
    String exerciseId,
    String lessonId,
    String text,
  ) async {
    if (text.trim().isEmpty) return;
    try {
      await _lessonRepo.updateLesson(
        _userId,
        exerciseId,
        lessonId,
        text.trim(),
      );
      await loadLessonsFor(exerciseId);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  // ── History (read-only past sets, for reference while planning) ──────────

  List<ExerciseHistorySession> historyFor(String exerciseId) =>
      state.value.historyByExercise[exerciseId] ?? const [];

  Future<void> loadHistoryIfNeeded() async {
    if (state.value.pastSetsLoaded) return;
    try {
      final pastSets = await _sessionRepo.loadPastSetsTimeline(_userId);
      state.value = state.value.copyWith(
        historyByExercise: groupHistoryByExercise(pastSets),
        pastSetsLoaded: true,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  bool _disposed = false;

  void dispose() {
    _disposed = true;
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
