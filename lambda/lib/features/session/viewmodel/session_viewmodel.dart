import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/planned_session_exercise_set.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/models/program_progress.dart';
import '../../../data/models/session.dart';
import '../../../data/models/exercise_usage.dart';
import '../../../data/models/session_exercise.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../core/powersync/database.dart' as ps;
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/program_run_repository.dart';
import '../../../data/repositories/planned_session_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../shared/widgets/slide_pages.dart';
import '../model/pr_engine.dart';
import '../model/session_local_state.dart';

class SessionViewModel extends ChangeNotifier {
  SessionViewModel({
    SessionRepository? sessionRepo,
    ExerciseRepository? exerciseRepo,
    ProgramRepository? programRepo,
    ProgramRunRepository? programRunRepo,
    LessonRepository? lessonRepo,
    PlannedSessionRepository? plannedSessionRepo,
  }) : _sessionRepo = sessionRepo ?? SessionRepository(),
       _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
       _programRepo = programRepo ?? ProgramRepository(),
       _programRunRepo = programRunRepo ?? ProgramRunRepository(),
       _lessonRepo = lessonRepo ?? LessonRepository(),
       _plannedSessionRepo = plannedSessionRepo ?? PlannedSessionRepository() {
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

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  // ── Startup ─────────────────────────────────────────────────────────────────
  bool initLoading = true;

  // ── Workout state ──────────────────────────────────────────────────────────
  /// Called when the workout fully ends (endWorkout or cancelWorkout) so the
  /// session screen can clear its static cache and create a fresh VM next time.
  VoidCallback? onWorkoutEnded;
  String? currentWorkoutId;
  DateTime? workoutStartedAt;

  /// The session's exercise rows (the tab layer) — order IS the persisted
  /// tab order (`exercise_order` column; the old JSON blob is gone).
  List<SessionExercise> sessionExercises = [];
  List<SessionExerciseSet> sets = [];
  bool setsLoading = false;

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
  Map<String, PlannedSessionExerciseSet> get plannedSetById => {
        for (final list in plannedSetsByExercise.values)
          for (final p in list) p.plannedSetId: p,
      };

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

  bool isDraftBoundRow(String setId) => _draftRowIds.containsValue(setId);

  // ── Lessons (persisted — per-exercise, cross-session) ─────────────────────
  Map<String, List<Lesson>> lessonsByExercise = {};

  // ── History / PR baseline (read-only reuse of past-sets timeline) ────────
  List<PastSetRow> _pastSets = [];
  bool pastSetsLoaded = false;

  /// exerciseId → most recent workout date, for "most recently used" ordering.
  /// (The same map also holds variation-id → last use — ids never collide.)
  Map<String, DateTime> lastUsedByExercise = {};
  Map<String, List<ExerciseHistorySession>> historyByExercise = {};

  /// All active variations, most recently used first — the set-row picker
  /// order. Variations are a flat per-user library (no exercise assignment
  /// since schema v2).
  List<CustomVariation> get variationsByRecency =>
      CustomVariation.sortByLastUsed(allVariations, lastUsedByExercise);

  /// PR events for the ACTIVE session, oldest first — one per set that
  /// extended its pair's best-ever frontier (see pr_engine.dart). The
  /// single source for counts, accents, and before/after values.
  List<PrEvent> sessionPrEvents = [];

  /// Every PR event (full timeline + this session's sets), keyed by source
  /// set id — the history viewer's rows use it for PR badges.
  Map<String, PrEvent> prEventsBySetId = {};

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

  Future<void> _init() async {
    // On a cold start after login, PowerSync may not have finished its first
    // sync yet — the local DB would read as empty. Wait briefly so the session
    // reflects the user's real data instead of a stale/blank state. Falls back
    // to the existing guarded stages if the wait times out or sync is offline.
    try {
      await ps.db.waitForFirstSync().timeout(const Duration(seconds: 10));
    } catch (_) {}
    // Each stage is individually guarded so one transient failure (e.g.
    // PowerSync not synced on cold start) doesn't block the others.
    // In particular, _restoreActiveWorkout must run even if catalog fetch
    // fails, otherwise the active workout is invisible after a hot restart.
    try {
      await refreshCatalog();
    } catch (_) {}
    try {
      await Future.wait([_loadPlannedSession(), _loadPastSets()]);
    } catch (_) {}
    try {
      await _restoreActiveWorkout();
    } catch (_) {}
    initLoading = false;
    notifyListeners();
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
      await _loadSelectedSessionSets();
    } catch (_) {}
    notifyListeners();
  }

  /// Loads the planned sets for the currently selected workout (program or
  /// standalone).
  Future<void> _loadSelectedSessionSets() async {
    if (selectedStandaloneWorkout != null) {
      // Consolidation keeps the preview consistent with the planner — one
      // group per exercise, no-target stubs archived (idempotent).
      final sets = await _plannedSessionRepo.consolidateDuplicateExerciseGroups(
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
      final plannedSets =
          await _plannedSessionRepo.consolidateDuplicateExerciseGroups(
            pw.sessionId,
          );
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

  /// Picks a standalone workout to log.
  Future<void> selectStandaloneWorkout(PlannedSession w) async {
    selectedStandaloneWorkout = w;
    selectedPlannedSession = null;
    final sets = await _plannedSessionRepo.consolidateDuplicateExerciseGroups(
      w.sessionId,
    );
    plannedSetsByExercise = _plannedMapFromSets(sets);
    plannedExerciseOrder = _plannedOrderFromSets(sets);
    notifyListeners();
  }

  /// Picks a different planned workout to log and loads its planned sets.
  Future<void> selectPlannedSession(PlannedSession w) async {
    selectedPlannedSession = w;
    selectedStandaloneWorkout = null;
    await _loadSelectedSessionSets();
    notifyListeners();
  }

  /// Clears the template selection — the session becomes free-form
  /// (no planned sets, no program attribution).
  void clearTemplateSelection() {
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

      programProgress = await _programRunRepo.getProgress(_userId);
      final programId = programProgress?.program.programId;
      if (programId != null) {
        availableWorkouts = await _programRepo.fetchPlannedSessions(programId);
        selectedPlannedSession =
            programProgress?.nextPlannedSession ??
            availableWorkouts.firstOrNull;
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
      await _loadSelectedSessionSets();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadPastSets({bool keepReflectionPosition = false}) async {
    try {
      _pastSets = await _sessionRepo.loadPastSetsTimeline(_userId);
      historyByExercise = groupHistoryByExercise(_pastSets);
      lastUsedByExercise = lastUsedByEntity(_pastSets);
    } catch (_) {}
    pastSetsLoaded = true;
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
  Future<void> refreshShownReflection() async {
    await _loadPastSets(keepReflectionPosition: true);
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
    final sessionPrs =
        prEvents(_pastSets).where((r) => r.sessionId == id).toList();

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

  Future<void> _restoreActiveWorkout() async {
    final activeId = await _sessionRepo.getActiveSessionId(_userId);
    if (activeId != null) {
      currentWorkoutId = activeId;
      final workout = await _sessionRepo.fetchSession(activeId);
      workoutStartedAt = workout?.createdDatetime;
      await _restorePlannedContext(workout);
      slidePagesController.resetToPage(kTrainingPage);
      await _loadSets();
      _seedExerciseSlots(seedDrafts: false);
    }
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
      final plannedSets =
          await _plannedSessionRepo.consolidateDuplicateExerciseGroups(
            parentId,
          );
      plannedSetsByExercise = _plannedMapFromSets(plannedSets);
      plannedExerciseOrder = _plannedOrderFromSets(plannedSets);
    } catch (_) {}
  }

  Future<void> _loadSets() async {
    if (currentWorkoutId == null) return;
    setsLoading = true;
    notifyListeners();
    sets = await _sessionRepo.loadSetsForSession(currentWorkoutId!);
    sessionExercises = await _sessionRepo.loadSessionExercises(
      currentWorkoutId!,
    );
    setsLoading = false;
    _recomputePRs();
    notifyListeners();
  }

  /// Recomputes which sets are PRs using the engine's frontier semantics —
  /// history first, then this session's sets in set-number order, so any
  /// set that extends its pair's best-ever frontier highlights. One event
  /// per PR set; the same events feed counts, accents, and before/after
  /// values, so the surfaces can never disagree.
  void _recomputePRs() {
    final id = currentWorkoutId;
    if (id == null) {
      prSetIds = {};
      sessionPrEvents = [];
      prEventsBySetId = {};
      return;
    }
    final combined = <PastSetRow>[..._pastSets.where((s) => s.sessionId != id)];
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
    final events = prEvents(combined);
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
  }

  bool isPrSet(String setId) => prSetIds.contains(setId);

  // ── Exercise tabs ──────────────────────────────────────────────────────────

  void _seedExerciseSlots({bool seedDrafts = true}) {
    final slots = <SessionExerciseSlot>[];
    final seen = <String>{};
    // Session exercises come back ordered by exercise_order — the persisted
    // tab arrangement (the old JSON blob's replacement).
    for (final se in sessionExercises) {
      final exId = se.exerciseId;
      if (exId == null || !seen.add(exId)) continue;
      // Materialized planned rows are the entry rows — seed a draft only when
      // the exercise has no rows left or its last row is filled (mirrors the
      // freestyle rule below). Restores pass seedDrafts: false — a restart
      // must not invent empty rows the user never created.
      final exerciseSets = sets
          .where((x) => x.exerciseId == exId)
          .toList();
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
    if (index == activeSlotIndex) return;
    activeSlotIndex = index;
    notifyListeners();
  }

  /// Long-press drag reorder of the exercise tab bar.
  void reorderExercises(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
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
    await _ensureSessionExercise(exerciseId);
    addDraftSet(exerciseId);
    _persistExerciseOrder();
    loadLessonsFor(exerciseId);
    activeSlotIndex = exerciseSlots.length - 1;
    notifyListeners();
    return true;
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
  Future<void> removeExerciseSlot(int index) async {
    if (index < 0 || index >= exerciseSlots.length) return;
    final slot = exerciseSlots.removeAt(index);

    // Delete the exercise row and its sets for every exercise in the slot.
    for (final exerciseId in slot.exerciseIds) {
      final sessionExercise = sessionExercises.firstWhereOrNull(
        (e) => e.exerciseId == exerciseId,
      );
      if (sessionExercise != null) {
        await _sessionRepo.deleteSessionExercise(
          sessionExercise.sessionExerciseId,
        );
        sessionExercises.remove(sessionExercise);
      }
      sets.removeWhere((s) => s.exerciseId == exerciseId);
      draftSlotsByExercise.remove(exerciseId);
    }

    // Adjust active tab index
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
    return exerciseSets.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) +
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
      await _sessionRepo.insertSet(
        sessionExerciseId: sessionExercise.sessionExerciseId,
        sessionId: currentWorkoutId!,
        userId: _userId,
        setNumber: nextNum,
        weight: null,
        reps: const [],
      );
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

  /// Seeds a virtual draft slot for [exerciseId] — nothing is persisted
  /// until the first commit (lazy binding in commitDraftSet), so restoring
  /// a workout never writes phantom empty rows to the DB.
  void _seedDraft(String exerciseId) {
    final draftId = _nextDraftId++;
    draftSlotsByExercise.putIfAbsent(exerciseId, () => []).add(draftId);
  }

  void removeDraftSet(String exerciseId, int draftId) {
    draftSlotsByExercise[exerciseId]?.remove(draftId);
    final rowId = _draftRowIds.remove(draftId);
    if (rowId != null) {
      _sessionRepo.deleteSet(rowId);
      sets.removeWhere((s) => s.sessionExerciseSetId == rowId);
    }
    _recomputePRs();
    notifyListeners();
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

  Future<void> updateSetField(
    SessionExerciseSet set, {
    double? weight,
    bool clearWeight = false,
    List<num>? reps,

    String? variationId,
    bool clearVariation = false,
    String? notes,
    bool clearNotes = false,
  }) async {
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
      await _loadSets();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  /// Edits a set from a *completed* workout — the history viewer's editable
  /// grid. Reuses the same `updateSet` write as the live session (it isn't
  /// gated by workout status), but reloads past-sets/PR-baseline state
  /// instead of the live `sets` list, since the edited row lives there.
  Future<void> updateHistoricalSetField(
    PastSetRow set, {
    double? weight,
    bool clearWeight = false,
    List<num>? reps,
    String? variationId,
    bool clearVariation = false,
    String? notes,
    bool clearNotes = false,
  }) async {
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
      await _loadPastSets();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteSetById(String setId) async {
    await _sessionRepo.deleteSet(setId);
    await _loadSets();
  }

  /// Inserts a new set copying [set]'s weight/reps/variation/notes — the
  /// grid row's swipe-action "Duplicate" button.
  Future<void> duplicateSet(SessionExerciseSet set) async {
    if (currentWorkoutId == null) return;
    final exerciseId = set.exerciseId;
    if (exerciseId == null) return;
    try {
      await _sessionRepo.insertSet(
        sessionExerciseId: set.sessionExerciseId,
        sessionId: currentWorkoutId!,
        userId: _userId,
        variationId: set.variationId,
        setNumber: _nextSetNumberFor(exerciseId),
        weight: set.weight,
        reps: set.reps,
        notes: set.notes,
      );
      await _loadSets();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
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
      final template = selectedStandaloneWorkout ?? selectedPlannedSession;
      final id = await _sessionRepo.createSession(
        _userId,
        preNotes: startNotes.trim().isEmpty ? null : startNotes.trim(),
        programRunId: selectedStandaloneWorkout != null
            ? null
            : programProgress?.run.programRunId,
        plannedSessionId: template?.sessionId,
        plannedSessionName: template?.name,
        preFeeling: sessionFeeling,
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
      await _materializePlannedSets();
      // Reload so rows hydrate their exerciseId from the parent exercise row
      // (insertSet returns bare rows) — _seedExerciseSlots' draft logic keys
      // on it, and without the reload it would seed phantom drafts on top of
      // the freshly materialized planned rows.
      await _loadSets();
      _seedExerciseSlots();
    } catch (e) {
      error = e.toString();
    }
    startLoading = false;
    notifyListeners();
  }

  /// The plan becomes real rows at session start: one fact_session_exercise
  /// per planned exercise (linked via planned_exercise_id), then one fact set
  /// row per planned target linked to its template row via planned_set_id.
  /// Actual values (weight/reps/variation) start empty — the plan's targets
  /// stay background hints rendered from the dim rows, never copied into the
  /// numeric columns. Freestyle sessions materialize nothing.
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
            weight: null,
            reps: const [],
            plannedSetId: p.plannedSetId,
          ),
        );
      }
    }
    sets = materialized;
  }

  /// Ends the active session (Summary page's Finish Session): flushes,
  /// prunes untouched planned rows, stamps `end_datetime`, and slides to
  /// the post-questionnaire page. Post answers land separately in
  /// [completePostQuestionnaire] — nothing here writes them.
  Future<void> finishSession() async {
    if (currentWorkoutId == null) return;
    endLoading = true;
    notifyListeners();
    try {
      // Flush any in-flight row edits (typed but not yet blurred) so nothing
      // is pruned or finalized before the last keystroke lands.
      await flushPendingCommits();
      await _pruneUntouchedPlannedRows();
      // Capture BEFORE the reset wipes sets/sessionPrEvents/currentWorkoutId —
      // the post-questionnaire write target and the home congrats stats.
      lastEndedSessionId = currentWorkoutId;
      lastCompletedStats = _snapshotSessionStats();
      await _sessionRepo.endSession(currentWorkoutId!);
      _resetActiveWorkoutState();
      // Reload the timeline — the ended session joins the completed-session
      // pager the post-questionnaire page shows.
      await _loadPastSets();
      // The post-questionnaire page's comparison reference — the completed
      // session BEFORE the just-ended one (ids are newest-first; the ended
      // session sits at index 0).
      previousCompletedSession = null;
      if (_reflectionSessionIds.length >= 2) {
        try {
          previousCompletedSession =
              await _sessionRepo.fetchSession(_reflectionSessionIds[1]);
        } catch (_) {}
      }
      slidePagesController.slideToPage(kPostQuestionnairePage);
    } catch (e) {
      error = e.toString();
    }
    endLoading = false;
    notifyListeners();
  }

  /// The post-questionnaire page's Done: writes the post answers to the
  /// ended session, clears both questionnaires (the next session's pre-Q
  /// must start blank — the old flow leaked the previous answers), and
  /// lands Home with the congrats banner. [onWorkoutEnded] fires LAST —
  /// its consumer disposes the cached VM, so nothing may notify after it.
  Future<void> completePostQuestionnaire() async {
    final id = lastEndedSessionId;
    if (id == null) return;
    endLoading = true;
    notifyListeners();
    try {
      await _sessionRepo.updatePostQuestionnaire(
        id,
        feeling: endFeeling,
        notes: endNotes.trim().isEmpty ? null : endNotes.trim(),
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

  /// Planned rows the user never entered any data into are plan hints, not
  /// facts — remove them at session end so the log shows what actually
  /// happened. User-added rows (no planned link) persist even when empty, and
  /// any row with data (weight, reps, variation, or notes) persists.
  Future<void> _pruneUntouchedPlannedRows() async {
    if (currentWorkoutId == null) return;
    // Snapshot first — `sets.where(...)` is a lazy view of the live list and
    // removing rows inside the loop triggers a ConcurrentModificationError.
    final untouched = sets
        .where(
          (s) =>
              s.plannedSetId != null &&
              s.weight == null &&
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
    // An exercise row with no sets left is plan-hint residue too (or a group
    // the user emptied) — remove it so the logs viewer doesn't show empty
    // exercise tabs for workouts the user skipped.
    for (final se in List.of(sessionExercises)) {
      if (!sets.any((s) => s.sessionExerciseId == se.sessionExerciseId)) {
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
    sets = [];
    sessionExercises = [];
    endNotes = '';
    endFeeling = null;
    exerciseSlots = [];
    activeSlotIndex = 0;
    draftSlotsByExercise = {};
    _draftRowIds.clear();
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
