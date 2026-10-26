import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import 'package:uuid/uuid.dart';
import '../../../core/utils/device_id.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/name_limit.dart';
import '../../../core/utils/undo_history.dart';
import '../../../data/cache/past_sets_timeline_cache.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/exercise_usage.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/session.dart';
import '../../../data/models/session_exercise.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../programs/model/program_achievements.dart';
import '../../session/model/pr_engine.dart';
import '../../session/model/session_local_state.dart'
    show
        ExerciseHistorySession,
        SessionDateMode,
        groupHistoryByExercise,
        isSimilarVariationName;

/// One tab in the workout-detail screen — a single exercise that was logged
/// in this workout, backed by its fact_session_exercise row.
class SessionDetailExerciseSlot {
  const SessionDetailExerciseSlot({
    required this.groupOrder,
    required this.exerciseId,
    this.sessionExerciseId,
    this.deleted = false,
    this.planned = false,
  });
  final int groupOrder;
  final String exerciseId;
  final String? sessionExerciseId;

  /// Every row this exercise holds is flagged (`is_deleted`) — it was
  /// deleted during the workout (or a later edit) and is shown red, with a
  /// Restore, but keeps its slot so the reader sees what went (2026-10-14).
  final bool deleted;

  /// The exercise came from the plan (`planned_exercise_id` set). Sets
  /// deleted under a plan-linked exercise flag instead of hard-deleting —
  /// the plan's rows and the user's own additions alike — so its Restore
  /// brings back everything underneath it (2026-10-14).
  final bool planned;

  SessionDetailExerciseSlot copyWith({bool? deleted}) =>
      SessionDetailExerciseSlot(
        groupOrder: groupOrder,
        exerciseId: exerciseId,
        sessionExerciseId: sessionExerciseId,
        deleted: deleted ?? this.deleted,
        planned: planned,
      );
}

/// The date bar's neighbours (2026-10-22): the completed sessions on either
/// side of the record on screen, plus whether a live session stands past the
/// newest record — the bar's right arrow at the top of the stack walks back
/// onto "today" rather than dead-ending. Null until read; a failed read
/// leaves the bar's arrows inert rather than failing the page.
class SessionWalk {
  const SessionWalk({this.olderId, this.newerId, this.hasLiveSession = false});

  /// The next-older completed session; null when this record is the oldest.
  final String? olderId;

  /// The next-newer completed session; null at the top of the stack, where
  /// [hasLiveSession] decides whether the right arrow has somewhere to go.
  final String? newerId;

  /// Whether this device has a live session right now — the "today" the
  /// newest record steps forward onto.
  final bool hasLiveSession;
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
    this.allPrEvents = const [],
    this.prEventSetIds = const {},
    this.goalSetIds = const {},
    this.walk,
    this.dateBarMode = SessionDateMode.exercise,
    this.exerciseHistoryIndex = 0,
    this.exerciseHistoryForId,
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

  /// Every PR event on the merged timeline for the exercises this record
  /// holds — history plus this record's own rows, oldest first. The PR
  /// History sheet's full feed (2026-10-22).
  final List<PrEvent> allPrEvents;
  final Set<String> prEventSetIds;

  /// The sets that achieved one of the user's goals (2026-10-20) — green with
  /// the `G` badge, the same marks the live grid draws. A set that is both a
  /// goal's and a PR draws as the goal while still counting as a PR.
  final Set<String> goalSetIds;

  /// The date bar's neighbours — read alongside the session, not part of it
  /// (2026-10-22). Null while unknown: the arrows hold their spent shape.
  final SessionWalk? walk;

  /// Which stack the date bar walks (2026-10-23). EXERCISE — the default on
  /// this surface too — walks the active exercise's own past performances
  /// and swaps only the card's sets; SESSION walks whole records
  /// ([walk]), the page swapping under the bar.
  final SessionDateMode dateBarMode;

  /// EXERCISE mode's position in [exerciseHistoryStack]: 0 is the record on
  /// screen, N its Nth-older performance of the active exercise. Only
  /// meaningful for the exercise it was stepped on ([exerciseHistoryForId]);
  /// a structural change that puts another exercise on the card reads as
  /// home without a reset at every add/remove site (2026-10-23).
  final int exerciseHistoryIndex;

  /// The exercise [exerciseHistoryIndex] belongs to.
  final String? exerciseHistoryForId;

  /// The record's name in a header: the plan it followed at the time
  /// (`fact_session.planned_session_name`), or Freestyle when it had no plan
  /// (2026-10-23). Null while no record is loaded — the caller keeps whatever
  /// it was naming until the record lands.
  String? get sessionTitle => session == null
      ? null
      : (session!.plannedSessionName ?? 'Freestyle Session');

  SessionDetailExerciseSlot? get activeSlot => exerciseSlots.isEmpty
      ? null
      : exerciseSlots[activeSlotIndex.clamp(0, exerciseSlots.length - 1)];

  List<SessionExerciseSet> setsFor(int groupOrder) =>
      setsByOrder[groupOrder] ?? [];

  /// The active exercise's performances EXERCISE mode can walk: the ones
  /// strictly older than the record on screen, newest first (2026-10-23).
  /// The record itself is home (index 0), drawn as the card's real grid —
  /// edit mode and all — so it is not in the stack; sessions later than
  /// this record are not walked either, because the page keeps naming the
  /// record it opened on. Empty until the heavy read lands.
  List<ExerciseHistorySession> get exerciseHistoryStack {
    final slot = activeSlot;
    final recordId = session?.sessionId;
    if (slot == null || recordId == null) return const [];
    final all = historyByExercise[slot.exerciseId] ?? const [];
    final at = all.indexWhere(
      (h) => h.sets.isNotEmpty && h.sets.first.sessionId == recordId,
    );
    if (at < 0) return const [];
    return all.sublist(at + 1);
  }

  /// EXERCISE mode's effective position: [exerciseHistoryIndex] only while
  /// the exercise it was stepped on still owns the card and the stack still
  /// holds that far; home (0) otherwise.
  int get effectiveExerciseHistoryIndex {
    if (dateBarMode != SessionDateMode.exercise) return 0;
    if (activeSlot?.exerciseId != exerciseHistoryForId) return 0;
    return exerciseHistoryIndex.clamp(0, exerciseHistoryStack.length);
  }

  /// The performance the card is drawing in EXERCISE mode; null at home,
  /// where the record's own sets are the card.
  ExerciseHistorySession? get viewedHistorySession {
    final position = effectiveExerciseHistoryIndex;
    if (position <= 0) return null;
    final stack = exerciseHistoryStack;
    final index = position - 1;
    return index < stack.length ? stack[index] : null;
  }

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
    List<PrEvent>? allPrEvents,
    Set<String>? prEventSetIds,
    Set<String>? goalSetIds,
    SessionWalk? walk,
    bool clearWalk = false,
    SessionDateMode? dateBarMode,
    int? exerciseHistoryIndex,
    String? exerciseHistoryForId,
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
    allPrEvents: allPrEvents ?? this.allPrEvents,
    prEventSetIds: prEventSetIds ?? this.prEventSetIds,
    goalSetIds: goalSetIds ?? this.goalSetIds,
    walk: clearWalk ? null : (walk ?? this.walk),
    dateBarMode: dateBarMode ?? this.dateBarMode,
    exerciseHistoryIndex: exerciseHistoryIndex ?? this.exerciseHistoryIndex,
    exerciseHistoryForId: exerciseHistoryForId ?? this.exerciseHistoryForId,
  );
}

/// Goal ids are minted here, the way the goals screen mints its own: a goal
/// created from a record is the same row, written from the other door.
const _uuid = Uuid();

class SessionDetailViewModel {
  SessionDetailViewModel({
    SessionRepository? sessionRepo,
    ExerciseRepository? exerciseRepo,
    LessonRepository? lessonRepo,
    ProgramRepository? programRepo,
    String? userId,
  }) : _sessionRepo = sessionRepo ?? SessionRepository(),
       _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
       _lessonRepo = lessonRepo ?? LessonRepository(),
       _programRepo = programRepo ?? ProgramRepository(),
       _userIdOverride = userId;

  final SessionRepository _sessionRepo;
  final ExerciseRepository _exerciseRepo;
  final LessonRepository _lessonRepo;
  final ProgramRepository _programRepo;
  final state = ValueNotifier(const SessionDetailState());

  int _nextDraftId = 1;

  /// The host-test seam's answer; null reads the live Supabase session.
  final String? _userIdOverride;

  String get _userId =>
      _userIdOverride ?? Supabase.instance.client.auth.currentUser!.id;

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

  /// The user's goals, read with the heavy context so a set that achieved one
  /// wears the G badge (2026-10-20). Empty when the read failed — the grid
  /// renders bare rather than not at all.
  List<Goal> _goals = const [];

  /// The completed history the goal form reads — its "already beat this"
  /// verdict and its picker ordering (2026-10-26). The record on screen is in
  /// it: this is a past session, and its own sets are exactly what the form
  /// is asking about.
  List<PastSetRow> get pastSets => _timelineAsc;

  /// exerciseId/variation-id → the date last trained, over the same timeline
  /// — the goal form's picker ordering on this surface.
  Map<String, DateTime> get lastUsedByExercise => lastUsedByEntity(_timelineAsc);

  /// Writes a goal from a set on this page (2026-10-26) — the row's own
  /// drawer opens the New goal form seeded with it, and this is the write
  /// behind its ADD.
  ///
  /// The same row the goals screen writes (`Goal` is scoped by user, and
  /// this view model's user is the record's owner), and then the target is
  /// folded into the derived G badges IN PLACE: `_computePRs` re-walks the
  /// merged timeline against the new goal, so the set that meets it wears
  /// its `G` with the record still on the desk — no reload.
  Future<bool> createGoalFromTarget(ExerciseTarget target) async {
    final notes = target.notes?.trim();
    final goal = Goal(
      goalId: _uuid.v4(),
      userId: _userId,
      text: target.exerciseName,
      description: (notes?.isEmpty ?? true) ? null : notes,
      exerciseId: target.exerciseId,
      variationId: target.variationId,
      targetWeight: target.weight,
      targetReps: target.reps,
      targetDate: target.targetDate == null
          ? null
          : dateOnly(target.targetDate!),
    );
    try {
      await _programRepo.createGoal(_userId, goal);
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
      return false;
    }
    _goals = [..._goals, goal];
    _computePRs();
    return true;
  }

  // ── Undo/redo (structural actions only — 2026-10-13) ──────────────────────
  final ActionUndoHistory undoHistory = ActionUndoHistory();
  bool _suppressHistory = false;
  bool _undoInFlight = false;

  bool get canUndo => undoHistory.canUndo;
  bool get canRedo => undoHistory.canRedo;

  void _recordUndo(UndoAction action) {
    if (_suppressHistory) return;
    undoHistory.push(action);
  }

  /// Drains the debounce maps — an undo/redo must not race a typed edit's
  /// settle (2026-10-13).
  Future<void> flushPendingCommits() async {
    for (final id in List.of(_pendingSetWrites.keys)) {
      _setDebounceTimers.remove(id)?.cancel();
      try {
        await _flushSetWrite(id);
      } catch (_) {}
    }
  }

  Future<void> undo() async {
    if (_undoInFlight || !undoHistory.canUndo) return;
    _undoInFlight = true;
    try {
      await flushPendingCommits();
      await undoHistory.undo();
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
    _undoInFlight = false;
    state.value = state.value.copyWith();
  }

  Future<void> redo() async {
    if (_undoInFlight || !undoHistory.canRedo) return;
    _undoInFlight = true;
    try {
      await flushPendingCommits();
      await undoHistory.redo();
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
    _undoInFlight = false;
    state.value = state.value.copyWith();
  }

  /// Builds slots in the order the user arranged them during the session —
  /// `fact_session_exercise.exercise_order` (a real column now; the old JSON
  /// blob is gone). Exercises with no logged row (null exercise) are skipped.
  ///
  /// An exercise whose rows are ALL flagged was deleted — during the workout
  /// or in an edit — and still gets a slot, at its own number, with
  /// `deleted: true`: the viewer draws it red and offers the restore, because
  /// the deletion is a historic fact (2026-10-14).
  List<SessionDetailExerciseSlot> _buildSlots(
    List<SessionExercise> exercises,
    List<SessionExerciseSet> sets,
  ) {
    final sorted = [...exercises]
      ..sort((a, b) => a.exerciseOrder.compareTo(b.exerciseOrder));
    final slots = <SessionDetailExerciseSlot>[];
    var order = 1;
    for (final e in sorted) {
      final exerciseId = e.exerciseId;
      if (exerciseId == null) continue;
      final rows = [
        for (final s in sets)
          if (s.sessionExerciseId == e.sessionExerciseId) s,
      ];
      slots.add(
        SessionDetailExerciseSlot(
          groupOrder: order++,
          exerciseId: exerciseId,
          sessionExerciseId: e.sessionExerciseId,
          deleted: _rowsAllFlagged(rows),
          planned: e.plannedExerciseId != null,
        ),
      );
    }
    return slots;
  }

  /// True when there are rows and every one of them is flagged.
  static bool _rowsAllFlagged(List<SessionExerciseSet> rows) =>
      rows.isNotEmpty && rows.every((r) => r.isDeleted);

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

  /// Opens a record — the route's first load, or a different route id under
  /// a reused State. Shows the spinner: there is nothing on screen yet.
  Future<void> load(String sessionId, {String? initialExerciseId}) =>
      _loadSession(sessionId, initialExerciseId: initialExerciseId);

  /// Steps the date bar onto a neighbouring record **in place** (2026-10-22):
  /// the same screen and the same view model read the other session — the PR
  /// Lab's pager, not a navigation. The record being left stays on screen
  /// until the new read lands (never a spinner over a page that already has
  /// sets), and nothing belonging to it survives the step: edit mode and its
  /// drafts end, and the session-scoped reads (PRs, history, lessons) are
  /// rebuilt for the record arriving.
  Future<void> walkTo(String sessionId) =>
      _loadSession(sessionId, inPlace: true);

  /// The newest load wins: a fast second step must not be overwritten by the
  /// slower read it overtook.
  int _loadToken = 0;

  Future<void> _loadSession(
    String sessionId, {
    String? initialExerciseId,
    bool inPlace = false,
  }) async {
    final token = ++_loadToken;
    final carried = state.value;
    // The edit pass belongs to the record being left — its undo steps must
    // not outlive it, or an undo on the arriving record would rewrite the
    // one that left (2026-10-22).
    if (inPlace) undoHistory.clear();
    state.value = carried.copyWith(
      isLoading: !inPlace,
      clearError: true,
      // A stepped-to record is a different session: the previous record's
      // neighbours must not brief the bar while the new one loads.
      clearWalk: true,
      // A step leaves the old record's edit pass behind; the one arriving
      // is read-only until its own Edit is tapped.
      isEditing: false,
      clearSessionSetDrafts: true,
      // The card opens on the record's own sets, whatever the last one's
      // exercise walk was showing.
      exerciseHistoryIndex: 0,
    );
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
      if (token != _loadToken) return;
      final exercises = results[1] as List<SessionExercise>;
      final sets = results[2] as List<SessionExerciseSet>;
      final session = results[0] as Session?;
      final slots = _buildSlots(exercises, sets);
      // A step starts the record clean. The catalog, the variations, the
      // user's history and the exercises' notes are the user's, not the
      // record's, so they cross with the reader rather than blinking
      // through an empty list — the swap frame can draw the card's history
      // picker, notes and PR badges from the first paint (2026-10-23).
      // The date bar's mode is the reader's reading, not the record's: a
      // SESSION walk keeps walking sessions.
      final base = inPlace
          ? SessionDetailState(
              exerciseDetailMap: carried.exerciseDetailMap,
              allVariations: carried.allVariations,
              historyByExercise: carried.historyByExercise,
              pastSetsLoaded: carried.pastSetsLoaded,
              lessonsByExercise: carried.lessonsByExercise,
              dateBarMode: carried.dateBarMode,
            )
          : state.value;
      state.value = base.copyWith(
        isLoading: false,
        session: session,
        exerciseSlots: slots,
        setsByOrder: _groupByOrder(sets, slots),
        // The goal sheet's completion row opens the workout that hit the goal
        // (2026-10-20): the reader lands on the exercise that achieved it.
        activeSlotIndex: _slotForExercise(slots, initialExerciseId),
        exerciseHistoryIndex: 0,
      );
      // The timeline already in hand (the shared cache, or the record just
      // left) re-derives this record's PRs NOW, so the swap frame carries
      // its badges instead of waiting for the heavy wave to return.
      if (_timelineAsc.isNotEmpty) _computePRs();
      _loadHeavyContext();
      // The date bar's walk, alongside the page: the arrows fill in when the
      // list answers, and an unanswerable read leaves them inert.
      unawaited(_loadWalk(sessionId));
      // Lessons for the session's exercises load with the session, so the
      // card's pill and the floor tile count from the first frame — waiting
      // for the modal to open would leave both reading zero (2026-10-22).
      for (final id in {for (final sl in slots) sl.exerciseId}) {
        unawaited(loadLessonsFor(id));
      }
    } catch (e) {
      if (token != _loadToken) return;
      state.value = state.value.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// The slot drawing [exerciseId], or 0 — a workout can hold the exercise
  /// twice, and the first slot is as good an answer as the second.
  int _slotForExercise(
    List<SessionDetailExerciseSlot> slots,
    String? exerciseId,
  ) {
    if (exerciseId == null) return 0;
    final index = slots.indexWhere((s) => s.exerciseId == exerciseId);
    return index < 0 ? 0 : index;
  }

  /// Reads the date bar's neighbours (2026-10-22): the completed sessions
  /// either side of this record, and — at the newest record — whether a
  /// live session stands past it ("today"). Chrome, so failure is silent:
  /// the arrows stay spent rather than the page refusing to open.
  Future<void> _loadWalk(String sessionId) async {
    try {
      final stamps = await _sessionRepo.loadCompletedSessionStamps(_userId);
      final index = stamps.indexWhere((s) => s.sessionId == sessionId);
      if (index < 0) return;
      var hasLive = false;
      if (index == 0) {
        hasLive =
            await _sessionRepo.getActiveSessionId(
              _userId,
              deviceId: await DeviceId.get(),
            ) !=
            null;
      }
      // A fast second step can land the old read after the new session's;
      // the walk is only ever written for the record now on screen.
      if (state.value.session?.sessionId != sessionId) return;
      state.value = state.value.copyWith(
        walk: SessionWalk(
          olderId: index + 1 < stamps.length
              ? stamps[index + 1].sessionId
              : null,
          newerId: index > 0 ? stamps[index - 1].sessionId : null,
          hasLiveSession: hasLive,
        ),
      );
    } catch (_) {
      // The walk is chrome — a failed read leaves the arrows inert.
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
      final grouped = groupHistoryByExercise(timeline);
      state.value = state.value.copyWith(
        exerciseDetailMap: results[0] as Map<String, ExerciseDetail>,
        historyByExercise: grouped,
        pastSetsLoaded: true,
        allVariations: results[2] as List<CustomVariation>,
      );
      // Goals ride along, non-fatal: the G badge is an extra on the grid, and
      // a failed goal read must not take the timeline down with it
      // (2026-10-20).
      try {
        _goals = [
          for (final option in await _programRepo.fetchGoalOptions(_userId))
            option.goal,
        ];
      } catch (_) {
        _goals = const [];
      }
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

    final slotExerciseIds = s.exerciseSlots.map((sl) => sl.exerciseId).toSet();

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
      // The full feed the PR History sheet reads — every PR the record's
      // exercises ever landed, this record's own included (2026-10-22).
      allPrEvents: allEvents,
      // Full-timeline event set ids — accents use the session events; the
      // history viewer's rows badge past sets via this map.
      prEventSetIds: {
        for (final e in allEvents)
          if (e.sessionExerciseSetId != null) e.sessionExerciseSetId!,
      },
      // The goal sets over the same merged timeline — the earliest set that
      // met each target, so only it wears the G (2026-10-20).
      goalSetIds: goalAchievingSetIds(goals: _goals, sets: combined),
    );
  }

  /// This workout's current sets as timeline rows — set-number order, all
  /// sharing the workout's session date. Flagged (deleted) rows are left out:
  /// a deleted set is not performed work and never earns a PR (2026-10-14).
  List<PastSetRow> _thisSessionRows(SessionDetailState s, DateTime date) {
    final rows = <PastSetRow>[];
    for (final sets in s.setsByOrder.values) {
      for (final set in sets) {
        if (set.isDeleted) continue;
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
      state.value.prEvents.where((p) => p.exerciseId == exerciseId).toList();

  /// Every PR [exerciseId] ever landed — all its variations, oldest first —
  /// the PR History sheet's full feed (2026-10-22).
  List<PrEvent> prHistoryFor(String exerciseId) => [
    for (final e in state.value.allPrEvents)
      if (e.exerciseId == exerciseId) e,
  ];

  /// The set ids this record landed PRs on for [exerciseId] — what splits
  /// [prHistoryFor] into `THIS SESSION` and `PREVIOUSLY`.
  Set<String> sessionPrSetIdsFor(String exerciseId) => {
    for (final e in state.value.prEvents)
      if (e.exerciseId == exerciseId && e.sessionExerciseSetId != null)
        e.sessionExerciseSetId!,
  };

  Future<void> _reloadSets(String sessionId) async {
    final exercises = await _sessionRepo.loadSessionExercises(sessionId);
    final sets = await _sessionRepo.loadSetsForSession(sessionId);
    final slots = _buildSlots(exercises, sets);
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
    undoHistory.clear();
    final w = state.value.session;
    state.value = state.value.copyWith(
      isEditing: true,
      // The edit surface is the record's own grid: a past performance the
      // date bar was showing steps aside for it (2026-10-23).
      exerciseHistoryIndex: 0,
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

  /// The star callbacks carry the tapped number, not the resulting value —
  /// these setters own the toggle rule (tap the selected star to clear),
  /// exactly like the live VM's `setSessionFeeling` / `setEndFeeling`, so
  /// the ratings sheet and the stored value can never disagree (2026-10-22).
  void setPreFeelingDraft(int? v) => state.value = state.value.copyWith(
    preFeelingDraft: state.value.preFeelingDraft == v ? null : v,
  );

  void setPostFeelingDraft(int? v) => state.value = state.value.copyWith(
    postFeelingDraft: state.value.postFeelingDraft == v ? null : v,
  );

  Future<void> saveNotes() async {
    // The record on screen, not a route id: the date bar swaps records in
    // place, so the URL keeps naming the page that opened (2026-10-22).
    final sessionId = state.value.session?.sessionId;
    if (sessionId == null) return;
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

  void tapTab(int index) => state.value = state.value.copyWith(
    activeSlotIndex: index,
    // The card decides what EXERCISE mode walks: a new exercise starts home.
    exerciseHistoryIndex: 0,
  );

  void reorderExercises(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final s = state.value;
    // A deleted exercise is not movable — it sits at its historic number
    // until restored (2026-10-14). The persisted arrangement below keeps it
    // in the list, so its order column stays in step with the visible bar.
    if (oldIndex < 0 ||
        oldIndex >= s.exerciseSlots.length ||
        s.exerciseSlots[oldIndex].deleted) {
      return;
    }
    final orderBefore = [for (final sl in s.exerciseSlots) sl.groupOrder];

    Future<void> forward() async {
      final cur = state.value;
      final slots = [...cur.exerciseSlots];
      final slot = slots.removeAt(oldIndex);
      slots.insert(newIndex, slot);
      int newActive = cur.activeSlotIndex;
      if (cur.activeSlotIndex == oldIndex) {
        newActive = newIndex;
      } else if (oldIndex < cur.activeSlotIndex &&
          newIndex >= cur.activeSlotIndex) {
        newActive = cur.activeSlotIndex - 1;
      } else if (oldIndex > cur.activeSlotIndex &&
          newIndex <= cur.activeSlotIndex) {
        newActive = cur.activeSlotIndex + 1;
      }
      state.value = cur.copyWith(
        exerciseSlots: slots,
        activeSlotIndex: newActive,
      );
      // Persist the arrangement back to fact_session_exercise.exercise_order so
      // a reorder made here sticks for the live viewer's restore too.
      final w = state.value.session;
      if (w != null) {
        await _sessionRepo.reorderSessionExercises(w.sessionId, [
          for (final slot in state.value.exerciseSlots)
            if (slot.sessionExerciseId != null) slot.sessionExerciseId!,
        ]);
      }
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final cur = state.value;
          final byOrder = {
            for (final sl in cur.exerciseSlots) sl.groupOrder: sl,
          };
          state.value = cur.copyWith(
            exerciseSlots: [
              for (final o in orderBefore)
                if (byOrder[o] != null) byOrder[o]!,
            ],
            activeSlotIndex: cur.activeSlotIndex,
          );
          final w = state.value.session;
          if (w != null) {
            await _sessionRepo.reorderSessionExercises(w.sessionId, [
              for (final slot in state.value.exerciseSlots)
                if (slot.sessionExerciseId != null) slot.sessionExerciseId!,
            ]);
          }
        },
        replay: () async {
          _suppressHistory = true;
          try {
            await forward();
          } finally {
            _suppressHistory = false;
          }
        },
      ),
    );
    unawaited(forward());
  }

  // ── Deleted exercises — the historic trash (2026-10-14) ────────────────────

  /// The workout's deleted exercises in arrangement (number) order — what
  /// the past-session viewer's trash menu lists. Each entry reports the slot
  /// it sits at, so a row tapped can be viewed. Historic deletion ORDER is
  /// not stored (the live session's order list is memory-only); the stored
  /// arrangement, which the deleted exercise keeps, stands in for it.
  List<({int slotIndex, String name})> get deletedExerciseEntries => [
    for (var i = 0; i < state.value.exerciseSlots.length; i++)
      if (state.value.exerciseSlots[i].deleted)
        (
          slotIndex: i,
          name: exerciseDisplayName(state.value.exerciseSlots[i].exerciseId),
        ),
  ];

  bool get hasDeletedExercises =>
      state.value.exerciseSlots.any((sl) => sl.deleted);

  /// The trash menu's row callback: shows the deleted exercise — the reader
  /// looks at what was deleted before deciding to restore (the Restore
  /// button under the card is the write).
  void viewDeletedExerciseAt(int entryIndex) {
    final entries = deletedExerciseEntries;
    if (entryIndex < 0 || entryIndex >= entries.length) return;
    state.value = state.value.copyWith(
      activeSlotIndex: entries[entryIndex].slotIndex,
    );
  }

  /// Restores an exercise's deleted sets: un-flags every flagged row — the
  /// sets rejoin the grid and the timeline, so PRs see them again — and,
  /// when the exercise had folded away entirely, its slot stops reading
  /// deleted (a partly-deleted exercise never left). One undo step; the
  /// acting history is cleared when the edit session begins, so a restore
  /// never mixes with actions from when the session was live.
  Future<void> restoreDeletedExercise(int slotIndex) async {
    final w = state.value.session;
    if (w == null) return;
    final slots = state.value.exerciseSlots;
    if (slotIndex < 0 || slotIndex >= slots.length) return;
    final slot = slots[slotIndex];
    final rows = [
      for (final s in state.value.setsFor(slot.groupOrder))
        if (s.isDeleted) s,
    ];
    if (rows.isEmpty) return;

    Future<void> forward() async {
      for (final row in rows) {
        await _sessionRepo.updateSet(
          row.sessionExerciseSetId,
          clearIsDeleted: true,
        );
      }
      await _reloadSets(w.sessionId);
      // The restored exercise is what the user wants to see.
      state.value = state.value.copyWith(activeSlotIndex: slotIndex);
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          // The soft-delete ids are stable, so the inverse is the cheap
          // re-flag — no re-insert, no new ids.
          for (final row in rows) {
            await _sessionRepo.updateSet(
              row.sessionExerciseSetId,
              isDeleted: true,
            );
          }
          await _reloadSets(w.sessionId);
        },
        replay: () async {
          _suppressHistory = true;
          try {
            await forward();
          } finally {
            _suppressHistory = false;
          }
        },
      ),
    );
    await forward();
  }

  /// The trash menu's restore half, addressed by entry index — used where a
  /// row is known to be a restore (the Restore button flows through
  /// [restoreDeletedExercise] directly).
  Future<void> restoreDeletedExerciseAt(int entryIndex) async {
    final entries = deletedExerciseEntries;
    if (entryIndex < 0 || entryIndex >= entries.length) return;
    await restoreDeletedExercise(entries[entryIndex].slotIndex);
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
      // Adding back an exercise that was deleted restores it — a second
      // exercise row would read as two tabs of one thing (the live screen's
      // rule, 2026-10-13).
      if (s.exerciseSlots[existingIndex].deleted) {
        await restoreDeletedExercise(existingIndex);
        return;
      }
      state.value = s.copyWith(activeSlotIndex: existingIndex);
      return;
    }
    final box = UndoBox<String>();

    Future<void> forward() async {
      final s = state.value;
      // Persist the exercise row immediately so the tab survives a reload.
      final sessionExerciseId = await _ensureSessionExercise(exerciseId);
      if (sessionExerciseId == null) return;
      box.value = sessionExerciseId;
      final nextOrder = s.exerciseSlots.isEmpty
          ? 1
          : s.exerciseSlots
                    .map((sl) => sl.groupOrder)
                    .reduce((a, b) => a > b ? a : b) +
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

    _recordUndo(
      UndoAction(
        inverse: () async {
          final seId = box.value;
          if (seId != null) {
            await _sessionRepo.deleteSessionExercise(seId);
          }
          final cur = state.value;
          final order = cur.exerciseSlots
              .firstWhere((sl) => sl.exerciseId == exerciseId)
              .groupOrder;
          state.value = cur.copyWith(
            exerciseSlots: [
              for (final sl in cur.exerciseSlots)
                if (sl.exerciseId != exerciseId) sl,
            ],
            workoutSetDrafts: {
              for (final e in cur.workoutSetDrafts.entries)
                if (e.key != order) e.key: e.value,
            },
            activeSlotIndex: cur.activeSlotIndex > 0
                ? cur.activeSlotIndex - 1
                : 0,
          );
        },
        replay: () async {
          _suppressHistory = true;
          try {
            await forward();
          } finally {
            _suppressHistory = false;
          }
        },
      ),
    );
    await forward();
  }

  /// Removes an exercise group — the past-session viewer's mirror of the
  /// planner's remove, so removing a ticked row in the add-exercise modal
  /// works in edit mode. Planned rows SOFT-delete (flagged, kept — the group
  /// becomes a red, restorable entry at its number); user-added rows die hard
  /// as they always have, and a group with no planned rows at all goes
  /// entirely, as before (2026-10-14). One undo step for the whole group.
  Future<void> removeExerciseGroup(int index) async {
    final s = state.value;
    if (index < 0 || index >= s.exerciseSlots.length) return;
    final slot = s.exerciseSlots[index];
    if (slot.deleted) return;
    final capturedSets = List<SessionExerciseSet>.of(
      s.setsFor(slot.groupOrder),
    );
    final activeBefore = s.activeSlotIndex;
    final boxes = <String, UndoBox<String>>{};

    Future<void> forward() async {
      final cur = state.value;
      final idx = cur.exerciseSlots.indexWhere(
        (sl) => sl.groupOrder == slot.groupOrder,
      );
      if (idx == -1) return;
      final curSlot = cur.exerciseSlots[idx];
      final sets = List<SessionExerciseSet>.of(cur.setsFor(curSlot.groupOrder));
      var keptRows = 0;
      for (final set in sets) {
        // A plan-linked exercise keeps everything — the plan's rows and the
        // user's additions alike; a user-added exercise's rows die hard, as
        // they always have (2026-10-14).
        if (curSlot.planned || set.plannedSetId != null) {
          await _sessionRepo.updateSet(
            set.sessionExerciseSetId,
            isDeleted: true,
          );
          keptRows++;
        } else {
          try {
            await _sessionRepo.deleteSet(set.sessionExerciseSetId);
          } catch (_) {}
        }
      }
      if (keptRows == 0) {
        // Nothing planned was kept — the exercise row is residue, exactly
        // like a group the user fully emptied (the pre-2026-10-14 behavior).
        final rowId = curSlot.sessionExerciseId;
        if (rowId != null) {
          try {
            await _sessionRepo.deleteSessionExercise(rowId);
          } catch (_) {}
        }
      }
      final w = state.value.session;
      if (w == null) return;
      await _reloadSets(w.sessionId);
      final after = state.value;
      if (after.activeSlotIndex >= after.exerciseSlots.length) {
        state.value = after.copyWith(
          activeSlotIndex: after.exerciseSlots.isEmpty
              ? 0
              : after.exerciseSlots.length - 1,
        );
      }
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final w = state.value.session;
          if (w == null) return;
          String? seId = slot.sessionExerciseId;
          // Un-flag what the forward flagged — its ids are stable. A planned
          // exercise kept every row; a user-added one hard-deleted them all.
          final keepsAll = slot.planned;
          for (final set in capturedSets) {
            if (keepsAll || set.plannedSetId != null) {
              await _sessionRepo.updateSet(
                set.sessionExerciseSetId,
                clearIsDeleted: true,
              );
            }
          }
          // Re-insert the hard-deleted rows, and the exercise row if the
          // forward removed it — bound to the id it actually got, never the
          // stale one.
          final userRows = [
            for (final s in capturedSets)
              if (!(keepsAll || s.plannedSetId != null)) s,
          ];
          final seExists =
              seId != null &&
              state.value.exerciseSlots.any(
                (sl) => sl.sessionExerciseId == seId,
              );
          if (!seExists) {
            if (seId != null) {
              seId = (await _sessionRepo.insertSessionExercise(
                sessionId: w.sessionId,
                userId: _userId,
                exerciseId: slot.exerciseId,
                exerciseOrder: slot.groupOrder,
              )).sessionExerciseId;
            } else {
              seId = await _ensureSessionExercise(slot.exerciseId);
            }
          }
          for (final set in userRows) {
            final inserted = await _sessionRepo.insertSet(
              sessionExerciseId: seId!,
              sessionId: w.sessionId,
              userId: _userId,
              variationId: set.variationId,
              setNumber: set.setNumber,
              weight: set.weight,
              reps: set.reps,
              notes: set.notes,
              plannedSetId: set.plannedSetId,
            );
            boxes[set.sessionExerciseSetId] = UndoBox<String>()
              ..value = inserted.sessionExerciseSetId;
          }
          await _reloadSets(w.sessionId);
          final cur = state.value;
          state.value = cur.copyWith(activeSlotIndex: activeBefore);
        },
        replay: () async {
          _suppressHistory = true;
          try {
            await forward();
          } finally {
            _suppressHistory = false;
          }
        },
      ),
    );
    await forward();
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
    final group = [...state.value.setsFor(groupOrder)]
      ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
    if (group.length < 2) return;
    if (newIndex >= group.length) newIndex = group.length - 1;
    if (oldIndex == newIndex || oldIndex < 0 || oldIndex >= group.length) {
      return;
    }
    final idsBefore = [for (final g in group) g.sessionExerciseSetId];

    Future<void> forward() async {
      final current = [...state.value.setsFor(groupOrder)]
        ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
      if (current.length < 2 || newIndex >= current.length) return;
      current.insert(newIndex, current.removeAt(oldIndex));
      final ordered = [
        for (var i = 0; i < current.length; i++)
          current[i].copyWith(setNumber: i + 1),
      ];
      final byOrder = Map<int, List<SessionExerciseSet>>.from(
        state.value.setsByOrder,
      );
      byOrder[groupOrder] = ordered;
      state.value = state.value.copyWith(setsByOrder: byOrder);

      final w = state.value.session;
      if (w != null) {
        await _sessionRepo.reorderSets(w.sessionId, [
          for (final s in ordered) s.sessionExerciseSetId,
        ]);
      }
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final w = state.value.session;
          if (w != null) {
            await _sessionRepo.reorderSets(w.sessionId, idsBefore);
          }
          final byId = {
            for (final s in state.value.setsFor(groupOrder))
              s.sessionExerciseSetId: s,
          };
          final ordered = [
            for (var i = 0; i < idsBefore.length; i++)
              byId[idsBefore[i]]!.copyWith(setNumber: i + 1),
          ];
          final byOrder = Map<int, List<SessionExerciseSet>>.from(
            state.value.setsByOrder,
          );
          byOrder[groupOrder] = ordered;
          state.value = state.value.copyWith(setsByOrder: byOrder);
          _computePRs();
        },
        replay: () async {
          _suppressHistory = true;
          try {
            await forward();
          } finally {
            _suppressHistory = false;
          }
        },
      ),
    );
    unawaited(forward());
  }

  /// "+ ADD SET" in edit mode pre-creates an empty set in the DB so it
  /// survives hot restarts. Empty sets are NOT purged here — they were
  /// intentionally added by the user editing a finished workout.
  Future<void> addDraftSet(int groupOrder) async {
    final w = state.value.session;
    if (w == null) return;
    final box = UndoBox<String>();

    Future<void> forward() async {
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
          : existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) +
                1;
      final inserted = await _sessionRepo.insertSet(
        sessionExerciseId: sessionExerciseId,
        sessionId: w.sessionId,
        userId: _userId,
        setNumber: nextNum,
        weight: null,
        reps: const [],
      );
      box.value = inserted.sessionExerciseSetId;
      await _reloadSets(w.sessionId);
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final id = box.value;
          if (id == null) return;
          await _deleteSetFromState(id);
          try {
            await _sessionRepo.deleteSet(id);
            await _reloadSets(w.sessionId);
          } catch (e) {
            state.value = state.value.copyWith(error: e.toString());
          }
        },
        replay: () async {
          _suppressHistory = true;
          try {
            await forward();
          } finally {
            _suppressHistory = false;
          }
        },
      ),
    );
    await forward();
  }

  void removeDraftSet(int groupOrder, int draftId) {
    Future<void> forward() {
      final drafts = Map<int, List<int>>.from(state.value.workoutSetDrafts);
      drafts[groupOrder]?.remove(draftId);
      state.value = state.value.copyWith(workoutSetDrafts: drafts);
      return Future.value();
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final drafts = Map<int, List<int>>.from(state.value.workoutSetDrafts);
          drafts.putIfAbsent(groupOrder, () => []).add(draftId);
          state.value = state.value.copyWith(workoutSetDrafts: drafts);
        },
        replay: () async {
          _suppressHistory = true;
          try {
            await forward();
          } finally {
            _suppressHistory = false;
          }
        },
      ),
    );
    unawaited(forward());
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
      // the asc copy for the sorted PR walk. The fresh row is also the one
      // authority on the variation's CURRENT name, which the patch needs:
      // the row only stores the id (2026-10-25).
      final userId = _userId;
      final timeline = await PastSetsTimelineCache.instance.get(userId);
      _timelineAsc = PastSetsTimelineCache.instance.asc(userId) ?? timeline;
      _applySetPatchToState(
        setId,
        p,
        freshRow: _timelineRowFor(timeline, setId),
      );
      _computePRs();
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  /// The freshly re-read timeline row for [setId], if the timeline holds one.
  /// A completed record's rows always are; an active session's are not (the
  /// timeline only reads ended sessions), and a flagged row is filtered out
  /// at the SQL level — both fall back to the catalogue (2026-10-25).
  PastSetRow? _timelineRowFor(List<PastSetRow> timeline, String setId) {
    for (final row in timeline) {
      if (row.sessionExerciseSetId == setId) return row;
    }
    return null;
  }

  /// The name that belongs to the variation a just-written set now points at
  /// (2026-10-25). Names live in `dim_variation`, not on the set: carrying the
  /// PREVIOUS name forward left the read-only cell naming the variation the
  /// set no longer had until the record was reopened, which is exactly what
  /// Done showed. The fresh timeline row (it joins the dims, archived names
  /// included) is the authority; the live catalogue covers a row the timeline
  /// cannot hold; an unchanged id keeps its snapshot name, so an archived
  /// variation that was readable never turns blank.
  String? _variationNameAfterWrite({
    required PastSetRow? fresh,
    required String? variationId,
    required String? previousId,
    required String? previousName,
  }) {
    if (variationId == null) return null;
    if (fresh != null &&
        fresh.variationId == variationId &&
        fresh.variationName != null) {
      return fresh.variationName;
    }
    for (final v in state.value.allVariations) {
      if (v.variationId == variationId) return v.name;
    }
    return variationId == previousId ? previousName : null;
  }

  /// Replaces the edited row in [SessionDetailState.setsByOrder] and in its
  /// timeline copy ([SessionDetailState.historyByExercise]) with the values
  /// just written — the DB and the patch agree by construction.
  void _applySetPatchToState(
    String setId,
    _PendingDetailSetWrite p, {
    PastSetRow? freshRow,
  }) {
    final s = state.value;

    // The id the row now carries — the write's when it named one, the stored
    // id otherwise — and the name that goes with it.
    String? patchedId(String? storedId) =>
        p.clearVariation ? null : (p.variationId ?? storedId);
    String? patchedName(String? storedId, String? storedName) =>
        _variationNameAfterWrite(
          fresh: freshRow,
          variationId: patchedId(storedId),
          previousId: storedId,
          previousName: storedName,
        );

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
              variationId: patchedId(set.variationId),
              setNumber: set.setNumber,
              weight: p.clearWeight ? null : (p.weight ?? set.weight),
              reps: p.clearReps ? const [] : (p.reps ?? set.reps),
              notes: p.clearNotes ? null : (p.notes ?? set.notes),
              exerciseName: set.exerciseName,
              variationName: patchedName(set.variationId, set.variationName),
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
                    variationId: patchedId(set.variationId),
                    setNumber: set.setNumber,
                    weight: p.clearWeight ? null : (p.weight ?? set.weight),
                    reps: p.clearReps ? const [] : (p.reps ?? set.reps),
                    notes: p.clearNotes ? null : (p.notes ?? set.notes),
                    exerciseName: set.exerciseName,
                    variationName: patchedName(
                      set.variationId,
                      set.variationName,
                    ),
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
    final box = UndoBox<String>();

    Future<void> forward() async {
      final w = state.value.session;
      if (w == null) return;
      try {
        final inserted = await _sessionRepo.insertSet(
          sessionExerciseId: set.sessionExerciseId,
          sessionId: w.sessionId,
          userId: _userId,
          variationId: set.variationId,
          setNumber: nextNum,
          weight: weight ?? set.weight,
          reps: reps ?? set.reps,
          notes: set.notes,
        );
        box.value = inserted.sessionExerciseSetId;
        await _reloadSets(w.sessionId);
        _computePRs();
      } catch (e) {
        state.value = state.value.copyWith(error: e.toString());
      }
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final id = box.value;
          if (id == null) return;
          await _deleteSetFromState(id);
          try {
            await _sessionRepo.deleteSet(id);
            await _reloadSets(w.sessionId);
            _computePRs();
          } catch (e) {
            state.value = state.value.copyWith(error: e.toString());
          }
        },
        replay: () async {
          _suppressHistory = true;
          try {
            await forward();
          } finally {
            _suppressHistory = false;
          }
        },
      ),
    );
    await forward();
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
  ///
  /// A row that came from the plan SOFT-deletes (flagged, kept, shown red,
  /// restorable — the exercise turns deleted when this was its last active
  /// row); a user-added row hard-deletes as before (2026-10-14).
  Future<void> deleteSetCascade(String setId, String exerciseId) async {
    final w = state.value.session;
    if (w == null) return;
    final captured = state.value.setsByOrder.values
        .expand((l) => l)
        .where((s) => s.sessionExerciseSetId == setId)
        .firstOrNull;
    final box = UndoBox<String>();
    // Flag when the row is planned or its exercise came from the plan — the
    // whole of a planned exercise's deletions are kept, the user's own
    // additions included, so its Restore brings back everything underneath
    // it (2026-10-14). A row of a user-added exercise hard-deletes: the undo
    // stack is its way back.
    final slot = state.value.exerciseSlots.firstWhereOrNull(
      (sl) => sl.sessionExerciseId == captured?.sessionExerciseId,
    );
    final isPlanned =
        captured?.plannedSetId != null || (slot?.planned ?? false);

    Future<void> forward() async {
      final w = state.value.session;
      if (w == null) return;
      if (isPlanned) {
        try {
          await _sessionRepo.updateSet(setId, isDeleted: true);
          await _reloadSets(w.sessionId);
        } catch (e) {
          state.value = state.value.copyWith(error: e.toString());
        }
        return;
      }
      await _deleteSetFromState(setId);
      try {
        await _sessionRepo.deleteSet(setId);
        _computePRs();
        await _reloadSets(w.sessionId);
      } catch (e) {
        state.value = state.value.copyWith(error: e.toString());
      }
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final w = state.value.session;
          if (w == null || captured == null) return;
          if (isPlanned) {
            // Stable ids make the inverse the cheap un-flag.
            try {
              await _sessionRepo.updateSet(setId, clearIsDeleted: true);
              await _reloadSets(w.sessionId);
            } catch (e) {
              state.value = state.value.copyWith(error: e.toString());
            }
            return;
          }
          try {
            final inserted = await _sessionRepo.insertSet(
              sessionExerciseId: captured.sessionExerciseId,
              sessionId: w.sessionId,
              userId: _userId,
              variationId: captured.variationId,
              setNumber: captured.setNumber,
              weight: captured.weight,
              reps: captured.reps,
              notes: captured.notes,
              plannedSetId: captured.plannedSetId,
            );
            box.value = inserted.sessionExerciseSetId;
            await _reloadSets(w.sessionId);
            _computePRs();
          } catch (e) {
            state.value = state.value.copyWith(error: e.toString());
          }
        },
        replay: () async {
          _suppressHistory = true;
          try {
            await forward();
          } finally {
            _suppressHistory = false;
          }
        },
      ),
    );
    await forward();
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
    return _variationsByRecencyCache = CustomVariation.sortByLastUsed(
      variations,
      last,
    );
  }

  List<Lesson> lessonsFor(String exerciseId) =>
      state.value.lessonsByExercise[exerciseId] ?? const [];

  /// The lessons born in THIS session for [exerciseId] — what the card's
  /// pill, the floor tile and the breakdown sheet count. Past sessions'
  /// lessons stay visible in the modal and the pinned bar but don't inflate
  /// the number (the live session's rule, mirrored 2026-10-22).
  int sessionLessonsCount(String exerciseId) {
    final sessionId = state.value.session?.sessionId;
    if (sessionId == null) return 0;
    var count = 0;
    for (final l in lessonsFor(exerciseId)) {
      if (l.sessionId == sessionId) count++;
    }
    return count;
  }

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
      // A cue written while reading a record was learned NOW — stamping the
      // record's id would back-date it into that past session's own shelf,
      // editing a workout the reader only navigated to (2026-10-23). Left
      // session-less, it lands under AFTER and the record's lessons stay
      // untouched.
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

  // ── History ────────────────────────────────────────────────────────────────

  List<ExerciseHistorySession> historyFor(String exerciseId) =>
      state.value.historyByExercise[exerciseId] ?? const [];

  // ── The date bar's two stacks (2026-10-23) ────────────────────────────────

  /// Switches the date bar's stacks. A mode change returns the card home —
  /// the record's own sets — so each mode starts from the page being read.
  void setDateBarMode(SessionDateMode mode) {
    if (state.value.dateBarMode == mode) return;
    state.value = state.value.copyWith(
      dateBarMode: mode,
      exerciseHistoryIndex: 0,
    );
  }

  void toggleDateBarMode() => setDateBarMode(
    state.value.dateBarMode == SessionDateMode.exercise
        ? SessionDateMode.session
        : SessionDateMode.exercise,
  );

  /// Steps EXERCISE mode: +1 older, -1 newer, both ends holding. The record
  /// stays the page; only the card's sets move. Pending keystrokes settle
  /// first — the rows on screen are about to be swapped out, the same rule
  /// a tab switch follows.
  Future<void> stepExerciseHistory(int delta) async {
    if (state.value.dateBarMode != SessionDateMode.exercise) return;
    final slot = state.value.activeSlot;
    if (slot == null) return;
    final position = state.value.effectiveExerciseHistoryIndex;
    final next = position + delta;
    if (next < 0 || next > state.value.exerciseHistoryStack.length) return;
    if (next == position) return;
    await flushPendingCommits();
    if (state.value.dateBarMode != SessionDateMode.exercise) return;
    state.value = state.value.copyWith(
      exerciseHistoryIndex: next,
      exerciseHistoryForId: slot.exerciseId,
    );
  }

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
