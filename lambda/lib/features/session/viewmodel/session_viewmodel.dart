import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/planned_session_set.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/models/program_progress.dart';
import '../../../data/models/session.dart';
import '../../../data/models/exercise_usage.dart';
import '../../../data/models/session_set.dart';
import '../../../core/powersync/database.dart' as ps;
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/program_run_repository.dart';
import '../../../data/repositories/planned_session_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../shared/widgets/slide_pages.dart';
import '../model/pr_engine.dart' hide bestEverForExercise;
import '../model/session_local_state.dart';


class SessionViewModel extends ChangeNotifier {
  SessionViewModel({
    SessionRepository? sessionRepo,
    ExerciseRepository? exerciseRepo,
    ProgramRepository? programRepo,
    ProgramRunRepository? programRunRepo,
    LessonRepository? lessonRepo,
    PlannedSessionRepository? plannedSessionRepo,
  })  : _sessionRepo = sessionRepo ?? SessionRepository(),
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

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  // ── Startup ─────────────────────────────────────────────────────────────────
  bool initLoading = true;

  // ── Workout state ──────────────────────────────────────────────────────────
  /// Called when the workout fully ends (endWorkout or cancelWorkout) so the
  /// session screen can clear its static cache and create a fresh VM next time.
  VoidCallback? onWorkoutEnded;
  String? currentWorkoutId;
  DateTime? workoutStartedAt;

  /// The active workout row fetched at restore — carries `exerciseOrder` so
  /// the tab arrangement (incl. supersets) can be rebuilt after a hot restart.
  Session? _session;
  List<SessionSet> sets = [];
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

  // ── Error ──────────────────────────────────────────────────────────────────
  String? error;

  // ── Today's planned workout (read-only reuse of the Programs feature) ────
  ProgramProgress? programProgress;
  Map<String, List<PlannedSessionSet>> plannedSetsByExercise = {};
  List<String> plannedExerciseOrder = [];

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

  // ── Lessons (persisted — per-exercise, cross-session) ─────────────────────
  Map<String, List<Lesson>> lessonsByExercise = {};

  // ── History / PR baseline (read-only reuse of past-sets timeline) ────────
  List<PastSetRow> _pastSets = [];
  bool pastSetsLoaded = false;

  /// exerciseId → most recent workout date, for "most recently used" ordering.
  Map<String, DateTime> lastUsedByExercise = {};
  Map<String, List<ExerciseHistorySession>> historyByExercise = {};
  /// PR baseline keyed by (exerciseId, variationId) — curves are scoped
  /// per exercise × variation, so the live-session baseline must be too.
  Map<(String, String?), ({num weight, num reps})?> prevBestByExerciseVariation = {};

  /// Previous-best records per axis (rep-max N, weight-max W) derived from
  /// completed history only — used by the reflection page's before/after.
  final _prevRepMax = <(String, String?, int), PrRecord?>{};
  final _prevWeightMax = <(String, String?, num), PrRecord?>{};

  PrRecord? previousRepMax(String exerciseId, String? variationId, int reps) =>
      _prevRepMax[(exerciseId, variationId, reps)];

  PrRecord? previousWeightMax(String exerciseId, String? variationId, num weight) =>
      _prevWeightMax[(exerciseId, variationId, weight)];

  // ── Historical set editing ─────────────────────────────────────────────────
  bool historyEditConfirmed = false;

  void confirmHistoryEdit() {
    historyEditConfirmed = true;
    notifyListeners();
  }


  // ── Derived ───────────────────────────────────────────────────────────────
  bool get hasActiveWorkout => currentWorkoutId != null;

  int get distinctExerciseCount => sets.map((s) => s.exerciseId).toSet().length;

  int get totalPRsThisSession => prSetIds.length;


  /// PRs achieved this session using the full rep-max timeline engine.
  List<PrRecord> get prsThisSession {
    // Combine history + current session sets, ordered by time
    final all = [..._pastSets];
    // Build PastSetRows for current session sets (no createdDate) — use now
    final now = DateTime.now();
    for (final s in sets) {
      all.add(PastSetRow(
        sessionSetId: s.sessionSetId,
        sessionId: s.sessionId,
        userId: s.userId,
        exerciseId: s.exerciseId,
        setNumber: s.setNumber,
        reps: s.reps,
        sessionCreatedDate: now,
        variationId: s.variationId,
        weight: s.weight,
        notes: s.notes,
        exerciseName: s.exerciseName,
        variationName: s.variationName,
        supersetGroupNumber: s.supersetGroupNumber,
      ));
    }
    // PRs in the current workout are those whose sessionId is the active one.
    // Only count explicit (non-propagated) PRs — the user sees what they
    // directly achieved, not the knock-on records the engine inferred.
    return prsForWorkout(all, currentWorkoutId ?? '')
        .where((p) => !p.isPropagated)
        .toList();
  }

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
      final bridges = await _exerciseRepo.fetchBridges(_userId);
      final counts = <String, int>{};
      for (final b in bridges) {
        final varId = b['custom_variation_id'] as String;
        counts[varId] = (counts[varId] ?? 0) + 1;
      }
      variationExerciseCounts = counts;
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
    // Deactivated exercise — use the snapshot name from the first set.
    for (final s in sets) {
      if (s.exerciseId == exerciseId && s.exerciseName != null) {
        return s.exerciseName!;
      }
    }
    return exerciseId;
  }

  /// All of the user's variations (not just ones already assigned to some
  /// exercise) — variations are shared many-to-many across exercises via the
  /// exercise/variation bridge, so this is the pool "did you mean?" and
  /// silent-reuse checks search against.
  List<CustomVariation> allVariations = [];
  Map<String, int> variationExerciseCounts = {};

  /// Near-duplicate variation names (e.g. "Paused" vs "Pause") to flag as
  /// "did you mean?" before creating a brand-new one, each annotated with how
  /// many exercises it's already assigned to.
  List<({String id, String name, int exerciseCount})> findSimilarVariations(String name) {
    final results = <({String id, String name, int exerciseCount})>[];
    for (final v in allVariations) {
      if (isSimilarVariationName(name, v.name)) {
        results.add((id: v.variationId, name: v.name, exerciseCount: variationExerciseCounts[v.variationId] ?? 0));
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
        availableWorkouts =
            await _programRepo.fetchPlannedSessions(programId);
        selectedPlannedSession =
            programProgress?.nextPlannedSession ?? availableWorkouts.firstOrNull;
      }
      standaloneWorkouts = await _plannedSessionRepo.fetchPlannedSessions(_userId);
      await _loadSelectedSessionSets();
    } catch (_) {}
    notifyListeners();
  }

  /// Loads the planned sets for the currently selected workout (program or
  /// standalone).
  Future<void> _loadSelectedSessionSets() async {
    if (selectedStandaloneWorkout != null) {
      final sets = await _plannedSessionRepo.fetchPlannedSets(selectedStandaloneWorkout!.sessionId);
      plannedSetsByExercise = _plannedMapFromSessionSets(sets);
      plannedExerciseOrder = _plannedOrderFromSessionSets(sets);
      return;
    }
    final pw = selectedPlannedSession;
    if (pw == null) {
      plannedSetsByExercise = {};
      plannedExerciseOrder = [];
      return;
    }
    try {
      final plannedSets = await _programRepo.fetchPlannedSessionSets(pw.sessionId);
      plannedSetsByExercise = _plannedMapFromSets(plannedSets);
      plannedExerciseOrder = _plannedOrderFromSets(plannedSets);
    } catch (_) {}
  }

  Map<String, List<PlannedSessionSet>> _plannedMapFromSets(List<PlannedSessionSet> sets) {
    final sorted = [...sets]
      ..sort((a, b) => a.exerciseSequenceOrder.compareTo(b.exerciseSequenceOrder));
    final byExercise = <String, List<PlannedSessionSet>>{};
    for (final p in sorted) {
      byExercise.putIfAbsent(p.exerciseId, () => []).add(p);
    }
    return byExercise;
  }

  List<String> _plannedOrderFromSets(List<PlannedSessionSet> sets) {
    final sorted = [...sets]
      ..sort((a, b) => a.exerciseSequenceOrder.compareTo(b.exerciseSequenceOrder));
    final order = <String>[];
    for (final p in sorted) {
      if (!order.contains(p.exerciseId)) order.add(p.exerciseId);
    }
    return order;
  }

  Map<String, List<PlannedSessionSet>> _plannedMapFromSessionSets(List<PlannedSessionSet> sets) =>
      _plannedMapFromSets(_setsFromSessionSets(sets));

  List<String> _plannedOrderFromSessionSets(List<PlannedSessionSet> sets) =>
      _plannedOrderFromSets(_setsFromSessionSets(sets));

  List<PlannedSessionSet> _setsFromSessionSets(List<PlannedSessionSet> sets) => [
        for (final s in sets)
          PlannedSessionSet(
            setId: s.setId,
            sessionId: s.sessionId,
            userId: s.userId,
            exerciseId: s.exerciseId,
            variationId: s.variationId,
            exerciseSequenceOrder: s.exerciseSequenceOrder,
            setNumber: s.setNumber,
            targetWeight: s.targetWeight?.toDouble(),
            targetReps: s.targetReps,
                        targetNotes: s.targetNotes,
            exerciseName: s.exerciseName,
            variationName: s.variationName,
            isArchived: false,
          ),
      ];

  /// Picks a standalone workout to log.
  Future<void> selectStandaloneWorkout(PlannedSession w) async {
    selectedStandaloneWorkout = w;
    selectedPlannedSession = null;
    final sets = await _plannedSessionRepo.fetchPlannedSets(w.sessionId);
    plannedSetsByExercise = _plannedMapFromSessionSets(sets);
    plannedExerciseOrder = _plannedOrderFromSessionSets(sets);
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
    try {
      // Validate the program reference regardless of active-workout state:
      // if the user deleted the program from the library mid-session, clear
      // the stale header so we don't show a dangling "Week N · Program".
      if (currentWorkoutId != null && programProgress != null) {
        final program = await _programRepo.fetchProgram(
            programProgress!.program.programId);
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
        availableWorkouts =
            await _programRepo.fetchPlannedSessions(programId);
        selectedPlannedSession =
            programProgress?.nextPlannedSession ?? availableWorkouts.firstOrNull;
      } else {
        availableWorkouts = [];
        selectedPlannedSession = null;
        plannedSetsByExercise = {};
        plannedExerciseOrder = [];
      }
      // Standalone templates are independent of the program — re-fetch them
      // too so a template created on another tab shows without a restart.
      standaloneWorkouts =
          await _plannedSessionRepo.fetchPlannedSessions(_userId);
      await _loadSelectedSessionSets();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadPastSets() async {
    try {
      _pastSets = await _sessionRepo.loadPastSetsTimeline(_userId);
      historyByExercise = groupHistoryByExercise(_pastSets);
      lastUsedByExercise = lastUsedByEntity(_pastSets);
      final byKey = <(String, String?), List<PastSetRow>>{};
      for (final s in _pastSets) {
        byKey.putIfAbsent((s.exerciseId, s.variationId), () => []).add(s);
      }
      prevBestByExerciseVariation = byKey.map(
          (key, sets) => MapEntry(key, bestEverForExercise(sets, variationId: key.$2)));
    } catch (_) {}
    pastSetsLoaded = true;
    notifyListeners();
  }

  Future<void> _restoreActiveWorkout() async {
    final activeId = await _sessionRepo.getActiveSessionId(_userId);
    if (activeId != null) {
      currentWorkoutId = activeId;
      final workout = await _sessionRepo.fetchSession(activeId);
      _session = workout;
      workoutStartedAt = workout?.createdDate;
      slidePagesController.resetToPage(1);
      await _loadSets();
      _seedExerciseSlots();
    }
  }

  Future<void> _loadSets() async {
    if (currentWorkoutId == null) return;
    setsLoading = true;
    notifyListeners();
    sets = await _sessionRepo.loadSetsForSession(currentWorkoutId!);
    setsLoading = false;
    _recomputePRs();
    notifyListeners();
  }

  /// Recomputes which sets are PRs using the engine's exact semantics (same
  /// `fullPrTimeline` walk `_persistPRs` uses) — history first, then this
  /// session's sets in set-number order, so a set that improves any rep-max
  /// or weight-max axis highlights, not just the single best (weight,reps).
  void _recomputePRs() {
    final id = currentWorkoutId;
    if (id == null) {
      prSetIds = {};
      return;
    }
    final combined = <PastSetRow>[
      ..._pastSets.where((s) => s.sessionId != id),
    ];
    final sessionDate = workoutStartedAt ?? DateTime.now();
    final ordered = [...sets]..sort((a, b) => a.setNumber.compareTo(b.setNumber));
    for (final s in ordered) {
      combined.add(PastSetRow(
        sessionSetId: s.sessionSetId,
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
        supersetGroupNumber: s.supersetGroupNumber,
      ));
    }
    final records = fullPrTimeline(combined);
    // Only THIS session's records — the timeline includes all of history, and
    // the stats bar must count this session's PRs, not every set that ever
    // caused a PR.
    prSetIds = {
      for (final r in records)
        if (r.sessionId == id && r.setId != null && r.setId!.isNotEmpty)
          r.setId!,
    };

    // Session-aware "before" per axis: the previous record for each of this
    // session's records, considering history AND earlier sets in the same
    // session (5x7 logged before 5x9 makes the 9-rep record's before = 7).
    _prevRepMax.clear();
    _prevWeightMax.clear();
    final lastRepMax = <(String, String?, int), PrRecord?>{};
    final lastWeightMax = <(String, String?, num), PrRecord?>{};
    for (final r in records) {
      if (r.type == PrType.repMax && r.targetReps != null) {
        final key = (r.exerciseId, r.variationId, r.targetReps!);
        if (r.sessionId == id) _prevRepMax[key] = lastRepMax[key];
        lastRepMax[key] = r;
      } else if (r.type == PrType.weightMax && r.targetWeight != null) {
        final key = (r.exerciseId, r.variationId, r.targetWeight!);
        if (r.sessionId == id) _prevWeightMax[key] = lastWeightMax[key];
        lastWeightMax[key] = r;
      }
    }
  }

  bool isPrSet(String setId) => prSetIds.contains(setId);

  // ── Exercise tabs ──────────────────────────────────────────────────────────

  void _seedExerciseSlots() {
    final seen = <String>{};
    final slots = <SessionExerciseSlot>[];

    // Supersets reconstructed from the sets' superset_group_number: exercises
    // sharing a non-null group become one superset tab (in first-set order).
    final supersetGroups = <int, List<String>>{};
    for (final s in sets) {
      final g = s.supersetGroupNumber;
      if (g == null) continue;
      supersetGroups.putIfAbsent(g, () => []).add(s.exerciseId);
    }
    final groupMembers = supersetGroups.values
        .map((ids) => {for (final id in ids) id})
        .toList();

    bool isSuperseded(String exerciseId) =>
        groupMembers.any((m) => m.contains(exerciseId));

    void addSlot(List<String> ids, {bool planned = false}) {
      final unique = <String>[];
      for (final id in ids) {
        if (unique.contains(id)) continue;
        unique.add(id);
        if (seen.add(id)) {
          draftSlotsByExercise.putIfAbsent(id, () => [_nextDraftId++]);
          loadLessonsFor(id);
        }
      }
      if (unique.isEmpty) return;
      slots.add(SessionExerciseSlot(
          id: _nextSlotId++,
          type: unique.length > 1 ? SessionSlotType.superset : SessionSlotType.single,
          exerciseIds: unique,
          planned: planned));
    }

    for (final exId in plannedExerciseOrder) {
      if (isSuperseded(exId)) continue;
      addSlot([exId], planned: true);
    }
    for (final s in sets) {
      if (!seen.add(s.exerciseId)) continue;
      final group = s.supersetGroupNumber;
      if (group != null) continue; // handled by group slot below
      // An empty trailing set (a freshly-added exercise that hasn't been
      // filled yet) already serves as the next-set slot — don't add a ghost.
      final exerciseSets = sets.where((x) => x.exerciseId == s.exerciseId).toList();
      final last = exerciseSets.isEmpty ? null : exerciseSets.last;
      final lastEmpty = last != null && last.reps.isEmpty;
      if (!lastEmpty) draftSlotsByExercise.putIfAbsent(s.exerciseId, () => [_nextDraftId++]);
      loadLessonsFor(s.exerciseId);
      addSlot([s.exerciseId]);
    }
    for (final ids in groupMembers) {
      addSlot(ids.toList());
    }

    exerciseSlots = slots;
    activeSlotIndex = 0;
    _applyPersistedOrder();
    notifyListeners();
  }

  /// Reorders the freshly-seeded slots to match the persisted
  /// `fact_session.exercise_order` (preserves the user's tab arrangement and
  /// the superset grouping across a hot restart).
  void _applyPersistedOrder() {
    final order = _session?.exerciseOrder;
    if (order == null || order.isEmpty) return;
    List<dynamic>? parsed;
    try {
      parsed = jsonDecode(order) as List<dynamic>;
    } catch (_) {
      return;
    }
    final byIds = {
      for (final slot in exerciseSlots) slot.exerciseIds.join(','): slot,
    };
    final reordered = <SessionExerciseSlot>[];
    for (final raw in parsed) {
      final ids = ((raw as Map<String, dynamic>)['exerciseIds'] as List<dynamic>)
          .cast<String>();
      final match = byIds[ids.join(',')];
      if (match != null) {
        reordered.add(match);
        byIds.remove(ids.join(','));
      }
    }
    // Any slots not named in the persisted order keep their seeded position.
    for (final slot in exerciseSlots) {
      if (!reordered.contains(slot)) reordered.add(slot);
    }
    if (reordered.length == exerciseSlots.length) {
      exerciseSlots = reordered;
    }
  }

  /// Tapping the already-active superset tab cycles to its next exercise;
  /// tapping any other tab switches to it.
  void tapTab(int index) {
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

  /// Serializes the current tab slots (order + superset grouping) to
  /// `fact_session.exercise_order` so the tab bar survives a hot restart.
  void _persistExerciseOrder() {
    final id = currentWorkoutId;
    if (id == null) return;
    final payload = [
      for (final slot in exerciseSlots)
        {
          'id': slot.id,
          'type': slot.type.name,
          'exerciseIds': slot.exerciseIds,
        },
    ];
    _sessionRepo.saveExerciseOrder(id, jsonEncode(payload));
  }

  /// Jumps a superset tab straight to one of its exercises — the in-card
  /// superset nav's tap handler. More discoverable than the old "tap the
  /// tab again to cycle" gesture.
  void setSupersetIndex(SessionExerciseSlot slot, int index) {
    if (index < 0 || index >= slot.exerciseIds.length) return;
    slot.activeIndex = index;
    notifyListeners();
  }

  /// If [exerciseId] is already active in some tab (plain or inside a
  /// superset), adding it again would create a confusing duplicate slot with
  /// its own separate set history — instead this just navigates to the
  /// existing tab (and the right superset sub-index) and reports that it did
  /// so, so the caller doesn't also treat it as "added."
  bool addExerciseSlot(String exerciseId) {
    final existingIndex = exerciseSlots.indexWhere((s) => s.exerciseIds.contains(exerciseId));
    if (existingIndex != -1) {
      activeSlotIndex = existingIndex;
      final slot = exerciseSlots[existingIndex];
      final subIndex = slot.exerciseIds.indexOf(exerciseId);
      if (subIndex != -1) slot.activeIndex = subIndex;
      notifyListeners();
      return false;
    }
    exerciseSlots.add(SessionExerciseSlot(
        id: _nextSlotId++, type: SessionSlotType.single, exerciseIds: [exerciseId]));
    // Persist an empty set row so the exercise survives a hot restart — the
    // restore path only rediscovers exercises that exist in fact_session_set.
    addDraftSet(exerciseId);
    _persistExerciseOrder();
    loadLessonsFor(exerciseId);
    activeSlotIndex = exerciseSlots.length - 1;
    notifyListeners();
    return true;
  }

  void addSupersetSlot(List<String> exerciseIds) {
    exerciseSlots.add(SessionExerciseSlot(
        id: _nextSlotId++, type: SessionSlotType.superset, exerciseIds: exerciseIds));
    for (final id in exerciseIds) {
      // Persist an empty set per exercise so supersets survive a hot restart.
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

    // Delete persisted sets for every exercise in the slot
    for (final exerciseId in slot.exerciseIds) {
      final exerciseSets = sets.where((s) => s.exerciseId == exerciseId).toList();
      for (final s in exerciseSets) {
        await _sessionRepo.deleteSet(s.sessionSetId);
      }
      sets.removeWhere((s) => s.exerciseId == exerciseId);
      draftSlotsByExercise.remove(exerciseId);
    }

    // Adjust active tab index
    if (activeSlotIndex >= exerciseSlots.length) {
      activeSlotIndex = (exerciseSlots.length - 1).clamp(0, exerciseSlots.length);
    }
    _persistExerciseOrder();
    _recomputePRs();
    notifyListeners();
  }

  /// The superset group to stamp onto a newly logged set for [exerciseId] —
  /// the containing slot's id if it's a superset tab, else null (a plain
  /// single-exercise slot is never "part of a superset"). This is the only
  /// place a superset's grouping survives past the in-memory session state:
  /// once stamped onto `fact_session_set.superset_group_number` it's
  /// queryable/excludable in analytics even after the session ends.
  int? _supersetGroupFor(String exerciseId) {
    final slot = exerciseSlots.firstWhereOrNull(
        (s) => s.type == SessionSlotType.superset && s.exerciseIds.contains(exerciseId));
    return slot?.id;
  }

  String? _variationName(String exerciseId, String? variationId) {
    if (variationId == null) return null;
    return exerciseDetailMap[exerciseId]
        ?.assignedVariations
        .where((v) => v.variationId == variationId)
        .map((v) => v.name)
        .firstOrNull;
  }

  // ── Draft set rows ─────────────────────────────────────────────────────────

  /// Tapping "+ ADD SET" pre-creates an empty set in the DB so it survives
  /// hot restarts. Empty sets are purged on endWorkout.
  void addDraftSet(String exerciseId) {
    if (currentWorkoutId == null) return;
    final nextNum = sets.isEmpty
        ? 1
        : sets.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    _sessionRepo.insertSet(
      sessionId: currentWorkoutId!,
      userId: _userId,
      exerciseId: exerciseId,
      exerciseName: exerciseDetailMap[exerciseId]?.name,
      setNumber: nextNum,
      weight: null,
      reps: [],
      supersetGroupNumber: _supersetGroupFor(exerciseId),
    ).then((newSet) {
      sets.add(newSet);
      _recomputePRs();
      notifyListeners();
    });
  }

  void removeDraftSet(String exerciseId, int draftId) {
    draftSlotsByExercise[exerciseId]?.remove(draftId);
    notifyListeners();
  }

  /// Commits a set — if the last set for this exercise is empty, fills it in;
  /// otherwise inserts a new row.
  Future<bool> commitDraftSet(
    String exerciseId,
    int draftId, {
    String? variationId,
    double? weight,
    required List<num> reps,
    String? notes,
  }) async {
    if (currentWorkoutId == null) return false;
    if (reps.isEmpty) return false;
    final nextNum = sets.isEmpty
        ? 1
        : sets.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    // Find an empty pre-created set for this exercise to fill in
    final emptyIdx = sets.lastIndexWhere(
      (s) => s.exerciseId == exerciseId && s.reps.isEmpty);
    try {
      if (emptyIdx >= 0) {
        await _sessionRepo.updateSet(
          sets[emptyIdx].sessionSetId,
          variationId: variationId,
          clearVariation: variationId == null,
          weight: weight,
          clearWeight: weight == null,
          reps: reps,
          notes: notes,
          clearNotes: notes == null || notes.isEmpty,
        );
      } else {
        await _sessionRepo.insertSet(
          sessionId: currentWorkoutId!,
          userId: _userId,
          exerciseId: exerciseId,
          exerciseName: exerciseDetailMap[exerciseId]?.name,
          variationId: variationId,
          variationName: _variationName(exerciseId, variationId),
          setNumber: nextNum,
          weight: weight,
          reps: reps,
          notes: notes,
          supersetGroupNumber: _supersetGroupFor(exerciseId),
        );
      }
      draftSlotsByExercise[exerciseId]?.remove(draftId);
      await _loadSets();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> updateSetField(
    SessionSet set, {
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
        set.sessionSetId,
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
  }) async {
    try {
      await _sessionRepo.updateSet(
        set.sessionSetId,
        weight: weight,
        clearWeight: clearWeight,
        reps: reps,
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
  Future<void> duplicateSet(SessionSet set) async {
    if (currentWorkoutId == null) return;
    final nextNum = sets.isEmpty
        ? 1
        : sets.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    try {
      await _sessionRepo.insertSet(
        sessionId: currentWorkoutId!,
        userId: _userId,
        exerciseId: set.exerciseId,
        exerciseName: set.exerciseName ?? exerciseDetailMap[set.exerciseId]?.name,
        variationId: set.variationId,
        variationName: set.variationName ?? _variationName(set.exerciseId, set.variationId),
        setNumber: nextNum,
        weight: set.weight,
        reps: set.reps,
        notes: set.notes,
        supersetGroupNumber: _supersetGroupFor(set.exerciseId),
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

  /// Loads (or refreshes) the persisted lessons for one exercise — called
  /// whenever an exercise slot is created so the card's lesson preview/count
  /// is populated without requiring the Lessons modal to be opened first.
  Future<void> loadLessonsFor(String exerciseId) async {
    try {
      lessonsByExercise[exerciseId] = await _lessonRepo.fetchLessons(_userId, exerciseId);
      _lessonLog.info('loadLessonsFor($exerciseId) → ${lessonsByExercise[exerciseId]!.length}');
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> addLesson(String exerciseId, String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _lessonRepo.createLesson(_userId, exerciseId, text.trim(),
          sessionId: currentWorkoutId);
      await loadLessonsFor(exerciseId);
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> toggleLessonPin(String exerciseId, String lessonId) async {
    final lesson =
        lessonsByExercise[exerciseId]?.firstWhereOrNull((l) => l.lessonId == lessonId);
    if (lesson == null) return;
    try {
      await _lessonRepo.setPinned(_userId, exerciseId, lessonId, !lesson.pinned);
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

  // ── History / PR baseline ─────────────────────────────────────────────────

  List<ExerciseHistorySession> historyFor(String exerciseId) =>
      historyByExercise[exerciseId] ?? const [];

  ({num weight, num reps})? prevBestFor(String exerciseId, String? variationId) =>
      prevBestByExerciseVariation[(exerciseId, variationId)];

  /// The PR baseline for [exerciseId]: the better of the past-best and the
  /// best set logged earlier in the current session (excluding [excludingSetId],
  /// so a set isn't compared against itself). Lets a set that beats something
  /// done earlier in the same workout highlight as a PR, matching what the
  /// engine persists at endWorkout (the day's best).
  ({num weight, num reps})? baselineFor(String exerciseId, String? variationId,
      {String? excludingSetId}) {
    final pastBest = prevBestByExerciseVariation[(exerciseId, variationId)];
    ({num weight, num reps})? sessionBest;
    for (final s in sets) {
      if (s.exerciseId != exerciseId) continue;
      if (s.variationId != variationId) continue;
      if (excludingSetId != null && s.sessionSetId == excludingSetId) continue;
      final weight = s.weight ?? 0;
      final reps = s.reps.isNotEmpty ? s.reps.first : null;
      if (reps == null) continue;
      if (sessionBest == null ||
          weight > sessionBest.weight ||
          (weight == sessionBest.weight && reps > sessionBest.reps)) {
        sessionBest = (weight: weight, reps: reps);
      }
    }
    if (pastBest == null) return sessionBest;
    if (sessionBest == null) return pastBest;
    if (sessionBest.weight > pastBest.weight ||
        (sessionBest.weight == pastBest.weight && sessionBest.reps > pastBest.reps)) {
      return sessionBest;
    }
    return pastBest;
  }

  int prCountFor(String exerciseId) =>
      sets.where((s) => s.exerciseId == exerciseId && prSetIds.contains(s.sessionSetId)).length;

  // ── Start / end / cancel workout ──────────────────────────────────────────

  Future<void> startWorkout() async {
    startLoading = true;
    error = null;
    notifyListeners();
    try {
      final template = selectedStandaloneWorkout ?? selectedPlannedSession;
      final id = await _sessionRepo.createSession(
        _userId,
        preNotes: startNotes.trim().isEmpty ? null : startNotes.trim(),
        programId: selectedStandaloneWorkout != null
            ? null
            : programProgress?.program.programId,
        programName: selectedStandaloneWorkout != null
            ? null
            : programProgress?.program.name,
        programRunId: selectedStandaloneWorkout != null
            ? null
            : programProgress?.run.programRunId,
        parentSessionId: template?.sessionId,
        parentSessionName: template?.name,
        preFeeling: sessionFeeling,
      );
      currentWorkoutId = id;
      workoutStartedAt = DateTime.now();
      sets = [];
      startNotes = '';
      sessionFeeling = null;
      _seedExerciseSlots();
      slidePagesController.slideIn();
    } catch (e) {
      error = e.toString();
    }
    startLoading = false;
    notifyListeners();
  }

  Future<void> endSession() async {
    if (currentWorkoutId == null) return;
    endLoading = true;
    notifyListeners();
    try {
      await _purgeEmptySets();
      await _sessionRepo.endSession(
          currentWorkoutId!,
          postNotes: endNotes.trim().isEmpty ? null : endNotes.trim(),
          feeling: endFeeling);
      _resetActiveWorkoutState();
      slidePagesController.slideOut();
      onWorkoutEnded?.call();
    } catch (e) {
      error = e.toString();
    }
    endLoading = false;
    notifyListeners();
  }

  Future<void> cancelSession() async {
    if (currentWorkoutId == null) return;
    final id = currentWorkoutId!;
    _resetActiveWorkoutState();
    slidePagesController.slideOut();
    notifyListeners();
    onWorkoutEnded?.call();
    await _sessionRepo.cancelSession(id);
  }

  Future<void> _purgeEmptySets() async {
    if (currentWorkoutId == null) return;
    final empty = sets.where((s) => s.reps.isEmpty).toList();
    for (final s in empty) {
      try {
        await _sessionRepo.deleteSet(s.sessionSetId);
      } catch (_) {}
    }
  }


  void _resetActiveWorkoutState() {
    currentWorkoutId = null;
    workoutStartedAt = null;
    _session = null;
    sets = [];
    endNotes = '';
    endFeeling = null;
    exerciseSlots = [];
    activeSlotIndex = 0;
    draftSlotsByExercise = {};
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
        if (existing.isArchived) {
          error = '"$trimmed" already exists.';
          newExCreating = false;
          notifyListeners();
          return null;
        }
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

  /// Variations are shared many-to-many across exercises (via the bridge
  /// table), so a name that already exists is never an error here — it's
  /// silently reused and bridged to [exerciseId] if it isn't already.
  /// [useExistingId] short-circuits straight to that reuse-and-bridge path —
  /// used when the caller already resolved a "did you mean?" pick, so this
  /// doesn't re-run the name lookup.
  Future<String?> submitNewVariation(String name, {required String exerciseId, String? useExistingId}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty && useExistingId == null) return null;
    newVarCreating = true;
    notifyListeners();
    try {
      String id;
      if (useExistingId != null) {
        id = useExistingId;
        final existing = allVariations.firstWhereOrNull((v) => v.variationId == useExistingId);
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
