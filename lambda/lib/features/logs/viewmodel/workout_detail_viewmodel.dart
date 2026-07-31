import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/workout.dart';
import '../../../data/models/workout_set.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/workout_repository.dart';
import '../../session/model/session_local_state.dart'
    show
        ExerciseHistorySession,
        groupHistoryByExercise,
        isSimilarVariationName,
        bestEverForExercise,
        isPr;

/// One tab in the workout-detail screen — a single exercise that was logged
/// in this workout.
class WorkoutDetailExerciseSlot {
  const WorkoutDetailExerciseSlot({required this.groupOrder, required this.exerciseId});
  final int groupOrder;
  final String exerciseId;
}

class WorkoutDetailState {
  const WorkoutDetailState({
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    this.workout,
    this.exerciseDetailMap = const {},
    this.isEditing = false,
    this.preNotesDraft = '',
    this.postNotesDraft = '',
    this.exerciseSlots = const [],
    this.activeSlotIndex = 0,
    this.setsByOrder = const {},
    this.workoutSetDrafts = const {},
    // Catalog / create-new
    this.allVariations = const [],
    this.variationExerciseCounts = const {},
    this.newExCreating = false,
    this.newVarCreating = false,
    // Lessons and history
    this.lessonsByExercise = const {},
    this.historyByExercise = const {},
    this.pastSetsLoaded = false,
    this.prsByExercise = const {},
    this.totalPRCount = 0,
  });

  final bool isLoading;
  final bool isSaving;
  final String? error;
  final Workout? workout;
  final Map<String, ExerciseDetail> exerciseDetailMap;
  final bool isEditing;
  final String preNotesDraft;
  final String postNotesDraft;

  final List<WorkoutDetailExerciseSlot> exerciseSlots;
  final int activeSlotIndex;
  final Map<int, List<WorkoutSet>> setsByOrder;
  final Map<int, List<int>> workoutSetDrafts;

  final List<CustomVariation> allVariations;
  final Map<String, int> variationExerciseCounts;
  final bool newExCreating;
  final bool newVarCreating;

  final Map<String, List<Lesson>> lessonsByExercise;
  final Map<String, List<ExerciseHistorySession>> historyByExercise;
  final bool pastSetsLoaded;
  final Map<String, int> prsByExercise;
  final int totalPRCount;

  WorkoutDetailExerciseSlot? get activeSlot => exerciseSlots.isEmpty
      ? null
      : exerciseSlots[activeSlotIndex.clamp(0, exerciseSlots.length - 1)];

  List<WorkoutSet> setsFor(int groupOrder) =>
      setsByOrder[groupOrder] ?? [];

  WorkoutDetailState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? error,
    bool clearError = false,
    Workout? workout,
    Map<String, ExerciseDetail>? exerciseDetailMap,
    bool? isEditing,
    String? preNotesDraft,
    String? postNotesDraft,
    List<WorkoutDetailExerciseSlot>? exerciseSlots,
    int? activeSlotIndex,
    Map<int, List<WorkoutSet>>? setsByOrder,
    bool clearSetsByOrder = false,
    Map<int, List<int>>? workoutSetDrafts,
    bool clearWorkoutSetDrafts = false,
    List<CustomVariation>? allVariations,
    Map<String, int>? variationExerciseCounts,
    bool? newExCreating,
    bool? newVarCreating,
    Map<String, List<Lesson>>? lessonsByExercise,
    Map<String, List<ExerciseHistorySession>>? historyByExercise,
    bool? pastSetsLoaded,
    Map<String, int>? prsByExercise,
    int? totalPRCount,
  }) =>
      WorkoutDetailState(
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        error: clearError ? null : error ?? this.error,
        workout: workout ?? this.workout,
        exerciseDetailMap: exerciseDetailMap ?? this.exerciseDetailMap,
        isEditing: isEditing ?? this.isEditing,
        preNotesDraft: preNotesDraft ?? this.preNotesDraft,
        postNotesDraft: postNotesDraft ?? this.postNotesDraft,
        exerciseSlots: exerciseSlots ?? this.exerciseSlots,
        activeSlotIndex: activeSlotIndex ?? this.activeSlotIndex,
        setsByOrder: clearSetsByOrder ? const {} : (setsByOrder ?? this.setsByOrder),
        workoutSetDrafts:
            clearWorkoutSetDrafts ? const {} : (workoutSetDrafts ?? this.workoutSetDrafts),
        allVariations: allVariations ?? this.allVariations,
        variationExerciseCounts: variationExerciseCounts ?? this.variationExerciseCounts,
        newExCreating: newExCreating ?? this.newExCreating,
        newVarCreating: newVarCreating ?? this.newVarCreating,
        lessonsByExercise: lessonsByExercise ?? this.lessonsByExercise,
        historyByExercise: historyByExercise ?? this.historyByExercise,
        pastSetsLoaded: pastSetsLoaded ?? this.pastSetsLoaded,
        prsByExercise: prsByExercise ?? this.prsByExercise,
        totalPRCount: totalPRCount ?? this.totalPRCount,
      );
}

class WorkoutDetailViewModel {
  WorkoutDetailViewModel({
    WorkoutRepository? workoutRepo,
    ExerciseRepository? exerciseRepo,
    LessonRepository? lessonRepo,
  })  : _workoutRepo = workoutRepo ?? WorkoutRepository(),
        _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
        _lessonRepo = lessonRepo ?? LessonRepository();

  final WorkoutRepository _workoutRepo;
  final ExerciseRepository _exerciseRepo;
  final LessonRepository _lessonRepo;
  final state = ValueNotifier(const WorkoutDetailState());

  int _nextDraftId = 1;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  List<WorkoutDetailExerciseSlot> _buildSlots(List<WorkoutSet> sets) {
    final seen = <String>{};
    final slots = <WorkoutDetailExerciseSlot>[];
    for (var i = 0; i < sets.length; i++) {
      if (seen.add(sets[i].exerciseId)) {
        slots.add(WorkoutDetailExerciseSlot(groupOrder: slots.length + 1, exerciseId: sets[i].exerciseId));
      }
    }
    return slots;
  }

  Map<int, List<WorkoutSet>> _groupByOrder(List<WorkoutSet> sets, List<WorkoutDetailExerciseSlot> slots) {
    final map = <int, List<WorkoutSet>>{};
    for (final slot in slots) {
      map[slot.groupOrder] = [];
    }
    for (final s in sets) {
      final slot = slots.firstWhere(
        (sl) => sl.exerciseId == s.exerciseId,
        orElse: () => slots.last,
      );
      map[slot.groupOrder]?.add(s);
    }
    return map;
  }

  // ── Loading ────────────────────────────────────────────────────────────────

  Future<void> load(String workoutId) async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _workoutRepo.fetchWorkout(workoutId),
        _workoutRepo.loadSetsForWorkout(workoutId),
        _exerciseRepo.fetchExerciseDetailMap(_userId),
        _workoutRepo.loadPastSetsTimeline(_userId),
        _exerciseRepo.fetchVariations(_userId),
        _exerciseRepo.fetchBridges(_userId),
      ]);
      final sets = results[1] as List<WorkoutSet>;
      final slots = _buildSlots(sets);
      final bridges = results[5] as List<Map<String, dynamic>>;
      final counts = <String, int>{};
      for (final b in bridges) {
        final varId = b['custom_variation_id'] as String;
        counts[varId] = (counts[varId] ?? 0) + 1;
      }
      state.value = state.value.copyWith(
        isLoading: false,
        workout: results[0] as Workout?,
        exerciseDetailMap: results[2] as Map<String, ExerciseDetail>,
        historyByExercise: groupHistoryByExercise(results[3] as List<PastSetRow>),
        pastSetsLoaded: true,
        allVariations: results[4] as List<CustomVariation>,
        variationExerciseCounts: counts,
        exerciseSlots: slots,
        setsByOrder: _groupByOrder(sets, slots),
      );
      _computePRs();
    } catch (e) {
      state.value = state.value.copyWith(isLoading: false, error: e.toString());
    }
  }

  void _computePRs() {
    final s = state.value;
    // Build prevBest from all history *except* this workout's sets
    final exclusions = s.workout?.workoutId != null ? {s.workout!.workoutId} : <String>{};
    final filtered = <PastSetRow>[];
    for (final sessions in s.historyByExercise.values) {
      for (final session in sessions) {
        for (final set in session.sets) {
          if (!exclusions.contains(set.workoutId)) {
            filtered.add(set);
          }
        }
      }
    }
    final byExercise = <String, List<PastSetRow>>{};
    for (final set in filtered) {
      byExercise.putIfAbsent(set.exerciseId, () => []).add(set);
    }
    final prevBest = <String, ({num weight, num reps})?>{};
    for (final entry in byExercise.entries) {
      final best = bestEverForExercise(entry.value);
      if (best != null) prevBest[entry.key] = best;
    }

    final prs = <String, int>{};
    var total = 0;
    for (final e in s.setsByOrder.entries) {
      for (final set in e.value) {
        if (isPr(set, prevBest[set.exerciseId])) {
          prs[set.exerciseId] = (prs[set.exerciseId] ?? 0) + 1;
          total++;
        }
      }
    }
    state.value = state.value.copyWith(prsByExercise: prs, totalPRCount: total);
  }

  int prCountFor(String exerciseId) =>
      state.value.prsByExercise[exerciseId] ?? 0;

  Future<void> _reloadSets(String workoutId) async {
    final sets = await _workoutRepo.loadSetsForWorkout(workoutId);
    final existingSlots = state.value.exerciseSlots;
    state.value = state.value.copyWith(
      setsByOrder: _groupByOrder(sets, existingSlots),
      clearWorkoutSetDrafts: true,
    );
    _computePRs();
  }

  // ── Edit mode ──────────────────────────────────────────────────────────────

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
      final updated = await _workoutRepo.fetchWorkout(workoutId);
      state.value = state.value.copyWith(
        isSaving: false,
        isEditing: false,
        workout: updated,
      );
    } catch (e) {
      state.value = state.value.copyWith(isSaving: false, error: e.toString());
    }
  }

  // ── Tabs ───────────────────────────────────────────────────────────────────

  void tapTab(int index) =>
      state.value = state.value.copyWith(activeSlotIndex: index);

  void reorderExercises(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final s = state.value;
    final slots = [...s.exerciseSlots];
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
    state.value = s.copyWith(exerciseSlots: slots, activeSlotIndex: newActive);
  }

  void addExerciseGroup(String exerciseId) {
    final s = state.value;
    final existingIndex = s.exerciseSlots.indexWhere((sl) => sl.exerciseId == exerciseId);
    if (existingIndex != -1) {
      state.value = s.copyWith(activeSlotIndex: existingIndex);
      return;
    }
    final nextOrder = s.exerciseSlots.isEmpty
        ? 1
        : s.exerciseSlots.map((sl) => sl.groupOrder).reduce((a, b) => a > b ? a : b) + 1;
    final slots = [...s.exerciseSlots, WorkoutDetailExerciseSlot(groupOrder: nextOrder, exerciseId: exerciseId)];
    final drafts = Map<int, List<int>>.from(s.workoutSetDrafts);
    drafts.putIfAbsent(nextOrder, () => []).add(_nextDraftId++);
    state.value = s.copyWith(
      exerciseSlots: slots,
      workoutSetDrafts: drafts,
      activeSlotIndex: slots.length - 1,
    );
    loadLessonsFor(exerciseId);
  }

  // ── Draft set rows ─────────────────────────────────────────────────────────

  void addDraftSet(int groupOrder) {
    final drafts = Map<int, List<int>>.from(state.value.workoutSetDrafts);
    drafts.putIfAbsent(groupOrder, () => []).add(_nextDraftId++);
    state.value = state.value.copyWith(workoutSetDrafts: drafts);
  }

  void removeDraftSet(int groupOrder, int draftId) {
    final drafts = Map<int, List<int>>.from(state.value.workoutSetDrafts);
    drafts[groupOrder]?.remove(draftId);
    state.value = state.value.copyWith(workoutSetDrafts: drafts);
  }

  Future<bool> commitDraftSet(
    String exerciseId,
    int groupOrder,
    int draftId, {
    String? variationId,
    double? weight,
    required List<num> reps,
    required List<num> duration,
    String? notes,
  }) async {
    final w = state.value.workout;
    if (w == null) return false;
    if (reps.isEmpty && duration.isEmpty) return false;
    final existing = state.value.setsFor(groupOrder);
    final nextNum = existing.isEmpty ? 1 : existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    try {
      await _workoutRepo.insertSet(
        workoutId: w.workoutId,
        exerciseId: exerciseId,
        variationId: variationId,
        setNumber: nextNum,
        weight: weight,
        reps: reps,
        duration: duration,
        notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
      );
      removeDraftSet(groupOrder, draftId);
      await _reloadSets(w.workoutId);
      return true;
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
      return false;
    }
  }

  Future<void> quickUpdateSet(
    WorkoutSet set, {
    double? weight,
    bool clearWeight = false,
    List<num>? reps,
    String? variationId,
    bool clearVariation = false,
    String? notes,
    bool clearNotes = false,
  }) async {
    final w = state.value.workout;
    if (w == null) return;
    try {
      await _workoutRepo.updateSet(
        set.setId,
        weight: weight,
        clearWeight: clearWeight,
        reps: reps,
        variationId: variationId,
        clearVariation: clearVariation,
        notes: notes,
        clearNotes: clearNotes,
      );
      await _reloadSets(w.workoutId);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> duplicateSet(WorkoutSet set) async {
    final w = state.value.workout;
    if (w == null) return;
    final existing = state.value.setsFor(
      state.value.exerciseSlots.firstWhere((sl) => sl.exerciseId == set.exerciseId).groupOrder,
    );
    final nextNum = existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    try {
      await _workoutRepo.insertSet(
        workoutId: w.workoutId,
        exerciseId: set.exerciseId,
        variationId: set.variationId,
        setNumber: nextNum,
        weight: set.weight,
        reps: set.reps,
        duration: set.duration,
        notes: set.notes,
      );
      await _reloadSets(w.workoutId);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> deleteSetById(String setId) async {
    final w = state.value.workout;
    if (w == null) return;
    await _workoutRepo.deleteSet(setId);
    await _reloadSets(w.workoutId);
  }

  // ── New exercise / variation ───────────────────────────────────────────────

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

  // ── Lessons ────────────────────────────────────────────────────────────────

  List<Lesson> lessonsFor(String exerciseId) =>
      state.value.lessonsByExercise[exerciseId] ?? const [];

  Future<void> loadLessonsFor(String exerciseId) async {
    try {
      final lessons = await _lessonRepo.fetchLessons(_userId, exerciseId);
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
      await _lessonRepo.toggleLessonPin(lessonId, !lesson.pinned);
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

  // ── History ────────────────────────────────────────────────────────────────

  List<ExerciseHistorySession> historyFor(String exerciseId) =>
      state.value.historyByExercise[exerciseId] ?? const [];

  ExerciseDetail? getExerciseDetail(String exerciseId) =>
      state.value.exerciseDetailMap[exerciseId];

  void dispose() => state.dispose();
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
