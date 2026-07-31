import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/workout.dart';
import '../../../data/models/workout_set.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/pr_repository.dart';
import '../../../data/repositories/workout_repository.dart';
import '../../session/model/pr_engine.dart';
import '../../session/model/session_local_state.dart'
    show ExerciseHistorySession, groupHistoryByExercise, isSimilarVariationName;

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
    this.prRecords = const [],
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
  final List<PrRecord> prRecords;

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
    List<PrRecord>? prRecords,
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
        prRecords: prRecords ?? this.prRecords,
      );
}

class WorkoutDetailViewModel {
  WorkoutDetailViewModel({
    WorkoutRepository? workoutRepo,
    ExerciseRepository? exerciseRepo,
    LessonRepository? lessonRepo,
    PrRepository? prRepo,
  })  : _workoutRepo = workoutRepo ?? WorkoutRepository(),
        _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
        _lessonRepo = lessonRepo ?? LessonRepository(),
        _prRepo = prRepo ?? PrRepository();

  final WorkoutRepository _workoutRepo;
  final ExerciseRepository _exerciseRepo;
  final LessonRepository _lessonRepo;
  final PrRepository _prRepo;
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
    // Fast path: the workout + its own sets are all the screen needs to render.
    // The heavy queries (full past-sets timeline, exercise catalog) load in
    // the background and populate lessons/history/PR data without blocking.
    try {
      final results = await Future.wait([
        _workoutRepo.fetchWorkout(workoutId),
        _workoutRepo.loadSetsForWorkout(workoutId),
      ]);
      final sets = results[1] as List<WorkoutSet>;
      final slots = _buildSlots(sets);
      state.value = state.value.copyWith(
        isLoading: false,
        workout: results[0] as Workout?,
        exerciseSlots: slots,
        setsByOrder: _groupByOrder(sets, slots),
      );
      _loadHeavyContext();
    } catch (e) {
      state.value = state.value.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Loads the heavier cross-session context in the background: full history
  /// (for PRs + the history picker), the exercise catalog, variations, and
  /// bridge counts. Renders whatever's ready; the screen doesn't block on it.
  Future<void> _loadHeavyContext() async {
    try {
      final results = await Future.wait([
        _exerciseRepo.fetchExerciseDetailMap(_userId),
        _workoutRepo.loadPastSetsTimeline(_userId),
        _exerciseRepo.fetchVariations(_userId),
        _exerciseRepo.fetchBridges(_userId),
      ]);
      final bridges = results[3] as List<Map<String, dynamic>>;
      final counts = <String, int>{};
      for (final b in bridges) {
        final varId = b['custom_variation_id'] as String;
        counts[varId] = (counts[varId] ?? 0) + 1;
      }
      state.value = state.value.copyWith(
        exerciseDetailMap: results[0] as Map<String, ExerciseDetail>,
        historyByExercise: groupHistoryByExercise(results[1] as List<PastSetRow>),
        pastSetsLoaded: true,
        allVariations: results[2] as List<CustomVariation>,
        variationExerciseCounts: counts,
      );
      _computePRs();
    } catch (_) {
      // Background context is best-effort; core workout already rendered.
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

    // Compute PRs with the engine: history (excluding this workout) + this
    // workout's sets, then keep records whose workoutId matches this one.
    final thisWorkoutId = s.workout?.workoutId;
    final combined = [...filtered];
    for (final e in s.setsByOrder.entries) {
      for (final set in e.value) {
        combined.add(PastSetRow(
          setId: set.setId,
          workoutId: set.workoutId,
          exerciseId: set.exerciseId,
          setNumber: set.setNumber,
          reps: set.reps,
          duration: set.duration,
          workoutCreatedDate: s.workout?.createdDate ?? DateTime.now(),
          variationId: set.variationId,
          weight: set.weight,
          notes: set.notes,
          exerciseName: set.exerciseName,
          variationName: set.variationName,
          supersetGroupNumber: set.supersetGroupNumber,
        ));
      }
    }

    final records = thisWorkoutId != null ? prsForWorkout(combined, thisWorkoutId) : <PrRecord>[];
    final prs = <String, int>{};
    for (final pr in records) {
      prs[pr.exerciseId] = (prs[pr.exerciseId] ?? 0) + 1;
    }
    state.value = state.value.copyWith(
      prsByExercise: prs,
      totalPRCount: records.length,
      prRecords: records,
    );
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

  /// Re-derives fact_pr for the edited exercise from current, accurate data —
  /// this workout's in-state sets (which reflect the edit/delete just made)
  /// plus other workouts' loaded history. Deletes then re-inserts that
  /// exercise's records (promoting the next-best from the remaining sets).
  ///
  /// If the full past-sets history hasn't loaded yet, the recompute is
  /// skipped entirely — otherwise an empty baseline would wipe every PR
  /// record for the exercise.
  Future<void> recomputeExercisePRs(String exerciseId) async {
    final s = state.value;
    if (!s.pastSetsLoaded) return;

    final thisWorkoutId = s.workout?.workoutId;
    final combined = <PastSetRow>[];
    // Other workouts' history (accurate — this workout isn't in it)
    for (final sessions in s.historyByExercise.values) {
      for (final session in sessions) {
        for (final set in session.sets) {
          if (set.workoutId != thisWorkoutId) combined.add(set);
        }
      }
    }
    // This workout's CURRENT sets — reflects the optimistic delete already
    // applied to setsByOrder, so the deleted set is not included.
    for (final sets in s.setsByOrder.values) {
      for (final set in sets) {
        combined.add(PastSetRow(
          setId: set.setId,
          workoutId: set.workoutId,
          exerciseId: set.exerciseId,
          setNumber: set.setNumber,
          reps: set.reps,
          duration: set.duration,
          workoutCreatedDate: s.workout?.createdDate ?? DateTime.now(),
          variationId: set.variationId,
          weight: set.weight,
          notes: set.notes,
          exerciseName: set.exerciseName,
          variationName: set.variationName,
          supersetGroupNumber: set.supersetGroupNumber,
        ));
      }
    }

    final exerciseSets = combined.where((x) => x.exerciseId == exerciseId).toList();
    final timeline = fullPrTimeline(exerciseSets);
    try {
      await _prRepo.deleteForExercise(_userId, exerciseId);
      if (timeline.isNotEmpty) await _prRepo.insertPrs(_userId, timeline);
    } catch (_) {}
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

  /// "+ ADD SET" in edit mode pre-creates an empty set in the DB so it
  /// survives hot restarts. Empty sets are NOT purged here — they were
  /// intentionally added by the user editing a finished workout.
  void addDraftSet(int groupOrder) {
    final w = state.value.workout;
    if (w == null) return;
    final existing = state.value.setsFor(groupOrder);
    final nextNum = existing.isEmpty ? 1 : existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    final slot = state.value.exerciseSlots.firstWhere((s) => s.groupOrder == groupOrder);
    _workoutRepo.insertSet(
      workoutId: w.workoutId,
      exerciseId: slot.exerciseId,
      setNumber: nextNum,
      weight: null,
      reps: [],
      duration: [],
    ).then((_) => _reloadSets(w.workoutId));
  }

  void removeDraftSet(int groupOrder, int draftId) {
    final drafts = Map<int, List<int>>.from(state.value.workoutSetDrafts);
    drafts[groupOrder]?.remove(draftId);
    state.value = state.value.copyWith(workoutSetDrafts: drafts);
  }

  /// Finds an existing empty set for this exercise and fills it in, or
  /// inserts a new row. Allows empty reps for finished workouts (the user
  /// explicitly added them in edit mode).
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
    final existing = state.value.setsFor(groupOrder);
    final nextNum = existing.isEmpty ? 1 : existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    // Find an empty pre-created set for this exercise
    final emptyIdx = existing.lastIndexWhere((s) => s.reps.isEmpty && s.duration.isEmpty);
    try {
      if (emptyIdx >= 0) {
        await _workoutRepo.updateSet(
          existing[emptyIdx].setId,
          variationId: variationId,
          clearVariation: variationId == null,
          weight: weight,
          clearWeight: weight == null,
          reps: reps,
          duration: duration,
          notes: notes,
          clearNotes: notes == null || notes.isEmpty,
        );
      } else {
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
      }
      removeDraftSet(groupOrder, draftId);
      await _reloadSets(w.workoutId);
      await recomputeExercisePRs(exerciseId);
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
      await recomputeExercisePRs(set.exerciseId);
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
      await recomputeExercisePRs(set.exerciseId);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  /// Removes [setId] from the in-memory setsByOrder immediately so the UI
  /// reflects the delete without depending on a reload round-trip, then
  /// deletes from the DB and reloads as the source of truth.
  Future<void> _deleteSetFromState(String setId) async {
    final s = state.value;
    final newSetsByOrder = <int, List<WorkoutSet>>{};
    for (final e in s.setsByOrder.entries) {
      newSetsByOrder[e.key] = e.value.where((x) => x.setId != setId).toList();
    }
    state.value = s.copyWith(setsByOrder: newSetsByOrder);
    _computePRs();
  }

  /// Deletes the set AND its fact_pr records (the set was the reason the PRs
  /// existed), then recomputes the exercise from remaining valid history so
  /// the next-best record is promoted (e.g. delete a 170 1RM → the 160 that
  /// once beat 150 becomes the 1RM again).
  Future<void> deleteSetCascade(String setId, String exerciseId) async {
    final w = state.value.workout;
    if (w == null) return;
    await _deleteSetFromState(setId);
    try {
      await _workoutRepo.deleteSet(setId);
      await _prRepo.deleteForSets(_userId, [setId]);
      await recomputeExercisePRs(exerciseId);
      await _reloadSets(w.workoutId);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
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
