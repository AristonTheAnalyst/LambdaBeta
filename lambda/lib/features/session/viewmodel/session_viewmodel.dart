import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/workout_format.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/workout_set.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/workout_repository.dart';
import '../../../shared/widgets/slide_pages.dart';

class SessionViewModel extends ChangeNotifier {
  SessionViewModel({
    WorkoutRepository? workoutRepo,
    ExerciseRepository? exerciseRepo,
  })  : _workoutRepo = workoutRepo ?? WorkoutRepository(),
        _exerciseRepo = exerciseRepo ?? ExerciseRepository() {
    slidePagesController = SlidePagesController();
    _init();
  }

  final WorkoutRepository _workoutRepo;
  final ExerciseRepository _exerciseRepo;
  late final SlidePagesController slidePagesController;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  // ── Workout state ──────────────────────────────────────────────────────────
  String? currentWorkoutId;
  List<WorkoutSet> sets = [];
  bool setsLoading = false;

  // ── Exercise catalog ───────────────────────────────────────────────────────
  bool catalogLoading = false;
  List<ExerciseDetail> get exercises =>
      exerciseDetailMap.values.toList();
  Map<String, ExerciseDetail> exerciseDetailMap = {};

  // ── View mode ──────────────────────────────────────────────────────────────
  String viewMode = 'grouped';

  // ── Start workout form ─────────────────────────────────────────────────────
  String startNotes = '';
  int? sessionFeeling;
  bool startLoading = false;

  // ── End workout ────────────────────────────────────────────────────────────
  String endNotes = '';
  bool endLoading = false;

  // ── Log set form ───────────────────────────────────────────────────────────
  String? selectedExId;
  String? selectedVarId;
  String logWeight = '';
  String logRepsOrDuration = '';
  String logVolumeType = 'reps'; // 'reps' | 'duration' — chosen per set
  String logNotes = '';
  bool logLoading = false;

  // ── Edit set form ──────────────────────────────────────────────────────────
  WorkoutSet? editingSet;
  String? editExId;
  String? editVarId;
  String editWeight = '';
  String editRepsOrDuration = '';
  String editVolumeType = 'reps';
  String editNotes = '';
  bool editLoading = false;

  // ── New exercise ───────────────────────────────────────────────────────────
  String newExName = '';
  bool newExCreating = false;
  bool _newExForLog = true; // true=log form, false=edit form

  // ── New variation / assign ─────────────────────────────────────────────────
  String newVarName = '';
  bool newVarCreating = false;
  bool _newVarForLog = true;

  // ── Error ──────────────────────────────────────────────────────────────────
  String? error;

  // ── Derived ───────────────────────────────────────────────────────────────
  ExerciseDetail? get selectedExDetail =>
      selectedExId != null ? exerciseDetailMap[selectedExId] : null;

  ExerciseDetail? get editExDetail =>
      editExId != null ? exerciseDetailMap[editExId] : null;

  bool get hasActiveWorkout => currentWorkoutId != null;

  Future<void> _init() async {
    await _loadCatalog();
    await _restoreActiveWorkout();
  }

  Future<void> _loadCatalog() async {
    catalogLoading = true;
    notifyListeners();
    try {
      exerciseDetailMap = await _exerciseRepo.fetchExerciseDetailMap(_userId);
    } catch (_) {}
    catalogLoading = false;
    notifyListeners();
  }

  Future<void> _restoreActiveWorkout() async {
    final activeId = await _workoutRepo.getActiveWorkoutId(_userId);
    if (activeId != null) {
      currentWorkoutId = activeId;
      slidePagesController.resetToPage(1);
      await _loadSets();
    }
  }

  Future<void> _loadSets() async {
    if (currentWorkoutId == null) return;
    setsLoading = true;
    notifyListeners();
    sets = await _workoutRepo.loadSetsForWorkout(currentWorkoutId!);
    setsLoading = false;
    notifyListeners();
  }

  // ── Start workout ──────────────────────────────────────────────────────────

  Future<void> startWorkout() async {
    startLoading = true;
    error = null;
    notifyListeners();
    try {
      final id = await _workoutRepo.createWorkout(
          _userId,
          preNotes: startNotes.trim().isEmpty ? null : startNotes.trim());
      currentWorkoutId = id;
      sets = [];
      startNotes = '';
      sessionFeeling = null;
      slidePagesController.slideIn();
    } catch (e) {
      error = e.toString();
    }
    startLoading = false;
    notifyListeners();
  }

  // ── End workout ────────────────────────────────────────────────────────────

  Future<void> endWorkout() async {
    if (currentWorkoutId == null) return;
    endLoading = true;
    notifyListeners();
    try {
      await _workoutRepo.endWorkout(
          currentWorkoutId!,
          postNotes: endNotes.trim().isEmpty ? null : endNotes.trim());
      currentWorkoutId = null;
      sets = [];
      endNotes = '';
      slidePagesController.slideOut();
    } catch (e) {
      error = e.toString();
    }
    endLoading = false;
    notifyListeners();
  }

  Future<void> cancelWorkout() async {
    if (currentWorkoutId == null) return;
    final id = currentWorkoutId!;
    currentWorkoutId = null;
    sets = [];
    slidePagesController.slideOut();
    notifyListeners();
    await _workoutRepo.cancelWorkout(id);
  }

  // ── Log set ────────────────────────────────────────────────────────────────

  void selectExercise(String? exId) {
    selectedExId = exId;
    selectedVarId = null;
    logWeight = '';
    logRepsOrDuration = '';
    logVolumeType = 'reps';
    notifyListeners();
  }

  void selectVariation(String? varId) {
    selectedVarId = varId;
    notifyListeners();
  }

  void setLogVolumeType(String v) {
    logVolumeType = v;
    notifyListeners();
  }

  /// Prefills weight/variation/volume-type from the most recently logged set
  /// for this exercise, so the user isn't re-entering the same values every
  /// time. Guards against a stale result landing after the user has already
  /// moved on to a different exercise.
  Future<void> prefillLastUsedForLog(String exerciseId) async {
    final last = await _workoutRepo.findLastSetForExercise(_userId, exerciseId);
    if (last == null || selectedExId != exerciseId) return;
    selectedVarId = last.variationId;
    logWeight = last.weight != null ? '${last.weight}' : '';
    logVolumeType = last.duration.isNotEmpty ? 'duration' : 'reps';
    notifyListeners();
  }

  Future<bool> submitLogSet() async {
    final detail = selectedExDetail;
    if (currentWorkoutId == null || selectedExId == null || detail == null) {
      return false;
    }
    final values = parseValues(logRepsOrDuration);
    if (values.isEmpty) {
      error = logVolumeType == 'reps'
          ? 'Enter reps to log this set.'
          : 'Enter a duration to log this set.';
      notifyListeners();
      return false;
    }

    final isReps = logVolumeType == 'reps';
    final nextNum = sets.isEmpty
        ? 1
        : sets.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;

    logLoading = true;
    notifyListeners();
    try {
      await _workoutRepo.insertSet(
        workoutId: currentWorkoutId!,
        exerciseId: selectedExId!,
        variationId: selectedVarId,
        setNumber: nextNum,
        weight: double.tryParse(logWeight),
        reps: isReps ? values : [],
        duration: isReps ? [] : values,
        notes: logNotes.trim().isEmpty ? null : logNotes.trim(),
      );
      // Clear log form
      selectedExId = null;
      selectedVarId = null;
      logWeight = '';
      logRepsOrDuration = '';
      logNotes = '';
      logLoading = false;
      notifyListeners();
      await _loadSets();
      return true;
    } catch (e) {
      error = e.toString();
      logLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ── Edit set ───────────────────────────────────────────────────────────────

  void openEditSet(WorkoutSet s) {
    editingSet = s;
    editExId = s.exerciseId;
    editVarId = s.variationId;
    editWeight = s.weight != null ? '${s.weight}' : '';
    final vals = s.reps.isNotEmpty ? s.reps : s.duration;
    editRepsOrDuration = vals.join(',');
    editVolumeType = s.duration.isNotEmpty ? 'duration' : 'reps';
    editNotes = s.notes ?? '';
    notifyListeners();
  }

  void clearEditSet() {
    editingSet = null;
    editExId = null;
    editVarId = null;
    editWeight = '';
    editRepsOrDuration = '';
    editVolumeType = 'reps';
    editNotes = '';
    notifyListeners();
  }

  void setEditVolumeType(String v) {
    editVolumeType = v;
    notifyListeners();
  }

  /// Same as [prefillLastUsedForLog], for the edit form.
  Future<void> prefillLastUsedForEdit(String exerciseId) async {
    final last = await _workoutRepo.findLastSetForExercise(_userId, exerciseId);
    if (last == null || editExId != exerciseId) return;
    editVarId = last.variationId;
    editWeight = last.weight != null ? '${last.weight}' : '';
    editVolumeType = last.duration.isNotEmpty ? 'duration' : 'reps';
    notifyListeners();
  }

  Future<bool> submitEditSet() async {
    final detail = editExDetail;
    if (editingSet == null || editExId == null || detail == null) return false;
    final values = parseValues(editRepsOrDuration);
    if (values.isEmpty) {
      error = editVolumeType == 'reps'
          ? 'Enter reps to log this set.'
          : 'Enter a duration to log this set.';
      notifyListeners();
      return false;
    }

    final isReps = editVolumeType == 'reps';
    editLoading = true;
    notifyListeners();
    try {
      await _workoutRepo.updateSet(
        editingSet!.setId,
        exerciseId: editExId,
        variationId: editVarId,
        clearVariation: editVarId == null,
        weight: double.tryParse(editWeight),
        clearWeight: editWeight.isEmpty,
        reps: isReps ? values : [],
        duration: isReps ? [] : values,
        notes: editNotes.trim().isEmpty ? null : editNotes.trim(),
        clearNotes: editNotes.trim().isEmpty,
      );
      editLoading = false;
      clearEditSet();
      await _loadSets();
      return true;
    } catch (e) {
      error = e.toString();
      editLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> deleteSet(String setId) async {
    clearEditSet();
    await _workoutRepo.deleteSet(setId);
    await _loadSets();
  }

  Future<void> reorderSets(
      List<WorkoutSet> reordered, List<String> ids) async {
    sets = reordered;
    notifyListeners();
    if (currentWorkoutId != null) {
      await _workoutRepo.reorderSets(currentWorkoutId!, ids);
    }
  }

  // ── New exercise ───────────────────────────────────────────────────────────

  void prepareNewExercise({required bool forLog}) {
    _newExForLog = forLog;
    newExName = '';
    notifyListeners();
  }

  Future<String?> submitNewExercise() async {
    final name = newExName.trim();
    if (name.isEmpty) return null;
    newExCreating = true;
    notifyListeners();
    try {
      final existing = await _exerciseRepo.findExerciseByName(_userId, name);
      String id;
      if (existing != null) {
        if (existing.isActive) {
          error = '"$name" already exists.';
          newExCreating = false;
          notifyListeners();
          return null;
        }
        await _exerciseRepo.reactivateExercise(existing.exerciseId);
        id = existing.exerciseId;
      } else {
        final exercise = await _exerciseRepo.createExercise(_userId, name);
        id = exercise.exerciseId;
      }
      await _loadCatalog();
      newExCreating = false;
      if (_newExForLog) {
        selectExercise(id);
      } else {
        editExId = id;
        editVarId = null;
      }
      notifyListeners();
      return id;
    } catch (e) {
      error = e.toString();
      newExCreating = false;
      notifyListeners();
      return null;
    }
  }

  // ── New variation ──────────────────────────────────────────────────────────

  void prepareNewVariation({required bool forLog}) {
    _newVarForLog = forLog;
    newVarName = '';
    notifyListeners();
  }

  Future<String?> submitNewVariation() async {
    final name = newVarName.trim();
    if (name.isEmpty) return null;
    final exId = _newVarForLog ? selectedExId : editExId;
    if (exId == null) return null;

    newVarCreating = true;
    notifyListeners();
    try {
      final existing = await _exerciseRepo.findVariationByName(_userId, name);
      String id;
      if (existing != null) {
        if (existing.isActive) {
          error = '"$name" already exists.';
          newVarCreating = false;
          notifyListeners();
          return null;
        }
        await _exerciseRepo.reactivateVariation(existing.variationId);
        id = existing.variationId;
      } else {
        final variation = await _exerciseRepo.createVariation(_userId, name);
        id = variation.variationId;
      }
      await _exerciseRepo.addBridge(_userId, exId, id);
      await _loadCatalog();
      newVarCreating = false;
      if (_newVarForLog) {
        selectedVarId = id;
      } else {
        editVarId = id;
      }
      notifyListeners();
      return id;
    } catch (e) {
      error = e.toString();
      newVarCreating = false;
      notifyListeners();
      return null;
    }
  }

  void setSessionFeeling(int? n) {
    sessionFeeling = sessionFeeling == n ? null : n;
    notifyListeners();
  }

  void toggleViewMode() {
    viewMode = viewMode == 'grouped' ? 'chrono' : 'grouped';
    notifyListeners();
  }

  void setEditExId(String? id) {
    editExId = id;
    editVarId = null;
    editVolumeType = 'reps';
    notifyListeners();
  }

  void setEditVarId(String? id) {
    editVarId = id;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    slidePagesController.dispose();
    super.dispose();
  }
}
