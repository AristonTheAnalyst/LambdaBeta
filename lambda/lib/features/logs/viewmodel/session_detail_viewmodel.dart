import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import '../../../core/utils/name_limit.dart';
import '../../../data/cache/past_sets_timeline_cache.dart';
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
    String? userId,
  }) : _sessionRepo = sessionRepo ?? SessionRepository(),
       _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
       _lessonRepo = lessonRepo ?? LessonRepository(),
       _userIdOverride = userId;

  final SessionRepository _sessionRepo;
  final ExerciseRepository _exerciseRepo;
  final LessonRepository _lessonRepo;
  final state = ValueNotifier(const SessionDetailState());

  int _nextDraftId = 1;

  /// The host-test seam's answer; null reads the live Supabase session.
  final String? _userIdOverride;

  String get _userId => _userIdOverride ?? Supabase.instance.client.auth.currentUser!.id;

  // ── Debounced set writes (the live VM's sibling machinery) ────────────────
  /// Same contract as `SessionViewModel.kAutoCommitDebounce` — keep the two
  /// in step (2026-10-13).
  static const kAutoCommitDebounce = Duration(milliseconds: 250);

  final Map<String, _PendingDetailSetWrite> _pendingSetWrites = {};
  final Map<String, Timer> _setDebounceTimers = {};
  final Map<String, Future<void>> _setWriteChains = {};

  /// The flat timeline (oldest first) behind history derivations — served by
  /// the shared cache, refreshed whenever a write invalidates it.
  List<PastSetRow> _timelineAsc = const [];

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
        // The shared timeline cache — the first reader pays the query, every
        // later reader (logs list, library, exercise detail) rides it until
        // a write or a sync round invalidates (2026-10-13).
        PastSetsTimelineCache.instance.get(_userId),
        _exerciseRepo.fetchVariations(_userId),
      ]);
      final timeline = results[1] as List<PastSetRow>;
      _timelineAsc = PastSetsTimelineCache.instance.asc(_userId) ?? timeline;
      state.value = state.value.copyWith(
        exerciseDetailMap: results[0] as Map<String, ExerciseDetail>,
        historyByExercise: groupHistoryByExercise(timeline),
        pastSetsLoaded: true,
        allVariations: results[2] as List<CustomVariation>,
      );
      _computePRs();
    } catch (_) {
      // Background context is best-effort; core workout already rendered.
    }
  }

  /// Re-derives PR highlighting from the timeline (oldest-first, excluding
  /// this workout's own stale rows) merged with this workout's CURRENT sets,
  /// scoped to the exercises this screen can show (2026-10-13). The merge is
  /// positional, not a sort: the timeline already walks chronologically, and
  /// this workout's rows slot in at their session date — the one tolerance
  /// is a same-timestamp session, where the tie-break follows insertion
  /// order rather than set number (timestamps carry milliseconds, so the
  /// case is effectively unreachable).
  void _computePRs() {
    final s = state.value;
    final thisWorkoutId = s.session?.sessionId;
    final thisDate = s.session?.createdDatetime ?? DateTime.now();

    final slotExerciseIds = s.exerciseSlots
        .map((sl) => sl.exerciseId)
        .toSet();

    final combined = <PastSetRow>[];
    var inserted = false;
    for (final row in _timelineAsc) {
      if (row.sessionId == thisWorkoutId) continue; // replaced below
      if (row.exerciseId == null || !slotExerciseIds.contains(row.exerciseId)) {
        continue;
      }
      if (!inserted && row.sessionCreatedDate.isAfter(thisDate)) {
        combined.addAll(_thisSessionRows(s, thisDate));
        inserted = true;
      }
      combined.add(row);
    }
    if (!inserted) combined.addAll(_thisSessionRows(s, thisDate));

    final allEvents = prEventsSorted(combined);
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

  /// This workout's current sets as timeline rows — set-number order, all
  /// sharing the workout's session date.
  List<PastSetRow> _thisSessionRows(SessionDetailState s, DateTime date) {
    final rows = <PastSetRow>[];
    for (final sets in s.setsByOrder.values) {
      for (final set in sets) {
        rows.add(
          PastSetRow(
            sessionExerciseSetId: set.sessionExerciseSetId,
            sessionExerciseId: set.sessionExerciseId,
            sessionId: set.sessionId,
            userId: set.userId,
            exerciseId: set.exerciseId,
            setNumber: set.setNumber,
            reps: set.reps,
            sessionCreatedDate: date,
            variationId: set.variationId,
            weight: set.weight,
            notes: set.notes,
            exerciseName: set.exerciseName,
            variationName: set.variationName,
          ),
        );
      }
    }
    rows.sort((a, b) => a.setNumber.compareTo(b.setNumber));
    return rows;
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
    // History derives from the same timeline — through the shared cache,
    // which the structural write that led here has already invalidated
    // (2026-10-13).
    final userId = _userId;
    final timeline = await PastSetsTimelineCache.instance.get(userId);
    _timelineAsc = PastSetsTimelineCache.instance.asc(userId) ?? timeline;
    state.value = state.value.copyWith(
      exerciseSlots: slots,
      setsByOrder: _groupByOrder(sets, slots),
      historyByExercise: groupHistoryByExercise(timeline),
      clearSessionSetDrafts: true,
    );
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
  /// viewer's mirror of the planner's remove, so removing a ticked row in the
  /// add-exercise modal works in edit mode. Sets go through
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

  /// Hold-and-drag reorder of one exercise group's logged sets.
  ///
  /// [oldIndex] and [newIndex] count that group's REAL rows only, and
  /// [newIndex] arrives already adjusted for the row being lifted out
  /// (`onReorderItem`). Draft rows sit past the end and cannot be dropped
  /// into — a drop there means "last real set".
  ///
  /// The renumber is local only, like [reorderExercises]: nothing is re-read,
  /// because the values are untouched and the only thing that changed is the
  /// column the read already sorts by. Renumbering is also what makes the new
  /// order real — the group renders in `set_number` order, so a reorder that
  /// left the numbers alone would undo itself on the next rebuild.
  void reorderSets(int groupOrder, int oldIndex, int newIndex) {
    final group = [
      ...state.value.setsFor(groupOrder),
    ]..sort((a, b) => a.setNumber.compareTo(b.setNumber));
    if (group.length < 2) return;
    if (newIndex >= group.length) newIndex = group.length - 1;
    if (oldIndex == newIndex || oldIndex < 0 || oldIndex >= group.length) {
      return;
    }

    group.insert(newIndex, group.removeAt(oldIndex));
    // The group list becomes the new order — this viewer has no sort of its
    // own, it draws `setsFor` exactly as it finds it.
    final ordered = [
      for (var i = 0; i < group.length; i++) group[i].copyWith(setNumber: i + 1),
    ];
    final byOrder = Map<int, List<SessionExerciseSet>>.from(
      state.value.setsByOrder,
    );
    byOrder[groupOrder] = ordered;
    state.value = state.value.copyWith(setsByOrder: byOrder);

    final w = state.value.session;
    if (w != null) {
      _sessionRepo.reorderSets(w.sessionId, [
        for (final s in ordered) s.sessionExerciseSetId,
      ]);
    }
  }

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
      return true;
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
      return false;
    }
  }

  /// The edit-mode set write (2026-10-13): keystroke commits merge into one
  /// debounced write per settle — the same contract as the live VM. The
  /// settle writes once, patches the row in state (both the sets grid and
  /// the timeline's copy of it — the edited workout IS in the timeline), and
  /// re-derives PRs — zero queries per keystroke, one state update per
  /// settle. Discrete edits (blur flush, variation pick, notes save) pass
  /// [immediate] and write now. A failed write patches nothing: the state
  /// keeps the pre-edit row, and the error surface says what happened.
  Future<void> quickUpdateSet(
    SessionExerciseSet set, {
    double? weight,
    bool clearWeight = false,
    List<num>? reps,
    bool clearReps = false,
    String? variationId,
    bool clearVariation = false,
    String? notes,
    bool clearNotes = false,
    bool immediate = false,
  }) {
    final w = state.value.session;
    if (w == null) return Future.value();
    final pending = _pendingSetWrites.putIfAbsent(
      set.sessionExerciseSetId,
      _PendingDetailSetWrite.new,
    );
    pending.merge(
      weight: weight,
      clearWeight: clearWeight,
      reps: reps,
      clearReps: clearReps,
      variationId: variationId,
      clearVariation: clearVariation,
      notes: notes,
      clearNotes: clearNotes,
    );
    _setDebounceTimers.remove(set.sessionExerciseSetId)?.cancel();
    if (immediate) return _flushSetWrite(set.sessionExerciseSetId);
    _setDebounceTimers[set.sessionExerciseSetId] = Timer(
      kAutoCommitDebounce,
      () {
        _setDebounceTimers.remove(set.sessionExerciseSetId);
        unawaited(_flushSetWrite(set.sessionExerciseSetId));
      },
    );
    return Future.value();
  }

  Future<void> _flushSetWrite(String setId) async {
    final pending = _pendingSetWrites.remove(setId);
    if (pending == null) return;
    final previous = _setWriteChains[setId];
    final run = (previous ?? Future<void>.value()).then(
      (_) => _writePendingSet(setId, pending),
    );
    _setWriteChains[setId] = run;
    await run;
    if (identical(_setWriteChains[setId], run)) _setWriteChains.remove(setId);
  }

  Future<void> _writePendingSet(String setId, _PendingDetailSetWrite p) async {
    try {
      await _sessionRepo.updateSet(
        setId,
        weight: p.weight,
        clearWeight: p.clearWeight,
        reps: p.reps,
        clearReps: p.clearReps,
        variationId: p.variationId,
        clearVariation: p.clearVariation,
        notes: p.notes,
        clearNotes: p.clearNotes,
      );
      // The write invalidated the shared timeline cache — re-read it so the
      // next derivation (here and everywhere else) sees the edit, and keep
      // the asc copy for the sorted PR walk.
      final userId = _userId;
      final timeline = await PastSetsTimelineCache.instance.get(userId);
      _timelineAsc = PastSetsTimelineCache.instance.asc(userId) ?? timeline;
      _applySetPatchToState(setId, p);
      _computePRs();
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  /// Replaces the edited row in [SessionDetailState.setsByOrder] and in its
  /// timeline copy ([SessionDetailState.historyByExercise]) with the values
  /// just written — the DB and the patch agree by construction.
  void _applySetPatchToState(String setId, _PendingDetailSetWrite p) {
    final s = state.value;

    final newSetsByOrder = <int, List<SessionExerciseSet>>{};
    for (final e in s.setsByOrder.entries) {
      newSetsByOrder[e.key] = [
        for (final set in e.value)
          if (set.sessionExerciseSetId == setId)
            SessionExerciseSet(
              sessionExerciseSetId: set.sessionExerciseSetId,
              sessionExerciseId: set.sessionExerciseId,
              sessionId: set.sessionId,
              userId: set.userId,
              exerciseId: set.exerciseId,
              variationId: p.clearVariation
                  ? null
                  : (p.variationId ?? set.variationId),
              setNumber: set.setNumber,
              weight: p.clearWeight ? null : (p.weight ?? set.weight),
              reps: p.clearReps ? const [] : (p.reps ?? set.reps),
              notes: p.clearNotes ? null : (p.notes ?? set.notes),
              exerciseName: set.exerciseName,
              variationName: set.variationName,
              plannedSetId: set.plannedSetId,
            )
          else
            set,
      ];
    }

    final newHistory = <String, List<ExerciseHistorySession>>{};
    for (final entry in s.historyByExercise.entries) {
      newHistory[entry.key] = [
        for (final session in entry.value)
          ExerciseHistorySession(
            date: session.date,
            sets: [
              for (final set in session.sets)
                if (set.sessionExerciseSetId == setId)
                  PastSetRow(
                    sessionExerciseSetId: set.sessionExerciseSetId,
                    sessionExerciseId: set.sessionExerciseId,
                    sessionId: set.sessionId,
                    userId: set.userId,
                    exerciseId: set.exerciseId,
                    variationId: p.clearVariation
                        ? null
                        : (p.variationId ?? set.variationId),
                    setNumber: set.setNumber,
                    weight: p.clearWeight ? null : (p.weight ?? set.weight),
                    reps: p.clearReps ? const [] : (p.reps ?? set.reps),
                    notes: p.clearNotes ? null : (p.notes ?? set.notes),
                    exerciseName: set.exerciseName,
                    variationName: set.variationName,
                    plannedSetId: set.plannedSetId,
                    sessionCreatedDate: set.sessionCreatedDate,
                  )
                else
                  set,
            ],
          ),
      ];
    }

    state.value = s.copyWith(
      setsByOrder: newSetsByOrder,
      historyByExercise: newHistory,
    );
  }

  /// Inserts a new set copying [set] — the grid row's swipe Duplicate. The
  /// row passes the text on screen as [weight]/[reps] overrides: the copy
  /// must carry what the user just typed, which a debounced write may not
  /// have settled into [set] yet (2026-10-13).
  Future<void> duplicateSet(
    SessionExerciseSet set, {
    double? weight,
    List<num>? reps,
  }) async {
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
        weight: weight ?? set.weight,
        reps: reps ?? set.reps,
        notes: set.notes,
      );
      await _reloadSets(w.sessionId);
      _computePRs();
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
      _computePRs();
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
    if (nameTooLong(trimmed)) return null;
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
    // Only the name-bearing path is capped: a "did you mean?" pick carries the
    // id, and refusing it over the typed text would break the reuse it exists
    // for.
    if (useExistingId == null && nameTooLong(trimmed)) return null;
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
  /// Most recently used first — memoized on the identity of its two inputs
  /// (both are replaced wholesale), so a rebuild no longer walks the whole
  /// history per access (2026-10-13).
  List<CustomVariation>? _variationsByRecencyCache;
  Map<String, List<ExerciseHistorySession>>? _vrHistory;
  List<CustomVariation>? _vrAllVariations;

  List<CustomVariation> get variationsByRecency {
    final history = state.value.historyByExercise;
    final variations = state.value.allVariations;
    if (identical(_vrHistory, history) &&
        identical(_vrAllVariations, variations) &&
        _variationsByRecencyCache != null) {
      return _variationsByRecencyCache!;
    }
    _vrHistory = history;
    _vrAllVariations = variations;
    final last = <String, DateTime>{};
    for (final sessions in history.values) {
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
    return _variationsByRecencyCache =
        CustomVariation.sortByLastUsed(variations, last);
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

/// One set's merged, not-yet-written edits — the detail VM's debounce holder
/// (mirrors the live VM's `_PendingSetWrite`; the two VMs flush differently,
/// so each owns its copy — 2026-10-13).
class _PendingDetailSetWrite {
  double? weight;
  bool clearWeight = false;
  List<num>? reps;
  bool clearReps = false;
  String? variationId;
  bool clearVariation = false;
  String? notes;
  bool clearNotes = false;

  void merge({
    double? weight,
    bool clearWeight = false,
    List<num>? reps,
    bool clearReps = false,
    String? variationId,
    bool clearVariation = false,
    String? notes,
    bool clearNotes = false,
  }) {
    if (weight != null || clearWeight) {
      this.weight = weight;
      this.clearWeight = clearWeight;
    }
    if (reps != null || clearReps) {
      this.reps = reps;
      this.clearReps = clearReps;
    }
    if (variationId != null || clearVariation) {
      this.variationId = variationId;
      this.clearVariation = clearVariation;
    }
    if (notes != null || clearNotes) {
      this.notes = notes;
      this.clearNotes = clearNotes;
    }
  }
}
