import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/session.dart';
import '../../../data/models/session_set.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/pr_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../session/model/pr_engine.dart';
import '../../session/model/session_local_state.dart'
    show ExerciseHistorySession, groupHistoryByExercise, isSimilarVariationName;

/// One tab in the workout-detail screen — a single exercise that was logged
/// in this workout.
class SessionDetailExerciseSlot {
  const SessionDetailExerciseSlot({required this.groupOrder, required this.exerciseId});
  final int groupOrder;
  final String exerciseId;
}

class SessionDetailState {
  const SessionDetailState({
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    this.session,
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
  final Session? session;
  final Map<String, ExerciseDetail> exerciseDetailMap;
  final bool isEditing;
  final String preNotesDraft;
  final String postNotesDraft;

  final List<SessionDetailExerciseSlot> exerciseSlots;
  final int activeSlotIndex;
  final Map<int, List<SessionSet>> setsByOrder;
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

  SessionDetailExerciseSlot? get activeSlot => exerciseSlots.isEmpty
      ? null
      : exerciseSlots[activeSlotIndex.clamp(0, exerciseSlots.length - 1)];

  List<SessionSet> setsFor(int groupOrder) =>
      setsByOrder[groupOrder] ?? [];

  SessionDetailState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? error,
    bool clearError = false,
    Session? session,
    Map<String, ExerciseDetail>? exerciseDetailMap,
    bool? isEditing,
    String? preNotesDraft,
    String? postNotesDraft,
    List<SessionDetailExerciseSlot>? exerciseSlots,
    int? activeSlotIndex,
    Map<int, List<SessionSet>>? setsByOrder,
    bool clearSetsByOrder = false,
    Map<int, List<int>>? workoutSetDrafts,
    bool clearSessionSetDrafts = false,
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
      SessionDetailState(
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        error: clearError ? null : error ?? this.error,
        session: session ?? this.session,
        exerciseDetailMap: exerciseDetailMap ?? this.exerciseDetailMap,
        isEditing: isEditing ?? this.isEditing,
        preNotesDraft: preNotesDraft ?? this.preNotesDraft,
        postNotesDraft: postNotesDraft ?? this.postNotesDraft,
        exerciseSlots: exerciseSlots ?? this.exerciseSlots,
        activeSlotIndex: activeSlotIndex ?? this.activeSlotIndex,
        setsByOrder: clearSetsByOrder ? const {} : (setsByOrder ?? this.setsByOrder),
        workoutSetDrafts:
            clearSessionSetDrafts ? const {} : (workoutSetDrafts ?? this.workoutSetDrafts),
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

class SessionDetailViewModel {
  SessionDetailViewModel({
    SessionRepository? workoutRepo,
    ExerciseRepository? exerciseRepo,
    LessonRepository? lessonRepo,
    PrRepository? prRepo,
  })  : _sessionRepo = workoutRepo ?? SessionRepository(),
        _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
        _lessonRepo = lessonRepo ?? LessonRepository(),
        _prRepo = prRepo ?? PrRepository();

  final SessionRepository _sessionRepo;
  final ExerciseRepository _exerciseRepo;
  final LessonRepository _lessonRepo;
  final PrRepository _prRepo;
  final state = ValueNotifier(const SessionDetailState());

  int _nextDraftId = 1;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  List<SessionDetailExerciseSlot> _buildSlots(List<SessionSet> sets) {
    final seen = <String>{};
    final slots = <SessionDetailExerciseSlot>[];
    for (var i = 0; i < sets.length; i++) {
      if (seen.add(sets[i].exerciseId)) {
        slots.add(SessionDetailExerciseSlot(groupOrder: slots.length + 1, exerciseId: sets[i].exerciseId));
      }
    }
    return slots;
  }

  Map<int, List<SessionSet>> _groupByOrder(List<SessionSet> sets, List<SessionDetailExerciseSlot> slots) {
    final map = <int, List<SessionSet>>{};
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

  Future<void> load(String sessionId) async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    // Fast path: the workout + its own sets are all the screen needs to render.
    // The heavy queries (full past-sets timeline, exercise catalog) load in
    // the background and populate lessons/history/PR data without blocking.
    try {
      final results = await Future.wait([
        _sessionRepo.fetchSession(sessionId),
        _sessionRepo.loadSetsForSession(sessionId),
      ]);
      final sets = results[1] as List<SessionSet>;
      final slots = _buildSlots(sets);
      state.value = state.value.copyWith(
        isLoading: false,
        session: results[0] as Session?,
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
        _sessionRepo.loadPastSetsTimeline(_userId),
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
    final exclusions = s.session?.sessionId != null ? {s.session!.sessionId} : <String>{};
    final filtered = <PastSetRow>[];
    for (final sessions in s.historyByExercise.values) {
      for (final session in sessions) {
        for (final set in session.sets) {
          if (!exclusions.contains(set.sessionId)) {
            filtered.add(set);
          }
        }
      }
    }

    // Compute PRs with the engine: history (excluding this workout) + this
    // workout's sets, then keep records whose sessionId matches this one.
    final thisWorkoutId = s.session?.sessionId;
    final combined = [...filtered];
    for (final e in s.setsByOrder.entries) {
      for (final set in e.value) {
        combined.add(PastSetRow(
          sessionSetId: set.sessionSetId,
          sessionId: set.sessionId,
          userId: set.userId,
          exerciseId: set.exerciseId,
          setNumber: set.setNumber,
          reps: set.reps,
          duration: set.duration,
          sessionCreatedDate: s.session?.createdDate ?? DateTime.now(),
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

  Future<void> _reloadSets(String sessionId) async {
    final sets = await _sessionRepo.loadSetsForSession(sessionId);
    final existingSlots = state.value.exerciseSlots;
    state.value = state.value.copyWith(
      setsByOrder: _groupByOrder(sets, existingSlots),
      clearSessionSetDrafts: true,
    );
    _computePRs();
  }

  /// Re-derives fact_pr for the edited exercise from current, accurate data —
  /// this workout's in-state sets (which reflect the edit/delete just made)
  /// plus other workouts' loaded history. Deletes then re-inserts that
  /// exercise's records (promoting the next-best from the remaining sets).
  ///
  /// If the combined source (other workouts' history + this workout's sets)
  /// has no data for the exercise, the recompute is skipped — otherwise an
  /// empty baseline would wipe every PR record for the exercise. Editing
  /// before history loads is fine: in-state sets alone still re-derive this
  /// workout's PRs, and there's no loaded history to lose.
  Future<void> recomputeExercisePRs(String exerciseId) async {
    final s = state.value;

    final thisWorkoutId = s.session?.sessionId;
    final combined = <PastSetRow>[];
    // Other workouts' history (accurate — this workout isn't in it)
    for (final sessions in s.historyByExercise.values) {
      for (final session in sessions) {
        for (final set in session.sets) {
          if (set.sessionId != thisWorkoutId) combined.add(set);
        }
      }
    }
    // This workout's CURRENT sets — reflects the optimistic delete already
    // applied to setsByOrder, so the deleted set is not included.
    for (final sets in s.setsByOrder.values) {
      for (final set in sets) {
        combined.add(PastSetRow(
          sessionSetId: set.sessionSetId,
          sessionId: set.sessionId,
          userId: set.userId,
          exerciseId: set.exerciseId,
          setNumber: set.setNumber,
          reps: set.reps,
          duration: set.duration,
          sessionCreatedDate: s.session?.createdDate ?? DateTime.now(),
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
    // Nothing to derive from — skip entirely so we never wipe existing PRs
    // with an empty baseline.
    if (exerciseSets.isEmpty) return;
    final timeline = fullPrTimeline(exerciseSets);
    try {
      await _prRepo.deleteForExercise(_userId, exerciseId);
      if (timeline.isNotEmpty) await _prRepo.insertPrs(_userId, timeline);
    } catch (_) {}
  }

  // ── Edit mode ──────────────────────────────────────────────────────────────

  void startEditing() {
    final w = state.value.session;
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

  Future<void> saveNotes(String sessionId) async {
    state.value = state.value.copyWith(isSaving: true);
    try {
      await _sessionRepo.endSession(
        sessionId,
        postNotes: state.value.postNotesDraft,
      );
      final updated = await _sessionRepo.fetchSession(sessionId);
      state.value = state.value.copyWith(
        isSaving: false,
        isEditing: false,
        session: updated,
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
    final slots = [...s.exerciseSlots, SessionDetailExerciseSlot(groupOrder: nextOrder, exerciseId: exerciseId)];
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
    final w = state.value.session;
    if (w == null) return;
    final existing = state.value.setsFor(groupOrder);
    final nextNum = existing.isEmpty ? 1 : existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    final slot = state.value.exerciseSlots.firstWhere((s) => s.groupOrder == groupOrder);
    _sessionRepo.insertSet(
      sessionId: w.sessionId,
      userId: _userId,
      exerciseId: slot.exerciseId,
      exerciseName: _exerciseName(slot.exerciseId),
      setNumber: nextNum,
      weight: null,
      reps: [],
      duration: [],
    ).then((_) => _reloadSets(w.sessionId));
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
    final w = state.value.session;
    if (w == null) return false;
    final existing = state.value.setsFor(groupOrder);
    final nextNum = existing.isEmpty ? 1 : existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    // Find an empty pre-created set for this exercise
    final emptyIdx = existing.lastIndexWhere((s) => s.reps.isEmpty && s.duration.isEmpty);
    try {
      if (emptyIdx >= 0) {
        await _sessionRepo.updateSet(
          existing[emptyIdx].sessionSetId,
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
        await _sessionRepo.insertSet(
          sessionId: w.sessionId,
          userId: _userId,
          exerciseId: exerciseId,
          exerciseName: _exerciseName(exerciseId),
          variationId: variationId,
          variationName: _variationName(exerciseId, variationId),
          setNumber: nextNum,
          weight: weight,
          reps: reps,
          duration: duration,
          notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
        );
      }
      removeDraftSet(groupOrder, draftId);
      await _reloadSets(w.sessionId);
      await recomputeExercisePRs(exerciseId);
      return true;
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
      return false;
    }
  }

  Future<void> quickUpdateSet(
    SessionSet set, {
    double? weight,
    bool clearWeight = false,
    List<num>? reps,
    String? variationId,
    bool clearVariation = false,
    String? notes,
    bool clearNotes = false,
  }) async {
    final w = state.value.session;
    if (w == null) return;
    try {
      await _sessionRepo.updateSet(
        set.sessionSetId,
        weight: weight,
        clearWeight: clearWeight,
        reps: reps,
        variationId: variationId,
        clearVariation: clearVariation,
        notes: notes,
        clearNotes: clearNotes,
      );
      await _reloadSets(w.sessionId);
      await recomputeExercisePRs(set.exerciseId);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> duplicateSet(SessionSet set) async {
    final w = state.value.session;
    if (w == null) return;
    final existing = state.value.setsFor(
      state.value.exerciseSlots.firstWhere((sl) => sl.exerciseId == set.exerciseId).groupOrder,
    );
    final nextNum = existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    try {
      await _sessionRepo.insertSet(
        sessionId: w.sessionId,
        userId: _userId,
        exerciseId: set.exerciseId,
        exerciseName: set.exerciseName ?? _exerciseName(set.exerciseId),
        variationId: set.variationId,
        variationName: set.variationName ?? _variationName(set.exerciseId, set.variationId),
        setNumber: nextNum,
        weight: set.weight,
        reps: set.reps,
        duration: set.duration,
        notes: set.notes,
      );
      await _reloadSets(w.sessionId);
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
    final newSetsByOrder = <int, List<SessionSet>>{};
    for (final e in s.setsByOrder.entries) {
      newSetsByOrder[e.key] = e.value.where((x) => x.sessionSetId != setId).toList();
    }
    state.value = s.copyWith(setsByOrder: newSetsByOrder);
    _computePRs();
  }

  /// Deletes the set AND its fact_pr records (the set was the reason the PRs
  /// existed), then recomputes the exercise from remaining valid history so
  /// the next-best record is promoted (e.g. delete a 170 1RM → the 160 that
  /// once beat 150 becomes the 1RM again).
  Future<void> deleteSetCascade(String setId, String exerciseId) async {
    final w = state.value.session;
    if (w == null) return;
    await _deleteSetFromState(setId);
    try {
      await _sessionRepo.deleteSet(setId);
      await _prRepo.deleteForSets(_userId, [setId]);
      await recomputeExercisePRs(exerciseId);
      await _reloadSets(w.sessionId);
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
        if (existing.isArchived) {
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
        if (existing != null && !existing.isArchived) {
          await _exerciseRepo.reactivateVariation(id);
        }
      } else {
        final existing = await _exerciseRepo.findVariationByName(_userId, trimmed);
        if (existing != null) {
          if (!existing.isArchived) await _exerciseRepo.reactivateVariation(existing.variationId);
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

  // ── History ────────────────────────────────────────────────────────────────

  List<ExerciseHistorySession> historyFor(String exerciseId) =>
      state.value.historyByExercise[exerciseId] ?? const [];

  ExerciseDetail? getExerciseDetail(String exerciseId) =>
      state.value.exerciseDetailMap[exerciseId];

  /// Display name for an exercise, falling back to the snapshot name on any
  /// set when the exercise has been deactivated and is no longer in the
  /// catalog.
  String exerciseDisplayName(String exerciseId) {
    final catalog = _exerciseName(exerciseId);
    if (catalog != null) return catalog;
    // Deactivated — use the snapshot name from the first set for this
    // exercise.
    for (final entry in state.value.setsByOrder.values) {
      for (final s in entry) {
        if (s.exerciseId == exerciseId && s.exerciseName != null) {
          return s.exerciseName!;
        }
      }
    }
    return exerciseId;
  }

  String? _exerciseName(String exerciseId) =>
      state.value.exerciseDetailMap[exerciseId]?.name;

  String? _variationName(String exerciseId, String? variationId) {
    if (variationId == null) return null;
    return state.value.exerciseDetailMap[exerciseId]
        ?.assignedVariations
        .where((v) => v.variationId == variationId)
        .map((v) => v.name)
        .firstOrNull;
  }

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
