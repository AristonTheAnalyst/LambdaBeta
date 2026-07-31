import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/workout_format.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/planned_set.dart';
import '../../../data/models/program_progress.dart';
import '../../../data/models/workout_set.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/program_run_repository.dart';
import '../../../data/repositories/rest_period_repository.dart';
import '../../../data/repositories/workout_repository.dart';
import '../../../shared/widgets/slide_pages.dart';
import '../model/session_local_state.dart';

const restDefaultSeconds = 90;
const restPresets = [60, 90, 120, 180];

class SessionViewModel extends ChangeNotifier {
  SessionViewModel({
    WorkoutRepository? workoutRepo,
    ExerciseRepository? exerciseRepo,
    ProgramRepository? programRepo,
    ProgramRunRepository? programRunRepo,
    LessonRepository? lessonRepo,
    RestPeriodRepository? restPeriodRepo,
  })  : _workoutRepo = workoutRepo ?? WorkoutRepository(),
        _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
        _programRepo = programRepo ?? ProgramRepository(),
        _programRunRepo = programRunRepo ?? ProgramRunRepository(),
        _lessonRepo = lessonRepo ?? LessonRepository(),
        _restPeriodRepo = restPeriodRepo ?? RestPeriodRepository() {
    slidePagesController = SlidePagesController();
    _init();
  }

  final WorkoutRepository _workoutRepo;
  final ExerciseRepository _exerciseRepo;
  final ProgramRepository _programRepo;
  final ProgramRunRepository _programRunRepo;
  final LessonRepository _lessonRepo;
  final RestPeriodRepository _restPeriodRepo;
  late final SlidePagesController slidePagesController;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  // ── Startup ─────────────────────────────────────────────────────────────────
  bool initLoading = true;

  // ── Workout state ──────────────────────────────────────────────────────────
  /// Called when the workout fully ends (endWorkout or cancelWorkout) so the
  /// session screen can clear its static cache and create a fresh VM next time.
  VoidCallback? onWorkoutEnded;
  String? currentWorkoutId;
  DateTime? workoutStartedAt;
  List<WorkoutSet> sets = [];
  bool setsLoading = false;

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
  Map<String, List<PlannedSet>> plannedSetsByExercise = {};
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
  Map<String, List<ExerciseHistorySession>> historyByExercise = {};
  Map<String, ({num weight, num reps})?> prevBestByExercise = {};

  // ── Historical set editing ─────────────────────────────────────────────────
  bool historyEditConfirmed = false;

  void confirmHistoryEdit() {
    historyEditConfirmed = true;
    notifyListeners();
  }

  // ── Rest timer ─────────────────────────────────────────────────────────────
  int? restRemaining;
  int restTotal = restDefaultSeconds;
  bool restRunning = false;
  Timer? _restTimer;
  List<int> restDurationsThisSession = [];
  String? _restExerciseId;

  // ── Derived ───────────────────────────────────────────────────────────────
  bool get hasActiveWorkout => currentWorkoutId != null;

  int get distinctExerciseCount => sets.map((s) => s.exerciseId).toSet().length;

  int get totalPRsThisSession =>
      sets.where((s) => isPr(s, prevBestByExercise[s.exerciseId])).length;

  double? get avgRestSeconds => restDurationsThisSession.isEmpty
      ? null
      : restDurationsThisSession.reduce((a, b) => a + b) /
          restDurationsThisSession.length;

  List<({String exercise, num? weight, num? reps})> get prsThisSession => sets
      .where((s) => isPr(s, prevBestByExercise[s.exerciseId]))
      .map((s) => (
            exercise: toProperCase(exerciseDetailMap[s.exerciseId]?.name ?? ''),
            weight: s.weight,
            reps: s.reps.isNotEmpty ? s.reps.first : (s.duration.isNotEmpty ? s.duration.first : null),
          ))
      .toList();

  Future<void> _init() async {
    // Each stage is individually guarded so one transient failure (e.g.
    // PowerSync not synced on cold start) doesn't block the others.
    // In particular, _restoreActiveWorkout must run even if catalog fetch
    // fails, otherwise the active workout is invisible after a hot restart.
    try {
      await _loadCatalog();
    } catch (_) {}
    try {
      await Future.wait([_loadPlannedWorkout(), _loadPastSets()]);
    } catch (_) {}
    try {
      await _restoreActiveWorkout();
    } catch (_) {}
    initLoading = false;
    notifyListeners();
  }

  Future<void> _loadCatalog() async {
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

  Future<void> _loadPlannedWorkout() async {
    try {
      programProgress = await _programRunRepo.getProgress(_userId);
      final pw = programProgress?.nextPlannedWorkout;
      if (pw != null) {
        final plannedSets = await _programRepo.fetchPlannedSets(pw.plannedWorkoutId);
        final sorted = [...plannedSets]
          ..sort((a, b) => a.exerciseSequenceOrder.compareTo(b.exerciseSequenceOrder));
        final byExercise = <String, List<PlannedSet>>{};
        final order = <String>[];
        for (final p in sorted) {
          if (!byExercise.containsKey(p.exerciseId)) order.add(p.exerciseId);
          byExercise.putIfAbsent(p.exerciseId, () => []).add(p);
        }
        plannedSetsByExercise = byExercise;
        plannedExerciseOrder = order;
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _loadPastSets() async {
    try {
      _pastSets = await _workoutRepo.loadPastSetsTimeline(_userId);
      historyByExercise = groupHistoryByExercise(_pastSets);
      final byExercise = <String, List<PastSetRow>>{};
      for (final s in _pastSets) {
        byExercise.putIfAbsent(s.exerciseId, () => []).add(s);
      }
      prevBestByExercise = byExercise.map(
          (exerciseId, sets) => MapEntry(exerciseId, bestEverForExercise(sets)));
    } catch (_) {}
    pastSetsLoaded = true;
    notifyListeners();
  }

  Future<void> _restoreActiveWorkout() async {
    final activeId = await _workoutRepo.getActiveWorkoutId(_userId);
    if (activeId != null) {
      currentWorkoutId = activeId;
      final workout = await _workoutRepo.fetchWorkout(activeId);
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
    sets = await _workoutRepo.loadSetsForWorkout(currentWorkoutId!);
    setsLoading = false;
    notifyListeners();
  }

  // ── Exercise tabs ──────────────────────────────────────────────────────────

  void _seedExerciseSlots() {
    final seen = <String>{};
    final slots = <SessionExerciseSlot>[];
    for (final exId in plannedExerciseOrder) {
      if (seen.add(exId)) {
        slots.add(SessionExerciseSlot(
            id: _nextSlotId++, type: SessionSlotType.single, exerciseIds: [exId], planned: true));
        draftSlotsByExercise.putIfAbsent(exId, () => [_nextDraftId++]);
        loadLessonsFor(exId);
      }
    }
    for (final s in sets) {
      if (seen.add(s.exerciseId)) {
        slots.add(SessionExerciseSlot(
            id: _nextSlotId++, type: SessionSlotType.single, exerciseIds: [s.exerciseId], planned: false));
        draftSlotsByExercise.putIfAbsent(s.exerciseId, () => [_nextDraftId++]);
        loadLessonsFor(s.exerciseId);
      }
    }
    exerciseSlots = slots;
    activeSlotIndex = 0;
    notifyListeners();
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
    notifyListeners();
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
    draftSlotsByExercise.putIfAbsent(exerciseId, () => [_nextDraftId++]);
    loadLessonsFor(exerciseId);
    activeSlotIndex = exerciseSlots.length - 1;
    notifyListeners();
    return true;
  }

  void addSupersetSlot(List<String> exerciseIds) {
    exerciseSlots.add(SessionExerciseSlot(
        id: _nextSlotId++, type: SessionSlotType.superset, exerciseIds: exerciseIds));
    for (final id in exerciseIds) {
      draftSlotsByExercise.putIfAbsent(id, () => [_nextDraftId++]);
      loadLessonsFor(id);
    }
    activeSlotIndex = exerciseSlots.length - 1;
    notifyListeners();
  }

  /// The superset group to stamp onto a newly logged set for [exerciseId] —
  /// the containing slot's id if it's a superset tab, else null (a plain
  /// single-exercise slot is never "part of a superset"). This is the only
  /// place a superset's grouping survives past the in-memory session state:
  /// once stamped onto `fact_workout_set.superset_group_number` it's
  /// queryable/excludable in analytics even after the session ends.
  int? _supersetGroupFor(String exerciseId) {
    final slot = exerciseSlots.firstWhereOrNull(
        (s) => s.type == SessionSlotType.superset && s.exerciseIds.contains(exerciseId));
    return slot?.id;
  }

  // ── Draft set rows ─────────────────────────────────────────────────────────

  /// Tapping "+ ADD SET" pre-creates an empty set in the DB so it survives
  /// hot restarts. Empty sets are purged on endWorkout.
  void addDraftSet(String exerciseId) {
    if (currentWorkoutId == null) return;
    final nextNum = sets.isEmpty
        ? 1
        : sets.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    _workoutRepo.insertSet(
      workoutId: currentWorkoutId!,
      exerciseId: exerciseId,
      setNumber: nextNum,
      weight: null,
      reps: [],
      duration: [],
      supersetGroupNumber: _supersetGroupFor(exerciseId),
    ).then((newSet) {
      sets.add(newSet);
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
    required List<num> duration,
    String? notes,
  }) async {
    if (currentWorkoutId == null) return false;
    if (reps.isEmpty && duration.isEmpty) return false;
    final nextNum = sets.isEmpty
        ? 1
        : sets.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    // Find an empty pre-created set for this exercise to fill in
    final emptyIdx = sets.lastIndexWhere(
      (s) => s.exerciseId == exerciseId && s.reps.isEmpty && s.duration.isEmpty);
    try {
      if (emptyIdx >= 0) {
        await _workoutRepo.updateSet(
          sets[emptyIdx].setId,
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
          workoutId: currentWorkoutId!,
          exerciseId: exerciseId,
          variationId: variationId,
          setNumber: nextNum,
          weight: weight,
          reps: reps,
          duration: duration,
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
    WorkoutSet set, {
    double? weight,
    bool clearWeight = false,
    List<num>? reps,
    List<num>? duration,
    String? variationId,
    bool clearVariation = false,
    String? notes,
    bool clearNotes = false,
  }) async {
    try {
      await _workoutRepo.updateSet(
        set.setId,
        weight: weight,
        clearWeight: clearWeight,
        reps: reps,
        duration: duration,
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
      await _workoutRepo.updateSet(
        set.setId,
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
    await _workoutRepo.deleteSet(setId);
    await _loadSets();
  }

  /// Inserts a new set copying [set]'s weight/reps/variation/notes — the
  /// grid row's swipe-action "Duplicate" button.
  Future<void> duplicateSet(WorkoutSet set) async {
    if (currentWorkoutId == null) return;
    final nextNum = sets.isEmpty
        ? 1
        : sets.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    try {
      await _workoutRepo.insertSet(
        workoutId: currentWorkoutId!,
        exerciseId: set.exerciseId,
        variationId: set.variationId,
        setNumber: nextNum,
        weight: set.weight,
        reps: set.reps,
        duration: set.duration,
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
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> addLesson(String exerciseId, String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _lessonRepo.createLesson(_userId, exerciseId, text.trim());
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
      await _lessonRepo.toggleLessonPin(lessonId, !lesson.pinned);
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

  ({num weight, num reps})? prevBestFor(String exerciseId) =>
      prevBestByExercise[exerciseId];

  int prCountFor(String exerciseId) => sets
      .where((s) => s.exerciseId == exerciseId && isPr(s, prevBestFor(exerciseId)))
      .length;

  // ── Rest timer ─────────────────────────────────────────────────────────────
  // Every rest period is logged to fact_rest as its own event
  // (planned vs. actual seconds) once it ends — whether it completes
  // naturally, is stopped early, or is discarded via Restart. Pausing alone
  // never logs, since the rest is still in progress.

  void startRest(int seconds) {
    if (seconds <= 0) return;
    _restTimer?.cancel();
    restTotal = seconds;
    restRemaining = seconds;
    restRunning = true;
    _restExerciseId = activeSlot?.activeExerciseId;
    _tickRest();
    notifyListeners();
  }

  void pauseRest() {
    _restTimer?.cancel();
    restRunning = false;
    notifyListeners();
  }

  void resumeRest() {
    if (restRemaining == null || restRemaining == 0) return;
    restRunning = true;
    _tickRest();
    notifyListeners();
  }

  Future<void> restartRest() async {
    await _logRestIfInProgress();
    startRest(restTotal);
  }

  /// Explicit "End" — stops the timer and, if it was cut short, logs the
  /// partial rest. A naturally-completed rest is already logged by
  /// `_tickRest`, so `_logRestIfInProgress` is a no-op in that case.
  Future<void> endRest() async {
    await _logRestIfInProgress();
    _stopRestTimer();
    notifyListeners();
  }

  /// Cancels the ticking timer and clears rest state without logging —
  /// used when the whole workout is being torn down (`cancelWorkout`), where
  /// the workout row (and any of its rest_period rows) is about to be
  /// deleted, so logging here would just create instantly-orphaned data.
  void _stopRestTimer() {
    _restTimer?.cancel();
    restRemaining = null;
    restRunning = false;
    _restExerciseId = null;
  }

  Future<void> _logRestIfInProgress() async {
    final remaining = restRemaining;
    final workoutId = currentWorkoutId;
    if (workoutId == null || remaining == null || remaining <= 0) return;
    try {
      await _restPeriodRepo.logRestPeriod(
        _userId,
        workoutId,
        exerciseId: _restExerciseId,
        plannedSeconds: restTotal,
        actualSeconds: restTotal - remaining,
      );
    } catch (_) {}
  }

  void _tickRest() {
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      final r = restRemaining;
      if (r == null || r <= 1) {
        t.cancel();
        restRunning = false;
        restRemaining = 0;
        restDurationsThisSession.add(restTotal);
        final workoutId = currentWorkoutId;
        if (workoutId != null) {
          try {
            await _restPeriodRepo.logRestPeriod(
              _userId,
              workoutId,
              exerciseId: _restExerciseId,
              plannedSeconds: restTotal,
              actualSeconds: restTotal,
            );
          } catch (_) {}
        }
      } else {
        restRemaining = r - 1;
      }
      notifyListeners();
    });
  }

  // ── Start / end / cancel workout ──────────────────────────────────────────

  Future<void> startWorkout() async {
    startLoading = true;
    error = null;
    notifyListeners();
    try {
      final id = await _workoutRepo.createWorkout(
        _userId,
        preNotes: startNotes.trim().isEmpty ? null : startNotes.trim(),
        programId: programProgress?.program.programId,
        programRunId: programProgress?.run.programRunId,
        plannedWorkoutId: programProgress?.nextPlannedWorkout?.plannedWorkoutId,
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

  Future<void> endWorkout() async {
    if (currentWorkoutId == null) return;
    endLoading = true;
    notifyListeners();
    try {
      // A rest still in progress when the workout ends is a real, meaningful
      // partial rest (unlike cancelWorkout, this workout isn't being
      // deleted) — log it before resetting state.
      await _logRestIfInProgress();
      await _purgeEmptySets();
      await _workoutRepo.endWorkout(
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

  Future<void> cancelWorkout() async {
    if (currentWorkoutId == null) return;
    final id = currentWorkoutId!;
    _resetActiveWorkoutState();
    slidePagesController.slideOut();
    notifyListeners();
    onWorkoutEnded?.call();
    await _workoutRepo.cancelWorkout(id);
  }

  Future<void> _purgeEmptySets() async {
    if (currentWorkoutId == null) return;
    final empty = sets.where((s) => s.reps.isEmpty && s.duration.isEmpty).toList();
    for (final s in empty) {
      try {
        await _workoutRepo.deleteSet(s.setId);
      } catch (_) {}
    }
  }

  void _resetActiveWorkoutState() {
    currentWorkoutId = null;
    workoutStartedAt = null;
    sets = [];
    endNotes = '';
    endFeeling = null;
    exerciseSlots = [];
    activeSlotIndex = 0;
    draftSlotsByExercise = {};
    // lessonsByExercise is intentionally NOT cleared — lessons are durable,
    // cross-session data now, not reset per workout.
    restDurationsThisSession = [];
    historyEditConfirmed = false;
    _stopRestTimer();
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
        if (existing.isActive) {
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
      await _loadCatalog();
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
      await _loadCatalog();
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
    _restTimer?.cancel();
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
