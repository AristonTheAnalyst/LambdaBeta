import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/session.dart';
import '../../../data/models/session_exercise.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../session/model/pr_engine.dart';
import '../../session/model/session_local_state.dart'
    show ExerciseHistorySession, groupHistoryByExercise, isSimilarVariationName;

/// One tab in the workout-detail screen — a single exercise that was logged
/// in this workout, backed by its fact_session_exercise row.
class SessionDetailExerciseSlot {
  const SessionDetailExerciseSlot({
    required this.groupOrder,
    required this.exerciseId,
    this.sessionExerciseId,
  });
  final int groupOrder;
  final String exerciseId;
  final String? sessionExerciseId;
}

/// Sentinel distinguishing "not provided" from "explicitly null" in
/// [SessionDetailState.copyWith] — a feeling toggles OFF by writing null.
const Object _feelingUnset = Object();

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
    this.preFeelingDraft,
    this.postFeelingDraft,
    this.exerciseSlots = const [],
    this.activeSlotIndex = 0,
    this.setsByOrder = const {},
    this.workoutSetDrafts = const {},
    // Catalog / create-new
    this.allVariations = const [],
    this.newExCreating = false,
    this.newVarCreating = false,
    // Lessons and history
    this.lessonsByExercise = const {},
    this.historyByExercise = const {},
    this.pastSetsLoaded = false,
    this.prsByExercise = const {},
    this.totalPRCount = 0,
    this.prEvents = const [],
    this.prEventSetIds = const {},
  });

  final bool isLoading;
  final bool isSaving;
  final String? error;
  final Session? session;
  final Map<String, ExerciseDetail> exerciseDetailMap;
  final bool isEditing;
  final String preNotesDraft;
  final String postNotesDraft;
  final int? preFeelingDraft;
  final int? postFeelingDraft;

  final List<SessionDetailExerciseSlot> exerciseSlots;
  final int activeSlotIndex;
  final Map<int, List<SessionExerciseSet>> setsByOrder;
  final Map<int, List<int>> workoutSetDrafts;

  final List<CustomVariation> allVariations;
  final bool newExCreating;
  final bool newVarCreating;

  final Map<String, List<Lesson>> lessonsByExercise;
  final Map<String, List<ExerciseHistorySession>> historyByExercise;
  final bool pastSetsLoaded;
  final Map<String, int> prsByExercise;
  final int totalPRCount;
  final List<PrEvent> prEvents;
  final Set<String> prEventSetIds;

  SessionDetailExerciseSlot? get activeSlot => exerciseSlots.isEmpty
      ? null
      : exerciseSlots[activeSlotIndex.clamp(0, exerciseSlots.length - 1)];

  List<SessionExerciseSet> setsFor(int groupOrder) => setsByOrder[groupOrder] ?? [];

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
    Object? preFeelingDraft = _feelingUnset,
    Object? postFeelingDraft = _feelingUnset,
    List<SessionDetailExerciseSlot>? exerciseSlots,
    int? activeSlotIndex,
    Map<int, List<SessionExerciseSet>>? setsByOrder,
    bool clearSetsByOrder = false,
    Map<int, List<int>>? workoutSetDrafts,
    bool clearSessionSetDrafts = false,
    List<CustomVariation>? allVariations,
    bool? newExCreating,
    bool? newVarCreating,
    Map<String, List<Lesson>>? lessonsByExercise,
    Map<String, List<ExerciseHistorySession>>? historyByExercise,
    bool? pastSetsLoaded,
    Map<String, int>? prsByExercise,
    int? totalPRCount,
    List<PrEvent>? prEvents,
    Set<String>? prEventSetIds,
  }) => SessionDetailState(
    isLoading: isLoading ?? this.isLoading,
    isSaving: isSaving ?? this.isSaving,
    error: clearError ? null : error ?? this.error,
    session: session ?? this.session,
    exerciseDetailMap: exerciseDetailMap ?? this.exerciseDetailMap,
    isEditing: isEditing ?? this.isEditing,
    preNotesDraft: preNotesDraft ?? this.preNotesDraft,
    postNotesDraft: postNotesDraft ?? this.postNotesDraft,
    preFeelingDraft: identical(preFeelingDraft, _feelingUnset)
        ? this.preFeelingDraft
        : preFeelingDraft as int?,
    postFeelingDraft: identical(postFeelingDraft, _feelingUnset)
        ? this.postFeelingDraft
        : postFeelingDraft as int?,
    exerciseSlots: exerciseSlots ?? this.exerciseSlots,
    activeSlotIndex: activeSlotIndex ?? this.activeSlotIndex,
    setsByOrder: clearSetsByOrder
        ? const {}
        : (setsByOrder ?? this.setsByOrder),
    workoutSetDrafts: clearSessionSetDrafts
        ? const {}
        : (workoutSetDrafts ?? this.workoutSetDrafts),
    allVariations: allVariations ?? this.allVariations,
    newExCreating: newExCreating ?? this.newExCreating,
    newVarCreating: newVarCreating ?? this.newVarCreating,
    lessonsByExercise: lessonsByExercise ?? this.lessonsByExercise,
    historyByExercise: historyByExercise ?? this.historyByExercise,
    pastSetsLoaded: pastSetsLoaded ?? this.pastSetsLoaded,
    prsByExercise: prsByExercise ?? this.prsByExercise,
    totalPRCount: totalPRCount ?? this.totalPRCount,
    prEvents: prEvents ?? this.prEvents,
    prEventSetIds: prEventSetIds ?? this.prEventSetIds,
  );
}

class SessionDetailViewModel {
  SessionDetailViewModel({
    SessionRepository? sessionRepo,
    ExerciseRepository? exerciseRepo,
    LessonRepository? lessonRepo,
  }) : _sessionRepo = sessionRepo ?? SessionRepository(),
       _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
       _lessonRepo = lessonRepo ?? LessonRepository();

  final SessionRepository _sessionRepo;
  final ExerciseRepository _exerciseRepo;
  final LessonRepository _lessonRepo;
  final state = ValueNotifier(const SessionDetailState());

  int _nextDraftId = 1;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  /// Builds slots in the order the user arranged them during the session —
  /// `fact_session_exercise.exercise_order` (a real column now; the old JSON
  /// blob is gone). Exercises with no logged row (null exercise) are skipped.
  List<SessionDetailExerciseSlot> _buildSlots(
    List<SessionExercise> exercises,
  ) {
    final sorted = [...exercises]
      ..sort((a, b) => a.exerciseOrder.compareTo(b.exerciseOrder));
    final slots = <SessionDetailExerciseSlot>[];
    var order = 1;
    for (final e in sorted) {
      final exerciseId = e.exerciseId;
      if (exerciseId == null) continue;
      slots.add(
        SessionDetailExerciseSlot(
          groupOrder: order++,
          exerciseId: exerciseId,
          sessionExerciseId: e.sessionExerciseId,
        ),
      );
    }
    return slots;
  }

  Map<int, List<SessionExerciseSet>> _groupByOrder(
    List<SessionExerciseSet> sets,
    List<SessionDetailExerciseSlot> slots,
  ) {
    final map = <int, List<SessionExerciseSet>>{};
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
    // Fast path: the workout + its own exercise rows and sets are all the
    // screen needs to render. The heavy queries (full past-sets timeline,
    // exercise catalog) load in the background and populate
    // lessons/history/PR data without blocking.
    try {
      final results = await Future.wait([
        _sessionRepo.fetchSession(sessionId),
        _sessionRepo.loadSessionExercises(sessionId),
        _sessionRepo.loadSetsForSession(sessionId),
      ]);
      final exercises = results[1] as List<SessionExercise>;
      final sets = results[2] as List<SessionExerciseSet>;
      final session = results[0] as Session?;
      final slots = _buildSlots(exercises);
      state.value = state.value.copyWith(
        isLoading: false,
        session: session,
        exerciseSlots: slots,
        setsByOrder: _groupByOrder(sets, slots),
      );
      _loadHeavyContext();
    } catch (e) {
      state.value = state.value.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Loads the heavier cross-session context in the background: full history
  /// (for PRs + the history picker), the exercise catalog, and variations.
  /// Renders whatever's ready; the screen doesn't block on it.
  Future<void> _loadHeavyContext() async {
    try {
      final results = await Future.wait([
        _exerciseRepo.fetchExerciseDetailMap(_userId),
        _sessionRepo.loadPastSetsTimeline(_userId),
        _exerciseRepo.fetchVariations(_userId),
      ]);
      state.value = state.value.copyWith(
        exerciseDetailMap: results[0] as Map<String, ExerciseDetail>,
        historyByExercise: groupHistoryByExercise(
          results[1] as List<PastSetRow>,
        ),
        pastSetsLoaded: true,
        allVariations: results[2] as List<CustomVariation>,
      );
      _computePRs();
    } catch (_) {
      // Background context is best-effort; core workout already rendered.
    }
  }

  void _computePRs() {
    final s = state.value;
    // Build prevBest from all history *except* this workout's sets
    final exclusions = s.session?.sessionId != null
        ? {s.session!.sessionId}
        : <String>{};
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
        combined.add(
          PastSetRow(
            sessionExerciseSetId: set.sessionExerciseSetId,
            sessionExerciseId: set.sessionExerciseId,
            sessionId: set.sessionId,
            userId: set.userId,
            exerciseId: set.exerciseId,
            setNumber: set.setNumber,
            reps: set.reps,
            sessionCreatedDate: s.session?.createdDatetime ?? DateTime.now(),
            variationId: set.variationId,
            weight: set.weight,
            notes: set.notes,
            exerciseName: set.exerciseName,
            variationName: set.variationName,
          ),
        );
      }
    }

    final allEvents =
        thisWorkoutId != null ? prEvents(combined) : <PrEvent>[];
    // This session's events — one per frontier-extending set; each event
    // carries its own before-facts.
    final events = allEvents
        .where((e) => e.sessionId == thisWorkoutId)
        .toList();
    final prs = <String, int>{};
    for (final pr in events) {
      prs[pr.exerciseId] = (prs[pr.exerciseId] ?? 0) + 1;
    }
    state.value = state.value.copyWith(
      prsByExercise: prs,
      totalPRCount: events.length,
      prEvents: events,
      // Full-timeline event set ids — accents use the session events; the
      // history viewer's rows badge past sets via this map.
      prEventSetIds: {
        for (final e in allEvents)
          if (e.sessionExerciseSetId != null) e.sessionExerciseSetId!,
      },
    );
  }

  int prCountFor(String exerciseId) =>
      state.value.prsByExercise[exerciseId] ?? 0;

  /// The events the PRs pill should DISPLAY for an exercise.
  List<PrEvent> displayPrsFor(String exerciseId) =>
      state.value.prEvents
          .where((p) => p.exerciseId == exerciseId)
          .toList();

  Future<void> _reloadSets(String sessionId) async {
    final exercises = await _sessionRepo.loadSessionExercises(sessionId);
    final sets = await _sessionRepo.loadSetsForSession(sessionId);
    final slots = _buildSlots(exercises);
    // History derives from the same timeline — reload it too, otherwise the
    // History picker shows the pre-edit version of the workout being edited.
    final timeline = await _sessionRepo.loadPastSetsTimeline(_userId);
    state.value = state.value.copyWith(
      exerciseSlots: slots,
      setsByOrder: _groupByOrder(sets, slots),
      historyByExercise: groupHistoryByExercise(timeline),
      clearSessionSetDrafts: true,
    );
    _computePRs();
  }

  /// Re-derives PR highlighting for the edited exercise from current data —
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
        combined.add(
          PastSetRow(
            sessionExerciseSetId: set.sessionExerciseSetId,
            sessionExerciseId: set.sessionExerciseId,
            sessionId: set.sessionId,
            userId: set.userId,
            exerciseId: set.exerciseId,
            setNumber: set.setNumber,
            reps: set.reps,
            sessionCreatedDate: s.session?.createdDatetime ?? DateTime.now(),
            variationId: set.variationId,
            weight: set.weight,
            notes: set.notes,
            exerciseName: set.exerciseName,
            variationName: set.variationName,
          ),
        );
      }
    }

    // PRs are derived from the sets on read — after an edit the state's
    // in-memory derivation is simply refreshed. Nothing is persisted.
    _computePRs();
  }

  // ── Edit mode ──────────────────────────────────────────────────────────────

  void startEditing() {
    final w = state.value.session;
    state.value = state.value.copyWith(
      isEditing: true,
      preNotesDraft: w?.preNotes ?? '',
      postNotesDraft: w?.postNotes ?? '',
      preFeelingDraft: w?.preFeeling,
      postFeelingDraft: w?.feeling,
    );
  }

  void cancelEditing() => state.value = state.value.copyWith(isEditing: false);

  void setPreNotesDraft(String v) =>
      state.value = state.value.copyWith(preNotesDraft: v);

  void setPostNotesDraft(String v) =>
      state.value = state.value.copyWith(postNotesDraft: v);

  void setPreFeelingDraft(int? v) =>
      state.value = state.value.copyWith(preFeelingDraft: v);

  void setPostFeelingDraft(int? v) =>
      state.value = state.value.copyWith(postFeelingDraft: v);

  Future<void> saveNotes(String sessionId) async {
    state.value = state.value.copyWith(isSaving: true);
    try {
      // The full bookend state persists — drafts, plus the feeling ratings
      // (pre-notes were silently dropped before; feelings were read-only).
      await _sessionRepo.updateSessionNotes(
        sessionId,
        preNotes: state.value.preNotesDraft,
        postNotes: state.value.postNotesDraft,
        preFeeling: state.value.preFeelingDraft,
        postFeeling: state.value.postFeelingDraft,
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
    // Persist the arrangement back to fact_session_exercise.exercise_order so
    // a reorder made here sticks for the live viewer's restore too.
    final w = state.value.session;
    if (w != null) {
      _sessionRepo.reorderSessionExercises(
        w.sessionId,
        [
          for (final slot in state.value.exerciseSlots)
            if (slot.sessionExerciseId != null) slot.sessionExerciseId!,
        ],
      );
    }
  }

  /// The session-exercise row for [exerciseId], creating one (with the next
  /// exercise_order) when the exercise doesn't have a row yet — the
  /// past-session editor's add-exercise path.
  Future<String?> _ensureSessionExercise(String exerciseId) async {
    final w = state.value.session;
    if (w == null) return null;
    final existing = state.value.exerciseSlots.firstWhereOrNull(
      (sl) => sl.exerciseId == exerciseId,
    );
    if (existing?.sessionExerciseId != null) {
      return existing!.sessionExerciseId;
    }
    final nextOrder = state.value.exerciseSlots.isEmpty
        ? 1
        : state.value.exerciseSlots
                  .map((sl) => sl.groupOrder)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    final row = await _sessionRepo.insertSessionExercise(
      sessionId: w.sessionId,
      userId: _userId,
      exerciseId: exerciseId,
      exerciseOrder: nextOrder,
    );
    return row.sessionExerciseId;
  }

  Future<void> addExerciseGroup(String exerciseId) async {
    final s = state.value;
    final existingIndex = s.exerciseSlots.indexWhere(
      (sl) => sl.exerciseId == exerciseId,
    );
    if (existingIndex != -1) {
      state.value = s.copyWith(activeSlotIndex: existingIndex);
      return;
    }
    // Persist the exercise row immediately so the tab survives a reload.
    final sessionExerciseId = await _ensureSessionExercise(exerciseId);
    final nextOrder = s.exerciseSlots.isEmpty
        ? 1
        : s.exerciseSlots.map((sl) => sl.groupOrder).reduce(
              (a, b) => a > b ? a : b,
            ) +
              1;
    final slots = [
      ...s.exerciseSlots,
      SessionDetailExerciseSlot(
        groupOrder: nextOrder,
        exerciseId: exerciseId,
        sessionExerciseId: sessionExerciseId,
      ),
    ];
    final drafts = Map<int, List<int>>.from(s.workoutSetDrafts);
    drafts.putIfAbsent(nextOrder, () => []).add(_nextDraftId++);
    state.value = s.copyWith(
      exerciseSlots: slots,
      workoutSetDrafts: drafts,
      activeSlotIndex: slots.length - 1,
    );
    loadLessonsFor(exerciseId);
  }

  /// Removes an exercise group (slot + all its sets) — the past-session
  /// viewer's mirror of the planner's remove, so the full-mirror selector's
  /// hold-to-delete X works in edit mode. Sets go through
  /// [deleteSetCascade] so PRs recompute from the remaining history.
  Future<void> removeExerciseGroup(int index) async {
    final s = state.value;
    if (index < 0 || index >= s.exerciseSlots.length) return;
    final slot = s.exerciseSlots[index];
    final sets = List<SessionExerciseSet>.of(s.setsFor(slot.groupOrder));
    for (final set in sets) {
      await deleteSetCascade(
        set.sessionExerciseSetId,
        set.exerciseId ?? slot.exerciseId,
      );
    }
    final rowId = slot.sessionExerciseId;
    if (rowId != null) {
      try {
        await _sessionRepo.deleteSessionExercise(rowId);
      } catch (_) {}
    }
    final slots = [...state.value.exerciseSlots]..removeAt(index);
    int newActive = state.value.activeSlotIndex;
    if (newActive >= slots.length) {
      newActive = slots.isEmpty ? 0 : slots.length - 1;
    }
    state.value = state.value.copyWith(
      exerciseSlots: slots,
      activeSlotIndex: newActive,
    );
  }

  // ── Draft set rows ─────────────────────────────────────────────────────────

  /// "+ ADD SET" in edit mode pre-creates an empty set in the DB so it
  /// survives hot restarts. Empty sets are NOT purged here — they were
  /// intentionally added by the user editing a finished workout.
  Future<void> addDraftSet(int groupOrder) async {
    final w = state.value.session;
    if (w == null) return;
    final slot = state.value.exerciseSlots.firstWhere(
      (s) => s.groupOrder == groupOrder,
    );
    final sessionExerciseId = await _ensureSessionExercise(slot.exerciseId);
    if (sessionExerciseId == null) return;
    final existing = state.value.setsFor(groupOrder);
    final nextNum = existing.isEmpty
        ? 1
        : existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    await _sessionRepo.insertSet(
      sessionExerciseId: sessionExerciseId,
      sessionId: w.sessionId,
      userId: _userId,
      setNumber: nextNum,
      weight: null,
      reps: const [],
    );
    await _reloadSets(w.sessionId);
  }

  void removeDraftSet(int groupOrder, int draftId) {
    final drafts = Map<int, List<int>>.from(state.value.workoutSetDrafts);
    drafts[groupOrder]?.remove(draftId);
    state.value = state.value.copyWith(workoutSetDrafts: drafts);
  }

  /// Commits a draft row — always inserts a fresh set row (mirrors the live
  /// session's fix: the old "fill the last empty set" heuristic landed typed
  /// data on a different row whenever an empty "+ ADD SET" row and a draft
  /// coexisted). Allows empty reps for finished workouts (the user
  /// explicitly added them in edit mode).
  Future<bool> commitDraftSet(
    String exerciseId,
    int groupOrder,
    int draftId, {
    String? variationId,
    double? weight,
    required List<num> reps,
    String? notes,
  }) async {
    final w = state.value.session;
    if (w == null) return false;
    final sessionExerciseId = await _ensureSessionExercise(exerciseId);
    if (sessionExerciseId == null) return false;
    final existing = state.value.setsFor(groupOrder);
    final nextNum = existing.isEmpty
        ? 1
        : existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    try {
      await _sessionRepo.insertSet(
        sessionExerciseId: sessionExerciseId,
        sessionId: w.sessionId,
        userId: _userId,
        variationId: variationId,
        setNumber: nextNum,
        weight: weight,
        reps: reps,
        notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
      );
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
    SessionExerciseSet set, {
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
        set.sessionExerciseSetId,
        weight: weight,
        clearWeight: clearWeight,
        reps: reps,
        variationId: variationId,
        clearVariation: clearVariation,
        notes: notes,
        clearNotes: clearNotes,
      );
      await _reloadSets(w.sessionId);
      final exerciseId = set.exerciseId;
      if (exerciseId != null) await recomputeExercisePRs(exerciseId);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> duplicateSet(SessionExerciseSet set) async {
    final w = state.value.session;
    if (w == null) return;
    final exerciseId = set.exerciseId;
    if (exerciseId == null) return;
    final existing = state.value.setsFor(
      state.value.exerciseSlots
          .firstWhere((sl) => sl.exerciseId == exerciseId)
          .groupOrder,
    );
    final nextNum =
        existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    try {
      await _sessionRepo.insertSet(
        sessionExerciseId: set.sessionExerciseId,
        sessionId: w.sessionId,
        userId: _userId,
        variationId: set.variationId,
        setNumber: nextNum,
        weight: set.weight,
        reps: set.reps,
        notes: set.notes,
      );
      await _reloadSets(w.sessionId);
      await recomputeExercisePRs(exerciseId);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  /// Removes [setId] from the in-memory setsByOrder immediately so the UI
  /// reflects the delete without depending on a reload round-trip, then
  /// deletes from the DB and reloads as the source of truth.
  Future<void> _deleteSetFromState(String setId) async {
    final s = state.value;
    final newSetsByOrder = <int, List<SessionExerciseSet>>{};
    for (final e in s.setsByOrder.entries) {
      newSetsByOrder[e.key] = e.value
          .where((x) => x.sessionExerciseSetId != setId)
          .toList();
    }
    state.value = s.copyWith(setsByOrder: newSetsByOrder);
    _computePRs();
  }

  /// Deletes the set, then re-derives PRs from the remaining history so
  /// the next-best record is promoted (e.g. delete a 170 1RM → the 160 that
  /// once beat 150 becomes the 1RM again).
  Future<void> deleteSetCascade(String setId, String exerciseId) async {
    final w = state.value.session;
    if (w == null) return;
    await _deleteSetFromState(setId);
    try {
      await _sessionRepo.deleteSet(setId);
      await recomputeExercisePRs(exerciseId);
      await _reloadSets(w.sessionId);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  // ── New exercise / variation ───────────────────────────────────────────────

  List<({String id, String name, int exerciseCount})> findSimilarVariations(
    String name,
  ) {
    // Variations are a flat library (no exercise assignment since schema v2) —
    // "used in N exercises" is derived from history.
    final usedWith = <String, Set<String>>{};
    for (final sessions in state.value.historyByExercise.values) {
      for (final session in sessions) {
        for (final s in session.sets) {
          final vid = s.variationId;
          final exId = s.exerciseId;
          if (vid != null && exId != null) {
            usedWith.putIfAbsent(vid, () => {}).add(exId);
          }
        }
      }
    }
    final results = <({String id, String name, int exerciseCount})>[];
    for (final v in state.value.allVariations) {
      if (isSimilarVariationName(name, v.name)) {
        results.add((
          id: v.variationId,
          name: v.name,
          exerciseCount: usedWith[v.variationId]?.length ?? 0,
        ));
      }
    }
    return results;
  }

  Future<void> _reloadCatalog() async {
    final map = await _exerciseRepo.fetchExerciseDetailMap(_userId);
    final variations = await _exerciseRepo.fetchVariations(_userId);
    state.value = state.value.copyWith(
      exerciseDetailMap: map,
      allVariations: variations,
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
          // Reusing an archived variation must bring it back.
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

  // ── Lessons ────────────────────────────────────────────────────────────────

  /// All active variations, most recently used first — the set-row picker
  /// order. Variations are a flat per-user library.
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
      await _lessonRepo.createLesson(
        _userId,
        exerciseId,
        text.trim(),
        sessionId: state.value.session?.sessionId,
      );
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
