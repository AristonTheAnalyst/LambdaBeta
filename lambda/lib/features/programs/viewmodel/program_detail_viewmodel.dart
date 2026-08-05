import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/planned_set.dart';
import '../../../data/models/planned_workout.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_progress.dart';
import '../../../data/models/program_run.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/program_run_repository.dart';
import '../../../data/repositories/workout_repository.dart';
import '../../session/model/session_local_state.dart'
    show ExerciseHistorySession, groupHistoryByExercise, isSimilarVariationName;

/// One tab in the plan-workout screen — a single exercise within the
/// workout being planned. Unlike the session screen there's no superset
/// concept here (no schema support for grouping multiple exercises under
/// one planned "round"), so this is deliberately simpler than
/// `SessionExerciseSlot`: one exercise per slot, always.
class PlanExerciseSlot {
  const PlanExerciseSlot({required this.exerciseSequenceOrder, required this.exerciseId});
  final int exerciseSequenceOrder;
  final String exerciseId;
}

class ProgramDetailState {
  const ProgramDetailState({
    this.isLoading = false,
    this.isSaving = false,
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
    this.workoutPlannedSets = const [],
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
    // Lessons (per-exercise, cross-session — reuses fact_lesson as-is)
    this.lessonsByExercise = const {},
    // History (read-only past-sets, reuses the session's read path as-is)
    this.historyByExercise = const {},
    this.pastSetsLoaded = false,
  });

  final bool isLoading;
  final bool isSaving;
  final String? error;
  final Program? program;
  final List<PlannedWorkout> plannedWorkouts;
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

  final PlannedWorkout? editingWorkout;
  final String workoutNameDraft;
  final String workoutNotesDraft;
  final int? workoutDayOfWeekDraft;
  final List<PlannedSet> workoutPlannedSets;
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

  bool get isCalendarMode => progressionModeDraft == 'calendar';

  PlanExerciseSlot? get activeSlot => workoutExerciseSlots.isEmpty
      ? null
      : workoutExerciseSlots[activeSlotIndex.clamp(0, workoutExerciseSlots.length - 1)];

  List<PlannedSet> plannedSetsFor(int exerciseSequenceOrder) =>
      workoutPlannedSets.where((ps) => ps.exerciseSequenceOrder == exerciseSequenceOrder).toList()
        ..sort((a, b) => a.setNumber.compareTo(b.setNumber));

  ProgramDetailState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? error,
    bool clearError = false,
    Program? program,
    List<PlannedWorkout>? plannedWorkouts,
    Map<String, ExerciseDetail>? exerciseDetailMap,
    bool? isCurrent,
    bool? settingCurrent,
    ProgramRun? activeRun,
    ProgramProgress? currentProgress,
    String? nameDraft,
    String? descriptionDraft,
    String? lengthWeeksDraft,
    String? progressionModeDraft,
    PlannedWorkout? editingWorkout,
    bool clearEditingWorkout = false,
    String? workoutNameDraft,
    String? workoutNotesDraft,
    int? workoutDayOfWeekDraft,
    bool clearWorkoutDayOfWeekDraft = false,
    List<PlannedSet>? workoutPlannedSets,
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
  }) =>
      ProgramDetailState(
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
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
        editingWorkout:
            clearEditingWorkout ? null : (editingWorkout ?? this.editingWorkout),
        workoutNameDraft: clearEditingWorkout
            ? ''
            : (workoutNameDraft ?? this.workoutNameDraft),
        workoutNotesDraft: clearEditingWorkout
            ? ''
            : (workoutNotesDraft ?? this.workoutNotesDraft),
        workoutDayOfWeekDraft: clearEditingWorkout || clearWorkoutDayOfWeekDraft
            ? null
            : (workoutDayOfWeekDraft ?? this.workoutDayOfWeekDraft),
        workoutPlannedSets: clearEditingWorkout
            ? const []
            : (workoutPlannedSets ?? this.workoutPlannedSets),
        workoutExerciseSlots: clearEditingWorkout
            ? const []
            : (workoutExerciseSlots ?? this.workoutExerciseSlots),
        activeSlotIndex: clearEditingWorkout ? 0 : (activeSlotIndex ?? this.activeSlotIndex),
        workoutSetDrafts: clearEditingWorkout
            ? const {}
            : (workoutSetDrafts ?? this.workoutSetDrafts),
        workoutSetsLoading:
            clearEditingWorkout ? false : (workoutSetsLoading ?? this.workoutSetsLoading),
        workoutUnsavedChanges: clearEditingWorkout
            ? false
            : (workoutUnsavedChanges ?? this.workoutUnsavedChanges),
        allVariations: allVariations ?? this.allVariations,
        variationExerciseCounts: variationExerciseCounts ?? this.variationExerciseCounts,
        newExCreating: newExCreating ?? this.newExCreating,
        newVarCreating: newVarCreating ?? this.newVarCreating,
        lessonsByExercise: lessonsByExercise ?? this.lessonsByExercise,
        historyByExercise: historyByExercise ?? this.historyByExercise,
        pastSetsLoaded: pastSetsLoaded ?? this.pastSetsLoaded,
      );
}

class ProgramDetailViewModel {
  ProgramDetailViewModel({
    ProgramRepository? repo,
    ProgramRunRepository? runRepo,
    ExerciseRepository? exerciseRepo,
    LessonRepository? lessonRepo,
    WorkoutRepository? workoutRepo,
  })  : _repo = repo ?? ProgramRepository(),
        _runRepo = runRepo ?? ProgramRunRepository(),
        _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
        _lessonRepo = lessonRepo ?? LessonRepository(),
        _workoutRepo = workoutRepo ?? WorkoutRepository();

  final ProgramRepository _repo;
  final ProgramRunRepository _runRepo;
  final ExerciseRepository _exerciseRepo;
  final LessonRepository _lessonRepo;
  final WorkoutRepository _workoutRepo;
  final state = ValueNotifier(const ProgramDetailState());

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  /// Creates a new program with only a progression mode (name/goals are set
  /// by the wizard's later steps) and returns its id, ready for [load].
  Future<String?> createNewProgram(String progressionMode) async {
    try {
      final created = await _repo.createProgram(_userId,
          name: 'New Program', progressionMode: progressionMode);
      return created.programId;
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
      return null;
    }
  }

  Future<void> load(String programId) async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _repo.fetchProgram(programId),
        _repo.fetchPlannedWorkouts(programId),
        _exerciseRepo.fetchExerciseDetailMap(_userId),
        _runRepo.getCurrentRun(_userId),
        _exerciseRepo.fetchVariations(_userId),
        _exerciseRepo.fetchBridges(_userId),
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
        plannedWorkouts: results[1] as List<PlannedWorkout>,
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
    } catch (e) {
      state.value = state.value.copyWith(isLoading: false, error: e.toString());
    }
  }

  // ── Program fields ───────────────────────────────────────────────────────

  void setNameDraft(String v) => state.value = state.value.copyWith(nameDraft: v);
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
      );
      final updated = await _repo.fetchProgram(s.program!.programId);
      state.value = state.value.copyWith(isSaving: false, program: updated);
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
    state.value = s.copyWith(settingCurrent: true, clearError: true);
    try {
      final run = await _runRepo.startProgramRun(_userId, s.program!.programId,
          targetSessions: targetSessions,
          targetWeeks: targetWeeks,
          endDate: endDate);
      if (_disposed) return;
      state.value = state.value.copyWith(
          settingCurrent: false, isCurrent: true, activeRun: run);
    } catch (e) {
      if (_disposed) return;
      state.value =
          state.value.copyWith(settingCurrent: false, error: e.toString());
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
      await _runRepo.updateRunConfig(run.programRunId,
          targetSessions: targetSessions,
          targetWeeks: targetWeeks,
          endDate: endDate,
          clearSessions: clearSessions,
          clearWeeks: clearWeeks,
          clearEndDate: clearEndDate);
      state.value = state.value.copyWith(clearError: true);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  // ── Planned workout editor (full screen) ─────────────────────────────────

  List<PlanExerciseSlot> _slotsFromSets(List<PlannedSet> sets) {
    final seen = <int>{};
    final slots = <PlanExerciseSlot>[];
    final sorted = [...sets]..sort((a, b) => a.exerciseSequenceOrder.compareTo(b.exerciseSequenceOrder));
    for (final ps in sorted) {
      if (seen.add(ps.exerciseSequenceOrder)) {
        slots.add(PlanExerciseSlot(exerciseSequenceOrder: ps.exerciseSequenceOrder, exerciseId: ps.exerciseId));
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
      final created = await _repo.createPlannedWorkout(
        _userId,
        programId,
        name: 'New Workout',
        sequenceOrder: state.value.plannedWorkouts.length + 1,
      );
      final workouts = await _repo.fetchPlannedWorkouts(programId);
      state.value = state.value.copyWith(
        plannedWorkouts: workouts,
        editingWorkout: created,
        workoutNameDraft: created.name,
        workoutNotesDraft: created.notes ?? '',
        clearWorkoutDayOfWeekDraft: true,
        workoutPlannedSets: const [],
        workoutExerciseSlots: const [],
        activeSlotIndex: 0,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> openEditWorkout(PlannedWorkout w) async {
    state.value = state.value.copyWith(
      editingWorkout: w,
      workoutNameDraft: w.name,
      workoutNotesDraft: w.notes ?? '',
      workoutDayOfWeekDraft: w.dayOfWeek,
      clearWorkoutDayOfWeekDraft: w.dayOfWeek == null,
      workoutSetsLoading: true,
    );
    try {
      final sets = await _repo.fetchPlannedSets(w.plannedWorkoutId);
      state.value = state.value.copyWith(
        workoutPlannedSets: sets,
        workoutExerciseSlots: _slotsFromSets(sets),
        activeSlotIndex: 0,
        workoutSetsLoading: false,
      );
      for (final slot in state.value.workoutExerciseSlots) {
        loadLessonsFor(slot.exerciseId);
      }
    } catch (e) {
      state.value =
          state.value.copyWith(workoutSetsLoading: false, error: e.toString());
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
          error: 'Add at least one exercise to this workout before saving.');
      return;
    }
    await Future.wait([
      commitWorkoutName(),
      commitWorkoutNotes(),
    ]);
    await _repo.fetchPlannedWorkouts(s.program?.programId ?? '');
    state.value = state.value.copyWith(workoutUnsavedChanges: false);
  }

  void closeWorkoutEditor() =>
      state.value = state.value.copyWith(clearEditingWorkout: true);

  Future<void> deleteWorkout() async {
    final w = state.value.editingWorkout;
    final programId = state.value.program?.programId;
    if (w == null || programId == null) return;
    closeWorkoutEditor();
    await _repo.archivePlannedWorkout(w.plannedWorkoutId);
    final workouts = await _repo.fetchPlannedWorkouts(programId);
    state.value = state.value.copyWith(plannedWorkouts: workouts);
  }

  Future<void> reorderWorkouts(
      List<PlannedWorkout> reordered, List<String> ids) async {
    state.value = state.value.copyWith(plannedWorkouts: reordered);
    await _repo.reorderPlannedWorkouts(ids);
  }

  // ── Workout name/notes/day-of-week — auto-commit on blur/change ─────────

  void setWorkoutNameDraft(String v) =>
      state.value = state.value.copyWith(workoutNameDraft: v, workoutUnsavedChanges: true);
  void setWorkoutNotesDraft(String v) =>
      state.value = state.value.copyWith(workoutNotesDraft: v, workoutUnsavedChanges: true);

  Future<void> commitWorkoutName() async {
    final w = state.value.editingWorkout;
    final name = state.value.workoutNameDraft.trim();
    if (w == null || name.isEmpty || name == w.name) return;
    await _repo.updatePlannedWorkout(w.plannedWorkoutId, name: name);
    final programId = state.value.program?.programId;
    if (programId != null) {
      final workouts = await _repo.fetchPlannedWorkouts(programId);
      state.value = state.value.copyWith(plannedWorkouts: workouts);
    }
  }

  Future<void> commitWorkoutNotes() async {
    final w = state.value.editingWorkout;
    if (w == null) return;
    final notes = state.value.workoutNotesDraft.trim();
    if (notes == (w.notes ?? '')) return;
    await _repo.updatePlannedWorkout(w.plannedWorkoutId,
        notes: notes.isEmpty ? null : notes);
  }

  Future<void> commitWorkoutDayOfWeek(int? v) async {
    final w = state.value.editingWorkout;
    if (w == null) return;
    state.value = v == null
        ? state.value.copyWith(clearWorkoutDayOfWeekDraft: true)
        : state.value.copyWith(workoutDayOfWeekDraft: v);
    await _repo.updatePlannedWorkout(w.plannedWorkoutId,
        dayOfWeek: v, clearDayOfWeek: v == null);
  }

  // ── Exercise tabs ─────────────────────────────────────────────────────────

  /// If [exerciseId] already has a tab, just switches to it — mirrors
  /// `SessionViewModel.addExerciseSlot`'s duplicate-prevention.
  void addPlannedExerciseGroup(String exerciseId) {
    final s = state.value;
    final existingIndex = s.workoutExerciseSlots.indexWhere((slot) => slot.exerciseId == exerciseId);
    if (existingIndex != -1) {
      state.value = s.copyWith(activeSlotIndex: existingIndex);
      return;
    }
    final nextOrder = s.workoutExerciseSlots.isEmpty
        ? 1
        : s.workoutExerciseSlots.map((sl) => sl.exerciseSequenceOrder).reduce((a, b) => a > b ? a : b) + 1;
    final slots = [...s.workoutExerciseSlots, PlanExerciseSlot(exerciseSequenceOrder: nextOrder, exerciseId: exerciseId)];
    // No draft row — the persisted empty planned set (below) IS the first set
    // row, so adding a ghost would double it.
    state.value = s.copyWith(
      workoutExerciseSlots: slots,
      activeSlotIndex: slots.length - 1,
      workoutUnsavedChanges: true,
    );
    // Persist an empty planned set so the exercise survives a save/reopen —
    // slots are reconstructed from persisted sets, so an exercise with no
    // committed set would otherwise vanish.
    final workout = s.editingWorkout;
    if (workout != null) {
      _persistEmptyPlannedSet(exerciseId, nextOrder);
    }
    loadLessonsFor(exerciseId);
  }

  void tapTab(int index) => state.value = state.value.copyWith(activeSlotIndex: index);

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
    state.value = s.copyWith(workoutExerciseSlots: slots, activeSlotIndex: newActive);
    // Persist: swap exerciseSequenceOrder for both exercises' planned sets
    final orderA = slot.exerciseSequenceOrder;
    final orderB = s.workoutExerciseSlots[oldIndex == newActive ? oldIndex : newIndex].exerciseSequenceOrder;
    await _repo.swapPlannedExerciseOrders(s.editingWorkout!.plannedWorkoutId, orderA, orderB);
    final sets = await _repo.fetchPlannedSets(s.editingWorkout!.plannedWorkoutId);
    state.value = state.value.copyWith(workoutPlannedSets: sets);
  }

  // ── Draft (unsaved) planned-set rows ──────────────────────────────────────

  /// Persists an empty planned set row so an exercise added to a planned
  /// workout survives a save/reopen even before any target is entered.
  Future<void> _persistEmptyPlannedSet(String exerciseId, int exerciseSequenceOrder) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    final existing = state.value.plannedSetsFor(exerciseSequenceOrder);
    final setNumber = existing.isEmpty
        ? 1
        : existing.map((ps) => ps.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    try {
      await _repo.createPlannedSet(
        _userId,
        workout.plannedWorkoutId,
        exerciseId: exerciseId,
        exerciseName: state.value.exerciseDetailMap[exerciseId]?.name,
        exerciseSequenceOrder: exerciseSequenceOrder,
        setNumber: setNumber,
      );
      final sets = await _repo.fetchPlannedSets(workout.plannedWorkoutId);
      state.value = state.value.copyWith(workoutPlannedSets: sets);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  void addDraftPlannedSet(int exerciseSequenceOrder) {
    // Persist an empty planned set immediately so "+ ADD SET" rows survive a
    // save/reopen even when no target is entered. The set number is assigned
    // here; the caller's PlanSetRow fills weight/reps on commit.
    final slot = state.value.workoutExerciseSlots
        .where((s) => s.exerciseSequenceOrder == exerciseSequenceOrder)
        .firstOrNull;
    if (slot == null) return;
    _persistEmptyPlannedSet(slot.exerciseId, exerciseSequenceOrder);
  }

  void removeDraftPlannedSet(int exerciseSequenceOrder, int draftId) {
    final drafts = Map<int, List<int>>.from(state.value.workoutSetDrafts);
    drafts[exerciseSequenceOrder]?.remove(draftId);
    state.value = state.value.copyWith(workoutSetDrafts: drafts, workoutUnsavedChanges: true);
  }

  Future<bool> quickCreatePlannedSet({
    required String exerciseId,
    required int exerciseSequenceOrder,
    required int draftId,
    String? variationId,
    double? weight,
    required List<num> reps,
    required List<num> duration,
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
        : existing.map((ps) => ps.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    try {
      await _repo.createPlannedSet(
        _userId,
        workout.plannedWorkoutId,
        exerciseId: exerciseId,
        exerciseName: state.value.exerciseDetailMap[exerciseId]?.name,
        variationId: variationId,
        variationName: _variationName(exerciseId, variationId),
        exerciseSequenceOrder: exerciseSequenceOrder,
        setNumber: setNumber,
        targetWeight: weight,
        targetReps: reps,
        targetDuration: duration,
        targetNotes: notes,
      );
      removeDraftPlannedSet(exerciseSequenceOrder, draftId);
      final sets = await _repo.fetchPlannedSets(workout.plannedWorkoutId);
      state.value = state.value.copyWith(workoutPlannedSets: sets);
      return true;
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
      return false;
    }
  }

  Future<void> quickUpdatePlannedSet(
    PlannedSet ps, {
    double? weight,
    bool clearWeight = false,
    List<num>? reps,
    String? variationId,
    bool clearVariation = false,
    String? notes,
    bool clearNotes = false,
  }) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    try {
      await _repo.updatePlannedSet(
        ps.plannedSetId,
        targetWeight: weight,
        clearTargetWeight: clearWeight,
        targetReps: reps,
        variationId: variationId,
        variationName: variationId != null ? _variationName(ps.exerciseId, variationId) : null,
        clearVariation: clearVariation,
        targetNotes: notes,
        clearTargetNotes: clearNotes,
      );
      final sets = await _repo.fetchPlannedSets(workout.plannedWorkoutId);
      state.value = state.value.copyWith(workoutPlannedSets: sets, workoutUnsavedChanges: true);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> duplicatePlannedSet(PlannedSet ps) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    final existing = state.value.plannedSetsFor(ps.exerciseSequenceOrder);
    final setNumber = existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    try {
      await _repo.createPlannedSet(
        _userId,
        workout.plannedWorkoutId,
        exerciseId: ps.exerciseId,
        exerciseName: ps.exerciseName ?? state.value.exerciseDetailMap[ps.exerciseId]?.name,
        variationId: ps.variationId,
        variationName: ps.variationName ?? _variationName(ps.exerciseId, ps.variationId),
        exerciseSequenceOrder: ps.exerciseSequenceOrder,
        setNumber: setNumber,
        targetWeight: ps.targetWeight,
        targetReps: ps.targetReps,
        targetDuration: ps.targetDuration,
        targetNotes: ps.targetNotes,
      );
      final sets = await _repo.fetchPlannedSets(workout.plannedWorkoutId);
      state.value = state.value.copyWith(workoutPlannedSets: sets, workoutUnsavedChanges: true);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> deletePlannedSet(String plannedSetId) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    await _repo.archivePlannedSet(plannedSetId);
    final sets = await _repo.fetchPlannedSets(workout.plannedWorkoutId);
    state.value = state.value.copyWith(workoutPlannedSets: sets, workoutUnsavedChanges: true);
  }

  // ── New exercise / variation (mirrors SessionViewModel) ───────────────────

  List<({String id, String name, int exerciseCount})> findSimilarVariations(String name) {
    final results = <({String id, String name, int exerciseCount})>[];
    for (final v in state.value.allVariations) {
      if (isSimilarVariationName(name, v.name)) {
        results.add((id: v.variationId, name: v.name, exerciseCount: state.value.variationExerciseCounts[v.variationId] ?? 0));
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
        if (existing.isActive) {
          state.value = state.value.copyWith(newExCreating: false, error: '"$trimmed" already exists.');
          return null;
        }
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
      state.value = state.value.copyWith(newExCreating: false, error: e.toString());
      return null;
    }
  }

  Future<String?> submitNewVariation(String name, {required String exerciseId, String? useExistingId}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty && useExistingId == null) return null;
    state.value = state.value.copyWith(newVarCreating: true);
    try {
      String id;
      if (useExistingId != null) {
        id = useExistingId;
        final existing = state.value.allVariations.where((v) => v.variationId == useExistingId).firstOrNull;
        if (existing != null && !existing.isActive) {
          await _exerciseRepo.reactivateVariation(id);
        }
      } else {
        final existing = await _exerciseRepo.findVariationByName(_userId, trimmed);
        if (existing != null) {
          if (!existing.isActive) await _exerciseRepo.reactivateVariation(existing.variationId);
          id = existing.variationId;
        } else {
          final variation = await _exerciseRepo.createVariation(_userId, trimmed);
          id = variation.variationId;
        }
      }
      await _exerciseRepo.addBridge(_userId, exerciseId, id);
      await _reloadCatalog();
      state.value = state.value.copyWith(newVarCreating: false);
      return id;
    } catch (e) {
      state.value = state.value.copyWith(newVarCreating: false, error: e.toString());
      return null;
    }
  }

  // ── Lessons (per-exercise, cross-session — same fact_lesson data session uses) ──

  String? _variationName(String exerciseId, String? variationId) {
    if (variationId == null) return null;
    return state.value.exerciseDetailMap[exerciseId]
        ?.assignedVariations
        .where((v) => v.variationId == variationId)
        .map((v) => v.name)
        .firstOrNull;
  }

  List<Lesson> lessonsFor(String exerciseId) => state.value.lessonsByExercise[exerciseId] ?? const [];

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
    final lesson = lessonsFor(exerciseId).firstWhereOrNull((l) => l.lessonId == lessonId);
    if (lesson == null) return;
    try {
      await _lessonRepo.setPinned(_userId, exerciseId, lessonId, !lesson.pinned);
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

  // ── History (read-only past sets, for reference while planning) ──────────

  List<ExerciseHistorySession> historyFor(String exerciseId) =>
      state.value.historyByExercise[exerciseId] ?? const [];

  Future<void> loadHistoryIfNeeded() async {
    if (state.value.pastSetsLoaded) return;
    try {
      final pastSets = await _workoutRepo.loadPastSetsTimeline(_userId);
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
