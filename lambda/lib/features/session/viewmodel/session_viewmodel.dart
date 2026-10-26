import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import 'package:uuid/uuid.dart';
import '../../../data/cache/past_sets_timeline_cache.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/planned_session_exercise_set.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/models/program_block.dart';
import '../../../data/models/program_progress.dart';
import '../../../data/models/session.dart';
import '../../../data/models/exercise_usage.dart';
import '../../../data/models/session_exercise.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../core/powersync/database.dart' as ps;
import '../../../core/utils/name_limit.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/program_run_repository.dart';
import '../../../data/repositories/planned_session_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../core/utils/device_id.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/planned_target.dart';
import '../../../core/utils/undo_history.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../../shared/widgets/slide_pages.dart';
import '../../logs/viewmodel/session_detail_viewmodel.dart';
import '../../programs/model/program_achievements.dart';
import '../model/past_session_seed.dart';
import '../model/pr_engine.dart';
import '../model/session_local_state.dart';

/// Goal ids are minted here, the way the goals screen mints its own: a goal
/// created from a session is the same row, written from the other door.
const _uuid = Uuid();

class SessionViewModel extends ChangeNotifier {
  SessionViewModel({
    SessionRepository? sessionRepo,
    ExerciseRepository? exerciseRepo,
    ProgramRepository? programRepo,
    ProgramRunRepository? programRunRepo,
    LessonRepository? lessonRepo,
    PlannedSessionRepository? plannedSessionRepo,
    Future<void> Function()? waitForFirstSync,
    String? userId,
    String? deviceId,
  }) : _sessionRepo = sessionRepo ?? SessionRepository(),
       _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
       _programRepo = programRepo ?? ProgramRepository(),
       _programRunRepo = programRunRepo ?? ProgramRunRepository(),
       _lessonRepo = lessonRepo ?? LessonRepository(),
       _plannedSessionRepo = plannedSessionRepo ?? PlannedSessionRepository(),
       // Seam for host tests, which have no live PowerSync database (or
       // Supabase session) to wait on — the defaults are the real ones
       // (2026-10-13).
       _waitForFirstSync = waitForFirstSync ?? (() => ps.db.waitForFirstSync()),
       _userIdOverride = userId,
       _deviceId = deviceId {
    slidePagesController = SlidePagesController();
    _init();
  }

  final SessionRepository _sessionRepo;
  final PlannedSessionRepository _plannedSessionRepo;
  final ExerciseRepository _exerciseRepo;
  final ProgramRepository _programRepo;
  final ProgramRunRepository _programRunRepo;
  final LessonRepository _lessonRepo;
  late final SlidePagesController slidePagesController;
  static final _lessonLog = Logger('lessons');

  /// Wizard page indices — the ONLY place page numbers live (the screen's
  /// header and every slide read these; the flow is Home → pre-questionnaire
  /// → Training → Summary → post-questionnaire → Home).
  static const int kSessionHomePage = 0;
  static const int kPreQuestionnairePage = 1;
  static const int kTrainingPage = 2;
  static const int kSummaryPage = 3;
  static const int kPostQuestionnairePage = 4;

  /// The host-test seam's answer; null reads the live Supabase session.
  final String? _userIdOverride;

  String get _userId =>
      _userIdOverride ?? Supabase.instance.client.auth.currentUser!.id;

  // ── Startup ─────────────────────────────────────────────────────────────────
  bool initLoading = true;

  // ── Workout state ──────────────────────────────────────────────────────────
  /// Called when the workout fully ends (endWorkout or cancelWorkout) so the
  /// session screen can clear its static cache and create a fresh VM next time.
  VoidCallback? onWorkoutEnded;
  String? currentWorkoutId;
  DateTime? workoutStartedAt;

  /// The date bar's older step (2026-10-22): the newest completed session
  /// started before this one — the record the live floor's left arrow opens.
  /// Null until read, or when this is the first session ever; the arrow is
  /// spent then.
  String? previousSessionId;

  /// Which stack the date bar walks (2026-10-23): EXERCISE (the default)
  /// reads the active exercise's own past performances under the live card;
  /// SESSION walks whole completed records (`previousSessionId` and the
  /// peek). Reset to EXERCISE with every new session.
  SessionDateMode dateBarMode = SessionDateMode.exercise;

  /// EXERCISE mode's position in [activeExerciseHistory]: 0 is today's live
  /// sets, N the exercise's Nth-newest past performance. Only meaningful in
  /// [SessionDateMode.exercise], and only for the exercise it was stepped on
  /// ([_exerciseHistoryForId]) — a structural change that puts another
  /// exercise on the card reads as home without needing a reset at every
  /// add/remove/restore site (2026-10-23).
  int exerciseHistoryIndex = 0;

  /// The exercise [exerciseHistoryIndex] belongs to. Read through
  /// [_exerciseHistoryPosition], which treats a mismatch (the card moved to
  /// another exercise mid-walk) as home.
  String? _exerciseHistoryForId;

  /// The session's exercise rows (the tab layer) — order IS the persisted
  /// tab order (`exercise_order` column; the old JSON blob is gone).
  List<SessionExercise> sessionExercises = [];
  List<SessionExerciseSet> sets = [];
  bool setsLoading = false;

  /// Planned rows the user deleted this session — flagged (`is_deleted`)
  /// rather than removed (2026-10-13). The read queries return ALL rows and
  /// the VM partitions them here, so a deleted planned exercise can sit in
  /// the selector with the minus mark and be restored on tap.
  List<SessionExerciseSet> deletedSets = [];

  /// The session-exercise ids of deleted planned exercises, in DELETION
  /// order. The trash menu reads it reversed (most recent first), and
  /// `deletedPlannedExercises` stays the derived lookup (2026-10-13).
  final List<String> _deletedPlannedOrder = [];

  /// The slot index each deleted planned exercise held when it went
  /// (session-exercise id → tab position). A restore reads it back, so the
  /// exercise returns to the tab it came from instead of landing at the end —
  /// delete + restore is a round trip, not a demotion (2026-10-13). One
  /// number, so it is exact for the single-delete case and for restoring a
  /// stack in the menu's own order (newest first); picking an older row first
  /// can still land it beside — never at the end of — the tabs it left.
  final Map<String, int> _deletedPlannedSlotIndex = {};

  /// The deleted planned exercise being VIEWED from the stats bar's trash
  /// menu (2026-10-14) — null when the session is not in the deleted view.
  /// Viewing is a reading: the card shows the exercise's surviving rows red,
  /// its selector lists every deleted exercise with this one selected (so
  /// another is a tap away, 2026-10-23), and
  /// [restoreViewedDeletedExercise] — the button under the card — does the
  /// write. Cleared by any tab switch, by an undo/redo, by a restore, and
  /// with the session; the stats bar's undo/redo pair is greyed while the
  /// mode is up, so an undo can never rewrite the very thing being read.
  String? deletedViewSeId;

  /// The session-exercise row behind the deleted view — null when not
  /// viewing.
  SessionExercise? get deletedViewSessionExercise {
    final id = deletedViewSeId;
    if (id == null) return null;
    return sessionExercises.firstWhereOrNull((e) => e.sessionExerciseId == id);
  }

  /// An exercise's deleted (flagged) rows, in set order — what the grid
  /// draws red and the Restore under the card brings back (2026-10-14).
  List<SessionExerciseSet> deletedSetsForExercise(String exerciseId) =>
      deletedSets.where((s) => s.exerciseId == exerciseId).toList()
        ..sort((a, b) => a.setNumber.compareTo(b.setNumber));

  /// Whether the tab on screen holds deleted sets — the Restore button
  /// under the live card appears while it does (2026-10-14).
  bool get activeSlotHasDeletedSets =>
      activeSlot != null &&
      deletedSetsForExercise(activeSlot!.activeExerciseId).isNotEmpty;

  /// The Restore under the active card: un-flags every deleted set under the
  /// exercise — the plan's rows and the user's own additions alike — one
  /// undo step (2026-10-14).
  Future<void> restoreDeletedSetsForActiveExercise() async {
    final slot = activeSlot;
    if (slot == null) return;
    final se = sessionExercises.firstWhereOrNull(
      (e) => e.exerciseId == slot.activeExerciseId,
    );
    if (se == null) return;
    await restoreDeletedPlannedExercise(se.sessionExerciseId);
  }

  /// The rows the viewed deleted exercise keeps, in set order.
  List<SessionExerciseSet> get deletedViewSets {
    final id = deletedViewSeId;
    if (id == null) return const [];
    return deletedSets.where((s) => s.sessionExerciseId == id).toList()
      ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
  }

  /// The trash menu's row callback: VIEWS the deleted exercise — its rows
  /// red, a Restore button under the card. A mistaken tap never changes the
  /// session (2026-10-14).
  Future<void> viewDeletedPlannedExerciseAt(int entryIndex) async {
    final entries = deletedPlannedExerciseEntries;
    if (entryIndex < 0 || entryIndex >= entries.length) return;
    // Flush in-flight edits first, like a tab switch — the rows on screen
    // are about to be swapped out.
    await flushPendingCommits();
    deletedViewSeId = entries[entryIndex].id;
    // The deleted reading has no history to walk: EXERCISE mode returns to
    // the live sets so the card it swaps back to starts home.
    exerciseHistoryIndex = 0;
    notifyListeners();
  }

  /// Leaves the deleted view without restoring — a tab switch, a picker add.
  void exitDeletedView() {
    if (deletedViewSeId == null) return;
    deletedViewSeId = null;
    notifyListeners();
  }

  /// The Restore button under the viewed card: un-flags the exercise's rows
  /// and puts the tab back at the slot the dot marked, focused. One undo
  /// step, like every structural action.
  Future<void> restoreViewedDeletedExercise() async {
    final id = deletedViewSeId;
    if (id == null) return;
    deletedViewSeId = null;
    await restoreDeletedPlannedExercise(id);
  }

  /// The trash menu's rows (2026-10-13): every deleted planned exercise with
  /// its display name, MOST RECENTLY DELETED first — the in-memory deletion
  /// order, so the menu is right the moment a delete lands, before the watch
  /// stream has re-emitted. [restoreDeletedPlannedExerciseAt] takes an index
  /// into this list.
  List<({String id, String name})> get deletedPlannedExerciseEntries {
    final out = <({String id, String name})>[];
    final seen = <String>{};
    for (final seId in _deletedPlannedOrder.reversed) {
      if (!seen.add(seId)) continue;
      final se = sessionExercises.firstWhereOrNull(
        (e) => e.sessionExerciseId == seId,
      );
      if (se == null) continue;
      out.add((
        id: seId,
        name: exerciseDetailMap[se.exerciseId]?.name ?? se.exerciseName ?? '',
      ));
    }
    return out;
  }

  /// Planned exercises whose every row is flagged, in persisted
  /// `exercise_order` order. Restored by [restoreDeletedPlannedExercise] or
  /// the trash button; hard-deleted by the end-of-session prune.
  List<SessionExercise> get deletedPlannedExercises {
    final out = <SessionExercise>[];
    for (final se in sessionExercises) {
      if (se.plannedExerciseId == null || se.exerciseId == null) continue;
      final hasActive = sets.any(
        (s) => s.sessionExerciseId == se.sessionExerciseId,
      );
      final hasFlagged = deletedSets.any(
        (s) => s.sessionExerciseId == se.sessionExerciseId,
      );
      if (!hasActive && hasFlagged) out.add(se);
    }
    return out;
  }

  /// Ids of sets that are PRs right now, per the engine's multi-axis model
  /// (a set is a PR if it improves the rep-max curve at any tracked rep count,
  /// or the weight-max for its weight). Recomputed from history + session sets
  /// on every sets change so live highlighting matches what `_persistPRs`
  /// records at endWorkout.
  Set<String> prSetIds = {};

  // ── Exercise catalog ───────────────────────────────────────────────────────
  bool catalogLoading = false;
  List<ExerciseDetail> get exercises => exerciseDetailMap.values.toList();
  Map<String, ExerciseDetail> exerciseDetailMap = {};

  // ── Start workout form ─────────────────────────────────────────────────────
  String startNotes = '';
  int? sessionFeeling;
  bool startLoading = false;

  // ── End workout ────────────────────────────────────────────────────────────
  String endNotes = '';
  int? endFeeling;
  bool endLoading = false;

  /// The session just finished — the post-questionnaire page's write
  /// target. Set in [finishSession] before the active state resets,
  /// cleared on completion, the next start, and cancel.
  String? lastEndedSessionId;

  /// Snapshot of the just-finished session's stats for the home congrats
  /// banner — captured in [finishSession] BEFORE [_resetActiveWorkoutState]
  /// wipes sets/sessionPrEvents.
  ({int sets, int exercises, int prs})? lastCompletedStats;

  /// The completed session BEFORE the just-ended one — the post-questionnaire
  /// page's comparison reference (the ended session itself is the newest).
  /// Fetched in [finishSession]; null when there is no earlier session.
  Session? previousCompletedSession;

  /// True after the post-questionnaire completes until the next one starts —
  /// Home greets with the completion banner.
  bool sessionJustCompleted = false;

  // ── Error ──────────────────────────────────────────────────────────────────
  String? error;

  // ── Today's planned workout (read-only reuse of the Programs feature) ────
  ProgramProgress? programProgress;
  Map<String, List<PlannedSessionExerciseSet>> plannedSetsByExercise = {};
  List<String> plannedExerciseOrder = [];

  /// setId → planned row, for matching a logged set to its template row by
  /// [SessionExerciseSet.plannedSetId] — id-anchored, never positional.
  /// Memoized on the source map's identity: the card rebuilds on every
  /// notify, and rebuilding the full map per rebuild was pure churn
  /// (2026-10-13).
  Map<String, PlannedSessionExerciseSet>? _plannedSetByIdCache;
  Map<String, List<PlannedSessionExerciseSet>>? _plannedSetByIdSource;

  Map<String, PlannedSessionExerciseSet> get plannedSetById {
    if (identical(_plannedSetByIdSource, plannedSetsByExercise) &&
        _plannedSetByIdCache != null) {
      return _plannedSetByIdCache!;
    }
    _plannedSetByIdSource = plannedSetsByExercise;
    return _plannedSetByIdCache = {
      for (final list in plannedSetsByExercise.values)
        for (final p in list) p.plannedSetId: p,
    };
  }

  // ── Exercise tabs ──────────────────────────────────────────────────────────
  List<SessionExerciseSlot> exerciseSlots = [];
  int activeSlotIndex = 0;
  int _nextSlotId = 1;

  SessionExerciseSlot? get activeSlot => exerciseSlots.isEmpty
      ? null
      : exerciseSlots[activeSlotIndex.clamp(0, exerciseSlots.length - 1)];

  // ── Draft (unsaved) set rows, per exercise ────────────────────────────────
  Map<String, List<int>> draftSlotsByExercise = {};
  int _nextDraftId = 1;

  /// draftId → the persisted row backing that draft slot. Drafts start
  /// virtual and bind lazily on first commit (commitDraftSet inserts the
  /// row), so seeding a draft never writes to the DB. Once bound, later
  /// commits update the row and the draft UI never remounts, so focus
  /// survives. Rows are excluded from the real-set list while their draft
  /// owns them.
  final Map<int, String> _draftRowIds = {};

  /// Serializes concurrent commits of the same draft. Only the first-ever
  /// commit may INSERT — see commitDraftSet.
  final Map<int, Future<bool>> _draftCommitsInFlight = {};

  /// Guards "+ ADD SET" against overlapping taps — a second tap arriving
  /// mid-insert would compute its set_number against a `sets` list that
  /// doesn't yet contain the first row (duplicate numbers, and duplicate
  /// fact_session_exercise rows from a racing _ensureSessionExercise).
  bool _addSetInFlight = false;

  /// A tap that arrived while an insert was in flight; replayed when it
  /// lands (last tap wins).
  String? _addSetQueuedExercise;

  // ── Debounced set writes ───────────────────────────────────────────────────
  /// How long a typed value waits before its write lands. Keystrokes merge
  /// into one write per settle; every flush point (blur, tab switch, wizard
  /// page change, lifecycle, session end) cancels the wait and commits
  /// immediately, so navigation can never lose a value — the one softening
  /// from the old per-keystroke commit is a hard kill within this window of
  /// the last keystroke (2026-10-13).
  static const kAutoCommitDebounce = Duration(milliseconds: 250);

  /// setId → the merged, not-yet-written field values. Only the latest
  /// value per field survives; clear flags accumulate so a later clearing
  /// keystroke still empties the column.
  final Map<String, _PendingSetWrite> _pendingSetWrites = {};

  /// setId → its debounce timer, armed while a merge waits for more
  /// keystrokes.
  final Map<String, Timer> _setDebounceTimers = {};

  /// setId → the write chain — per-set serialization so overlapping settles
  /// land in order (only the latest merged values matter, but ordering keeps
  /// a slow first write from clobbering a newer one).
  final Map<String, Future<void>> _setWriteChains = {};

  /// Live stream subscriptions for the active session's rows — the
  /// authoritative reads that replaced per-edit `_loadSets` pulls. Subscribed
  /// on start/restore, cancelled when the session ends or the VM disposes.
  StreamSubscription<List<SessionExerciseSet>>? _setsSub;
  StreamSubscription<List<SessionExercise>>? _exercisesSub;

  // ── The other devices' live sessions (2026-10-15) ─────────────────────────
  /// This install's device id — stamped on every session it creates, and the
  /// thing that tells its own live session apart from another device's.
  /// Resolved once from [DeviceId]; the constructor seam overrides it in
  /// tests.
  String? _deviceId;

  /// The other devices' live sessions — active, not this device's own, not
  /// dismissed. The app never adopts one silently: the session screen's
  /// notice offers Switch/Stay, and a Switch asks cancel-or-complete first.
  List<Session> foreignActiveSessions = const [];
  final Set<String> _dismissedForeignSessions = {};
  StreamSubscription<List<Session>>? _foreignSessionsSub;

  /// Resolves this install's device id once (prefs-backed; null when the
  /// store is unavailable — the safe reading, which only ever prompts).
  Future<String?> _resolveDeviceId() async =>
      _deviceId ??= await DeviceId.get();

  // ── Undo/redo (structural actions only — 2026-10-13) ──────────────────────
  final ActionUndoHistory undoHistory = ActionUndoHistory();
  bool _suppressHistory = false;
  bool _undoInFlight = false;

  bool get canUndo => undoHistory.canUndo;
  bool get canRedo => undoHistory.canRedo;

  /// Records a step unless a replay is running (replays re-run the forward
  /// action and must not record a second entry).
  void _recordUndo(UndoAction action) {
    if (_suppressHistory) return;
    undoHistory.push(action);
  }

  Future<void> undo() async {
    if (_undoInFlight || !undoHistory.canUndo) return;
    // Any undo leaves the deleted view before it runs: an inverse can
    // restore the very exercise being read (undoing the fold), and a view
    // of something that is no longer deleted is a state with no meaning
    // (2026-10-14). The buttons are greyed inside the view; this is the
    // belt under them.
    exitDeletedView();
    _undoInFlight = true;
    try {
      // A debounced typed edit must land before structure moves — the stack
      // restores rows, not half-written values.
      await flushPendingCommits();
      await undoHistory.undo();
    } catch (e) {
      error = e.toString();
    }
    _undoInFlight = false;
    notifyListeners();
  }

  Future<void> redo() async {
    if (_undoInFlight || !undoHistory.canRedo) return;
    // …and any redo too, for the same reason (2026-10-14).
    exitDeletedView();
    _undoInFlight = true;
    try {
      await flushPendingCommits();
      await undoHistory.redo();
    } catch (e) {
      error = e.toString();
    }
    _undoInFlight = false;
    notifyListeners();
  }

  bool isDraftBoundRow(String setId) => _draftRowIds.containsValue(setId);

  // ── Lessons (persisted — per-exercise, cross-session) ─────────────────────
  Map<String, List<Lesson>> lessonsByExercise = {};

  // ── History / PR baseline (read-only reuse of past-sets timeline) ────────
  List<PastSetRow> _pastSets = [];

  /// The same timeline sorted oldest-first (the PR engine's walk order),
  /// built once per timeline load — `_recomputePRs` runs on every sets
  /// change and must not pay the O(N log N) sort per run (2026-10-13).
  List<PastSetRow> _pastSetsAsc = [];

  /// `lastUsedByEntity(_pastSets)` computed at load time — the per-run
  /// recompute merges only the live rows over it.
  Map<String, DateTime> _timelineLastUsed = {};

  bool pastSetsLoaded = false;

  /// exerciseId → most recent workout date, for "most recently used" ordering.
  /// (The same map also holds variation-id → last use — ids never collide.)
  Map<String, DateTime> lastUsedByExercise = {};
  Map<String, List<ExerciseHistorySession>> historyByExercise = {};

  /// Bumped on every past-sets reload — Home's recent-logs strip keys its
  /// reload off this so edits made in Logs show up on return.
  int pastSetsVersion = 0;

  /// All active variations, most recently used first — the set-row picker
  /// order. Variations are a flat per-user library (no exercise assignment
  /// since schema v2). Memoized on the identity of its two inputs — both are
  /// replaced wholesale (catalog refresh, PR recompute), so a per-rebuild
  /// full sort was pure churn (2026-10-13).
  List<CustomVariation>? _variationsByRecencyCache;
  List<CustomVariation>? _vrAllVariations;
  Map<String, DateTime>? _vrLastUsed;

  List<CustomVariation> get variationsByRecency {
    final lastUsed = lastUsedByExercise;
    if (identical(_vrAllVariations, allVariations) &&
        identical(_vrLastUsed, lastUsed) &&
        _variationsByRecencyCache != null) {
      return _variationsByRecencyCache!;
    }
    _vrAllVariations = allVariations;
    _vrLastUsed = lastUsed;
    return _variationsByRecencyCache = CustomVariation.sortByLastUsed(
      allVariations,
      lastUsed,
    );
  }

  /// PR events for the ACTIVE session, oldest first — one per set that
  /// extended its pair's best-ever frontier (see pr_engine.dart). The
  /// single source for counts, accents, and before/after values.
  List<PrEvent> sessionPrEvents = [];

  /// Every PR event on the merged timeline — history plus this session's
  /// live rows, oldest first. The PR History sheet's full feed; each door
  /// reads the exercise's slice and splits it by [sessionPrSetIdsFor]
  /// (2026-10-22).
  List<PrEvent> allPrEvents = [];

  /// Every PR event (full timeline + this session's sets), keyed by source
  /// set id — the history viewer's rows use it for PR badges.
  Map<String, PrEvent> prEventsBySetId = {};

  /// The sets that achieved one of the user's goals — the earliest set that
  /// met each target, one per goal (2026-10-20). Drawn green with the `G`
  /// badge; a set that is also a PR still counts as one everywhere PRs are
  /// counted, and only loses the accent chrome.
  Set<String> goalSetIds = {};

  /// The user's goals, read with the timeline so the badge refreshes with the
  /// history it is derived from. Empty (never fatal) when the read fails: the
  /// grids must render without their marks rather than not at all.
  List<Goal> _goals = [];

  /// The completed history the goal form reads — its "already beat this"
  /// verdict and its picker ordering (2026-10-26). The live rows are not in
  /// it: a session in progress is not yet history, and the form is asking
  /// what has already been beaten.
  List<PastSetRow> get pastSets => _pastSets;

  /// Writes a goal from a set on this page (2026-10-26) — the row's own
  /// drawer opens the New goal form seeded with it, and this is the write
  /// behind its ADD.
  ///
  /// The same row the goals screen writes, and then the target is folded
  /// into the derived G badges IN PLACE: `_recomputePRs` re-walks the merged
  /// timeline against the new goal, so the set that meets it wears its `G`
  /// while the user is still looking at the row — no reload, no re-entry.
  Future<bool> createGoalFromTarget(ExerciseTarget target) async {
    final notes = target.notes?.trim();
    final goal = Goal(
      goalId: _uuid.v4(),
      userId: _userId,
      // The name is the label's fallback: a goal outlives the exercise it
      // names.
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
      error = friendlyError(e);
      notifyListeners();
      return false;
    }
    _goals = [..._goals, goal];
    _recomputePRs();
    notifyListeners();
    return true;
  }

  // ── Previous-session reflection (prep page card, paged) ────────────────────
  /// Reflection data of a completed past session — PRs and lessons only —
  /// rendered on the prep page's pressable LAST SESSION card. The card pages
  /// through completed history: [_reflectionSessionIds] is newest-first and
  /// [_reflectionIndex] selects which session is shown (0 = most recent).
  List<String> _reflectionSessionIds = [];
  int _reflectionIndex = 0;
  List<String> reflectionExercises = [];
  Map<String, List<PrEvent>> reflectionPrsByExercise = {};
  Map<String, List<String>> reflectionLessonsByExercise = {};
  Map<String, String> reflectionExerciseNames = {};

  /// The session (fact row) the viewer card currently shows — a completed
  /// session for the prep card, or the still-active workout when the
  /// reflection page's THIS SESSION position is selected. Null while
  /// loading or when there is no completed history yet.
  Session? reflectionSession;

  /// True when the reflection pager shows the still-active workout (the
  /// reflection page's THIS SESSION view) instead of a completed session.
  /// Virtual position: [_reflectionIndex] == -1 (never a real list index).
  bool get reflectionIsCurrent =>
      _reflectionIndex == -1 && currentWorkoutId != null;

  /// Whether the viewer card can page left (older) / right (newer). At the
  /// current-session position, older pages into completed history and newer
  /// is a dead end.
  bool get reflectionCanGoOlder {
    if (_reflectionIndex == -1) return _reflectionSessionIds.isNotEmpty;
    return _reflectionIndex < _reflectionSessionIds.length - 1;
  }

  bool get reflectionCanGoNewer {
    if (_reflectionIndex == -1) return false;
    if (_reflectionIndex == 0) return currentWorkoutId != null;
    return true;
  }

  // ── Historical set editing ─────────────────────────────────────────────────
  bool historyEditConfirmed = false;

  void confirmHistoryEdit() {
    historyEditConfirmed = true;
    notifyListeners();
  }

  // ── Derived ───────────────────────────────────────────────────────────────
  bool get hasActiveWorkout => currentWorkoutId != null;

  int get distinctExerciseCount =>
      sets.map((s) => s.exerciseId).whereType<String>().toSet().length;

  int get totalPRsThisSession => sessionPrEvents.length;

  /// On a cold start after login, PowerSync may not have finished its first
  /// sync yet — the local DB would read as empty. [_init] runs it alongside
  /// the first frame and re-reads afterwards if it lands late; it no longer
  /// sits in front of the draw.
  final Future<void> Function() _waitForFirstSync;

  /// [_init]'s three first-sync states, for the re-read gate.
  static const _kSyncPending = 0;
  static const _kSynced = 1;
  static const _kSyncFailed = 2;

  Future<void> _init() async {
    // The first sync runs alongside the first frame rather than in front of
    // it (2026-10-25). On every launch after the first, PowerSync answers it
    // from `ps_buckets` in milliseconds; on a first install it can take
    // seconds, and the mirror it fills is not needed to draw the landing
    // page — which reads whatever the device already holds.
    var syncState = _kSyncPending;
    final firstSync = _waitForFirstSync()
        .timeout(const Duration(seconds: 10))
        .then<void>(
          (_) => syncState = _kSynced,
          onError: (_) => syncState = _kSyncFailed,
        );

    // ── The frame ──────────────────────────────────────────────────────────
    // What the landing page draws: the catalog (names, variations) and the
    // timeline (the list, the PR walk, the Home screen's own read).
    try {
      await refreshCatalog();
    } catch (_) {}
    try {
      await _loadPastSets();
    } catch (_) {}
    // Whether the frame was built while the first sync was still out — the
    // one case where what it read may be older than what the device has.
    final drewWhileSyncing = syncState == _kSyncPending;

    initLoading = false;
    notifyListeners();

    // ── The plan context, then the live session ────────────────────────────
    // This is the slow stretch on a device whose mirror holds no current
    // run: that read falls back to REST. It cannot move in front of the
    // frame, and the restore cannot move in front of it — a resumed
    // session's template is classified against the program's workouts.
    try {
      await _loadPlannedSession();
    } catch (_) {}
    try {
      await _resolveDeviceId();
    } catch (_) {}
    try {
      _subscribeToForeignSessions();
    } catch (_) {}
    try {
      await _restoreActiveWorkout();
    } catch (_) {}

    // ── Freshness ──────────────────────────────────────────────────────────
    // A first install's sync may have landed after the frame was drawn. The
    // reads above are mirror-only (the catalog, the timeline and the
    // restore); the plan context already asked the server when the mirror
    // was empty, so it needs no second pass here.
    await firstSync;
    if (!drewWhileSyncing || syncState != _kSynced) return;
    try {
      await refreshCatalog();
    } catch (_) {}
    try {
      await _loadPastSets();
    } catch (_) {}
    try {
      // The first pass read a mirror with no active session; the sync may
      // have brought one down.
      if (currentWorkoutId == null) await _restoreActiveWorkout();
    } catch (_) {}
  }

  Future<void> refreshCatalog() async {
    catalogLoading = true;
    notifyListeners();
    try {
      exerciseDetailMap = await _exerciseRepo.fetchExerciseDetailMap(_userId);
      allVariations = await _exerciseRepo.fetchVariations(_userId);
    } catch (_) {}
    catalogLoading = false;
    notifyListeners();
  }

  /// Display name for an exercise, falling back to the snapshot name on any
  /// logged set when the exercise has been deactivated and is no longer in
  /// the catalog.
  String exerciseDisplayName(String exerciseId) {
    final detail = exerciseDetailMap[exerciseId];
    if (detail != null) return detail.name;
    // Deactivated exercise — use the live (FK-joined) name from the first
    // set. Names live in the dim; the hydrated field IS the dim's name.
    for (final s in sets) {
      if (s.exerciseId == exerciseId && s.exerciseName != null) {
        return s.exerciseName!;
      }
    }
    return exerciseId;
  }

  /// All of the user's variations — a flat library since schema v2 (no
  /// exercise assignment), so this is the pool "did you mean?" and
  /// silent-reuse checks search against.
  List<CustomVariation> allVariations = [];

  /// Near-duplicate variation names (e.g. "Paused" vs "Pause") to flag as
  /// "did you mean?" before creating a brand-new one, each annotated with how
  /// many exercises have actually used it in history (derived from the
  /// timeline — variations are no longer assigned to exercises).
  List<({String id, String name, int exerciseCount})> findSimilarVariations(
    String name,
  ) {
    final usedWith = <String, Set<String>>{};
    for (final s in _pastSets) {
      final vid = s.variationId;
      final exId = s.exerciseId;
      if (vid != null && exId != null) {
        usedWith.putIfAbsent(vid, () => {}).add(exId);
      }
    }
    final results = <({String id, String name, int exerciseCount})>[];
    for (final v in allVariations) {
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

  /// Planned workouts available for the current program, so the user can pick
  /// one to log rather than always taking the auto-suggested next workout.
  List<PlannedSession> availableWorkouts = [];

  /// The planned workout the user selected (or the auto-next by default).
  PlannedSession? selectedPlannedSession;

  /// Standalone workouts (no program) the user can log.
  List<PlannedSession> standaloneWorkouts = [];

  /// [standaloneWorkouts] in the app's one recency order — most recently
  /// logged first, then newest created (2026-10-26).
  ///
  /// The repository already reads its standalone listing in this order; this
  /// re-applies it from the live timeline so a session that just ended floats
  /// its template to the top of the picker immediately, without a re-read.
  void _sortStandaloneByRecency() {
    if (standaloneWorkouts.length < 2) return;
    sortByLastLogged(standaloneWorkouts, lastUsedByPlannedSession(_pastSets));
  }

  /// The standalone workout selected to log (mutually exclusive with
  /// [selectedPlannedSession]).
  PlannedSession? selectedStandaloneWorkout;

  Future<void> _loadPlannedSession() async {
    try {
      programProgress = await _programRunRepo.getProgress(_userId);
      final programId = programProgress?.program.programId;
      if (programId != null) {
        availableWorkouts = await _programRepo.fetchPlannedSessions(programId);
        selectedPlannedSession =
            programProgress?.nextPlannedSession ??
            availableWorkouts.firstOrNull;
      }
      standaloneWorkouts = await _plannedSessionRepo.fetchPlannedSessions(
        _userId,
      );
      _sortStandaloneByRecency();
      await _loadSelectedSessionSets();
    } catch (_) {}
    notifyListeners();
  }

  /// Loads the planned sets for the currently selected workout (program or
  /// standalone).
  Future<void> _loadSelectedSessionSets() async {
    if (selectedStandaloneWorkout != null) {
      // The preview reads through the same normalizing read the planner uses,
      // so both count the same sets in the same order.
      final sets = await _plannedSessionRepo.readNormalizedPlannedSession(
        selectedStandaloneWorkout!.sessionId,
      );
      plannedSetsByExercise = _plannedMapFromSets(sets);
      plannedExerciseOrder = _plannedOrderFromSets(sets);
      return;
    }
    final pw = selectedPlannedSession;
    if (pw == null) {
      plannedSetsByExercise = {};
      plannedExerciseOrder = [];
      return;
    }
    try {
      final plannedSets = await _plannedSessionRepo
          .readNormalizedPlannedSession(pw.sessionId);
      plannedSetsByExercise = _plannedMapFromSets(plannedSets);
      plannedExerciseOrder = _plannedOrderFromSets(plannedSets);
    } catch (_) {}
  }

  /// Groups planned sets by exercise. The repo returns rows ordered by
  /// (exercise_order, set_number), so insertion order preserves the template's
  /// exercise and set ordering.
  Map<String, List<PlannedSessionExerciseSet>> _plannedMapFromSets(
    List<PlannedSessionExerciseSet> sets,
  ) {
    final byExercise = <String, List<PlannedSessionExerciseSet>>{};
    for (final p in sets) {
      final exerciseId = p.exerciseId;
      if (exerciseId == null) continue;
      byExercise.putIfAbsent(exerciseId, () => []).add(p);
    }
    return byExercise;
  }

  /// The template's exercise order — first appearance in the repo's
  /// (exercise_order, set_number)-ordered rows.
  List<String> _plannedOrderFromSets(List<PlannedSessionExerciseSet> sets) {
    final order = <String>[];
    for (final p in sets) {
      final exerciseId = p.exerciseId;
      if (exerciseId == null) continue;
      if (!order.contains(exerciseId)) order.add(exerciseId);
    }
    return order;
  }

  /// The record the next session will repeat — "From past session"
  /// (2026-10-26). Set by [selectPastSession] and consumed (and cleared) by
  /// [startWorkout]; any template pick clears it, because picking a template
  /// is picking what today's session follows.
  PastSessionSeed? pastSessionSeed;

  /// Picks a standalone workout to log.
  Future<void> selectStandaloneWorkout(PlannedSession w) async {
    pastSessionSeed = null;
    selectedStandaloneWorkout = w;
    selectedPlannedSession = null;
    final sets = await _plannedSessionRepo.readNormalizedPlannedSession(
      w.sessionId,
    );
    plannedSetsByExercise = _plannedMapFromSets(sets);
    plannedExerciseOrder = _plannedOrderFromSets(sets);
    notifyListeners();
  }

  /// Picks a different planned workout to log and loads its planned sets.
  Future<void> selectPlannedSession(PlannedSession w) async {
    pastSessionSeed = null;
    selectedPlannedSession = w;
    selectedStandaloneWorkout = null;
    await _loadSelectedSessionSets();
    notifyListeners();
  }

  /// Picks a completed session to repeat (2026-10-26): reads its exercise
  /// arrangement once and resolves the plan it rode on, so Start can copy the
  /// record without a second read.
  ///
  /// The plan is attributed the way a restore attributes it (program
  /// membership picks the list), because a record that followed a plan starts
  /// today's session following the same one — that is what fills the header
  /// with the plan's name and the card's empty cells with its guides. A
  /// freestyle record follows no plan: the session starts flat, and the
  /// card's own history is the only guide it needs.
  Future<void> selectPastSession(SessionWithSets source) async {
    List<SessionExercise> exercises;
    try {
      exercises = await _sessionRepo.loadSessionExercises(
        source.session.sessionId,
      );
    } catch (_) {
      // The arrangement can still be read off the sets (first appearance);
      // only the plan links would be lost, and a repeat that copies the
      // morning's weights is better than a picker row that does nothing.
      exercises = const [];
    }
    final planId = source.session.plannedSessionId;
    PlannedSession? template;
    if (planId != null) {
      try {
        template = await _plannedSessionRepo.fetchPlannedSessionById(planId);
      } catch (_) {}
    }
    if (template != null) {
      final plan = template;
      final templateId = plan.sessionId;
      // Attribute the selection so the header reads the plan's live name and
      // the planned rows keep their guides — the same classification the
      // restore's `_restorePlannedContext` makes.
      final inProgram = availableWorkouts.any((w) => w.sessionId == templateId);
      if (inProgram) {
        selectedPlannedSession = plan;
        selectedStandaloneWorkout = null;
      } else {
        selectedStandaloneWorkout = plan;
        selectedPlannedSession = null;
      }
      try {
        final plannedSets = await _plannedSessionRepo
            .readNormalizedPlannedSession(templateId);
        plannedSetsByExercise = _plannedMapFromSets(plannedSets);
        plannedExerciseOrder = _plannedOrderFromSets(plannedSets);
      } catch (_) {}
    } else {
      selectedPlannedSession = null;
      selectedStandaloneWorkout = null;
      plannedSetsByExercise = {};
      plannedExerciseOrder = [];
    }
    pastSessionSeed = PastSessionSeed(
      source: source.session,
      exercises: exercises,
      sets: source.sets,
      plan: template,
    );
    notifyListeners();
  }

  /// Clears the template selection — the session becomes free-form
  /// (no planned sets, no program attribution).
  void clearTemplateSelection() {
    pastSessionSeed = null;
    selectedPlannedSession = null;
    selectedStandaloneWorkout = null;
    plannedSetsByExercise = {};
    plannedExerciseOrder = [];
    notifyListeners();
  }

  /// Refreshes the current program / planned-workout state — called when the
  /// session tab becomes active again so a newly created (or begun) program
  /// shows without a full restart.
  ///
  /// When a workout is active, only validates that the program reference is
  /// still alive (clears the header if the program was deleted).  Full reload
  /// of available workouts and planned sets is deferred until the workout ends.
  Future<void> refreshProgram() async {
    // Refresh the past-sets timeline (and the latest-session reflection built
    // from it) on tab return — edits made on other tabs (logs, lessons) must
    // show up here without a restart.
    await _loadPastSets();
    try {
      // Validate the program reference regardless of active-workout state:
      // if the user deleted the program from the library mid-session, clear
      // the stale header so we don't show a dangling "Week N · Program".
      if (currentWorkoutId != null && programProgress != null) {
        final program = await _programRepo.fetchProgram(
          programProgress!.program.programId,
        );
        if (program == null) {
          // Program was deleted — tear down the stale program state.
          programProgress = null;
          availableWorkouts = [];
          selectedPlannedSession = null;
          plannedSetsByExercise = {};
          plannedExerciseOrder = [];
          notifyListeners();
        }
        return;
      }
      if (currentWorkoutId != null) return;

      // A session seeded from a past record owns the idle page (2026-10-26):
      // the picker's defaults must not re-choose a template underneath it —
      // a tab switch is not a reason to drop the repeat, re-name the header
      // or swap the guides to another plan's.
      if (pastSessionSeed != null) return;

      programProgress = await _programRunRepo.getProgress(_userId);
      final programId = programProgress?.program.programId;
      if (programId != null) {
        availableWorkouts = await _programRepo.fetchPlannedSessions(programId);
        // An explicit pick survives a tab switch: re-entering refreshes the
        // list, it does not re-choose. Only an absent (or vanished) selection
        // falls back to the run's next workout.
        final picked = selectedPlannedSession;
        final stillAvailable =
            picked != null &&
            availableWorkouts.any((w) => w.sessionId == picked.sessionId);
        if (!stillAvailable) {
          selectedPlannedSession =
              programProgress?.nextPlannedSession ??
              availableWorkouts.firstOrNull;
        }
      } else {
        availableWorkouts = [];
        selectedPlannedSession = null;
        plannedSetsByExercise = {};
        plannedExerciseOrder = [];
      }
      // Standalone templates are independent of the program — re-fetch them
      // too so a template created on another tab shows without a restart.
      standaloneWorkouts = await _plannedSessionRepo.fetchPlannedSessions(
        _userId,
      );
      _sortStandaloneByRecency();
      // Same pick-persistence rule for a standalone template: only a selection
      // that no longer exists is dropped.
      final standalone = selectedStandaloneWorkout;
      if (standalone != null &&
          !standaloneWorkouts.any((w) => w.sessionId == standalone.sessionId)) {
        selectedStandaloneWorkout = null;
      }
      await _loadSelectedSessionSets();
      notifyListeners();
    } catch (_) {}
  }

  /// [bumpVersion] is the browse's remount signal: `pastSetsVersion` keys the
  /// Home list, so a bump rebuilds it at offset 0 with its filters cleared.
  /// A refresh that only re-reads what the list has already reloaded itself
  /// passes false and leaves the browse where the user left it
  /// (2026-10-25).
  Future<void> _loadPastSets({
    bool keepReflectionPosition = false,
    bool bumpVersion = true,
  }) async {
    try {
      // The timeline is the app's most-read query; the shared cache is its
      // memo (2026-10-13). Every fact write, sync round and sign-out
      // invalidates it, so this costs a query only when something changed
      // since the last read — and the list, the exercise detail and the
      // library all ride the same copy. `asc` is the cache's oldest-first
      // copy, the order the PR engine walks (2026-10-25).
      final cache = PastSetsTimelineCache.instance;
      _pastSets = await cache.get(_userId);
      _pastSetsAsc =
          cache.asc(_userId) ??
          ([..._pastSets]..sort((a, b) {
            final d = a.sessionCreatedDate.compareTo(b.sessionCreatedDate);
            return d != 0 ? d : a.setNumber.compareTo(b.setNumber);
          }));
      _timelineLastUsed = lastUsedByEntity(_pastSets);
      historyByExercise = groupHistoryByExercise(_pastSets);
      lastUsedByExercise = lastUsedByEntity(_pastSets);
      // The template picker's recency rides the same timeline: the template
      // that was just logged leads the list without waiting for the next
      // picker read (2026-10-26).
      _sortStandaloneByRecency();
      // A walk can never point past the stack it belongs to: an edit that
      // deleted the performance being read lands back on the last one
      // still there (2026-10-23).
      final stack = activeExerciseHistory.length;
      if (exerciseHistoryIndex > stack) exerciseHistoryIndex = stack;
    } catch (_) {}
    // Goals ride with the timeline: the G badge is derived from the same
    // history, and a failed goal read leaves the badge off rather than the
    // timeline empty — the read is an extra, never a blocker.
    try {
      _goals = [
        for (final option in await _programRepo.fetchGoalOptions(_userId))
          option.goal,
      ];
    } catch (_) {
      _goals = const [];
    }
    pastSetsLoaded = true;
    if (bumpVersion) pastSetsVersion++;
    notifyListeners();
    // The live session's PR highlighting and events derive from the
    // timeline — recompute on every reload so history edits and tab
    // re-entry don't leave stale badges or before-facts mid-workout.
    if (currentWorkoutId != null && sets.isNotEmpty) {
      _recomputePRs();
    }
    await _refreshReflection(keepPosition: keepReflectionPosition);
  }

  /// Rebuilds the viewer card's pageable session list from the past-sets
  /// timeline and shows the most recent completed session — or THIS SESSION
  /// (the still-active workout) when the wizard sits on the reflection page.
  /// Timeline rows are created_datetime DESC, so first-appearance order of
  /// session ids is newest-first (left/previous = older, right/next = newer).
  Future<void> _refreshReflection({bool keepPosition = false}) async {
    final ids = <String>[];
    for (final s in _pastSets) {
      if (!ids.contains(s.sessionId)) ids.add(s.sessionId);
    }
    _reflectionSessionIds = ids;
    // Position-preserving refresh — recompute whatever the card currently
    // shows (used after returning from the past-session viewer, whose edits
    // change the timeline but not the pager).
    if (keepPosition) {
      if (_reflectionIndex == -1) {
        if (currentWorkoutId != null) {
          await _computeReflectionFor(null);
          return;
        }
      } else if (_reflectionIndex < ids.length) {
        await _computeReflectionFor(ids[_reflectionIndex]);
        return;
      }
      // Fall through — stale position (e.g. index past the new end).
    }
    if (currentWorkoutId != null &&
        slidePagesController.currentPage == kSummaryPage) {
      _reflectionIndex = -1;
      // Runs even with an empty completed history — a first-ever session
      // still has live sets to reflect on.
      await _computeReflectionFor(null);
      return;
    }
    _reflectionIndex = 0;
    if (ids.isEmpty) {
      reflectionSession = null;
      reflectionExercises = [];
      reflectionPrsByExercise = {};
      reflectionLessonsByExercise = {};
      reflectionExerciseNames = {};
      notifyListeners();
      return;
    }
    await _computeReflectionFor(ids.first);
  }

  /// Steps the viewer card to the next older completed session (from THIS
  /// SESSION, the first completed one).
  void showOlderReflectionSession() {
    if (!reflectionCanGoOlder) return;
    _reflectionIndex = _reflectionIndex == -1 ? 0 : _reflectionIndex + 1;
    _computeReflectionFor(_reflectionSessionIds[_reflectionIndex]);
  }

  /// Steps the viewer card back toward the most recent completed session —
  /// and from there to THIS SESSION when a workout is active.
  void showNewerReflectionSession() {
    if (!reflectionCanGoNewer) return;
    _reflectionIndex--;
    _computeReflectionFor(
      _reflectionIndex == -1 ? null : _reflectionSessionIds[_reflectionIndex],
    );
  }

  /// Shows THIS SESSION (the still-active workout) — the reflection page's
  /// default position. Called before the wizard slides to page 2.
  Future<void> showCurrentReflection() async {
    if (currentWorkoutId == null) return;
    _reflectionIndex = -1;
    await _computeReflectionFor(null);
  }

  /// How many completed sessions the viewer can page through / list.
  int get completedSessionCount => _reflectionSessionIds.length;

  /// All completed sessions (newest first) with their sets — the data for
  /// the viewer card's all-sessions picker sheet.
  Future<List<SessionWithSets>> loadCompletedSessions() =>
      _sessionRepo.loadSessionsWithSets(_userId);

  /// Hard-deletes a completed session from the all-sessions picker, then
  /// rebuilds everything derived from the timeline — PR counts, history
  /// grouping, and the reflection pager. The picker can only ever list
  /// completed sessions (`loadSessionsWithSets` filters
  /// `end_datetime IS NOT NULL`), so the still-active workout is
  /// unreachable from here; the guard is belt-and-braces.
  ///
  /// Position is deliberately NOT preserved: removing a row shifts every
  /// index, so the pager falls through [_refreshReflection]'s default path
  /// (THIS SESSION on the summary page, else the newest completed session).
  Future<void> deleteCompletedSession(String sessionId) async {
    if (sessionId == currentWorkoutId) return;
    await _sessionRepo.deleteSession(sessionId);
    await _loadPastSets();
  }

  /// sessionId → exerciseId → PR count, one global `prEvents` walk of the
  /// loaded timeline (a set is a PR relative to all prior history, so
  /// counts must come from the global walk, never per-session sets). The
  /// all-sessions picker sheet's cards' trophy badges.
  Map<String, Map<String, int>> prCountsByCompletedSession() {
    final out = <String, Map<String, int>>{};
    for (final e in prEventsSorted(_pastSetsAsc)) {
      final byExercise = out.putIfAbsent(e.sessionId, () => {});
      byExercise[e.exerciseId] = (byExercise[e.exerciseId] ?? 0) + 1;
    }
    return out;
  }

  /// Jumps the viewer card to a completed session picked from the
  /// all-sessions sheet.
  void selectReflectionSession(String sessionId) {
    final idx = _reflectionSessionIds.indexOf(sessionId);
    if (idx < 0) return;
    _reflectionIndex = idx;
    _computeReflectionFor(sessionId);
  }

  /// Recomputes the reflection the viewer card currently shows after edits
  /// made in the past-session viewer — reloads the timeline first (set edits
  /// change it, and the stale timeline would otherwise poison the next
  /// workout's PR baseline) while keeping the pager position.
  ///
  /// [bumpVersion] decides whether the Home browse is re-keyed (and so
  /// rebuilt at offset 0). A refresh that hangs off the browse's own reload —
  /// a deleted card, a return from the viewer — passes false, because
  /// remounting there would only throw away the user's scroll and filters
  /// (2026-10-25).
  Future<void> refreshShownReflection({bool bumpVersion = true}) async {
    await _loadPastSets(keepReflectionPosition: true, bumpVersion: bumpVersion);
  }

  /// Resets the pager to the most recent completed session — called when the
  /// idle wizard steps back to Prep so a stale THIS SESSION position can
  /// never leak onto the prep card.
  Future<void> showLatestReflection() async {
    _reflectionIndex = 0;
    if (_reflectionSessionIds.isEmpty) {
      reflectionSession = null;
      reflectionExercises = [];
      reflectionPrsByExercise = {};
      reflectionLessonsByExercise = {};
      reflectionExerciseNames = {};
      notifyListeners();
      return;
    }
    await _computeReflectionFor(_reflectionSessionIds.first);
  }

  /// Computes one session's reflection summary — the same `prEvents` walk
  /// as `_recomputePRs`; events carry their own before-facts. A null
  /// [sessionId] means the still-active workout: the summary is built from
  /// live state instead of the completed timeline (which excludes active
  /// sessions).
  Future<void> _computeReflectionFor(String? sessionId) async {
    reflectionExercises = [];
    reflectionPrsByExercise = {};
    reflectionLessonsByExercise = {};
    reflectionExerciseNames = {};
    reflectionSession = null;

    final id = sessionId ?? currentWorkoutId;
    if (id == null) {
      notifyListeners();
      return;
    }
    final isLive = sessionId == null;

    try {
      reflectionSession = await _sessionRepo.fetchSession(id);
    } catch (_) {
      reflectionSession = null;
    }

    // ── Live branch: the still-active workout ──
    if (isLive) {
      final sessionPrs = sessionPrEvents;
      final orderedIds = <String>[];
      final nameById = <String, String>{};
      for (final s in sets) {
        final exerciseId = s.exerciseId;
        if (exerciseId == null) continue;
        nameById.putIfAbsent(
          exerciseId,
          () => exerciseDetailMap[exerciseId]?.name ?? s.exerciseName ?? '',
        );
        if (!orderedIds.contains(exerciseId)) orderedIds.add(exerciseId);
      }
      for (final exerciseId in orderedIds) {
        try {
          lessonsByExercise[exerciseId] = await _lessonRepo.fetchLessons(
            _userId,
            exerciseId,
          );
        } catch (_) {}
      }
      final contentIds = orderedIds
          .where(
            (exerciseId) =>
                sessionPrs.any((p) => p.exerciseId == exerciseId) ||
                lessonsThisSession(exerciseId).isNotEmpty,
          )
          .toList();
      reflectionExercises = contentIds;
      reflectionExerciseNames = {
        for (final exerciseId in contentIds)
          exerciseId: nameById[exerciseId] ?? '',
      };
      reflectionPrsByExercise = {
        for (final exerciseId in contentIds)
          exerciseId: sessionPrs
              .where((p) => p.exerciseId == exerciseId)
              .toList(),
      };
      reflectionLessonsByExercise = {
        for (final exerciseId in contentIds)
          exerciseId: [for (final l in lessonsThisSession(exerciseId)) l.text],
      };
      notifyListeners();
      return;
    }

    // ── Historical branch: a completed session ──
    // Events carry their own before-facts, so nothing extra to compute —
    // just the completed session's events.
    final sessionPrs = prEventsSorted(
      _pastSetsAsc,
    ).where((r) => r.sessionId == id).toList();

    // Exercise order = first appearance in the session (set-number order);
    // names prefer the current catalog, falling back to the logged snapshot
    // (mirrors exerciseDisplayName for deactivated exercises).
    final orderedIds = <String>[];
    final nameById = <String, String>{};
    for (final s in _pastSets) {
      if (s.sessionId != id) continue;
      final exerciseId = s.exerciseId;
      if (exerciseId == null) continue;
      nameById.putIfAbsent(
        exerciseId,
        () => exerciseDetailMap[exerciseId]?.name ?? s.exerciseName ?? '',
      );
      if (!orderedIds.contains(exerciseId)) orderedIds.add(exerciseId);
    }

    // Lessons are per-exercise and cross-session — fetch them so the preview
    // is populated without opening the lessons modal first (same pattern as
    // loadLessonsFor), and cache them for the upcoming session's cards.
    for (final exerciseId in orderedIds) {
      try {
        lessonsByExercise[exerciseId] = await _lessonRepo.fetchLessons(
          _userId,
          exerciseId,
        );
      } catch (_) {}
    }

    final contentIds = orderedIds
        .where(
          (exerciseId) =>
              sessionPrs.any((p) => p.exerciseId == exerciseId) ||
              (lessonsByExercise[exerciseId] ?? const []).isNotEmpty,
        )
        .toList();
    reflectionExercises = contentIds;
    reflectionExerciseNames = {
      for (final exerciseId in contentIds)
        exerciseId: nameById[exerciseId] ?? '',
    };
    reflectionPrsByExercise = {
      for (final exerciseId in contentIds)
        exerciseId: sessionPrs
            .where((p) => p.exerciseId == exerciseId)
            .toList(),
    };
    reflectionLessonsByExercise = {
      for (final exerciseId in contentIds)
        exerciseId: [
          // Session-scoped like the live reflection — only lessons born in
          // this session count toward its preview.
          for (final l in lessonsByExercise[exerciseId] ?? const <Lesson>[])
            if (l.sessionId == id) l.text,
        ],
    };
    notifyListeners();
  }

  /// Resumes THIS device's own live session (2026-10-15: filtered by device
  /// id, so a session running on another device is never silently adopted —
  /// it only ever surfaces through [foreignActiveSessions] and the notice).
  Future<void> _restoreActiveWorkout() async {
    final deviceId = await _resolveDeviceId();
    final activeId = await _sessionRepo.getActiveSessionId(
      _userId,
      deviceId: deviceId,
    );
    if (activeId != null) await _adoptSession(activeId);
  }

  /// Makes [sessionId] this device's live session — the launch resume and
  /// the foreign-session switch share every step (2026-10-15).
  Future<void> _adoptSession(String sessionId) async {
    currentWorkoutId = sessionId;
    final workout = await _sessionRepo.fetchSession(sessionId);
    workoutStartedAt = workout?.createdDatetime;
    // The pre answers were written at creation (Training's Start). Reseed
    // them on resume: the ratings pencil edits the same two fields, and
    // Done writes all four — without this, a restored session would save
    // blank pre answers over the ones the prep page collected (2026-10-22).
    startNotes = workout?.preNotes ?? '';
    sessionFeeling = workout?.preFeeling;
    await _restorePlannedContext(workout);
    slidePagesController.resetToPage(kTrainingPage);
    await _loadSets();
    _seedExerciseSlots(seedDrafts: false);
    _subscribeToSessionStreams();
    unawaited(_loadPreviousSession());
  }

  /// Reads the date bar's older step (2026-10-22): the newest completed
  /// session that started before this one. Chrome — a failed read leaves the
  /// left arrow spent rather than surfacing an error over the grid.
  Future<void> _loadPreviousSession() async {
    try {
      final stamps = await _sessionRepo.loadCompletedSessionStamps(_userId);
      final started = workoutStartedAt;
      previousSessionId = null;
      for (final s in stamps) {
        if (started == null || s.createdDatetime.isBefore(started)) {
          previousSessionId = s.sessionId;
          break;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Re-reads the older step after a peek found its record gone
  /// (2026-10-23): the stamp list the arrow was built from went stale — a
  /// sync round removed the row — and without a re-read the arrow would
  /// keep pointing at nothing for the rest of the session.
  void refreshPreviousSession() => unawaited(_loadPreviousSession());

  /// A reader for a record the live Training page has stepped onto
  /// (2026-10-22).
  ///
  /// The date bar walks the stack **in place** — the same page swaps the
  /// sets under it — so the live screen hosts the viewer's own reader
  /// instead of pushing `/logs/:id`. Same database, same user: the peek
  /// reads exactly what the viewer route would, with this session never
  /// leaving the screen.
  SessionDetailViewModel createRecordPeek() => SessionDetailViewModel(
    sessionRepo: _sessionRepo,
    exerciseRepo: _exerciseRepo,
    lessonRepo: _lessonRepo,
    programRepo: _programRepo,
    userId: _userId,
  );

  /// Watches for OTHER devices' live sessions (2026-10-15) — the notice's
  /// feed. Runs for the VM's whole life: at launch a foreign session is what
  /// the notice offers, mid-session it is what a Switch trades for.
  void _subscribeToForeignSessions() {
    _foreignSessionsSub?.cancel();
    _foreignSessionsSub = _sessionRepo.watchActiveSessions(_userId).listen((
      sessions,
    ) {
      final foreign = [
        for (final s in sessions)
          // Mine (by device id, or by being the session on screen) is
          // not foreign; the rest are, unless the user said Stay.
          if (s.sessionId != currentWorkoutId &&
              s.deviceId != _deviceId &&
              !_dismissedForeignSessions.contains(s.sessionId))
            s,
      ];
      foreignActiveSessions = foreign;
      notifyListeners();
    }, onError: (_) {});
  }

  /// The notice's "Stay": this device keeps its own session, and this other
  /// session stops asking for the rest of the VM's life.
  void dismissForeignSession(String sessionId) {
    _dismissedForeignSessions.add(sessionId);
    foreignActiveSessions = [
      for (final s in foreignActiveSessions)
        if (s.sessionId != sessionId) s,
    ];
    notifyListeners();
  }

  /// The preview's "Switch": make [sessionId] — a live session started on
  /// another device — this device's live session (2026-10-15). Answers
  /// whether it happened: false when the session ENDED on its own device
  /// while the user was reading the preview (a completed row is not
  /// something to adopt).
  ///
  /// With a session of this device's own in progress, [completeMine] says
  /// what happens to it: true ends it and files it in the logs (sets and
  /// all, no reflection wizard — the logs editor takes the notes later),
  /// false cancels it outright. Then the other session is CLAIMED (its
  /// device id becomes this device's, so the next launch resumes it here)
  /// and adopted.
  Future<bool> switchToForeignSession(
    String sessionId, {
    required bool completeMine,
  }) async {
    // Still live? It may have ended elsewhere since the preview loaded.
    try {
      final fresh = await _sessionRepo.fetchSession(sessionId);
      if (fresh != null && fresh.endDatetime != null) return false;
    } catch (_) {
      // A failed read must not block the switch — the adopt path re-checks
      // nothing but writes nothing destructive either way.
    }
    if (currentWorkoutId != null) {
      if (completeMine) {
        await _completeActiveForSwitch();
      } else {
        await cancelSession();
      }
    }
    final deviceId = await _resolveDeviceId();
    if (deviceId != null) {
      try {
        await _sessionRepo.claimSession(sessionId, deviceId);
      } catch (_) {}
    }
    await _adoptSession(sessionId);
    // The session on screen is this device's now — out of the notice's list
    // by the currentWorkoutId filter, and off the list right away.
    foreignActiveSessions = [
      for (final s in foreignActiveSessions)
        if (s.sessionId != sessionId) s,
    ];
    notifyListeners();
    return true;
  }

  /// Ends the active session without the reflection wizard — the switch's
  /// "complete mine". Same guards as [finishSession] up to the end stamp:
  /// flush typed edits, pull the authoritative rows, prune plan-hint
  /// residue, stamp `end_datetime`. The session then lives in the logs like
  /// any completed one (its pre/post notes stay editable there).
  Future<void> _completeActiveForSwitch() async {
    final id = currentWorkoutId;
    if (id == null) return;
    try {
      await flushPendingCommits();
      await _pullCurrentSession();
      await _pruneUntouchedPlannedRows();
      await _sessionRepo.endSession(id);
    } catch (_) {}
    _resetActiveWorkoutState();
    await _loadPastSets();
  }

  /// Re-derives the planned context from the active session's persisted
  /// [Session.plannedSessionId] — the template that was actually started, not
  /// whatever the default picker would choose. Without this, a hot restart
  /// of a standalone (or non-default) session loses its planned rows and
  /// hints entirely.
  Future<void> _restorePlannedContext(Session? workout) async {
    final parentId = workout?.plannedSessionId;
    if (parentId == null) return; // freestyle — no plan to restore
    final template = await _plannedSessionRepo.fetchPlannedSessionById(
      parentId,
    );
    if (template == null) {
      // Template is gone (deleted/archived) — the session keeps its logged
      // rows but has no planned hints left to show.
      plannedSetsByExercise = {};
      plannedExerciseOrder = [];
      return;
    }
    // Attribute the selection so the header and picker read the right
    // template — program membership is a join row now, so classify by
    // whether the template is among the program's workouts.
    final inProgram = availableWorkouts.any(
      (w) => w.sessionId == template.sessionId,
    );
    if (inProgram) {
      selectedPlannedSession = template;
      selectedStandaloneWorkout = null;
    } else {
      selectedStandaloneWorkout = template;
      selectedPlannedSession = null;
    }
    try {
      final plannedSets = await _plannedSessionRepo
          .readNormalizedPlannedSession(parentId);
      plannedSetsByExercise = _plannedMapFromSets(plannedSets);
      plannedExerciseOrder = _plannedOrderFromSets(plannedSets);
    } catch (_) {}
  }

  /// Splits the session's set rows into active and flagged (2026-10-13) —
  /// the queries return ALL rows; the grid, PRs and numbering see only the
  /// active half, while [deletedSets] backs the selector's minus entries.
  void _partitionSets(List<SessionExerciseSet> rows) {
    sets = [
      for (final r in rows)
        if (!r.isDeleted) r,
    ];
    deletedSets = [
      for (final r in rows)
        if (r.isDeleted) r,
    ];
  }

  Future<void> _loadSets() async {
    if (currentWorkoutId == null) return;
    setsLoading = true;
    notifyListeners();
    _partitionSets(await _sessionRepo.loadSetsForSession(currentWorkoutId!));
    sessionExercises = await _sessionRepo.loadSessionExercises(
      currentWorkoutId!,
    );
    setsLoading = false;
    _recomputePRs();
    notifyListeners();
  }

  /// The same pull as [_loadSets] minus the loading toggles and notifies —
  /// an authoritative refresh for the moments that must read the DB before
  /// the watch stream's next emission (the pre-prune read at session end).
  Future<void> _pullCurrentSession() async {
    final id = currentWorkoutId;
    if (id == null) return;
    try {
      _partitionSets(await _sessionRepo.loadSetsForSession(id));
      sessionExercises = await _sessionRepo.loadSessionExercises(id);
      _recomputePRs();
    } catch (_) {}
  }

  /// Subscribes to the active session's row streams. From here on, every
  /// write (debounced or discrete, local or synced) re-emits the
  /// authoritative rows and the listener recomputes PRs — no per-edit
  /// pulls. Subscribed AFTER the initial [_loadSets] so start/restore can
  /// seed slots from loaded rows first.
  void _subscribeToSessionStreams() {
    final id = currentWorkoutId;
    if (id == null) return;
    _cancelSessionStreams();
    _setsSub = _sessionRepo
        .watchSetsForSession(id)
        .listen(
          (rows) {
            _partitionSets(rows);
            setsLoading = false;
            _recomputePRs();
            notifyListeners();
          },
          onError: (Object e) {
            error = e.toString();
            notifyListeners();
          },
        );
    _exercisesSub = _sessionRepo
        .watchSessionExercises(id)
        .listen(
          (rows) {
            sessionExercises = rows;
            notifyListeners();
          },
          onError: (Object e) {
            error = e.toString();
            notifyListeners();
          },
        );
  }

  void _cancelSessionStreams() {
    _setsSub?.cancel();
    _setsSub = null;
    _exercisesSub?.cancel();
    _exercisesSub = null;
  }

  /// Recomputes which sets are PRs using the engine's frontier semantics —
  /// history first, then this session's sets in set-number order, so any
  /// set that extends its pair's best-ever frontier highlights. One event
  /// per PR set; the same events feed counts, accents, and before/after
  /// values, so the surfaces can never disagree.
  ///
  /// Runs on every sets change (each debounced write settle, each stream
  /// emission), so the hot parts are pre-sorted and pre-merged: the timeline
  /// walks in load-time order and `lastUsedByExercise` merges the live rows
  /// over the load-time map instead of re-walking the whole history
  /// (2026-10-13).
  void _recomputePRs() {
    final id = currentWorkoutId;
    if (id == null) {
      prSetIds = {};
      sessionPrEvents = [];
      allPrEvents = [];
      prEventsBySetId = {};
      goalSetIds = {};
      return;
    }
    final combined = <PastSetRow>[
      for (final s in _pastSetsAsc)
        if (s.sessionId != id) s,
    ];
    final sessionDate = workoutStartedAt ?? DateTime.now();
    final ordered = [...sets]
      ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
    for (final s in ordered) {
      combined.add(
        PastSetRow(
          sessionExerciseSetId: s.sessionExerciseSetId,
          sessionExerciseId: s.sessionExerciseId,
          sessionId: s.sessionId,
          userId: s.userId,
          exerciseId: s.exerciseId,
          setNumber: s.setNumber,
          reps: s.reps,
          sessionCreatedDate: sessionDate,
          variationId: s.variationId,
          weight: s.weight,
          notes: s.notes,
          exerciseName: s.exerciseName,
          variationName: s.variationName,
        ),
      );
    }
    // Recency includes the live rows: what was just trained is by definition
    // the most recent use, and a chooser opened mid-workout has to say so. The
    // past-sets timeline only sees completed sessions, so the merge happens
    // here — as an overwrite of the load-time map, not a full re-walk.
    lastUsedByExercise = Map.of(_timelineLastUsed);
    for (final s in ordered) {
      final exId = s.exerciseId;
      if (exId != null &&
          sessionDate.isAfter(
            lastUsedByExercise[exId] ?? DateTime.fromMillisecondsSinceEpoch(0),
          )) {
        lastUsedByExercise[exId] = sessionDate;
      }
      final vid = s.variationId;
      if (vid != null &&
          sessionDate.isAfter(
            lastUsedByExercise[vid] ?? DateTime.fromMillisecondsSinceEpoch(0),
          )) {
        lastUsedByExercise[vid] = sessionDate;
      }
    }
    final events = prEventsSorted(combined);
    allPrEvents = events;
    sessionPrEvents = events.where((e) => e.sessionId == id).toList();
    prSetIds = {
      for (final e in sessionPrEvents)
        if (e.sessionExerciseSetId != null) e.sessionExerciseSetId!,
    };
    // Full-timeline events keyed by source set — the history viewer's PR
    // badges (completed sets only; this session's sets badge via prSetIds).
    prEventsBySetId = {
      for (final e in events)
        if (e.sessionExerciseSetId != null) e.sessionExerciseSetId!: e,
    };
    // Goal sets over the same merged timeline, so a live session's own row
    // can wear the G the moment it achieves the target (2026-10-20).
    goalSetIds = goalAchievingSetIds(goals: _goals, sets: combined);
  }

  bool isPrSet(String setId) => prSetIds.contains(setId);

  /// Whether [setId] achieved one of the user's goals.
  bool isGoalSet(String setId) => goalSetIds.contains(setId);

  /// The PRs this session landed for [exerciseId] — the count its card pill
  /// and the floor's trophy tile show, and the PR History sheet's
  /// `THIS SESSION` group.
  int sessionPrCountFor(String exerciseId) =>
      sessionPrEvents.where((e) => e.exerciseId == exerciseId).length;

  /// Every PR [exerciseId] ever landed — all its variations, oldest first —
  /// the PR History sheet's full feed (2026-10-22).
  List<PrEvent> prHistoryFor(String exerciseId) => [
    for (final e in allPrEvents)
      if (e.exerciseId == exerciseId) e,
  ];

  /// The set ids this session landed PRs on for [exerciseId] — what splits
  /// [prHistoryFor] into `THIS SESSION` and `PREVIOUSLY`.
  Set<String> sessionPrSetIdsFor(String exerciseId) => {
    for (final e in sessionPrEvents)
      if (e.exerciseId == exerciseId && e.sessionExerciseSetId != null)
        e.sessionExerciseSetId!,
  };

  // ── Exercise tabs ──────────────────────────────────────────────────────────

  void _seedExerciseSlots({bool seedDrafts = true}) {
    // A fresh bar (a new workout, a restore) has no deleted view.
    deletedViewSeId = null;
    final slots = <SessionExerciseSlot>[];
    final seen = <String>{};
    // Session exercises come back ordered by exercise_order — the persisted
    // tab arrangement (the old JSON blob's replacement).
    for (final se in sessionExercises) {
      final exId = se.exerciseId;
      if (exId == null || !seen.add(exId)) continue;
      final exerciseSets = sets.where((x) => x.exerciseId == exId).toList();
      final exerciseFlagged = deletedSets
          .where((x) => x.sessionExerciseId == se.sessionExerciseId)
          .toList();
      // A planned exercise whose rows are ALL flagged was deleted this
      // session — it returns as a minus-marked selector entry, not a tab
      // (2026-10-13). Recording it here is what keeps the trash menu stocked
      // across a hot restart; the slot it would have taken stands as its
      // position.
      if (se.plannedExerciseId != null &&
          exerciseSets.isEmpty &&
          exerciseFlagged.isNotEmpty) {
        _deletedPlannedOrder.add(se.sessionExerciseId);
        _deletedPlannedSlotIndex[se.sessionExerciseId] = slots.length;
        continue;
      }
      // Materialized planned rows are the entry rows — seed a draft only when
      // the exercise has no rows left or its last row is filled (mirrors the
      // freestyle rule below). Restores pass seedDrafts: false — a restart
      // must not invent empty rows the user never created.
      final last = exerciseSets.isEmpty ? null : exerciseSets.last;
      final lastEmpty = last != null && last.reps.isEmpty;
      if (seedDrafts && !lastEmpty) {
        _seedDraft(exId);
      }
      loadLessonsFor(exId);
      slots.add(
        SessionExerciseSlot(
          id: _nextSlotId++,
          type: SessionSlotType.single,
          exerciseIds: [exId],
          planned: se.plannedExerciseId != null,
        ),
      );
    }
    exerciseSlots = slots;
    activeSlotIndex = 0;
    notifyListeners();
  }

  /// Tapping the already-active tab is a no-op; tapping any other tab
  /// switches to it.
  Future<void> tapTab(int index) async {
    if (index == activeSlotIndex) return;
    // Flush in-flight row edits before the rows unmount — switching tabs must
    // never lose typed values (commit is otherwise blur-only). Awaited so the
    // switch rebuild can't dispose rows mid-flush.
    await flushPendingCommits();
    // A tab switch leaves the deleted view: the tab tapped is what is on
    // screen now (2026-10-14).
    deletedViewSeId = null;
    if (index == activeSlotIndex) {
      notifyListeners();
      return;
    }
    activeSlotIndex = index;
    // The card on screen decides what EXERCISE mode walks: a new exercise
    // starts at today's sets, and its history rows re-earn the edit gate.
    exerciseHistoryIndex = 0;
    historyEditConfirmed = false;
    notifyListeners();
  }

  /// Long-press drag reorder of the exercise tab bar. Indices past the tab
  /// count are deleted-planned selector entries — not reorderable (2026-10-13).
  void reorderExercises(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 ||
        oldIndex >= exerciseSlots.length ||
        newIndex < 0 ||
        newIndex >= exerciseSlots.length) {
      return;
    }
    final orderBefore = [for (final sl in exerciseSlots) sl.id];
    final activeBefore = activeSlotIndex;

    Future<void> forward() async {
      final slot = exerciseSlots.removeAt(oldIndex);
      exerciseSlots.insert(newIndex, slot);
      if (activeSlotIndex == oldIndex) {
        activeSlotIndex = newIndex;
      } else if (oldIndex < activeSlotIndex && newIndex >= activeSlotIndex) {
        activeSlotIndex--;
      } else if (oldIndex > activeSlotIndex && newIndex <= activeSlotIndex) {
        activeSlotIndex++;
      }
      _persistExerciseOrder();
      notifyListeners();
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final byId = {for (final sl in exerciseSlots) sl.id: sl};
          exerciseSlots = [
            for (final id in orderBefore)
              if (byId[id] != null) byId[id]!,
          ];
          activeSlotIndex = activeBefore;
          _persistExerciseOrder();
          notifyListeners();
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

  /// Hold-and-drag reorder of one exercise's set rows.
  ///
  /// [oldIndex] and [newIndex] count that exercise's REAL rows only, and
  /// [newIndex] arrives already adjusted for the row being lifted out
  /// (`onReorderItem`). Draft rows sit past the end and cannot be dropped
  /// into — they are virtual, and a drop there means "last real set".
  ///
  /// The renumber is applied locally first so the grid settles into its new
  /// order on the drop's own frame; the write follows, and its reload has
  /// nothing left to change. The rows keep their ids, so ghosts, notes, PR
  /// events and the draft bindings all stay with the set that moved.
  void reorderSets(String exerciseId, int oldIndex, int newIndex) {
    final rows = <SessionExerciseSet>[
      for (final s in sets)
        if (s.exerciseId == exerciseId &&
            !isDraftBoundRow(s.sessionExerciseSetId))
          s,
    ]..sort((a, b) => a.setNumber.compareTo(b.setNumber));
    if (rows.length < 2) return;
    if (newIndex >= rows.length) newIndex = rows.length - 1;
    if (oldIndex == newIndex || oldIndex < 0 || oldIndex >= rows.length) {
      return;
    }
    final idsBefore = [for (final r in rows) r.sessionExerciseSetId];

    Future<void> forward() async {
      final current = <SessionExerciseSet>[
        for (final s in sets)
          if (s.exerciseId == exerciseId &&
              !isDraftBoundRow(s.sessionExerciseSetId))
            s,
      ]..sort((a, b) => a.setNumber.compareTo(b.setNumber));
      if (current.length < 2 || newIndex >= current.length) return;
      current.insert(newIndex, current.removeAt(oldIndex));
      var number = 0;
      for (var i = 0; i < sets.length; i++) {
        final s = sets[i];
        if (s.exerciseId != exerciseId ||
            isDraftBoundRow(s.sessionExerciseSetId)) {
          continue;
        }
        sets[i] = current[number].copyWith(setNumber: ++number);
      }
      notifyListeners();

      final workoutId = currentWorkoutId;
      if (workoutId == null) return;
      await _sessionRepo.reorderSets(workoutId, [
        for (final s in current) s.sessionExerciseSetId,
      ]);
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final workoutId = currentWorkoutId;
          if (workoutId != null) {
            await _sessionRepo.reorderSets(workoutId, idsBefore);
          }
          final byId = {for (final s in sets) s.sessionExerciseSetId: s};
          var number = 0;
          for (var i = 0; i < sets.length; i++) {
            final s = sets[i];
            if (s.exerciseId != exerciseId ||
                isDraftBoundRow(s.sessionExerciseSetId)) {
              continue;
            }
            final restored = byId[idsBefore[number]];
            if (restored != null) {
              sets[i] = restored.copyWith(setNumber: ++number);
            }
          }
          _recomputePRs();
          notifyListeners();
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

  /// Persists the current tab order to `fact_session_exercise.exercise_order`
  /// (one row per tab) so the tab bar survives a hot restart.
  void _persistExerciseOrder() {
    final id = currentWorkoutId;
    if (id == null) return;
    final byExerciseId = <String, String>{};
    for (final se in sessionExercises) {
      final exId = se.exerciseId;
      if (exId != null) byExerciseId[exId] = se.sessionExerciseId;
    }
    final ordered = <String>[];
    for (final slot in exerciseSlots) {
      for (final exerciseId in slot.exerciseIds) {
        final rowId = byExerciseId[exerciseId];
        if (rowId != null) ordered.add(rowId);
      }
    }
    // A deleted exercise keeps its number: replay the deletions backward —
    // each recorded the tab index it held at the moment it went — so the
    // persisted order is the arrangement as it truly stood, holes included.
    // The logs viewer re-seeds from this (2026-10-13).
    for (final seId in _deletedPlannedOrder.reversed) {
      final at = _deletedPlannedSlotIndex[seId] ?? ordered.length;
      final se = sessionExercises.firstWhereOrNull(
        (e) => e.sessionExerciseId == seId,
      );
      if (se == null || se.exerciseId == null) continue;
      if (ordered.contains(seId)) continue;
      ordered.insert(at.clamp(0, ordered.length), seId);
    }
    if (ordered.isEmpty) return;
    _sessionRepo.reorderSessionExercises(id, ordered);
  }

  /// Jumps a superset tab straight to one of its exercises — the in-card
  /// superset nav's tap handler. Supersets are retired from the UI; this
  /// remains for any legacy multi-exercise slot.
  void setSupersetIndex(SessionExerciseSlot slot, int index) {
    if (index < 0 || index >= slot.exerciseIds.length) return;
    slot.activeIndex = index;
    notifyListeners();
  }

  /// If [exerciseId] is already active in some tab, adding it again would
  /// create a confusing duplicate slot with its own separate set history —
  /// instead this just navigates to the existing tab and reports that it did
  /// so, so the caller doesn't also treat it as "added."
  Future<bool> addExerciseSlot(String exerciseId) async {
    // Adding navigates — the deleted view is over either way.
    deletedViewSeId = null;
    final existingIndex = exerciseSlots.indexWhere(
      (s) => s.exerciseIds.contains(exerciseId),
    );
    if (existingIndex != -1) {
      activeSlotIndex = existingIndex;
      final slot = exerciseSlots[existingIndex];
      final subIndex = slot.exerciseIds.indexOf(exerciseId);
      if (subIndex != -1) slot.activeIndex = subIndex;
      notifyListeners();
      return false;
    }
    // Adding an exercise that already exists as a deleted planned entry
    // restores it — a second session_exercise row would read as two tabs of
    // one thing. The restore is itself an undoable step, recorded by
    // `restoreDeletedPlannedExercise` (2026-10-13).
    final deleted = deletedPlannedExercises.firstWhereOrNull(
      (e) => e.exerciseId == exerciseId,
    );
    if (deleted != null) {
      await restoreDeletedPlannedExercise(deleted.sessionExerciseId);
      return true;
    }
    final activeBefore = activeSlotIndex;
    final box = UndoBox<String>();

    Future<void> forward() async {
      final existingIndex = exerciseSlots.indexWhere(
        (s) => s.exerciseIds.contains(exerciseId),
      );
      if (existingIndex != -1) return;
      exerciseSlots.add(
        SessionExerciseSlot(
          id: _nextSlotId++,
          type: SessionSlotType.single,
          exerciseIds: [exerciseId],
        ),
      );
      // Persist the exercise row (and an empty set bound to a draft) so the
      // tab survives a hot restart — restore rediscovers tabs from
      // fact_session_exercise.
      final se = await _ensureSessionExercise(exerciseId);
      if (se != null) box.value = se.sessionExerciseId;
      addDraftSet(exerciseId);
      _persistExerciseOrder();
      loadLessonsFor(exerciseId);
      activeSlotIndex = exerciseSlots.length - 1;
      notifyListeners();
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final seId = box.value;
          if (seId != null) {
            await _sessionRepo.deleteSessionExercise(seId);
          }
          exerciseSlots.removeWhere(
            (sl) => sl.exerciseIds.contains(exerciseId),
          );
          draftSlotsByExercise.remove(exerciseId);
          activeSlotIndex = activeBefore;
          notifyListeners();
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
    return true;
  }

  /// The trash menu's row callback: restores the [entryIndex]-th entry of
  /// [deletedPlannedExerciseEntries] (2026-10-13).
  Future<void> restoreDeletedPlannedExerciseAt(int entryIndex) async {
    final entries = deletedPlannedExerciseEntries;
    if (entryIndex < 0 || entryIndex >= entries.length) return;
    await restoreDeletedPlannedExercise(entries[entryIndex].id);
  }

  /// Brings back every deleted set under a plan-linked exercise (2026-10-14)
  /// — the plan's rows AND the user's own additions, which flag like
  /// everything else under a planned exercise — addressed by its
  /// session-exercise id. Un-flags them all and, when the exercise had
  /// folded away entirely, puts its tab back in the slot it held when it was
  /// deleted ([_deletedPlannedSlotIndex]), focused; an exercise that kept
  /// active rows never left the bar. Undoable: the inverse flags the rows
  /// again and drops the tab only if the forward added one.
  ///
  /// This is the one restore under the plan: the deleted view's Restore
  /// button, the trash's re-add through the picker, and the Restore under a
  /// card that holds deleted sets all land here.
  Future<void> restoreDeletedPlannedExercise(String sessionExerciseId) async {
    final se = sessionExercises.firstWhereOrNull(
      (e) => e.sessionExerciseId == sessionExerciseId,
    );
    if (se == null || se.exerciseId == null) return;
    final exerciseId = se.exerciseId!;
    // Restoring leaves the deleted view: the exercise reads as itself again.
    if (deletedViewSeId == sessionExerciseId) deletedViewSeId = null;
    // The tab the forward adds back, when it adds one — the inverse needs to
    // know whether the bar changed (a partial deletion never left it).
    final addedSlotBox = UndoBox<SessionExerciseSlot?>();

    Future<void> forward() async {
      _deletedPlannedOrder.remove(sessionExerciseId);
      // The slot it was deleted from — its old place, so a delete and a
      // restore leave the tab bar arranged as it was (an entry with no
      // recorded position goes to the end, where the old append put it).
      final at =
          (_deletedPlannedSlotIndex.remove(sessionExerciseId) ??
                  exerciseSlots.length)
              .clamp(0, exerciseSlots.length);
      final flagged = deletedSets
          .where((s) => s.sessionExerciseId == sessionExerciseId)
          .toList();
      for (final row in flagged) {
        await _sessionRepo.updateSet(
          row.sessionExerciseSetId,
          clearIsDeleted: true,
        );
      }
      addedSlotBox.value = null;
      // A stale trash entry must not add a second tab for an exercise that
      // still has one.
      if (!exerciseSlots.any((sl) => sl.exerciseIds.contains(exerciseId))) {
        final slot = SessionExerciseSlot(
          id: _nextSlotId++,
          type: SessionSlotType.single,
          exerciseIds: [exerciseId],
          planned: true,
        );
        exerciseSlots.insert(at, slot);
        addedSlotBox.value = slot;
        // Seed a draft when the exercise's last row is filled — the same
        // rule `_seedExerciseSlots` applies at seed time.
        final exerciseSets = sets
            .where((x) => x.sessionExerciseId == sessionExerciseId)
            .toList();
        final last = exerciseSets.isEmpty ? null : exerciseSets.last;
        final lastEmpty = last != null && last.reps.isEmpty;
        if (last != null && !lastEmpty) {
          _seedDraft(exerciseId);
        }
        activeSlotIndex = at;
      }
      _persistExerciseOrder();
      notifyListeners();
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final flagged = sets
              .where((x) => x.sessionExerciseId == sessionExerciseId)
              .toList();
          for (final row in flagged) {
            await _sessionRepo.updateSet(
              row.sessionExerciseSetId,
              isDeleted: true,
            );
          }
          // Only a tab the forward ADDED comes back out — an exercise that
          // kept active rows never left the bar, and pulling its tab would
          // fold an exercise the user is still working on.
          final added = addedSlotBox.value;
          if (added != null) {
            final slotIndex = exerciseSlots.indexWhere(
              (sl) => sl.id == added.id,
            );
            if (slotIndex != -1) {
              exerciseSlots.removeAt(slotIndex);
              // Back to deleted, from the slot it is being taken out of — the
              // redo's restore reads it back and lands where the undo began.
              _deletedPlannedSlotIndex[sessionExerciseId] = slotIndex;
            }
            if (activeSlotIndex >= exerciseSlots.length) {
              activeSlotIndex = (exerciseSlots.length - 1).clamp(
                0,
                exerciseSlots.length,
              );
            }
          }
          if (!_deletedPlannedOrder.contains(sessionExerciseId)) {
            _deletedPlannedOrder.add(sessionExerciseId);
          }
          notifyListeners();
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

  void addSupersetSlot(List<String> exerciseIds) {
    exerciseSlots.add(
      SessionExerciseSlot(
        id: _nextSlotId++,
        type: SessionSlotType.superset,
        exerciseIds: exerciseIds,
      ),
    );
    for (final id in exerciseIds) {
      // Persist an empty set per exercise so the tab survives a hot restart.
      addDraftSet(id);
      loadLessonsFor(id);
    }
    _persistExerciseOrder();
    activeSlotIndex = exerciseSlots.length - 1;
    notifyListeners();
  }

  /// Removes the exercise slot at [index] and all of its sets / drafts from
  /// the current session.  The slot's exercises (single or superset) are each
  /// cleaned up.  Active-index is clamped so the tab bar never points past the
  /// new end.
  ///
  /// A PLANNED slot soft-deletes (2026-10-13): its planned rows are flagged
  /// (`is_deleted`) and the session-exercise row kept, so the exercise shows
  /// as a minus-marked selector entry and can be restored. User-added rows
  /// and bound drafts still hard-delete. An unplanned slot keeps the old
  /// hard cascade.
  Future<void> removeExerciseSlot(int index) async {
    if (index < 0 || index >= exerciseSlots.length) return;
    // Captures for the inverse (before anything moves).
    final slot = exerciseSlots[index];
    final activeBefore = activeSlotIndex;
    final draftIdsBefore = <String, List<int>>{
      for (final e in slot.exerciseIds)
        if (draftSlotsByExercise[e] != null)
          e: List.of(draftSlotsByExercise[e]!),
    };
    final seBefore = <String, SessionExercise?>{
      for (final e in slot.exerciseIds)
        e: sessionExercises.firstWhereOrNull((x) => x.exerciseId == e),
    };
    // User-added rows inside an UNPLANNED slot die hard — captured to
    // re-insert. Inside a planned slot nothing dies: every row flags, the
    // user's own additions included, so the exercise's Restore brings back
    // everything underneath it (2026-10-14).
    final userRowsBefore = <SessionExerciseSet>[
      for (final e in slot.exerciseIds)
        for (final s in sets)
          if (s.exerciseId == e && s.plannedSetId == null) s,
    ];
    final boxes = <SessionExerciseSet, UndoBox<String>>{
      for (final r in userRowsBefore) r: UndoBox<String>(),
    };

    Future<void> forward() async {
      final currentIndex = exerciseSlots.indexWhere((sl) => sl.id == slot.id);
      if (currentIndex == -1) return;
      final currentSlot = exerciseSlots.removeAt(currentIndex);

      for (final exerciseId in currentSlot.exerciseIds) {
        final sessionExercise = sessionExercises.firstWhereOrNull(
          (e) => e.exerciseId == exerciseId,
        );
        if (sessionExercise != null && currentSlot.planned) {
          for (final s in List.of(sets)) {
            if (s.sessionExerciseId != sessionExercise.sessionExerciseId) {
              continue;
            }
            await _sessionRepo.updateSet(
              s.sessionExerciseSetId,
              isDeleted: true,
            );
          }
          sets.removeWhere(
            (s) => s.sessionExerciseId == sessionExercise.sessionExerciseId,
          );
          draftSlotsByExercise.remove(exerciseId);
          _deletedPlannedOrder.add(sessionExercise.sessionExerciseId);
          // The tab it just vacated — where a restore puts it back.
          _deletedPlannedSlotIndex[sessionExercise.sessionExerciseId] =
              currentIndex;
          continue;
        }
        if (sessionExercise != null) {
          await _sessionRepo.deleteSessionExercise(
            sessionExercise.sessionExerciseId,
          );
          sessionExercises.remove(sessionExercise);
        }
        sets.removeWhere((s) => s.exerciseId == exerciseId);
        draftSlotsByExercise.remove(exerciseId);
      }

      if (activeSlotIndex >= exerciseSlots.length) {
        activeSlotIndex = (exerciseSlots.length - 1).clamp(
          0,
          exerciseSlots.length,
        );
      }
      _persistExerciseOrder();
      _recomputePRs();
      notifyListeners();
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          // DB first: un-flag what the forward flagged; re-insert what it
          // hard-deleted (the unplanned slot's rows — a planned slot keeps
          // every row, so there the inverse is the cheap un-flag alone).
          for (final exerciseId in slot.exerciseIds) {
            final se = seBefore[exerciseId];
            if (se == null) continue;
            final flagged = deletedSets
                .where((s) => s.sessionExerciseId == se.sessionExerciseId)
                .toList();
            for (final f in flagged) {
              await _sessionRepo.updateSet(
                f.sessionExerciseSetId,
                clearIsDeleted: true,
              );
            }
            if (slot.planned) continue;
            final insertedSe = await _sessionRepo.insertSessionExercise(
              sessionId: se.sessionId,
              userId: se.userId,
              exerciseId: se.exerciseId,
              exerciseOrder: se.exerciseOrder,
            );
            for (final r in userRowsBefore) {
              if (r.exerciseId != exerciseId) continue;
              final inserted = await _sessionRepo.insertSet(
                sessionExerciseId: insertedSe.sessionExerciseId,
                sessionId: r.sessionId,
                userId: r.userId,
                variationId: r.variationId,
                setNumber: r.setNumber,
                weight: r.weight,
                reps: r.reps,
                notes: r.notes,
                plannedSetId: r.plannedSetId,
              );
              boxes[r]!.value = inserted.sessionExerciseSetId;
            }
          }
          // Memory restore — the slot back in its old place, and (a planned
          // slot) out of the trash lists: it is not deleted any more.
          exerciseSlots.insert(index.clamp(0, exerciseSlots.length), slot);
          if (slot.planned) {
            for (final e in slot.exerciseIds) {
              final se = seBefore[e];
              if (se == null) continue;
              _deletedPlannedOrder.remove(se.sessionExerciseId);
              _deletedPlannedSlotIndex.remove(se.sessionExerciseId);
            }
          }
          for (final e in draftIdsBefore.entries) {
            draftSlotsByExercise[e.key] = List.of(e.value);
          }
          activeSlotIndex = activeBefore;
          await _loadSets();
          _persistExerciseOrder();
          notifyListeners();
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

  /// The session-exercise row for [exerciseId], creating it (with the next
  /// exercise_order) when the exercise doesn't have one yet.
  Future<SessionExercise?> _ensureSessionExercise(String exerciseId) async {
    final existing = sessionExercises.firstWhereOrNull(
      (e) => e.exerciseId == exerciseId,
    );
    if (existing != null) return existing;
    final id = currentWorkoutId;
    if (id == null) return null;
    final nextOrder = sessionExercises.isEmpty
        ? 1
        : sessionExercises
                  .map((e) => e.exerciseOrder)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    try {
      final row = await _sessionRepo.insertSessionExercise(
        sessionId: id,
        userId: _userId,
        exerciseId: exerciseId,
        exerciseOrder: nextOrder,
      );
      sessionExercises.add(row);
      return row;
    } catch (_) {
      return null;
    }
  }

  // ── Draft set rows ─────────────────────────────────────────────────────────

  /// The next set_number for [exerciseId]'s group (per-exercise numbering —
  /// matches the template's materialized rows).
  int _nextSetNumberFor(String exerciseId) {
    final exerciseSets = sets.where((s) => s.exerciseId == exerciseId);
    if (exerciseSets.isEmpty) return 1;
    return exerciseSets
            .map((s) => s.setNumber)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }

  /// Tapping "+ ADD SET" pre-creates an empty set in the DB so it survives
  /// hot restarts. An empty set is a valid row — user-added rows persist even
  /// if never filled. Reloads after the insert so the row hydrates its
  /// exerciseId (insertSet returns a bare row) — without the reload the row
  /// stays invisible to the grid AND to set numbering, so each tap would
  /// insert another row with the same number.
  Future<void> addDraftSet(String exerciseId) async {
    if (currentWorkoutId == null) return;
    final box = UndoBox<String>();
    Future<void> forward() async {
      if (currentWorkoutId == null) return;
      if (_addSetInFlight) {
        // A previous tap is mid-insert; its number was computed before this
        // tap's row existed, so replay after it lands (last tap wins).
        _addSetQueuedExercise = exerciseId;
        return;
      }
      _addSetInFlight = true;
      try {
        final sessionExercise = await _ensureSessionExercise(exerciseId);
        if (sessionExercise == null) return;
        final nextNum = _nextSetNumberFor(exerciseId);
        final inserted = await _sessionRepo.insertSet(
          sessionExerciseId: sessionExercise.sessionExerciseId,
          sessionId: currentWorkoutId!,
          userId: _userId,
          setNumber: nextNum,
          weight: null,
          reps: const [],
        );
        box.value = inserted.sessionExerciseSetId;
        await _loadSets();
      } catch (e) {
        error = e.toString();
        notifyListeners();
      } finally {
        _addSetInFlight = false;
      }
      final queued = _addSetQueuedExercise;
      if (queued != null) {
        _addSetQueuedExercise = null;
        await addDraftSet(queued);
      }
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final id = box.value;
          if (id == null) return;
          await _sessionRepo.deleteSet(id);
          sets.removeWhere((s) => s.sessionExerciseSetId == id);
          _recomputePRs();
          notifyListeners();
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

  /// Seeds a virtual draft slot for [exerciseId] — nothing is persisted
  /// until the first commit (lazy binding in commitDraftSet), so restoring
  /// a workout never writes phantom empty rows to the DB.
  void _seedDraft(String exerciseId) {
    final draftId = _nextDraftId++;
    draftSlotsByExercise.putIfAbsent(exerciseId, () => []).add(draftId);
  }

  void removeDraftSet(String exerciseId, int draftId) {
    final boundRow = sets
        .where((x) => _draftRowIds[draftId] == x.sessionExerciseSetId)
        .firstOrNull;
    final box = UndoBox<String>();

    Future<void> forward() async {
      draftSlotsByExercise[exerciseId]?.remove(draftId);
      final rowId = _draftRowIds.remove(draftId);
      if (rowId != null) {
        await _sessionRepo.deleteSet(rowId);
        sets.removeWhere((s) => s.sessionExerciseSetId == rowId);
      }
      _recomputePRs();
      notifyListeners();
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          if (boundRow != null) {
            final inserted = await _sessionRepo.insertSet(
              sessionExerciseId: boundRow.sessionExerciseId,
              sessionId: boundRow.sessionId,
              userId: boundRow.userId,
              variationId: boundRow.variationId,
              setNumber: boundRow.setNumber,
              weight: boundRow.weight,
              reps: boundRow.reps,
              notes: boundRow.notes,
              plannedSetId: boundRow.plannedSetId,
            );
            box.value = inserted.sessionExerciseSetId;
            _draftRowIds[draftId] = inserted.sessionExerciseSetId;
          }
          draftSlotsByExercise.putIfAbsent(exerciseId, () => []).add(draftId);
          await _loadSets();
          _recomputePRs();
          notifyListeners();
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

  /// Commits a draft row. Drafts start virtual — the first commit lazily
  /// binds the draft to a freshly inserted row and keeps the slot (the row
  /// keeps its draft editor; removing it would remount the row and drop the
  /// field's focus). Later commits update that bound row.
  ///
  /// Concurrent commits are serialized per draft: blur and lifecycle flushes
  /// (inactive → paused → detached all fire on the way to the background)
  /// can overlap the draft's first insert. Only the first-ever commit may
  /// INSERT — any call that overlaps it waits for the binding and then
  /// updates that same row. Without this, each overlapping call sees no
  /// bound row and inserts its own copy (one typed set → three rows).
  Future<bool> commitDraftSet(
    String exerciseId,
    int draftId, {
    String? variationId,
    double? weight,
    List<num>? reps,
    String? notes,
  }) async {
    if (currentWorkoutId == null) return false;
    final inFlight = _draftCommitsInFlight[draftId];
    if (inFlight != null) {
      await inFlight;
      final boundId = _draftRowIds[draftId];
      if (boundId == null) return false; // the in-flight commit rejected it
      // The in-flight commit bound the row — apply this call's values as an
      // update so a superseding edit is never dropped.
      try {
        await _sessionRepo.updateSet(
          boundId,
          variationId: variationId,
          clearVariation: variationId == null,
          weight: weight,
          clearWeight: weight == null,
          reps: reps ?? const [],
          notes: notes,
          clearNotes: notes == null || notes.isEmpty,
        );
        await _loadSets();
        return true;
      } catch (e) {
        error = e.toString();
        notifyListeners();
        return false;
      }
    }
    final future = _commitDraftSet(
      exerciseId,
      draftId,
      variationId: variationId,
      weight: weight,
      reps: reps,
      notes: notes,
    );
    _draftCommitsInFlight[draftId] = future;
    try {
      return await future;
    } finally {
      if (identical(_draftCommitsInFlight[draftId], future)) {
        _draftCommitsInFlight.remove(draftId);
      }
    }
  }

  Future<bool> _commitDraftSet(
    String exerciseId,
    int draftId, {
    String? variationId,
    double? weight,
    List<num>? reps,
    String? notes,
  }) async {
    // Reps are not mandatory — a draft materializes with weight or a
    // variation alone.
    final repsList = reps ?? const [];
    final boundId = _draftRowIds[draftId];
    try {
      if (boundId != null) {
        await _sessionRepo.updateSet(
          boundId,
          variationId: variationId,
          clearVariation: variationId == null,
          weight: weight,
          clearWeight: weight == null,
          reps: repsList,
          notes: notes,
          clearNotes: notes == null || notes.isEmpty,
        );
      } else {
        final sessionExercise = await _ensureSessionExercise(exerciseId);
        if (sessionExercise == null) return false;
        final inserted = await _sessionRepo.insertSet(
          sessionExerciseId: sessionExercise.sessionExerciseId,
          sessionId: currentWorkoutId!,
          userId: _userId,
          variationId: variationId,
          setNumber: _nextSetNumberFor(exerciseId),
          weight: weight,
          reps: repsList,
          notes: notes,
        );
        // Lazily bind the draft to its own row and keep the slot. Recorded
        // before _loadSets so the reload's rebuild never sees the row
        // unbound (isDraftBoundRow keeps it from double-rendering under the
        // draft editor).
        _draftRowIds[draftId] = inserted.sessionExerciseSetId;
      }
      await _loadSets();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Merges one set-edit call into that set's pending write. The debounced
  /// path ([immediate] false — keystrokes) arms a [kAutoCommitDebounce]
  /// timer and returns without touching the DB or notifying; the timer (or
  /// an [immediate] caller) flushes the merged values as one write. The
  /// authoritative read after a live flush comes from the watch stream —
  /// nothing is patched by hand.
  Future<void> _queueSetWrite(
    String setId, {
    required bool historical,
    required bool immediate,
    double? weight,
    bool clearWeight = false,
    List<num>? reps,
    bool clearReps = false,
    String? variationId,
    bool clearVariation = false,
    String? notes,
    bool clearNotes = false,
  }) {
    final pending = _pendingSetWrites.putIfAbsent(setId, _PendingSetWrite.new);
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
    pending.historical |= historical;
    _setDebounceTimers.remove(setId)?.cancel();
    if (immediate) return _flushSetWrite(setId);
    _setDebounceTimers[setId] = Timer(kAutoCommitDebounce, () {
      _setDebounceTimers.remove(setId);
      unawaited(_flushSetWrite(setId));
    });
    return Future.value();
  }

  /// Writes the merged pending values for [setId] — one UPDATE for however
  /// many keystrokes fed it — chained per set so overlapping settles land in
  /// order. A failed write leaves the DB unchanged and the watch stream
  /// still delivering the authoritative rows, so no rollback is needed: the
  /// error surface says what happened.
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

  Future<void> _writePendingSet(String setId, _PendingSetWrite p) async {
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
      if (p.historical) {
        // A completed session's row lives in the timeline — reload it so the
        // history viewer and PR baseline read the edit.
        await _loadPastSets();
      }
      // Live rows: no reload, no patch — the session watch stream re-emits
      // the authoritative rows and recomputes.
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateSetField(
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
    if (currentWorkoutId == null) return Future.value();
    return _queueSetWrite(
      set.sessionExerciseSetId,
      historical: false,
      immediate: immediate,
      weight: weight,
      clearWeight: clearWeight,
      reps: reps,
      clearReps: clearReps,
      variationId: variationId,
      clearVariation: clearVariation,
      notes: notes,
      clearNotes: clearNotes,
    );
  }

  /// Edits a set from a *completed* workout — the history viewer's editable
  /// grid. Reuses the same `updateSet` write as the live session (it isn't
  /// gated by workout status), but reloads past-sets/PR-baseline state
  /// instead of the live `sets` list, since the edited row lives there.
  /// Keystrokes debounce exactly like live rows; discrete edits (variation
  /// pick, notes save) pass `immediate: true`.
  Future<void> updateHistoricalSetField(
    PastSetRow set, {
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
    if (currentWorkoutId == null) return Future.value();
    return _queueSetWrite(
      set.sessionExerciseSetId,
      historical: true,
      immediate: immediate,
      weight: weight,
      clearWeight: clearWeight,
      reps: reps,
      clearReps: clearReps,
      variationId: variationId,
      clearVariation: clearVariation,
      notes: notes,
      clearNotes: clearNotes,
    );
  }

  /// Deletes a set row: a row under a PLAN-LINKED exercise is flagged
  /// (`is_deleted`) instead of removed (2026-10-13, widened 2026-10-14) —
  /// the deleted sets stay visible in red, the exercise stays restorable,
  /// and when this was its last active row its tab folds into the trash.
  ///
  /// The flag covers the user's OWN additions too (a set added to a planned
  /// exercise), so the exercise's Restore brings back everything underneath
  /// it, not just the plan's rows. A row of a user-added exercise still
  /// hard-deletes — the undo stack is its way back, and there is no plan to
  /// restore against. Undoable either way.
  Future<void> deleteSetById(String setId) async {
    final row = sets.where((s) => s.sessionExerciseSetId == setId).firstOrNull;
    if (row == null) return;
    final se = sessionExercises.firstWhereOrNull(
      (e) => e.sessionExerciseId == row.sessionExerciseId,
    );
    final flagRow = row.plannedSetId != null || se?.plannedExerciseId != null;
    // Captures for the inverse.
    final capturedRow = row;
    final foldedSlotIndex = flagRow
        ? exerciseSlots.indexWhere(
            (sl) => sl.exerciseIds.contains(row.exerciseId),
          )
        : -1;
    final foldedSlot = foldedSlotIndex == -1
        ? null
        : exerciseSlots[foldedSlotIndex];
    final activeBefore = activeSlotIndex;
    final rowIdBox = UndoBox<String>()..value = setId;

    Future<void> forward() async {
      final current = sets
          .where((s) => s.sessionExerciseSetId == rowIdBox.value)
          .firstOrNull;
      if (current == null) return;
      if (flagRow) {
        await _sessionRepo.updateSet(
          current.sessionExerciseSetId,
          isDeleted: true,
        );
        // Last active row of a planned exercise? Fold the tab — the minus
        // entry takes its place in the selector.
        final remaining = sets.where(
          (s) =>
              s.sessionExerciseId == current.sessionExerciseId &&
              s.sessionExerciseSetId != current.sessionExerciseSetId,
        );
        if (remaining.isEmpty) {
          final se = sessionExercises.firstWhereOrNull(
            (e) => e.sessionExerciseId == current.sessionExerciseId,
          );
          if (se != null && se.plannedExerciseId != null) {
            final slotIndex = exerciseSlots.indexWhere(
              (sl) => sl.exerciseIds.contains(se.exerciseId),
            );
            if (slotIndex != -1) {
              exerciseSlots.removeAt(slotIndex);
              // The tab it vacated — where a restore puts it back.
              _deletedPlannedSlotIndex[se.sessionExerciseId] = slotIndex;
              if (activeSlotIndex >= exerciseSlots.length) {
                activeSlotIndex = (exerciseSlots.length - 1).clamp(
                  0,
                  exerciseSlots.length,
                );
              }
            }
            _deletedPlannedOrder.add(se.sessionExerciseId);
          }
        }
        // No reload — the watch stream re-emits and the partition moves the
        // flagged row into deletedSets.
        notifyListeners();
        return;
      }
      await _sessionRepo.deleteSet(current.sessionExerciseSetId);
      await _loadSets();
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          if (flagRow) {
            await _sessionRepo.updateSet(setId, clearIsDeleted: true);
            // Back on the bar — out of the trash lists (the redo's fold
            // re-records the position it folds from).
            _deletedPlannedOrder.remove(capturedRow.sessionExerciseId);
            _deletedPlannedSlotIndex.remove(capturedRow.sessionExerciseId);
            if (foldedSlot != null) {
              exerciseSlots.insert(foldedSlotIndex, foldedSlot);
              activeSlotIndex = activeBefore;
            }
            notifyListeners();
            return;
          }
          final inserted = await _sessionRepo.insertSet(
            sessionExerciseId: capturedRow.sessionExerciseId,
            sessionId: capturedRow.sessionId,
            userId: capturedRow.userId,
            variationId: capturedRow.variationId,
            setNumber: capturedRow.setNumber,
            weight: capturedRow.weight,
            reps: capturedRow.reps,
            notes: capturedRow.notes,
            plannedSetId: capturedRow.plannedSetId,
          );
          rowIdBox.value = inserted.sessionExerciseSetId;
          await _loadSets();
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

  /// Inserts a new set copying [set]'s weight/reps/variation/notes — the
  /// grid row's swipe-action "Duplicate" button. The row passes the text on
  /// screen as [weight]/[reps] overrides: the copy must carry what the user
  /// just typed, which a debounced write may not have settled into [set]
  /// yet (2026-10-13).
  Future<void> duplicateSet(
    SessionExerciseSet set, {
    double? weight,
    List<num>? reps,
  }) async {
    if (currentWorkoutId == null) return;
    final exerciseId = set.exerciseId;
    if (exerciseId == null) return;
    final box = UndoBox<String>();

    Future<void> forward() async {
      if (currentWorkoutId == null) return;
      final exerciseId = set.exerciseId;
      if (exerciseId == null) return;
      try {
        final inserted = await _sessionRepo.insertSet(
          sessionExerciseId: set.sessionExerciseId,
          sessionId: currentWorkoutId!,
          userId: _userId,
          variationId: set.variationId,
          setNumber: _nextSetNumberFor(exerciseId),
          weight: weight ?? set.weight,
          reps: reps ?? set.reps,
          notes: set.notes,
        );
        box.value = inserted.sessionExerciseSetId;
        await _loadSets();
      } catch (e) {
        error = e.toString();
        notifyListeners();
      }
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final id = box.value;
          if (id == null) return;
          await _sessionRepo.deleteSet(id);
          await _loadSets();
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

  // ── Lessons (persisted — per-exercise, cross-session) ─────────────────────

  List<Lesson> lessonsFor(String exerciseId) =>
      lessonsByExercise[exerciseId] ?? const [];

  /// Lessons created during the CURRENT session only — the session-scoped
  /// counts (stats bar, exercise-card button, reflection). [lessonsFor]
  /// remains the full cross-session list for the lessons modal and the
  /// pinned lesson bar, so past lessons stay visible without inflating
  /// this session's numbers.
  List<Lesson> lessonsThisSession(String exerciseId) =>
      (lessonsByExercise[exerciseId] ?? const <Lesson>[])
          .where((l) => l.sessionId == currentWorkoutId)
          .toList();

  /// Loads (or refreshes) the persisted lessons for one exercise — called
  /// whenever an exercise slot is created so the card's lesson preview/count
  /// is populated without requiring the Lessons modal to be opened first.
  Future<void> loadLessonsFor(String exerciseId) async {
    try {
      lessonsByExercise[exerciseId] = await _lessonRepo.fetchLessons(
        _userId,
        exerciseId,
      );
      _lessonLog.info(
        'loadLessonsFor($exerciseId) → ${lessonsByExercise[exerciseId]!.length}',
      );
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> addLesson(String exerciseId, String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _lessonRepo.createLesson(
        _userId,
        exerciseId,
        text.trim(),
        sessionId: currentWorkoutId,
      );
      await loadLessonsFor(exerciseId);
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> toggleLessonPin(String exerciseId, String lessonId) async {
    final lesson = lessonsByExercise[exerciseId]?.firstWhereOrNull(
      (l) => l.lessonId == lessonId,
    );
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
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteLesson(String exerciseId, String lessonId) async {
    try {
      await _lessonRepo.deleteLesson(lessonId);
      await loadLessonsFor(exerciseId);
    } catch (e) {
      error = e.toString();
      notifyListeners();
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
      error = e.toString();
      notifyListeners();
    }
  }

  // ── History / PR badges ────────────────────────────────────────────────────

  List<ExerciseHistorySession> historyFor(String exerciseId) =>
      historyByExercise[exerciseId] ?? const [];

  // ── The date bar's two stacks (2026-10-23) ────────────────────────────────

  /// The active exercise's past performances, newest first — the stack
  /// EXERCISE mode walks. Empty while the history read is in flight (and
  /// forever for an exercise never performed before).
  List<ExerciseHistorySession> get activeExerciseHistory {
    final slot = activeSlot;
    return slot == null ? const [] : historyFor(slot.activeExerciseId);
  }

  /// EXERCISE mode's effective position: [exerciseHistoryIndex] only while
  /// the exercise it was stepped on still owns the card and the stack still
  /// holds that far; home (0) otherwise, so a walk can never point at
  /// another exercise's or an edited-away performance.
  int get _exerciseHistoryPosition {
    if (dateBarMode != SessionDateMode.exercise) return 0;
    final slot = activeSlot;
    if (slot == null || slot.activeExerciseId != _exerciseHistoryForId) {
      return 0;
    }
    return exerciseHistoryIndex.clamp(0, activeExerciseHistory.length);
  }

  /// The performance the card is drawing in EXERCISE mode; null at home,
  /// where today's live sets are the card — and in SESSION mode, where the
  /// whole page walks instead.
  ExerciseHistorySession? get viewedExerciseHistory {
    final position = _exerciseHistoryPosition;
    if (position <= 0) return null;
    final stack = activeExerciseHistory;
    final index = position - 1;
    return index < stack.length ? stack[index] : null;
  }

  /// The exercise stack's ends, walked from home (0) toward older.
  bool get canStepExerciseOlder =>
      dateBarMode == SessionDateMode.exercise &&
      _exerciseHistoryPosition < activeExerciseHistory.length;

  bool get canStepExerciseNewer =>
      dateBarMode == SessionDateMode.exercise && _exerciseHistoryPosition > 0;

  /// Switches the date bar's stacks. A mode change returns home — the live
  /// sets — so each mode always starts from the page being read.
  void toggleDateBarMode() {
    dateBarMode = dateBarMode == SessionDateMode.exercise
        ? SessionDateMode.session
        : SessionDateMode.exercise;
    exerciseHistoryIndex = 0;
    notifyListeners();
  }

  /// Steps EXERCISE mode: +1 older, -1 newer. Home is today's live sets,
  /// and both ends hold. The live grid is about to swap under a focused
  /// cell, so pending keystrokes settle first — the same rule a tab switch
  /// follows — and a fresh performance re-earns the history edit gate.
  Future<void> stepExerciseHistory(int delta) async {
    if (dateBarMode != SessionDateMode.exercise) return;
    final slot = activeSlot;
    if (slot == null) return;
    final position = _exerciseHistoryPosition;
    final next = position + delta;
    if (next < 0 || next > activeExerciseHistory.length) return;
    if (next == position) return;
    await flushPendingCommits();
    if (dateBarMode != SessionDateMode.exercise) return;
    historyEditConfirmed = false;
    exerciseHistoryIndex = next;
    _exerciseHistoryForId = slot.activeExerciseId;
    notifyListeners();
  }

  // ── Pending-edit flush ─────────────────────────────────────────────────────
  /// Rows register their commit closure so the screen can flush in-flight
  /// edits on lifecycle pause / tab switch / session end — commit is
  /// otherwise blur-only, which loses typed values on a hard app kill.
  final List<Future<void> Function()> _commitHandles = [];

  void registerCommitHandle(Future<void> Function() handle) =>
      _commitHandles.add(handle);

  void unregisterCommitHandle(Future<void> Function() handle) =>
      _commitHandles.remove(handle);

  Future<void> flushPendingCommits() async {
    for (final handle in List.of(_commitHandles)) {
      try {
        await handle();
      } catch (_) {}
    }
    // Belt-and-braces: any queued debounced write with no live row handle
    // left (a timer that fired between row disposal and this flush) still
    // lands before the caller prunes, snapshots, or navigates.
    for (final id in List.of(_pendingSetWrites.keys)) {
      _setDebounceTimers.remove(id)?.cancel();
      try {
        await _flushSetWrite(id);
      } catch (_) {}
    }
  }

  // ── Start / end / cancel workout ──────────────────────────────────────────

  Future<void> startWorkout() async {
    // Re-entry guard — a second tap while the first start is mid-flight
    // would create a second active session (and a second materialization of
    // the plan).
    if (startLoading) return;
    startLoading = true;
    error = null;
    notifyListeners();
    try {
      final seed = pastSessionSeed;
      final template = selectedStandaloneWorkout ?? selectedPlannedSession;
      final id = await _sessionRepo.createSession(
        _userId,
        preNotes: startNotes.trim().isEmpty ? null : startNotes.trim(),
        // A repeat writes no run (2026-10-26): it is not the program's next
        // session, and finishing it must never advance the run's cursor.
        programRunId: seed != null || selectedStandaloneWorkout != null
            ? null
            : programProgress?.run.programRunId,
        // A seeded session follows the record's own plan, not whatever the
        // picker has chosen: the record is the input.
        plannedSessionId: seed != null
            ? seed.plannedSessionId
            : template?.sessionId,
        plannedSessionName: seed != null ? seed.planName : template?.name,
        preFeeling: sessionFeeling,
        // Stamped so this device can always tell its own session from
        // another device's (2026-10-15).
        deviceId: await _resolveDeviceId(),
      );
      currentWorkoutId = id;
      workoutStartedAt = DateTime.now();
      sets = [];
      sessionExercises = [];
      sessionJustCompleted = false;
      lastEndedSessionId = null;
      lastCompletedStats = null;
      // Start lives ON the training page now — no slide; the pre-questionnaire
      // answers were captured into createSession above and are cleared when
      // the post-questionnaire completes.
      if (seed != null) {
        // The record is the source of truth once Start is pressed: it has
        // been read, resolved and previewed, and a live session never needs
        // it again.
        await _materializeSeededSets(seed);
        pastSessionSeed = null;
      } else {
        await _materializePlannedSets();
      }
      // Reload so rows hydrate their exerciseId from the parent exercise row
      // (insertSet returns bare rows) — _seedExerciseSlots' draft logic keys
      // on it, and without the reload it would seed phantom drafts on top of
      // the freshly materialized planned rows.
      await _loadSets();
      _seedExerciseSlots();
      // Live updates from here on — the streams re-emit after every write.
      _subscribeToSessionStreams();
      // The floor's left arrow: the newest record this session walked over
      // (2026-10-22).
      unawaited(_loadPreviousSession());
    } catch (e) {
      error = e.toString();
    }
    startLoading = false;
    notifyListeners();
  }

  /// The plan becomes real rows at session start: one fact_session_exercise
  /// per planned exercise (linked via planned_exercise_id), then one fact set
  /// row per planned target linked to its template row via planned_set_id.
  ///
  /// A **single-number weight** target is recorded as the row's real weight
  /// (2026-10-23) — "record weight at start if it is a real value". A weight
  /// range never is: ranges stay guides. **Reps are never adopted**, even a
  /// single number ("5 reps"), so they always start as the blue hint. The
  /// target text itself still lives on the dim row, never copied as text.
  /// Freestyle sessions materialize nothing.
  Future<void> _materializePlannedSets() async {
    final id = currentWorkoutId;
    if (id == null || plannedExerciseOrder.isEmpty) return;
    final materialized = <SessionExerciseSet>[];
    var exerciseOrder = 1;
    for (final exerciseId in plannedExerciseOrder) {
      final plannedSets = [...?plannedSetsByExercise[exerciseId]]
        ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
      // Skip keep-alive stubs — a planned row with no target data
      // anywhere (weight, reps, notes, variation) contributes nothing to
      // the session.
      final usable = plannedSets.where(
        (p) =>
            p.targetWeight != null ||
            p.targetReps != null ||
            (p.targetNotes?.isNotEmpty ?? false) ||
            p.variationId != null,
      );
      if (usable.isEmpty) continue;
      final plannedExerciseId = usable.first.plannedExerciseId;
      final sessionExercise = await _sessionRepo.insertSessionExercise(
        sessionId: id,
        userId: _userId,
        exerciseId: exerciseId,
        exerciseOrder: exerciseOrder++,
        plannedExerciseId: plannedExerciseId,
      );
      sessionExercises.add(sessionExercise);
      var setNumber = 1;
      for (final p in usable) {
        materialized.add(
          await _sessionRepo.insertSet(
            sessionExerciseId: sessionExercise.sessionExerciseId,
            sessionId: id,
            userId: _userId,
            setNumber: setNumber++,
            weight: plannedWeightValue(p.targetWeight),
            reps: const [],
            plannedSetId: p.plannedSetId,
          ),
        );
      }
    }
    sets = materialized;
  }

  /// Start's other materialization (2026-10-26): a session seeded from a past
  /// record copies the record instead of the plan's targets — the same
  /// arrangement, each set's numeric kg as the real weight, the variation and
  /// the planned links, with **reps never copied** (a rep count is today's
  /// performance; the target's blue guide is what the empty cell shows).
  ///
  /// The rows go through the same three writes [startWorkout] uses for a plan
  /// ([SessionRepository.insertSessionExercise], then
  /// [SessionRepository.insertSet] per set) — a repeat is a normal session
  /// from here on, and nothing about it is a new kind of row. No
  /// `dim_planned_session` row is created: the linked plan is the one that
  /// already exists.
  Future<void> _materializeSeededSets(PastSessionSeed seed) async {
    final id = currentWorkoutId;
    if (id == null) return;
    final materialized = <SessionExerciseSet>[];
    var exerciseOrder = 1;
    // The preview and this write ask the same question, so what the user saw
    // before Start is what lands here.
    for (final group in seed.exercisesToCopy(plannedSetById)) {
      final sessionExercise = await _sessionRepo.insertSessionExercise(
        sessionId: id,
        userId: _userId,
        exerciseId: group.exerciseId,
        exerciseOrder: exerciseOrder++,
        plannedExerciseId: group.plannedExerciseId,
      );
      sessionExercises.add(sessionExercise);
      var setNumber = 1;
      for (final row in group.sets) {
        materialized.add(
          await _sessionRepo.insertSet(
            sessionExerciseId: sessionExercise.sessionExerciseId,
            sessionId: id,
            userId: _userId,
            setNumber: setNumber++,
            weight: row.weight,
            // Never real: the record's reps were that performance's, and
            // nothing was performed today yet.
            reps: const [],
            variationId: row.variationId,
            plannedSetId: row.plannedSetId,
          ),
        );
      }
    }
    sets = materialized;
  }

  /// Ends the active session (Summary page's Finish Session): flushes,
  /// prunes untouched planned rows, stamps `end_datetime`, and slides to
  /// the post-questionnaire page. Both questionnaires' answers land
  /// separately in [completePostQuestionnaire] — nothing here writes them.
  Future<void> finishSession() async {
    if (currentWorkoutId == null) return;
    endLoading = true;
    notifyListeners();
    try {
      // Flush any in-flight row edits (typed but not yet blurred) so nothing
      // is pruned or finalized before the last keystroke lands.
      await flushPendingCommits();
      // One authoritative pull before pruning: the prune reads `sets` in
      // memory, and the watch stream's next emission may not have landed
      // yet — a freshly typed value must never look like an untouched row.
      await _pullCurrentSession();
      await _pruneUntouchedPlannedRows();
      // Capture BEFORE the reset wipes sets/sessionPrEvents/currentWorkoutId —
      // the post-questionnaire write target and the home congrats stats.
      lastEndedSessionId = currentWorkoutId;
      lastCompletedStats = _snapshotSessionStats();
      await _sessionRepo.endSession(currentWorkoutId!);
      // The ratings pencil on the training page can collect post answers
      // mid-session (2026-10-22); carry them across the reset so the post
      // page opens showing the same values instead of blank ones. Done
      // clears them along with the pre half.
      final carriedEndFeeling = endFeeling;
      final carriedEndNotes = endNotes;
      _resetActiveWorkoutState();
      endFeeling = carriedEndFeeling;
      endNotes = carriedEndNotes;
      // Reload the timeline — the ended session joins the completed-session
      // pager the post-questionnaire page shows.
      await _loadPastSets();
      // The post-questionnaire page's comparison reference — the completed
      // session BEFORE the just-ended one (ids are newest-first; the ended
      // session sits at index 0).
      previousCompletedSession = null;
      if (_reflectionSessionIds.length >= 2) {
        try {
          previousCompletedSession = await _sessionRepo.fetchSession(
            _reflectionSessionIds[1],
          );
        } catch (_) {}
      }
      slidePagesController.slideToPage(kPostQuestionnairePage);
      // Re-read progress now that the session is behind us. Deliberately AFTER
      // `_resetActiveWorkoutState`: `refreshProgram` early-returns while a
      // workout is active, so before the reset this would be a no-op and the
      // idle screen would keep offering the session just completed — and, on a
      // block's last session, would not know the block was finished.
      //
      // After the slide rather than before it: the user has somewhere to be,
      // and this is bookkeeping for the page they are heading to.
      await refreshProgram();
    } catch (e) {
      error = e.toString();
    }
    endLoading = false;
    notifyListeners();
  }

  /// The block this run is following, once its length has run out — the
  /// condition that puts the "you've completed this training block" prompt on
  /// the idle training page. Null while a workout is open (nothing to announce
  /// mid-session), on a blockless run, and before the length is reached.
  ///
  /// Derived rather than flagged: the same read that refreshes the header's
  /// week line answers this, so there is no second piece of state to keep in
  /// step with it — and a prompt that is a state rather than an event also
  /// survives the user walking away without answering.
  ProgramBlock? get finishedBlock {
    if (currentWorkoutId != null) return null;
    final p = programProgress;
    // `isReadyToEnd` is the shared spelling of "done its length, still open";
    // what this site adds is the block to name, and the quiet while a workout
    // is open above.
    if (p == null || !p.isBlockRun || !p.isReadyToEnd) return null;
    return p.block;
  }

  /// The post-questionnaire page's Done: writes BOTH bookends to the ended
  /// session in one write — the post answers entered here and the pre
  /// answers restored or edited through the ratings pencil — then clears
  /// both questionnaires (the next session's pre-Q must start blank — the
  /// old flow leaked the previous answers), and lands Home with the congrats
  /// banner. [onWorkoutEnded] fires LAST — its consumer disposes the cached
  /// VM, so nothing may notify after it.
  Future<void> completePostQuestionnaire() async {
    final id = lastEndedSessionId;
    if (id == null) return;
    endLoading = true;
    notifyListeners();
    try {
      await _sessionRepo.updateSessionNotes(
        id,
        preNotes: startNotes.trim().isEmpty ? null : startNotes.trim(),
        postNotes: endNotes.trim().isEmpty ? null : endNotes.trim(),
        preFeeling: sessionFeeling,
        postFeeling: endFeeling,
      );
      sessionFeeling = null;
      startNotes = '';
      endFeeling = null;
      endNotes = '';
      lastEndedSessionId = null;
      sessionJustCompleted = true;
      // Re-fetch the ended session row so the home card's bookends show the
      // fresh post answers (the set timeline is unchanged — no reload needed).
      await showLatestReflection();
      slidePagesController.slideToPage(kSessionHomePage);
    } catch (e) {
      error = e.toString();
    }
    endLoading = false;
    notifyListeners();
    onWorkoutEnded?.call();
  }

  /// The just-finished session's numbers for the home congrats banner.
  ({int sets, int exercises, int prs}) _snapshotSessionStats() => (
    sets: sets.length,
    exercises: distinctExerciseCount,
    prs: sessionPrEvents.length,
  );

  Future<void> cancelSession() async {
    if (currentWorkoutId == null) return;
    final id = currentWorkoutId!;
    _resetActiveWorkoutState();
    lastEndedSessionId = null;
    // Deliberately NO slide and NO onWorkoutEnded: canceling returns the
    // user to the Training page's idle state (picker unlocked, Start back)
    // with the cached VM — and all questionnaire state — intact.
    notifyListeners();
    await _sessionRepo.cancelSession(id);
    // Reload the timeline — the cancelled session must leave the past-sets
    // timeline and the viewer card's pager (finishSession reloads too).
    await _loadPastSets();
  }

  /// Planned rows the user never performed are plan hints, not facts —
  /// remove them at session end so the log shows what actually happened.
  /// User-added rows (no planned link) persist even when empty, and any row
  /// with reps, a variation, or notes persists.
  ///
  /// **No reps means not performed** (2026-10-23): Start records a planned
  /// single-number weight into the row, so the weight column can no longer be
  /// a "did the user touch this?" signal — an untouched 60kg target would
  /// otherwise log a weight-only set every Finish. A weight without reps is
  /// an adopted hint; a typed rep is the performance. (The PR engine already
  /// reads empty reps as "not performed".)
  ///
  /// FLAGGED rows are deliberately NOT pruned (2026-10-13): a set or exercise
  /// deleted during the workout is a historic fact — the past-session viewer
  /// shows it red and offers a restore — so the flagged row keeps its values,
  /// its set_number, and its SE row (which carries the exercise's identity
  /// and `exercise_order` number).
  Future<void> _pruneUntouchedPlannedRows() async {
    if (currentWorkoutId == null) return;
    // Snapshot first — `sets.where(...)` is a lazy view of the live list and
    // removing rows inside the loop triggers a ConcurrentModificationError.
    final untouched = sets
        .where(
          (s) =>
              s.plannedSetId != null &&
              s.reps.isEmpty &&
              s.variationId == null &&
              (s.notes == null || s.notes!.isEmpty),
        )
        .toList();
    for (final s in untouched) {
      try {
        await _sessionRepo.deleteSet(s.sessionExerciseSetId);
        sets.remove(s);
      } catch (_) {}
    }
    // An exercise row with no rows AT ALL (active or flagged) is plan-hint
    // residue too (or a group the user emptied) — remove it so the logs
    // viewer doesn't show empty exercise tabs for workouts the user skipped.
    // A fully-deleted exercise keeps its row: that is what the trash lists.
    for (final se in List.of(sessionExercises)) {
      final hasRows =
          sets.any((s) => s.sessionExerciseId == se.sessionExerciseId) ||
          deletedSets.any((s) => s.sessionExerciseId == se.sessionExerciseId);
      if (!hasRows) {
        try {
          await _sessionRepo.deleteSessionExercise(se.sessionExerciseId);
        } catch (_) {}
        sessionExercises.remove(se);
      }
    }
  }

  void _resetActiveWorkoutState() {
    currentWorkoutId = null;
    workoutStartedAt = null;
    previousSessionId = null;
    // A seed belongs to the page it was picked on, never to an ended or
    // cancelled session (2026-10-26).
    pastSessionSeed = null;
    // Every session opens on the bar's default stack — EXERCISE, today's
    // sets — whatever the last session was reading (2026-10-23).
    dateBarMode = SessionDateMode.exercise;
    exerciseHistoryIndex = 0;
    _exerciseHistoryForId = null;
    sets = [];
    deletedSets = [];
    deletedViewSeId = null;
    _deletedPlannedOrder.clear();
    _deletedPlannedSlotIndex.clear();
    sessionExercises = [];
    endNotes = '';
    endFeeling = null;
    exerciseSlots = [];
    activeSlotIndex = 0;
    draftSlotsByExercise = {};
    _draftRowIds.clear();
    // A late debounce timer firing after cancel/end would write into a
    // session that no longer exists (or was pruned) — kill them all, and the
    // stream subscriptions with them.
    for (final t in _setDebounceTimers.values) {
      t.cancel();
    }
    _setDebounceTimers.clear();
    _pendingSetWrites.clear();
    undoHistory.clear();
    _cancelSessionStreams();
    // lessonsByExercise is intentionally NOT cleared — lessons are durable,
    // cross-session data now, not reset per workout.
    historyEditConfirmed = false;
  }

  // ── New exercise / variation ──────────────────────────────────────────────

  bool newExCreating = false;
  bool newVarCreating = false;

  Future<String?> submitNewExercise(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    if (nameTooLong(trimmed)) return null;
    newExCreating = true;
    notifyListeners();
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
      await refreshCatalog();
      newExCreating = false;
      notifyListeners();
      return id;
    } catch (e) {
      error = e.toString();
      newExCreating = false;
      notifyListeners();
      return null;
    }
  }

  /// Variations are a flat per-user library (no exercise assignment since
  /// schema v2), so a name that already exists is never an error here — it's
  /// silently reused. [useExistingId] short-circuits straight to that reuse
  /// path — used when the caller already resolved a "did you mean?" pick, so
  /// this doesn't re-run the name lookup.
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
    newVarCreating = true;
    notifyListeners();
    try {
      String id;
      if (useExistingId != null) {
        id = useExistingId;
        final existing = allVariations.firstWhereOrNull(
          (v) => v.variationId == useExistingId,
        );
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
      await refreshCatalog();
      newVarCreating = false;
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

  void setEndFeeling(int? n) {
    endFeeling = endFeeling == n ? null : n;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final t in _setDebounceTimers.values) {
      t.cancel();
    }
    _setDebounceTimers.clear();
    _cancelSessionStreams();
    _foreignSessionsSub?.cancel();
    _foreignSessionsSub = null;
    slidePagesController.dispose();
    super.dispose();
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

/// One set's merged, not-yet-written edits — the debounce holder. Only the
/// latest value per field survives; a later clearing keystroke sets the
/// clear flag, which outlives any earlier value merge.
class _PendingSetWrite {
  double? weight;
  bool clearWeight = false;
  List<num>? reps;
  bool clearReps = false;
  String? variationId;
  bool clearVariation = false;
  String? notes;
  bool clearNotes = false;

  /// True when the set lives in a COMPLETED session — the flush then
  /// reloads the past-sets timeline instead of relying on the live
  /// session's watch stream.
  bool historical = false;

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
