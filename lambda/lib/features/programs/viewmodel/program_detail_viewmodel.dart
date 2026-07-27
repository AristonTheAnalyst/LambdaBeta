import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/workout_format.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/planned_set.dart';
import '../../../data/models/planned_workout.dart';
import '../../../data/models/program.dart';
import '../../../data/models/program_run.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/program_run_repository.dart';

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
    // Program field drafts
    this.nameDraft = '',
    this.descriptionDraft = '',
    this.lengthWeeksDraft = '',
    this.progressionModeDraft = 'sequential',
    // Planned workout editor sheet
    this.editingWorkout,
    this.workoutNameDraft = '',
    this.workoutNotesDraft = '',
    this.workoutDayOfWeekDraft,
    this.workoutPlannedSets = const [],
    this.workoutSetsLoading = false,
    this.workoutSaving = false,
    // Planned set form (nested inside the workout editor sheet)
    this.editingSet,
    this.setExId,
    this.setVarId,
    this.setWeightDraft = '',
    this.setRepsDraft = '',
    this.setVolumeType = 'reps',
    this.setNotesDraft = '',
    this.setSaving = false,
  });

  final bool isLoading;
  final bool isSaving;
  final String? error;
  final Program? program;
  final List<PlannedWorkout> plannedWorkouts;
  final Map<String, ExerciseDetail> exerciseDetailMap;
  final bool isCurrent;
  final bool settingCurrent;

  final String nameDraft;
  final String descriptionDraft;
  final String lengthWeeksDraft;
  final String progressionModeDraft;

  final PlannedWorkout? editingWorkout;
  final String workoutNameDraft;
  final String workoutNotesDraft;
  final int? workoutDayOfWeekDraft;
  final List<PlannedSet> workoutPlannedSets;
  final bool workoutSetsLoading;
  final bool workoutSaving;

  final PlannedSet? editingSet;
  final String? setExId;
  final String? setVarId;
  final String setWeightDraft;
  final String setRepsDraft;
  final String setVolumeType; // 'reps' | 'duration'
  final String setNotesDraft;
  final bool setSaving;

  bool get isCalendarMode => progressionModeDraft == 'calendar';

  ExerciseDetail? get setExDetail =>
      setExId != null ? exerciseDetailMap[setExId] : null;

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
    bool? workoutSetsLoading,
    bool? workoutSaving,
    PlannedSet? editingSet,
    bool clearEditingSet = false,
    String? setExId,
    bool clearSetExId = false,
    String? setVarId,
    bool clearSetVarId = false,
    String? setWeightDraft,
    String? setRepsDraft,
    String? setVolumeType,
    String? setNotesDraft,
    bool? setSaving,
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
        workoutSetsLoading:
            clearEditingWorkout ? false : (workoutSetsLoading ?? this.workoutSetsLoading),
        workoutSaving: workoutSaving ?? this.workoutSaving,
        editingSet: clearEditingSet ? null : (editingSet ?? this.editingSet),
        setExId: clearEditingSet || clearSetExId ? null : (setExId ?? this.setExId),
        setVarId: clearEditingSet || clearSetVarId ? null : (setVarId ?? this.setVarId),
        setWeightDraft: clearEditingSet ? '' : (setWeightDraft ?? this.setWeightDraft),
        setRepsDraft: clearEditingSet ? '' : (setRepsDraft ?? this.setRepsDraft),
        setVolumeType: clearEditingSet ? 'reps' : (setVolumeType ?? this.setVolumeType),
        setNotesDraft: clearEditingSet ? '' : (setNotesDraft ?? this.setNotesDraft),
        setSaving: setSaving ?? this.setSaving,
      );
}

class ProgramDetailViewModel {
  ProgramDetailViewModel({
    ProgramRepository? repo,
    ProgramRunRepository? runRepo,
    ExerciseRepository? exerciseRepo,
  })  : _repo = repo ?? ProgramRepository(),
        _runRepo = runRepo ?? ProgramRunRepository(),
        _exerciseRepo = exerciseRepo ?? ExerciseRepository();

  final ProgramRepository _repo;
  final ProgramRunRepository _runRepo;
  final ExerciseRepository _exerciseRepo;
  final state = ValueNotifier(const ProgramDetailState());

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  Future<void> load(String programId) async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _repo.fetchProgram(programId),
        _repo.fetchPlannedWorkouts(programId),
        _exerciseRepo.fetchExerciseDetailMap(_userId),
        _runRepo.getCurrentRun(_userId),
      ]);
      final program = results[0] as Program?;
      final currentRun = results[3] as ProgramRun?;
      state.value = state.value.copyWith(
        isLoading: false,
        program: program,
        plannedWorkouts: results[1] as List<PlannedWorkout>,
        exerciseDetailMap: results[2] as Map<String, ExerciseDetail>,
        nameDraft: program?.name ?? '',
        descriptionDraft: program?.description ?? '',
        lengthWeeksDraft: program?.lengthWeeks?.toString() ?? '',
        progressionModeDraft: program?.progressionMode ?? 'sequential',
        isCurrent: currentRun != null && currentRun.programId == programId,
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

  Future<void> setAsCurrent() async {
    final s = state.value;
    if (s.program == null) return;
    state.value = s.copyWith(settingCurrent: true, clearError: true);
    try {
      await _runRepo.startProgramRun(_userId, s.program!.programId);
      state.value = state.value.copyWith(settingCurrent: false, isCurrent: true);
    } catch (e) {
      state.value =
          state.value.copyWith(settingCurrent: false, error: e.toString());
    }
  }

  // ── Planned workout editor ───────────────────────────────────────────────

  void openCreateWorkout() => state.value = state.value.copyWith(
        clearEditingWorkout: true,
        workoutNameDraft: '',
        workoutNotesDraft: '',
      );

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
      state.value =
          state.value.copyWith(workoutPlannedSets: sets, workoutSetsLoading: false);
    } catch (e) {
      state.value =
          state.value.copyWith(workoutSetsLoading: false, error: e.toString());
    }
  }

  void closeWorkoutEditor() =>
      state.value = state.value.copyWith(clearEditingWorkout: true);

  void setWorkoutNameDraft(String v) =>
      state.value = state.value.copyWith(workoutNameDraft: v);
  void setWorkoutNotesDraft(String v) =>
      state.value = state.value.copyWith(workoutNotesDraft: v);
  void setWorkoutDayOfWeekDraft(int? v) => state.value = v == null
      ? state.value.copyWith(clearWorkoutDayOfWeekDraft: true)
      : state.value.copyWith(workoutDayOfWeekDraft: v);

  /// Creates the workout on first save, then keeps the sheet open (switched
  /// to edit mode) so the user can immediately start adding planned sets.
  /// Subsequent saves just update the existing row.
  Future<void> submitWorkoutEditor() async {
    final s = state.value;
    final programId = s.program?.programId;
    if (programId == null || s.workoutNameDraft.trim().isEmpty) return;
    state.value = s.copyWith(workoutSaving: true, clearError: true);
    try {
      if (s.editingWorkout == null) {
        final created = await _repo.createPlannedWorkout(
          _userId,
          programId,
          name: s.workoutNameDraft.trim(),
          notes: s.workoutNotesDraft.trim().isEmpty ? null : s.workoutNotesDraft.trim(),
          sequenceOrder: s.plannedWorkouts.length + 1,
          dayOfWeek: s.workoutDayOfWeekDraft,
        );
        state.value = state.value.copyWith(
          workoutSaving: false,
          editingWorkout: created,
        );
      } else {
        await _repo.updatePlannedWorkout(
          s.editingWorkout!.plannedWorkoutId,
          name: s.workoutNameDraft.trim(),
          notes: s.workoutNotesDraft.trim().isEmpty ? null : s.workoutNotesDraft.trim(),
          dayOfWeek: s.workoutDayOfWeekDraft,
          clearDayOfWeek: s.workoutDayOfWeekDraft == null,
        );
        state.value = state.value.copyWith(workoutSaving: false);
      }
      final workouts = await _repo.fetchPlannedWorkouts(programId);
      state.value = state.value.copyWith(plannedWorkouts: workouts);
    } catch (e) {
      state.value = state.value.copyWith(workoutSaving: false, error: e.toString());
    }
  }

  Future<void> archiveWorkout(String plannedWorkoutId) async {
    final programId = state.value.program?.programId;
    if (programId == null) return;
    if (state.value.editingWorkout?.plannedWorkoutId == plannedWorkoutId) {
      closeWorkoutEditor();
    }
    await _repo.archivePlannedWorkout(plannedWorkoutId);
    final workouts = await _repo.fetchPlannedWorkouts(programId);
    state.value = state.value.copyWith(plannedWorkouts: workouts);
  }

  Future<void> reorderWorkouts(
      List<PlannedWorkout> reordered, List<String> ids) async {
    state.value = state.value.copyWith(plannedWorkouts: reordered);
    await _repo.reorderPlannedWorkouts(ids);
  }

  // ── Planned set form (nested in workout editor) ──────────────────────────

  void openCreateSet() => state.value = state.value.copyWith(clearEditingSet: true);

  void openEditSet(PlannedSet ps) {
    final vals = ps.targetReps.isNotEmpty ? ps.targetReps : ps.targetDuration;
    state.value = state.value.copyWith(
      editingSet: ps,
      setExId: ps.exerciseId,
      setVarId: ps.variationId,
      clearSetVarId: ps.variationId == null,
      setWeightDraft: ps.targetWeight != null ? '${ps.targetWeight}' : '',
      setRepsDraft: vals.join(','),
      setVolumeType: ps.targetDuration.isNotEmpty ? 'duration' : 'reps',
      setNotesDraft: ps.targetNotes ?? '',
    );
  }

  void closeSetForm() => state.value = state.value.copyWith(clearEditingSet: true);

  void setSetExId(String? id) => state.value = id == null
      ? state.value.copyWith(clearSetExId: true, clearSetVarId: true)
      : state.value.copyWith(setExId: id, clearSetVarId: true);

  void setSetVarId(String? id) => state.value = id == null
      ? state.value.copyWith(clearSetVarId: true)
      : state.value.copyWith(setVarId: id);

  void setSetWeightDraft(String v) =>
      state.value = state.value.copyWith(setWeightDraft: v);
  void setSetRepsDraft(String v) =>
      state.value = state.value.copyWith(setRepsDraft: v);
  void setSetVolumeType(String v) =>
      state.value = state.value.copyWith(setVolumeType: v);
  void setSetNotesDraft(String v) =>
      state.value = state.value.copyWith(setNotesDraft: v);

  Future<bool> submitSetForm() async {
    final s = state.value;
    final workout = s.editingWorkout;
    final detail = s.setExDetail;
    if (workout == null || s.setExId == null || detail == null) return false;
    final values = parseValues(s.setRepsDraft);
    if (values.isEmpty) return false;

    final isReps = s.setVolumeType == 'reps';
    state.value = s.copyWith(setSaving: true, clearError: true);
    try {
      if (s.editingSet == null) {
        final existingForEx = s.workoutPlannedSets
            .where((ps) => ps.exerciseId == s.setExId)
            .toList();
        final exerciseSequenceOrder = existingForEx.isNotEmpty
            ? existingForEx.first.exerciseSequenceOrder
            : (s.workoutPlannedSets.isEmpty
                ? 1
                : s.workoutPlannedSets
                        .map((ps) => ps.exerciseSequenceOrder)
                        .reduce((a, b) => a > b ? a : b) +
                    1);
        final setNumber = s.workoutPlannedSets.isEmpty
            ? 1
            : s.workoutPlannedSets.map((ps) => ps.setNumber).reduce((a, b) => a > b ? a : b) +
                1;
        await _repo.createPlannedSet(
          _userId,
          workout.plannedWorkoutId,
          exerciseId: s.setExId!,
          variationId: s.setVarId,
          exerciseSequenceOrder: exerciseSequenceOrder,
          setNumber: setNumber,
          targetWeight: double.tryParse(s.setWeightDraft),
          targetReps: isReps ? values : [],
          targetDuration: isReps ? [] : values,
          targetNotes: s.setNotesDraft.trim().isEmpty ? null : s.setNotesDraft.trim(),
        );
      } else {
        await _repo.updatePlannedSet(
          s.editingSet!.plannedSetId,
          exerciseId: s.setExId,
          variationId: s.setVarId,
          clearVariation: s.setVarId == null,
          targetWeight: double.tryParse(s.setWeightDraft),
          clearTargetWeight: s.setWeightDraft.isEmpty,
          targetReps: isReps ? values : [],
          targetDuration: isReps ? [] : values,
          targetNotes: s.setNotesDraft.trim().isEmpty ? null : s.setNotesDraft.trim(),
          clearTargetNotes: s.setNotesDraft.trim().isEmpty,
        );
      }
      final sets = await _repo.fetchPlannedSets(workout.plannedWorkoutId);
      state.value = state.value.copyWith(
        setSaving: false,
        workoutPlannedSets: sets,
        clearEditingSet: true,
      );
      return true;
    } catch (e) {
      state.value = state.value.copyWith(setSaving: false, error: e.toString());
      return false;
    }
  }

  Future<void> deletePlannedSet(String plannedSetId) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    closeSetForm();
    await _repo.archivePlannedSet(plannedSetId);
    final sets = await _repo.fetchPlannedSets(workout.plannedWorkoutId);
    state.value = state.value.copyWith(workoutPlannedSets: sets);
  }

  Future<void> reorderPlannedSets(
      List<PlannedSet> reordered, List<String> ids) async {
    state.value = state.value.copyWith(workoutPlannedSets: reordered);
    await _repo.reorderPlannedSets(ids);
  }

  void dispose() => state.dispose();
}
