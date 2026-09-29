import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/powersync/database.dart' as ps;
import '../../../core/utils/name_limit.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/models/planned_session_exercise.dart';
import '../../../data/models/planned_session_exercise_set.dart';
import '../../../data/models/planned_session_program.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/lesson_repository.dart';
import '../../../data/repositories/planned_session_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../session/model/session_local_state.dart'
    show ExerciseHistorySession, groupHistoryByExercise, isSimilarVariationName;

/// One tab in the plan-workout screen — a single exercise group within the
/// workout being planned. Backed by a dim_planned_session_exercise row
/// ([plannedExerciseId]); unlike the session screen there's no superset
/// concept here, so this is deliberately simpler than `SessionExerciseSlot`:
/// one exercise per slot, always.
class PlanExerciseSlot {
  const PlanExerciseSlot({
    required this.exerciseOrder,
    required this.exerciseId,
    this.plannedExerciseId,
  });
  final int exerciseOrder;
  final String exerciseId;

  /// Null for a virtual slot (added this editing session, persisted on
  /// input/Save — never a silent keep-alive stub).
  final String? plannedExerciseId;
}

/// What the editor needs from the program it is editing.
///
/// An interface rather than a reference to `ProgramDetailViewModel`: the
/// editor also runs with no program at all — the Workouts library opens one to
/// edit a standalone workout — and a missing host is what says so. Everything
/// the editor cannot answer by itself is here: the program's identity, and a
/// way to tell the host its list has gone stale.
///
/// The editor never writes the host's state. A workout rename shows up in the
/// program's list because the editor says "the contents changed" and the host
/// re-reads what it owns — one writer per piece of state, even between two
/// objects that always travel together.
abstract interface class WorkoutEditorHost {
  /// The program being edited, or null before it has loaded.
  String? get programId;

  /// The program's join rows. The editor reads the one belonging to the
  /// workout it opened, because day_of_week lives on the link, not the
  /// workout — a workout in two programs has two schedules.
  List<PlannedSessionProgram> get programLinks;

  /// How many workouts the program has, so a new one lands at the end.
  int get workoutCount;

  /// The editor changed the program's contents.
  Future<void> onContentsChanged();
}

class WorkoutEditorState {
  const WorkoutEditorState({
    this.error,
    this.editingWorkout,
    this.workoutNameDraft = '',
    this.workoutNotesDraft = '',
    this.workoutDayOfWeekDraft,
    this.workoutPlannedSessionExerciseSets = const [],
    this.workoutPlannedExercises = const [],
    this.workoutExerciseSlots = const [],
    this.activeSlotIndex = 0,
    this.workoutSetDrafts = const {},
    this.workoutSetsLoading = false,
    this.workoutUnsavedChanges = false,
    // Catalog / create-new (mirrors SessionViewModel)
    this.exerciseDetailMap = const {},
    this.allVariations = const [],
    this.newExCreating = false,
    this.newVarCreating = false,
    // Lessons (per-exercise, cross-session — reuses dim_lesson as-is)
    this.lessonsByExercise = const {},
    // History (read-only past-sets, reuses the session's read path as-is)
    this.historyByExercise = const {},
    this.pastSetsLoaded = false,
  });

  final String? error;

  /// The workout being edited — null until one is opened, which is what the
  /// screen's spinner is waiting on.
  final PlannedSession? editingWorkout;
  final String workoutNameDraft;
  final String workoutNotesDraft;
  final int? workoutDayOfWeekDraft;
  final List<PlannedSessionExerciseSet> workoutPlannedSessionExerciseSets;
  final List<PlannedSessionExercise> workoutPlannedExercises;
  final List<PlanExerciseSlot> workoutExerciseSlots;
  final int activeSlotIndex;
  final Map<String, List<int>> workoutSetDrafts;
  final bool workoutSetsLoading;
  final bool workoutUnsavedChanges;

  /// The editor's own catalog. The program screen keeps a copy too — it needs
  /// one for the goals panel — and the two are deliberately not shared: one
  /// state object per screen means a rebuild of the editor can never be
  /// triggered by, or trigger, the program underneath it.
  final Map<String, ExerciseDetail> exerciseDetailMap;
  final List<CustomVariation> allVariations;
  final bool newExCreating;
  final bool newVarCreating;

  final Map<String, List<Lesson>> lessonsByExercise;
  final Map<String, List<ExerciseHistorySession>> historyByExercise;
  final bool pastSetsLoaded;

  PlanExerciseSlot? get activeSlot => workoutExerciseSlots.isEmpty
      ? null
      : workoutExerciseSlots[activeSlotIndex.clamp(
          0,
          workoutExerciseSlots.length - 1,
        )];

  List<PlannedSessionExerciseSet> plannedSetsFor(String plannedExerciseId) =>
      workoutPlannedSessionExerciseSets
          .where((ps) => ps.plannedExerciseId == plannedExerciseId)
          .toList()
        ..sort((a, b) => a.setNumber.compareTo(b.setNumber));

  WorkoutEditorState copyWith({
    String? error,
    bool clearError = false,
    PlannedSession? editingWorkout,
    bool clearEditingWorkout = false,
    String? workoutNameDraft,
    String? workoutNotesDraft,
    int? workoutDayOfWeekDraft,
    bool clearWorkoutDayOfWeekDraft = false,
    List<PlannedSessionExerciseSet>? workoutPlannedSessionExerciseSets,
    List<PlannedSessionExercise>? workoutPlannedExercises,
    List<PlanExerciseSlot>? workoutExerciseSlots,
    int? activeSlotIndex,
    Map<String, List<int>>? workoutSetDrafts,
    bool? workoutSetsLoading,
    bool? workoutUnsavedChanges,
    Map<String, ExerciseDetail>? exerciseDetailMap,
    List<CustomVariation>? allVariations,
    bool? newExCreating,
    bool? newVarCreating,
    Map<String, List<Lesson>>? lessonsByExercise,
    Map<String, List<ExerciseHistorySession>>? historyByExercise,
    bool? pastSetsLoaded,
  }) => WorkoutEditorState(
    error: clearError ? null : error ?? this.error,
    editingWorkout: clearEditingWorkout
        ? null
        : (editingWorkout ?? this.editingWorkout),
    workoutNameDraft: clearEditingWorkout
        ? ''
        : (workoutNameDraft ?? this.workoutNameDraft),
    workoutNotesDraft: clearEditingWorkout
        ? ''
        : (workoutNotesDraft ?? this.workoutNotesDraft),
    workoutDayOfWeekDraft: clearEditingWorkout || clearWorkoutDayOfWeekDraft
        ? null
        : (workoutDayOfWeekDraft ?? this.workoutDayOfWeekDraft),
    workoutPlannedSessionExerciseSets: clearEditingWorkout
        ? const []
        : (workoutPlannedSessionExerciseSets ??
              this.workoutPlannedSessionExerciseSets),
    workoutPlannedExercises: clearEditingWorkout
        ? const []
        : (workoutPlannedExercises ?? this.workoutPlannedExercises),
    workoutExerciseSlots: clearEditingWorkout
        ? const []
        : (workoutExerciseSlots ?? this.workoutExerciseSlots),
    activeSlotIndex: clearEditingWorkout
        ? 0
        : (activeSlotIndex ?? this.activeSlotIndex),
    workoutSetDrafts: clearEditingWorkout
        ? const {}
        : (workoutSetDrafts ?? this.workoutSetDrafts),
    workoutSetsLoading: clearEditingWorkout
        ? false
        : (workoutSetsLoading ?? this.workoutSetsLoading),
    workoutUnsavedChanges: clearEditingWorkout
        ? false
        : (workoutUnsavedChanges ?? this.workoutUnsavedChanges),
    exerciseDetailMap: exerciseDetailMap ?? this.exerciseDetailMap,
    allVariations: allVariations ?? this.allVariations,
    newExCreating: newExCreating ?? this.newExCreating,
    newVarCreating: newVarCreating ?? this.newVarCreating,
    lessonsByExercise: lessonsByExercise ?? this.lessonsByExercise,
    historyByExercise: historyByExercise ?? this.historyByExercise,
    pastSetsLoaded: pastSetsLoaded ?? this.pastSetsLoaded,
  );
}

/// The planned-workout editor: everything that serves `PlanSessionScreen`.
///
/// Split out of `ProgramDetailViewModel`, which had grown to hold two screens'
/// worth of state. The seam is where it always was — the editor's fields are
/// the ones no program screen reads, and the program's fields are the ones the
/// editor only reaches through [WorkoutEditorHost].
///
/// Everything here is one workout: its header, its exercise tabs, its target
/// rows, and the reference data those need (catalog, variations, lessons,
/// history). Nothing here knows what a program's workout list or its runs look
/// like, which is why [WorkoutEditorHost] can be absent.
class WorkoutEditorViewModel {
  WorkoutEditorViewModel({
    WorkoutEditorHost? host,
    ExerciseRepository? exerciseRepo,
    LessonRepository? lessonRepo,
    SessionRepository? workoutRepo,
    PlannedSessionRepository? workoutPlanRepo,
    String? userId,
  }) : _host = host,
       _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
       _lessonRepo = lessonRepo ?? LessonRepository(),
       _sessionRepo = workoutRepo ?? SessionRepository(),
       _plannedSessionRepo = workoutPlanRepo ?? PlannedSessionRepository(),
       _userIdOverride = userId;

  /// The program being edited, or null when this is a standalone workout.
  ///
  /// This is the whole of "standalone mode": the library opens an editor with
  /// no program behind it, and every program-only affordance (the day-of-week
  /// picker, the link lookup, the parent list refresh) hangs off this being
  /// null. It used to be a separate id field, which had to be re-asserted at
  /// each open and could be left unset — a standalone workout that thought it
  /// was in a program, and offered the day picker accordingly.
  final WorkoutEditorHost? _host;

  final ExerciseRepository _exerciseRepo;
  final LessonRepository _lessonRepo;
  final SessionRepository _sessionRepo;
  final PlannedSessionRepository _plannedSessionRepo;

  /// The owner of everything this editor writes, when the caller knows it.
  ///
  /// Injectable for the same reason the repositories are: the identity
  /// otherwise arrives from `Supabase.instance`, which a host test has no way
  /// to sign in to — and that put the planner screen, where the draft-row
  /// commit contract lives, out of reach of `flutter test` entirely.
  final String? _userIdOverride;

  bool get isStandaloneMode => _host == null;

  /// The join row for the workout being edited (program mode only) — its
  /// day_of_week / week_offset live here, not on the planned session.
  PlannedSessionProgram? _editingLink;

  /// Virtual draft row ids for the workout editor — "+ ADD SET" and new
  /// exercise groups add drafts that materialize on input or explicit Save.
  int _nextDraftId = 1;

  // ── Discard rollback snapshot ─────────────────────────────────────────────
  /// The workout's state at open (or last Save) — groups + sets + header
  /// fields. Discard restores exactly this: sets auto-commit as they're
  /// edited, so without a snapshot "Discard" could never undo them.
  List<PlannedSessionExercise> _openedExercises = const [];
  List<PlannedSessionExerciseSet> _openedSetsSnapshot = const [];
  String? _openedName;
  String? _openedNotes;
  int? _openedDayOfWeek;
  bool _openedExisting = false;
  final state = ValueNotifier(const WorkoutEditorState());

  String get _userId =>
      _userIdOverride ?? Supabase.instance.client.auth.currentUser!.id;

  /// Builds the editor's exercise slots from the persisted group rows.
  List<PlanExerciseSlot> _slotsFromExercises(
    List<PlannedSessionExercise> exercises,
  ) {
    final sorted = [...exercises]
      ..sort((a, b) => a.exerciseOrder.compareTo(b.exerciseOrder));
    return [
      for (final e in sorted)
        PlanExerciseSlot(
          exerciseOrder: e.exerciseOrder,
          exerciseId: e.exerciseId ?? '',
          plannedExerciseId: e.plannedExerciseId,
        ),
    ];
  }

  /// Creates a brand-new planned workout immediately (placeholder name) and
  /// opens it for editing — mirrors how starting a session is a definite
  /// action; there's no separate "draft, unsaved workout" state to manage.
  Future<void> createWorkoutAndOpen() async {
    final host = _host;
    if (host == null) return;
    final programId = host.programId;
    if (programId == null) return;
    state.value = state.value.copyWith(clearError: true);
    await _ensureCatalog();
    try {
      final wp = await _plannedSessionRepo.createPlannedSession(_userId);
      final link = await _plannedSessionRepo.createProgramLink(
        _userId,
        programId: programId,
        plannedSessionId: wp.sessionId,
        sequenceOrder: host.workoutCount + 1,
      );
      _editingLink = link;
      // Created this editing session — Discard rolls back its existence.
      _openedExisting = false;
      _openedExercises = const [];
      _openedSetsSnapshot = const [];
      state.value = state.value.copyWith(
        editingWorkout: wp,
        workoutNameDraft: wp.name,
        workoutNotesDraft: wp.notes ?? '',
        clearWorkoutDayOfWeekDraft: true,
        workoutPlannedExercises: const [],
        workoutPlannedSessionExerciseSets: const [],
        workoutExerciseSlots: const [],
        activeSlotIndex: 0,
      );
      await host.onContentsChanged();
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> openEditWorkout(PlannedSession w) async {
    _editingLink = _linkFor(w.sessionId);
    state.value = state.value.copyWith(
      editingWorkout: w,
      workoutNameDraft: w.name,
      workoutNotesDraft: w.notes ?? '',
      workoutDayOfWeekDraft: _editingLink?.dayOfWeek,
      clearWorkoutDayOfWeekDraft: _editingLink?.dayOfWeek == null,
      workoutSetsLoading: true,
    );
    // The catalog is loaded here rather than inherited from the program
    // screen: the editor owns its own copy, so it must fetch its own.
    await _ensureCatalog();
    try {
      // The planner reads its sets through the same normalizing read the
      // session preview uses, so the two cannot disagree about a template's
      // shape — how many sets a group has, or what order the groups are in.
      final sets = await _plannedSessionRepo.fetchNormalizedPlannedSets(
        w.sessionId,
      );
      final exercises = await _plannedSessionRepo.fetchPlannedExercises(
        w.sessionId,
      );
      _openedExercises = exercises;
      _openedSetsSnapshot = sets;
      _openedName = w.name;
      _openedNotes = w.notes;
      _openedDayOfWeek = _editingLink?.dayOfWeek;
      _openedExisting = true;
      state.value = state.value.copyWith(
        workoutPlannedSessionExerciseSets: sets,
        workoutPlannedExercises: exercises,
        workoutExerciseSlots: _slotsFromExercises(exercises),
        activeSlotIndex: 0,
        workoutSetsLoading: false,
      );
      for (final slot in state.value.workoutExerciseSlots) {
        loadLessonsFor(slot.exerciseId);
      }
    } catch (e) {
      state.value = state.value.copyWith(
        workoutSetsLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Opens a standalone workout for editing (no program). Loads its name,
  /// notes, and planned sets into the editor.
  Future<void> openStandaloneWorkout(String sessionId) async {
    _editingLink = null;
    await _ensureCatalog();
    final workouts = await _plannedSessionRepo.fetchPlannedSessions(_userId);
    final w = workouts.where((x) => x.sessionId == sessionId).firstOrNull;
    if (w == null) {
      // Surfacing the failure keeps the editor from hanging on its loading
      // spinner when a just-created row hasn't synced back yet.
      state.value = state.value.copyWith(
        workoutSetsLoading: false,
        error: 'Could not open workout.',
      );
      return;
    }
    state.value = state.value.copyWith(
      editingWorkout: w,
      workoutNameDraft: w.name,
      workoutNotesDraft: w.notes ?? '',
      clearWorkoutDayOfWeekDraft: true,
      workoutSetsLoading: true,
    );
    try {
      // Same normalizing read as openEditWorkout — the planner and the session
      // preview agree because they read a template the same way.
      final sets = await _plannedSessionRepo.fetchNormalizedPlannedSets(
        sessionId,
      );
      final exercises = await _plannedSessionRepo.fetchPlannedExercises(
        sessionId,
      );
      _openedExercises = exercises;
      _openedSetsSnapshot = sets;
      _openedName = w.name;
      _openedNotes = w.notes;
      _openedDayOfWeek = null;
      _openedExisting = true;
      state.value = state.value.copyWith(
        workoutPlannedSessionExerciseSets: sets,
        workoutPlannedExercises: exercises,
        workoutExerciseSlots: _slotsFromExercises(exercises),
        activeSlotIndex: 0,
        workoutSetsLoading: false,
      );
      for (final slot in state.value.workoutExerciseSlots) {
        loadLessonsFor(slot.exerciseId);
      }
    } catch (e) {
      state.value = state.value.copyWith(
        workoutSetsLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Creates a brand-new standalone workout and opens it for editing.
  Future<void> createStandaloneWorkoutAndOpen() async {
    _editingLink = null;
    state.value = state.value.copyWith(clearError: true);
    await _ensureCatalog();
    try {
      final created = await _plannedSessionRepo.createPlannedSession(_userId);
      _openedExisting = false;
      _openedExercises = const [];
      _openedSetsSnapshot = const [];
      // Open the editor against the row we just created. Building state from
      // the returned object (rather than re-fetching) avoids a race where the
      // insert hasn't reflected into a follow-up SELECT yet — previously that
      // left editingWorkout null and the screen on an eternal spinner.
      state.value = state.value.copyWith(
        editingWorkout: created,
        workoutNameDraft: created.name,
        workoutNotesDraft: created.notes ?? '',
        clearWorkoutDayOfWeekDraft: true,
        workoutPlannedExercises: const [],
        workoutPlannedSessionExerciseSets: const [],
        workoutExerciseSlots: const [],
        activeSlotIndex: 0,
        workoutSetsLoading: false,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  /// Loads the exercise/variation catalog if not already loaded — the editor
  /// needs it to populate the add-exercise picker and the variation rows.
  Future<void> _ensureCatalog() async {
    if (state.value.exerciseDetailMap.isNotEmpty) return;
    try {
      await _reloadCatalog();
    } catch (_) {}
  }

  void markWorkoutDirty() =>
      state.value = state.value.copyWith(workoutUnsavedChanges: true);

  Future<void> saveWorkout() async {
    final s = state.value;
    if (!s.workoutUnsavedChanges) return;
    // A planned workout must contain at least one exercise — never save an
    // empty one.
    if (s.workoutExerciseSlots.isEmpty) {
      state.value = state.value.copyWith(
        error: 'Add at least one exercise to this workout before saving.',
      );
      return;
    }
    await Future.wait([
      commitWorkoutName(),
      commitWorkoutNotes(),
      commitWorkoutDayOfWeek(s.workoutDayOfWeekDraft),
    ]);
    // Flush before the draft pass below. A row the user gave a variation, or a
    // note, but no target holds it in the row until it commits — without this
    // the pass writes an empty row for it and what they entered is dropped.
    await flushPendingCommits();
    // Persist any remaining draft rows as (possibly empty) planned sets —
    // empty sets are valid and an explicit Save is intent.
    final workout = s.editingWorkout;
    if (workout != null) {
      var anyDrafts = false;
      for (final entry in state.value.workoutSetDrafts.entries) {
        final slot = state.value.workoutExerciseSlots
            .where((sl) => sl.plannedExerciseId == entry.key)
            .firstOrNull;
        if (slot == null) continue;
        for (final _ in entry.value) {
          await _persistEmptyPlannedSessionExerciseSet(
            slot.exerciseId,
            slot.plannedExerciseId!,
          );
          anyDrafts = true;
        }
      }
      if (anyDrafts) {
        state.value = state.value.copyWith(workoutSetDrafts: const {});
      }
      // Refresh the rollback snapshot — a later Discard rolls back to this
      // Save, not to open.
      _openedExercises = await _plannedSessionRepo.fetchPlannedExercises(
        workout.sessionId,
      );
      _openedSetsSnapshot = await _plannedSessionRepo.fetchPlannedSets(
        workout.sessionId,
      );
      final savedName = state.value.workoutNameDraft.trim();
      final savedNotes = state.value.workoutNotesDraft.trim();
      _openedName = savedName.isEmpty ? null : savedName;
      _openedNotes = savedNotes.isEmpty ? null : savedNotes;
      _openedDayOfWeek = state.value.workoutDayOfWeekDraft;
      _openedExisting = true;
    }
    state.value = state.value.copyWith(workoutUnsavedChanges: false);
    // The parent screen reads its list from the host's state, and the name and
    // order it shows may have just changed.
    await _host?.onContentsChanged();
  }

  /// Rolls the workout back to its open-time state (or last Save) — header
  /// fields, groups, and sets. Sets auto-commit as they're edited, so without
  /// this pass "Discard" could never undo them. A workout created in this
  /// editing session rolls back to nonexistence.
  Future<void> discardWorkoutChanges() async {
    final w = state.value.editingWorkout;
    if (w == null) return;
    if (!_openedExisting) {
      await deletePlannedSession();
      return;
    }
    try {
      await _plannedSessionRepo.updatePlannedSession(
        w.sessionId,
        name: _openedName,
        notes: _openedNotes,
        clearNotes: _openedNotes == null,
        userId: _userId,
      );
      // Day-of-week lives on the link row — restore its open-time value.
      if (_editingLink != null) {
        await _plannedSessionRepo.updateProgramLink(
          _editingLink!.plannedSessionProgramId,
          dayOfWeek: _openedDayOfWeek,
          clearDayOfWeek: _openedDayOfWeek == null,
        );
      }
      // Groups added since open are discarded; snapshot groups come back.
      final currentExercises = await _plannedSessionRepo.fetchPlannedExercises(
        w.sessionId,
      );
      final snapshotIds = {
        for (final e in _openedExercises) e.plannedExerciseId,
      };
      for (final e in currentExercises) {
        if (!snapshotIds.contains(e.plannedExerciseId)) {
          await _plannedSessionRepo.deletePlannedExercise(e.plannedExerciseId);
        }
      }
      for (final e in _openedExercises) {
        await ps.db.execute(
          'UPDATE dim_planned_session_exercise SET is_archived = 0, exercise_order = ? WHERE planned_exercise_id = ?',
          [e.exerciseOrder, e.plannedExerciseId],
        );
      }
      // Rows added since open are discarded.
      final current = await _plannedSessionRepo.fetchPlannedSets(w.sessionId);
      final snapshotSetIds = {
        for (final s in _openedSetsSnapshot) s.plannedSetId,
      };
      for (final s in current) {
        if (!snapshotSetIds.contains(s.plannedSetId)) {
          await _plannedSessionRepo.deletePlannedSet(s.plannedSetId);
        }
      }
      // Snapshot rows return to their open-time values (any archived during
      // editing come back).
      for (final s in _openedSetsSnapshot) {
        await _plannedSessionRepo.updatePlannedSet(
          s.plannedSetId,
          targetWeight: s.targetWeight,
          clearWeight: s.targetWeight == null,
          targetReps: s.targetReps,
          clearReps: s.targetReps == null,
          variationId: s.variationId,
          clearVariation: s.variationId == null,
          targetNotes: s.targetNotes,
          clearNotes: s.targetNotes == null,
        );
        await ps.db.execute(
          'UPDATE dim_planned_session_exercise_set SET is_archived = 0, set_number = ? WHERE planned_set_id = ?',
          [s.setNumber, s.plannedSetId],
        );
      }
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
    closeWorkoutEditor();
  }

  void closeWorkoutEditor() {
    // Clear editing state SYNCHRONOUSLY — dispose() commits pending
    // name/notes drafts, and a delayed clear would let a discarded draft
    // get written after the guard pops.
    state.value = state.value.copyWith(clearEditingWorkout: true);
    // When closing without saving (discard), still refresh the workout list
    // so that a newly-created-then-discarded workout shows its name correctly
    // and exercises added/removed during editing are reflected.
    _host?.onContentsChanged();
  }

  Future<void> deletePlannedSession() async {
    final w = state.value.editingWorkout;
    if (w == null) return;
    // Archive BEFORE clearing the editor — closeWorkoutEditor's list refetch
    // would otherwise race ahead and keep the deleted workout listed.
    await _plannedSessionRepo.deletePlannedSession(w.sessionId);
    closeWorkoutEditor();
  }

  // ── Session name/notes/day-of-week — auto-commit on blur/change ─────────
  void setWorkoutNameDraft(String v) => state.value = state.value.copyWith(
    workoutNameDraft: v,
    workoutUnsavedChanges: true,
  );
  void setWorkoutNotesDraft(String v) => state.value = state.value.copyWith(
    workoutNotesDraft: v,
    workoutUnsavedChanges: true,
  );

  /// Whether anything is still unsaved after an auto-commit — pending set
  /// drafts, or name/notes/day-of-week drafts that differ from the persisted
  /// workout. Auto-committed fields must clear the dirty flag or the back
  /// guard prompts "Discard/Save" for already-saved data.
  bool _workoutStillDirty(PlannedSession w) {
    if (state.value.workoutSetDrafts.values.any((l) => l.isNotEmpty)) {
      return true;
    }
    if (state.value.workoutNameDraft.trim() != w.name) return true;
    if (state.value.workoutNotesDraft.trim() != (w.notes ?? '')) return true;
    if (state.value.workoutDayOfWeekDraft != _editingLink?.dayOfWeek) {
      return true;
    }
    return false;
  }

  PlannedSession _withEditedWorkout(
    PlannedSession w, {
    String? name,
    String? notes,
  }) => PlannedSession(
    sessionId: w.sessionId,
    userId: w.userId,
    name: name ?? w.name,
    notes: notes ?? w.notes,
    archivedDate: w.archivedDate,
    createdDate: w.createdDate,
  );

  Future<void> commitWorkoutName() async {
    final w = state.value.editingWorkout;
    final name = state.value.workoutNameDraft.trim();
    if (w == null || name.isEmpty || name == w.name) return;
    await _plannedSessionRepo.updatePlannedSession(
      w.sessionId,
      name: name,
      userId: _userId,
    );
    final updated = _withEditedWorkout(w, name: name);
    state.value = state.value.copyWith(
      editingWorkout: updated,
      workoutUnsavedChanges: _workoutStillDirty(updated),
    );
    await _host?.onContentsChanged();
  }

  Future<void> commitWorkoutNotes() async {
    final w = state.value.editingWorkout;
    if (w == null) return;
    final notes = state.value.workoutNotesDraft.trim();
    if (notes == (w.notes ?? '')) return;
    await _plannedSessionRepo.updatePlannedSession(
      w.sessionId,
      notes: notes.isEmpty ? null : notes,
    );
    final updated = _withEditedWorkout(w, notes: notes.isEmpty ? null : notes);
    state.value = state.value.copyWith(
      editingWorkout: updated,
      workoutUnsavedChanges: _workoutStillDirty(updated),
    );
  }

  /// Persists the editing workout's day-of-week onto its program link row
  /// (standalone workouts have no weekday — no link, no-op).
  Future<void> commitWorkoutDayOfWeek(int? v) async {
    final w = state.value.editingWorkout;
    final host = _host;
    if (w == null || host == null) {
      return; // standalone workouts have no weekday
    }
    if (_editingLink == null) {
      // Shouldn't happen for program workouts (links exist for every
      // program session), but create one rather than drop the assignment.
      final programId = host.programId;
      if (programId == null) return;
      final link = await _plannedSessionRepo.createProgramLink(
        _userId,
        programId: programId,
        plannedSessionId: w.sessionId,
        sequenceOrder: host.workoutCount + 1,
      );
      _editingLink = link;
    }
    state.value = v == null
        ? state.value.copyWith(clearWorkoutDayOfWeekDraft: true)
        : state.value.copyWith(workoutDayOfWeekDraft: v);
    await _plannedSessionRepo.updateProgramLink(
      _editingLink!.plannedSessionProgramId,
      dayOfWeek: v,
      clearDayOfWeek: v == null,
    );
  }

  /// The join row for [sessionId] in the host program, if it has one.
  PlannedSessionProgram? _linkFor(String sessionId) {
    for (final l in _host?.programLinks ?? const <PlannedSessionProgram>[]) {
      if (l.plannedSessionId == sessionId) return l;
    }
    return null;
  }

  // ── Exercise tabs ─────────────────────────────────────────────────────────

  /// Display name for an exercise tab. Falls back to the live (FK-joined)
  /// name on the workout's planned sets when the exercise has been archived —
  /// the catalog filters archived rows out of
  /// [WorkoutEditorState.exerciseDetailMap]. Mirrors
  /// `SessionViewModel.exerciseDisplayName`.
  String exerciseDisplayName(String exerciseId) {
    final detail = state.value.exerciseDetailMap[exerciseId];
    if (detail != null) return detail.name;
    for (final set in state.value.workoutPlannedSessionExerciseSets) {
      if (set.exerciseId == exerciseId && set.exerciseName != null) {
        return set.exerciseName!;
      }
    }
    return exerciseId;
  }

  /// If [exerciseId] already has a tab, just switches to it — mirrors
  /// `SessionViewModel.addExerciseSlot`'s duplicate-prevention. Otherwise
  /// persists a new exercise group immediately (like the session's
  /// ensure-on-add) and seeds its virtual draft row — the entry row,
  /// materialized on input or on explicit Save (never as a silent
  /// keep-alive stub).
  Future<void> addPlannedExerciseGroup(String exerciseId) async {
    final s = state.value;
    final workout = s.editingWorkout;
    if (workout == null) return;
    final existingIndex = s.workoutExerciseSlots.indexWhere(
      (slot) => slot.exerciseId == exerciseId,
    );
    if (existingIndex != -1) {
      state.value = s.copyWith(activeSlotIndex: existingIndex);
      return;
    }
    final nextOrder = s.workoutExerciseSlots.isEmpty
        ? 1
        : s.workoutExerciseSlots.map((sl) => sl.exerciseOrder).reduce(
              (a, b) => a > b ? a : b,
            ) +
              1;
    try {
      final group = await _plannedSessionRepo.createPlannedExercise(
        _userId,
        workout.sessionId,
        exerciseId: exerciseId,
        exerciseOrder: nextOrder,
      );
      final slots = [
        ...s.workoutExerciseSlots,
        PlanExerciseSlot(
          exerciseOrder: nextOrder,
          exerciseId: exerciseId,
          plannedExerciseId: group.plannedExerciseId,
        ),
      ];
      final exercises = [...s.workoutPlannedExercises, group];
      final drafts = Map<String, List<int>>.from(s.workoutSetDrafts);
      drafts.putIfAbsent(group.plannedExerciseId, () => []).add(_nextDraftId++);
      state.value = s.copyWith(
        workoutPlannedExercises: exercises,
        workoutExerciseSlots: slots,
        workoutSetDrafts: drafts,
        activeSlotIndex: slots.length - 1,
        workoutUnsavedChanges: true,
      );
      loadLessonsFor(exerciseId);
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  /// Removes the exercise slot at [index] from the editing workout and
  /// archives its group + planned sets.  Active-index is clamped so the tab
  /// bar never points past the new end.
  Future<void> removePlannedExerciseGroup(int index) async {
    final s = state.value;
    final workout = s.editingWorkout;
    if (workout == null ||
        index < 0 ||
        index >= s.workoutExerciseSlots.length) {
      return;
    }
    final slot = s.workoutExerciseSlots[index];
    final plannedExerciseId = slot.plannedExerciseId;

    if (plannedExerciseId != null) {
      await _plannedSessionRepo.deletePlannedExercise(plannedExerciseId);
    }

    // Remove the slot and clamp active index
    final slots = [...s.workoutExerciseSlots]..removeAt(index);
    int newActive = s.activeSlotIndex;
    if (newActive >= slots.length) {
      newActive = (slots.length - 1).clamp(0, slots.length);
    }

    // Re-fetch groups + sets so the UI reflects the deletion
    final exercises = await _plannedSessionRepo.fetchPlannedExercises(
      workout.sessionId,
    );
    final plannedSets = await _plannedSessionRepo.fetchPlannedSets(
      workout.sessionId,
    );

    state.value = s.copyWith(
      workoutPlannedExercises: exercises,
      workoutExerciseSlots: _slotsFromExercises(exercises),
      activeSlotIndex: newActive,
      workoutPlannedSessionExerciseSets: plannedSets,
      workoutUnsavedChanges: true,
    );
  }

  Future<void> tapTab(int index) async {
    // A draft row keeps its variation and notes in the row until it commits
    // (so a keystroke can't materialize one mid-typing), and only the active
    // exercise's card is built — switching would dispose the row before any of
    // it reached the database.
    await flushPendingCommits();
    state.value = state.value.copyWith(activeSlotIndex: index);
  }

  Future<void> reorderExercises(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex || state.value.editingWorkout == null) return;
    final s = state.value;
    final slots = [...s.workoutExerciseSlots];
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
    // Renumber every slot's order 1..N in the new list order —
    // pair-swapping only survives adjacent moves, and a non-adjacent drag
    // would otherwise persist a different order than the one shown.
    final renumbered = [
      for (var i = 0; i < slots.length; i++)
        PlanExerciseSlot(
          exerciseOrder: i + 1,
          exerciseId: slots[i].exerciseId,
          plannedExerciseId: slots[i].plannedExerciseId,
        ),
    ];
    state.value = s.copyWith(
      workoutExerciseSlots: renumbered,
      activeSlotIndex: newActive,
    );
    final wid = s.editingWorkout!.sessionId;
    await _plannedSessionRepo.renumberExerciseOrders(wid, [
      for (var i = 0; i < slots.length; i++) (slots[i].exerciseOrder, i),
    ]);
    final exercises = await _plannedSessionRepo.fetchPlannedExercises(wid);
    final sets = await _plannedSessionRepo.fetchPlannedSets(wid);
    state.value = state.value.copyWith(
      workoutPlannedExercises: exercises,
      workoutExerciseSlots: _slotsFromExercises(exercises),
      workoutPlannedSessionExerciseSets: sets,
    );
  }

  // ── Draft (unsaved) planned-set rows ──────────────────────────────────────

  /// Persists an empty planned set row so an exercise added to a planned
  /// workout survives a save/reopen even before any target is entered.
  Future<void> _persistEmptyPlannedSessionExerciseSet(
    String exerciseId,
    String plannedExerciseId,
  ) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    final existing = state.value.plannedSetsFor(plannedExerciseId);
    final setNumber = existing.isEmpty
        ? 1
        : existing.map((ps) => ps.setNumber).reduce((a, b) => a > b ? a : b) +
              1;
    try {
      await _plannedSessionRepo.createPlannedSet(
        _userId,
        plannedExerciseId,
        plannedSessionId: workout.sessionId,
        exerciseId: exerciseId,
        setNumber: setNumber,
      );
      final sets = await _plannedSessionRepo.fetchPlannedSets(
        workout.sessionId,
      );
      state.value = state.value.copyWith(
        workoutPlannedSessionExerciseSets: sets,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  void addDraftPlannedSessionExerciseSet(String plannedExerciseId) {
    // "+ ADD SET" adds a virtual draft row — visible immediately and a REAL
    // change (marks the editor dirty, so the guard prompts on back and the
    // Save button appears). The draft materializes as a row on input, or as
    // an empty row on explicit Save (empty sets are valid).
    final drafts = Map<String, List<int>>.from(state.value.workoutSetDrafts);
    drafts.putIfAbsent(plannedExerciseId, () => []).add(_nextDraftId++);
    state.value = state.value.copyWith(
      workoutSetDrafts: drafts,
      workoutUnsavedChanges: true,
    );
  }

  void removeDraftPlannedSessionExerciseSet(
    String plannedExerciseId,
    int draftId,
  ) {
    final drafts = Map<String, List<int>>.from(state.value.workoutSetDrafts);
    drafts[plannedExerciseId]?.remove(draftId);
    state.value = state.value.copyWith(
      workoutSetDrafts: drafts,
      workoutUnsavedChanges: true,
    );
  }

  // ── Pending-edit flush ─────────────────────────────────────────────────────

  /// Rows register their commit closure so the editor can flush in-flight edits
  /// when a row is about to be destroyed — an exercise switch, a Save, the app
  /// going to the background. A draft row holds its variation and notes
  /// row-locally until it commits, deliberately (a keystroke must not
  /// materialize one mid-typing), so without a flush the only way they reach
  /// the database is a blur the user may never cause: pick a variation on an
  /// otherwise empty draft, leave the card, and it was gone.
  ///
  /// Same contract as the live session's; the planner is what was missing it.
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

  Future<bool> quickCreatePlannedSessionExerciseSet({
    required String exerciseId,
    required String plannedExerciseId,
    required int draftId,
    String? variationId,
    String? weight,
    String? reps,
    String? notes,
  }) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return false;
    // Empty planned sets are valid — a planned workout may list sets with no
    // target weight/reps yet (they show as blank rows, filled during the
    // session).
    final existing = state.value.plannedSetsFor(plannedExerciseId);
    final setNumber = existing.isEmpty
        ? 1
        : existing.map((ps) => ps.setNumber).reduce((a, b) => a > b ? a : b) +
              1;
    try {
      await _plannedSessionRepo.createPlannedSet(
        _userId,
        plannedExerciseId,
        plannedSessionId: workout.sessionId,
        exerciseId: exerciseId,
        variationId: variationId,
        setNumber: setNumber,
        targetWeight: weight,
        targetReps: reps,
        targetNotes: notes,
      );
      removeDraftPlannedSessionExerciseSet(plannedExerciseId, draftId);
      final sets = await _plannedSessionRepo.fetchPlannedSets(
        workout.sessionId,
      );
      state.value = state.value.copyWith(
        workoutPlannedSessionExerciseSets: sets,
      );
      return true;
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
      return false;
    }
  }

  Future<void> quickUpdatePlannedSessionExerciseSet(
    PlannedSessionExerciseSet ps, {
    String? weight,
    bool clearWeight = false,
    String? reps,
    bool clearReps = false,
    String? variationId,
    bool clearVariation = false,
    String? notes,
    bool clearNotes = false,
  }) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    try {
      await _plannedSessionRepo.updatePlannedSet(
        ps.plannedSetId,
        targetWeight: weight,
        clearWeight: clearWeight,
        targetReps: reps,
        clearReps: clearReps,
        variationId: variationId,
        clearVariation: clearVariation,
        targetNotes: notes,
        clearNotes: clearNotes,
      );
      final sets = await _plannedSessionRepo.fetchPlannedSets(
        workout.sessionId,
      );
      state.value = state.value.copyWith(
        workoutPlannedSessionExerciseSets: sets,
        workoutUnsavedChanges: true,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> duplicatePlannedSessionExerciseSet(
    PlannedSessionExerciseSet ps,
  ) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    final exerciseId = ps.exerciseId ?? '';
    final existing = state.value.plannedSetsFor(ps.plannedExerciseId);
    final setNumber =
        existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    try {
      await _plannedSessionRepo.createPlannedSet(
        _userId,
        ps.plannedExerciseId,
        plannedSessionId: workout.sessionId,
        exerciseId: exerciseId,
        variationId: ps.variationId,
        setNumber: setNumber,
        targetWeight: ps.targetWeight,
        targetReps: ps.targetReps,
        targetNotes: ps.targetNotes,
      );
      final sets = await _plannedSessionRepo.fetchPlannedSets(
        workout.sessionId,
      );
      state.value = state.value.copyWith(
        workoutPlannedSessionExerciseSets: sets,
        workoutUnsavedChanges: true,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  Future<void> deletePlannedSessionExerciseSet(String setId) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    await _plannedSessionRepo.deletePlannedSet(setId);
    final sets = await _plannedSessionRepo.fetchPlannedSets(workout.sessionId);
    state.value = state.value.copyWith(
      workoutPlannedSessionExerciseSets: sets,
      workoutUnsavedChanges: true,
    );
  }

  // ── New exercise / variation (mirrors SessionViewModel) ───────────────────

  List<({String id, String name, int exerciseCount})> findSimilarVariations(
    String name,
  ) {
    // Variations are a flat library (no exercise assignment since schema v2) —
    // "used in N exercises" is derived from history, so make sure it's loaded
    // (the label refreshes when the notify lands).
    if (!state.value.pastSetsLoaded) loadHistoryIfNeeded();
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

  // ── Lessons (per-exercise, cross-session — same dim_lesson data session uses) ──

  /// All active variations, most recently used first — the set-row picker
  /// order. Variations are a flat library (shared across ALL of a user's
  /// exercises since schema v2).
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

  // ── History (read-only past sets, for reference while planning) ──────────

  List<ExerciseHistorySession> historyFor(String exerciseId) =>
      state.value.historyByExercise[exerciseId] ?? const [];

  Future<void> loadHistoryIfNeeded() async {
    if (state.value.pastSetsLoaded) return;
    try {
      final pastSets = await _sessionRepo.loadPastSetsTimeline(_userId);
      state.value = state.value.copyWith(
        historyByExercise: groupHistoryByExercise(pastSets),
        pastSetsLoaded: true,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: e.toString());
    }
  }

  void dispose() {
    state.dispose();
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
