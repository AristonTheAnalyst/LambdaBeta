import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/workout_format.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/workout.dart';
import '../../../data/models/workout_set.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/workout_repository.dart';

class WorkoutDetailState {
  const WorkoutDetailState({
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    this.workout,
    this.sets = const [],
    this.exerciseDetailMap = const {},
    this.viewMode = 'grouped',
    this.isEditing = false,
    this.preNotesDraft = '',
    this.postNotesDraft = '',
    // Edit set form
    this.editingSet,
    this.editExId,
    this.editVarId,
    this.editWeight = '',
    this.editRepsOrDuration = '',
    this.editNotes = '',
    this.editLoading = false,
    // Log set form
    this.logSetVisible = false,
    this.selectedExId,
    this.selectedVarId,
    this.logWeight = '',
    this.logRepsOrDuration = '',
    this.logNotes = '',
    this.logLoading = false,
  });

  final bool isLoading;
  final bool isSaving;
  final String? error;
  final Workout? workout;
  final List<WorkoutSet> sets;
  final Map<String, ExerciseDetail> exerciseDetailMap;
  final String viewMode;
  final bool isEditing;
  final String preNotesDraft;
  final String postNotesDraft;

  final WorkoutSet? editingSet;
  final String? editExId;
  final String? editVarId;
  final String editWeight;
  final String editRepsOrDuration;
  final String editNotes;
  final bool editLoading;

  final bool logSetVisible;
  final String? selectedExId;
  final String? selectedVarId;
  final String logWeight;
  final String logRepsOrDuration;
  final String logNotes;
  final bool logLoading;

  List<String> get exerciseOptions => exerciseDetailMap.keys.toList();

  ExerciseDetail? get selectedExDetail =>
      selectedExId != null ? exerciseDetailMap[selectedExId] : null;

  ExerciseDetail? get editExDetail =>
      editExId != null ? exerciseDetailMap[editExId] : null;

  WorkoutDetailState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? error,
    bool clearError = false,
    Workout? workout,
    List<WorkoutSet>? sets,
    Map<String, ExerciseDetail>? exerciseDetailMap,
    String? viewMode,
    bool? isEditing,
    String? preNotesDraft,
    String? postNotesDraft,
    WorkoutSet? editingSet,
    bool clearEditingSet = false,
    String? editExId,
    bool clearEditExId = false,
    String? editVarId,
    bool clearEditVarId = false,
    String? editWeight,
    String? editRepsOrDuration,
    String? editNotes,
    bool? editLoading,
    bool? logSetVisible,
    String? selectedExId,
    bool clearSelectedExId = false,
    String? selectedVarId,
    bool clearSelectedVarId = false,
    String? logWeight,
    String? logRepsOrDuration,
    String? logNotes,
    bool? logLoading,
  }) =>
      WorkoutDetailState(
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        error: clearError ? null : error ?? this.error,
        workout: workout ?? this.workout,
        sets: sets ?? this.sets,
        exerciseDetailMap: exerciseDetailMap ?? this.exerciseDetailMap,
        viewMode: viewMode ?? this.viewMode,
        isEditing: isEditing ?? this.isEditing,
        preNotesDraft: preNotesDraft ?? this.preNotesDraft,
        postNotesDraft: postNotesDraft ?? this.postNotesDraft,
        editingSet: clearEditingSet ? null : (editingSet ?? this.editingSet),
        editExId: clearEditExId ? null : (editExId ?? this.editExId),
        editVarId: clearEditVarId ? null : (editVarId ?? this.editVarId),
        editWeight: editWeight ?? this.editWeight,
        editRepsOrDuration: editRepsOrDuration ?? this.editRepsOrDuration,
        editNotes: editNotes ?? this.editNotes,
        editLoading: editLoading ?? this.editLoading,
        logSetVisible: logSetVisible ?? this.logSetVisible,
        selectedExId: clearSelectedExId ? null : (selectedExId ?? this.selectedExId),
        selectedVarId: clearSelectedVarId ? null : (selectedVarId ?? this.selectedVarId),
        logWeight: logWeight ?? this.logWeight,
        logRepsOrDuration: logRepsOrDuration ?? this.logRepsOrDuration,
        logNotes: logNotes ?? this.logNotes,
        logLoading: logLoading ?? this.logLoading,
      );
}

class WorkoutDetailViewModel {
  WorkoutDetailViewModel({
    WorkoutRepository? workoutRepo,
    ExerciseRepository? exerciseRepo,
  })  : _workoutRepo = workoutRepo ?? WorkoutRepository(),
        _exerciseRepo = exerciseRepo ?? ExerciseRepository();

  final WorkoutRepository _workoutRepo;
  final ExerciseRepository _exerciseRepo;
  final state = ValueNotifier(const WorkoutDetailState());

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  Future<void> load(String workoutId) async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _workoutRepo.fetchWorkout(workoutId),
        _workoutRepo.loadSetsForWorkout(workoutId),
        _exerciseRepo.fetchExerciseDetailMap(_userId),
      ]);
      state.value = state.value.copyWith(
        isLoading: false,
        workout: results[0] as Workout?,
        sets: results[1] as List<WorkoutSet>,
        exerciseDetailMap:
            results[2] as Map<String, ExerciseDetail>,
      );
    } catch (e) {
      state.value =
          state.value.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> _reloadSets(String workoutId) async {
    final sets = await _workoutRepo.loadSetsForWorkout(workoutId);
    state.value = state.value.copyWith(sets: sets);
  }

  void toggleViewMode() {
    final next =
        state.value.viewMode == 'grouped' ? 'chrono' : 'grouped';
    state.value = state.value.copyWith(viewMode: next);
  }

  // ── Notes editing ──────────────────────────────────────────────────────────

  void startEditing() {
    final w = state.value.workout;
    state.value = state.value.copyWith(
      isEditing: true,
      preNotesDraft: w?.preNotes ?? '',
      postNotesDraft: w?.postNotes ?? '',
    );
  }

  void cancelEditing() =>
      state.value = state.value.copyWith(isEditing: false);

  void setPreNotesDraft(String v) =>
      state.value = state.value.copyWith(preNotesDraft: v);

  void setPostNotesDraft(String v) =>
      state.value = state.value.copyWith(postNotesDraft: v);

  Future<void> saveNotes(String workoutId) async {
    state.value = state.value.copyWith(isSaving: true);
    try {
      await _workoutRepo.endWorkout(
        workoutId,
        postNotes: state.value.postNotesDraft,
      );
      // Reload the workout to reflect saved notes
      final updated = await _workoutRepo.fetchWorkout(workoutId);
      state.value = state.value.copyWith(
          isSaving: false, isEditing: false, workout: updated);
    } catch (e) {
      state.value =
          state.value.copyWith(isSaving: false, error: e.toString());
    }
  }

  // ── Log set ────────────────────────────────────────────────────────────────

  void openLogSet() =>
      state.value = state.value.copyWith(logSetVisible: true);

  void closeLogSet() => state.value = state.value.copyWith(
        logSetVisible: false,
        clearSelectedExId: true,
        clearSelectedVarId: true,
        logWeight: '',
        logRepsOrDuration: '',
        logNotes: '',
      );

  void selectExercise(String? exId) {
    state.value = state.value.copyWith(
      clearSelectedExId: exId == null,
      selectedExId: exId,
      clearSelectedVarId: true,
      logWeight: '',
      logRepsOrDuration: '',
    );
  }

  void selectVariation(String? varId) => state.value = varId == null
      ? state.value.copyWith(clearSelectedVarId: true)
      : state.value.copyWith(selectedVarId: varId);

  void setLogWeight(String v) =>
      state.value = state.value.copyWith(logWeight: v);
  void setLogReps(String v) =>
      state.value = state.value.copyWith(logRepsOrDuration: v);
  void setLogNotes(String v) =>
      state.value = state.value.copyWith(logNotes: v);

  Future<bool> submitLogSet(String workoutId) async {
    final s = state.value;
    final detail = s.selectedExDetail;
    if (s.selectedExId == null || detail == null) return false;
    final values = parseValues(s.logRepsOrDuration);
    if (values.isEmpty) return false;

    final isReps = detail.volumeType == 'reps';
    final nextNum = s.sets.isEmpty
        ? 1
        : s.sets.map((x) => x.setNumber).reduce((a, b) => a > b ? a : b) + 1;

    state.value = s.copyWith(logLoading: true);
    try {
      await _workoutRepo.insertSet(
        workoutId: workoutId,
        exerciseId: s.selectedExId!,
        variationId: s.selectedVarId,
        setNumber: nextNum,
        weight: double.tryParse(s.logWeight),
        reps: isReps ? values : [],
        duration: isReps ? [] : values,
        notes: s.logNotes.trim().isEmpty ? null : s.logNotes.trim(),
      );
      state.value = state.value.copyWith(logLoading: false);
      WidgetsBinding.instance.addPostFrameCallback((_) => closeLogSet());
      await _reloadSets(workoutId);
      return true;
    } catch (e) {
      state.value = state.value.copyWith(
          logLoading: false, error: e.toString());
      return false;
    }
  }

  // ── Edit set ───────────────────────────────────────────────────────────────

  void openEditSet(WorkoutSet s) {
    final vals = s.reps.isNotEmpty ? s.reps : s.duration;
    state.value = state.value.copyWith(
      editingSet: s,
      editExId: s.exerciseId,
      editVarId: s.variationId,
      editWeight: s.weight != null ? '${s.weight}' : '',
      editRepsOrDuration: vals.join(','),
      editNotes: s.notes ?? '',
    );
  }

  void closeEditSet() => state.value = state.value.copyWith(
        clearEditingSet: true,
        clearEditExId: true,
        clearEditVarId: true,
        editWeight: '',
        editRepsOrDuration: '',
        editNotes: '',
      );

  void setEditExId(String? id) => state.value = id == null
      ? state.value.copyWith(clearEditExId: true, clearEditVarId: true)
      : state.value.copyWith(editExId: id, clearEditVarId: true);

  void setEditVarId(String? id) => state.value = id == null
      ? state.value.copyWith(clearEditVarId: true)
      : state.value.copyWith(editVarId: id);

  void setEditWeight(String v) =>
      state.value = state.value.copyWith(editWeight: v);
  void setEditReps(String v) =>
      state.value = state.value.copyWith(editRepsOrDuration: v);
  void setEditNotes(String v) =>
      state.value = state.value.copyWith(editNotes: v);

  Future<bool> submitEditSet(String workoutId) async {
    final s = state.value;
    final detail = s.editExDetail;
    if (s.editingSet == null || s.editExId == null || detail == null) {
      return false;
    }
    final values = parseValues(s.editRepsOrDuration);
    if (values.isEmpty) return false;

    final isReps = detail.volumeType == 'reps';
    state.value = s.copyWith(editLoading: true);
    try {
      await _workoutRepo.updateSet(
        s.editingSet!.setId,
        exerciseId: s.editExId,
        variationId: s.editVarId,
        clearVariation: s.editVarId == null,
        weight: double.tryParse(s.editWeight),
        clearWeight: s.editWeight.isEmpty,
        reps: isReps ? values : [],
        duration: isReps ? [] : values,
        notes: s.editNotes.trim().isEmpty ? null : s.editNotes.trim(),
        clearNotes: s.editNotes.trim().isEmpty,
      );
      closeEditSet();
      await _reloadSets(workoutId);
      return true;
    } catch (e) {
      state.value = state.value.copyWith(
          editLoading: false, error: e.toString());
      return false;
    }
  }

  Future<void> deleteSet(String setId, String workoutId) async {
    closeEditSet();
    await _workoutRepo.deleteSet(setId);
    await _reloadSets(workoutId);
  }

  Future<void> reorderSets(
      String workoutId, List<WorkoutSet> reordered, List<String> ids) async {
    state.value = state.value.copyWith(sets: reordered);
    await _workoutRepo.reorderSets(workoutId, ids);
  }

  void dispose() => state.dispose();
}
