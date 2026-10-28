import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/undo_history.dart';
import '../../../core/utils/name_limit.dart';
import '../../../data/models/custom_variation.dart';
import '../../../data/models/exercise_detail.dart';
import '../../../data/models/exercise_usage.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/exercise_note.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/models/planned_session_exercise.dart';
import '../../../data/models/planned_session_exercise_set.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/exercise_note_repository.dart';
import '../../../data/repositories/planned_session_repository.dart';
import '../../../data/repositories/planned_session_store.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/session_repository.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../programs/model/program_achievements.dart' show goalCompletionSet;
import '../../session/model/pr_engine.dart' show PrEvent, prEvents;
import '../../session/model/session_local_state.dart'
    show ExerciseHistorySession, groupHistoryByExercise, isSimilarVariationName;

const _uuid = Uuid();

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
    this.deleted = false,
  });
  final int exerciseOrder;
  final String exerciseId;

  /// Null for a virtual slot (added this editing session, persisted on
  /// input/Save — never a silent keep-alive stub).
  final String? plannedExerciseId;

  /// The group is archived — removed from the workout. Only an editor opened
  /// [includeArchived] sees one at all: inside a review a removal stays on the
  /// card, red, so its note can explain it (2026-10-26).
  final bool deleted;
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
    // Notes (per-exercise, cross-session — reuses dim_exercise_note as-is)
    this.notesByExercise = const {},
    // History (read-only past-sets, reuses the session's read path as-is)
    this.historyByExercise = const {},
    this.allPrEvents = const [],
    this.goalTimeline = const [],
    this.pastSetsLoaded = false,
    // Goals (the owner's own, cross-session — the floor's bullseye)
    this.goals = const [],
  });

  final String? error;

  /// The workout being edited — null until one is opened, which is what the
  /// screen's spinner is waiting on.
  final PlannedSession? editingWorkout;
  final String workoutNameDraft;
  final String workoutNotesDraft;
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

  final Map<String, List<ExerciseNote>> notesByExercise;
  final Map<String, List<ExerciseHistorySession>> historyByExercise;

  /// Every PR the user has ever landed, derived once at the same read that
  /// fills [historyByExercise] (2026-10-26) — the planner's floor shows an
  /// exercise's whole PR shelf, so it needs the feed, not the timeline. The
  /// engine sorts internally, so the timeline's newest-first order is fine.
  final List<PrEvent> allPrEvents;

  /// The same past-sets timeline, undivided — the goal sheet's "already beat
  /// this" check and the bullseye's completion rule read sets, not grouped
  /// history (2026-10-27).
  final List<PastSetRow> goalTimeline;

  final bool pastSetsLoaded;

  /// The owner's goals, any scope — the floor's bullseye (2026-10-27). Same
  /// read the session VMs take; a failed goal read leaves the bullseye at 0
  /// rather than taking the planner down with it.
  final List<Goal> goals;

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
    Map<String, List<ExerciseNote>>? notesByExercise,
    Map<String, List<ExerciseHistorySession>>? historyByExercise,
    List<PrEvent>? allPrEvents,
    List<PastSetRow>? goalTimeline,
    List<Goal>? goals,
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
    notesByExercise: notesByExercise ?? this.notesByExercise,
    historyByExercise: historyByExercise ?? this.historyByExercise,
    allPrEvents: allPrEvents ?? this.allPrEvents,
    goalTimeline: goalTimeline ?? this.goalTimeline,
    goals: goals ?? this.goals,
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
/// rows, and the reference data those need (catalog, variations, notes,
/// history). Nothing here knows what a program's workout list or its runs look
/// like, which is why [WorkoutEditorHost] can be absent.
class WorkoutEditorViewModel {
  WorkoutEditorViewModel({
    WorkoutEditorHost? host,
    ExerciseRepository? exerciseRepo,
    ExerciseNoteRepository? noteRepo,
    SessionRepository? workoutRepo,
    PlannedSessionStore? workoutPlanRepo,
    ProgramRepository? programRepo,
    String? userId,
    bool canDelete = true,
  }) : _canDelete = canDelete,
       _host = host,
       _exerciseRepo = exerciseRepo ?? ExerciseRepository(),
       _noteRepo = noteRepo ?? ExerciseNoteRepository(),
       _sessionRepo = workoutRepo ?? SessionRepository(),
       _plannedSessionRepo = workoutPlanRepo ?? PlannedSessionRepository(),
       _programRepo = programRepo ?? ProgramRepository(),
       _userIdOverride = userId;

  /// The program being edited, or null when this is a standalone workout.
  ///
  /// This is the whole of "standalone mode": the library opens an editor with
  /// no program behind it, and every program-only affordance (the link write
  /// on create, the parent list refresh) hangs off this being null. It used to
  /// be a separate id field, which had to be re-asserted at each open and could
  /// be left unset — a standalone workout that thought it was in a program.
  final WorkoutEditorHost? _host;

  final ExerciseRepository _exerciseRepo;
  final ExerciseNoteRepository _noteRepo;
  final SessionRepository _sessionRepo;
  final PlannedSessionStore _plannedSessionRepo;
  final ProgramRepository _programRepo;

  /// The owner of everything this editor writes, when the caller knows it.
  ///
  /// Injectable for the same reason the repositories are: the identity
  /// otherwise arrives from `Supabase.instance`, which a host test has no way
  /// to sign in to — and that put the planner screen, where the draft-row
  /// commit contract lives, out of reach of `flutter test` entirely.
  final String? _userIdOverride;

  /// Coach mode never deletes (2026-10-28). False makes every removal a no-op
  /// — group, set, draft and the discard rollback — so no DELETE reaches the
  /// uploader (the server would refuse it and quarantine the op).
  final bool _canDelete;

  bool get canDelete => _canDelete;

  /// Whose rows this editor writes — the athlete's in coach mode, the
  /// signed-in user's otherwise. The review bar reads it for its owner
  /// (2026-10-28).
  String get userId => _userId;

  bool get isStandaloneMode => _host == null;

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
  bool _openedExisting = false;

  /// Whether this editor reads the workout with its removals in it — true
  /// inside a review (2026-10-26). A group removed during the pass stays on
  /// the card, red, so the note can say why it went; outside a review the
  /// planner keeps hiding every archived group, as it always has.
  bool _includeArchived = false;

  /// Group ids that were ALREADY archived when the editor opened.
  ///
  /// A review's read brings back every archived group, which is what keeps a
  /// removal made DURING the pass on the card. A group removed before the
  /// pass began is not this pass's change: it stays hidden exactly as it is
  /// outside a review, or every old removal would resurface red on every
  /// later pass (2026-10-26 — a Back Squat removed months earlier came back
  /// on a workout that no longer contained it).
  Set<String> _archivedAtOpen = const {};

  /// The card's groups — the raw read, less the removals that predate it.
  List<PlannedSessionExercise> _visibleGroups(
    List<PlannedSessionExercise> groups,
  ) => _archivedAtOpen.isEmpty
      ? groups
      : [
          for (final g in groups)
            if (!g.isArchived || !_archivedAtOpen.contains(g.plannedExerciseId))
              g,
        ];

  /// The card's rows — a pre-archived group's sets go with it.
  List<PlannedSessionExerciseSet> _visibleSets(
    List<PlannedSessionExerciseSet> sets,
  ) => _archivedAtOpen.isEmpty
      ? sets
      : [
          for (final s in sets)
            if (!_archivedAtOpen.contains(s.plannedExerciseId)) s,
        ];

  final state = ValueNotifier(const WorkoutEditorState());

  String get _userId =>
      _userIdOverride ?? Supabase.instance.client.auth.currentUser!.id;

  /// The raw read: archived groups included when a review asked for them.
  Future<List<PlannedSessionExercise>> _readGroupsRaw(String sessionId) =>
      _plannedSessionRepo.fetchPlannedExercises(
        sessionId,
        includeArchived: _includeArchived,
      );

  /// The editor's own read of a template's exercise groups — the one place
  /// [_archivedAtOpen] is spent, so every re-read agrees about what the
  /// workout holds.
  Future<List<PlannedSessionExercise>> _readGroups(String sessionId) async =>
      _visibleGroups(await _readGroupsRaw(sessionId));

  /// The editor's own read of a template's sets. Inside a review it goes
  /// through the normalizing read so a removed group's rows come back
  /// numbered as they were, while a set removed on its own still drops.
  Future<List<PlannedSessionExerciseSet>> _readSets(String sessionId) async {
    if (!_includeArchived) {
      return _plannedSessionRepo.fetchPlannedSets(sessionId);
    }
    return _visibleSets(
      await _plannedSessionRepo.readNormalizedPlannedSession(
        sessionId,
        includeArchived: true,
      ),
    );
  }

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
          deleted: e.isArchived,
        ),
    ];
  }

  /// Creates a brand-new planned workout immediately (placeholder name) and
  /// opens it for editing — mirrors how starting a session is a definite
  /// action; there's no separate "draft, unsaved workout" state to manage.
  ///
  /// [blockId] files the new workout into a block as it is linked, which is
  /// how one is made from inside a block. The link is created with the block
  /// already on it rather than assigned afterwards: a blocked program has no
  /// Workouts tab, so a row that spent even a moment unfiled would be a row
  /// with nowhere to be seen — and a caller that assigned it later would have
  /// to guess which row appeared.
  Future<void> createWorkoutAndOpen({String? blockId}) async {
    final host = _host;
    if (host == null) return;
    final programId = host.programId;
    if (programId == null) return;
    state.value = state.value.copyWith(clearError: true);
    await _ensureCatalog();
    try {
      final wp = await _plannedSessionRepo.createPlannedSession(_userId);
      await _plannedSessionRepo.createProgramLink(
        _userId,
        programId: programId,
        plannedSessionId: wp.sessionId,
        sequenceOrder: host.workoutCount + 1,
        blockId: blockId,
      );
      // Created this editing session — Discard rolls back its existence.
      _openedExisting = false;
      _openedExercises = const [];
      _openedSetsSnapshot = const [];
      _includeArchived = false;
      _archivedAtOpen = const {};
      state.value = state.value.copyWith(
        editingWorkout: wp,
        workoutNameDraft: wp.name,
        workoutNotesDraft: wp.notes ?? '',
        workoutPlannedExercises: const [],
        workoutPlannedSessionExerciseSets: const [],
        workoutExerciseSlots: const [],
        activeSlotIndex: 0,
      );
      await host.onContentsChanged();
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  /// [includeArchived] is the review editor's read (2026-10-26): the groups
  /// the pass has removed stay on the card, red, so each removal can be
  /// explained in its note. Every other caller keeps the planner's read.
  Future<void> openEditWorkout(
    PlannedSession w, {
    bool includeArchived = false,
  }) async {
    _includeArchived = includeArchived;
    _archivedAtOpen = const {};
    state.value = state.value.copyWith(
      editingWorkout: w,
      workoutNameDraft: w.name,
      workoutNotesDraft: w.notes ?? '',
      workoutSetsLoading: true,
    );
    // The catalog is loaded here rather than inherited from the program
    // screen: the editor owns its own copy, so it must fetch its own.
    await _ensureCatalog();
    try {
      // The planner reads its sets through the same normalizing read the
      // session preview uses, so the two cannot disagree about a template's
      // shape — how many sets a group has, or what order the groups are in.
      final sets = await _plannedSessionRepo.readNormalizedPlannedSession(
        w.sessionId,
        includeArchived: _includeArchived,
      );
      final allExercises = await _readGroupsRaw(w.sessionId);
      // What was already archived when the pass opened is not this pass's
      // removal: the card hides it, exactly as the planner does outside a
      // review (2026-10-26).
      _archivedAtOpen = {
        if (_includeArchived)
          for (final e in allExercises)
            if (e.isArchived) e.plannedExerciseId,
      };
      final exercises = _visibleGroups(allExercises);
      // The snapshots are the RAW reads: Discard compares against them, and
      // a group that was already gone must stay gone through a rollback.
      _openedExercises = allExercises;
      _openedSetsSnapshot = sets;
      _openedName = w.name;
      _openedNotes = w.notes;
      _openedExisting = true;
      state.value = state.value.copyWith(
        workoutPlannedSessionExerciseSets: _visibleSets(sets),
        workoutPlannedExercises: exercises,
        workoutExerciseSlots: _slotsFromExercises(exercises),
        activeSlotIndex: 0,
        workoutSetsLoading: false,
      );
      await loadNotesForSlots();
    } catch (e) {
      state.value = state.value.copyWith(
        workoutSetsLoading: false,
        error: friendlyError(e),
      );
    }
  }

  /// Opens a standalone workout for editing (no program). Loads its name,
  /// notes, and planned sets into the editor.
  Future<void> openStandaloneWorkout(String sessionId) async {
    _includeArchived = false;
    _archivedAtOpen = const {};
    await _ensureCatalog();
    // One row by id — the old path read the ENTIRE standalone list to find
    // a single session (2026-10-13).
    final w = await _plannedSessionRepo.fetchPlannedSessionById(sessionId);
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
      workoutSetsLoading: true,
    );
    try {
      // Same normalizing read as openEditWorkout — the planner and the session
      // preview agree because they read a template the same way.
      final sets = await _plannedSessionRepo.readNormalizedPlannedSession(
        sessionId,
      );
      final exercises = await _readGroups(sessionId);
      _openedExercises = exercises;
      _openedSetsSnapshot = sets;
      _openedName = w.name;
      _openedNotes = w.notes;
      _openedExisting = true;
      state.value = state.value.copyWith(
        workoutPlannedSessionExerciseSets: sets,
        workoutPlannedExercises: exercises,
        workoutExerciseSlots: _slotsFromExercises(exercises),
        activeSlotIndex: 0,
        workoutSetsLoading: false,
      );
      await loadNotesForSlots();
    } catch (e) {
      state.value = state.value.copyWith(
        workoutSetsLoading: false,
        error: friendlyError(e),
      );
    }
  }

  /// Creates a brand-new standalone workout and opens it for editing.
  Future<void> createStandaloneWorkoutAndOpen() async {
    state.value = state.value.copyWith(clearError: true);
    await _ensureCatalog();
    try {
      final created = await _plannedSessionRepo.createPlannedSession(_userId);
      _openedExisting = false;
      _openedExercises = const [];
      _openedSetsSnapshot = const [];
      _includeArchived = false;
      _archivedAtOpen = const {};
      // Open the editor against the row we just created. Building state from
      // the returned object (rather than re-fetching) avoids a race where the
      // insert hasn't reflected into a follow-up SELECT yet — previously that
      // left editingWorkout null and the screen on an eternal spinner.
      state.value = state.value.copyWith(
        editingWorkout: created,
        workoutNameDraft: created.name,
        workoutNotesDraft: created.notes ?? '',
        workoutPlannedExercises: const [],
        workoutPlannedSessionExerciseSets: const [],
        workoutExerciseSlots: const [],
        activeSlotIndex: 0,
        workoutSetsLoading: false,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
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
    await Future.wait([commitWorkoutName(), commitWorkoutNotes()]);
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
      // Save, not to open. Read the way the editor opened it, so the
      // snapshot holds exactly the groups and rows the card is showing.
      _openedExercises = await _readGroups(workout.sessionId);
      _openedSetsSnapshot = await _readSets(workout.sessionId);
      final savedName = state.value.workoutNameDraft.trim();
      final savedNotes = state.value.workoutNotesDraft.trim();
      _openedName = savedName.isEmpty ? null : savedName;
      _openedNotes = savedNotes.isEmpty ? null : savedNotes;
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
    // Coach mode has no discard (2026-10-28): discarding a newly created
    // workout deletes it, and the coach may not delete.
    if (!_canDelete) return;
    final w = state.value.editingWorkout;
    if (w == null) return;
    if (!_openedExisting) {
      // Deleting is the rollback for a workout born in this session, and the
      // host learns about it on the way out like every other discard below.
      await deletePlannedSession(notifyHost: false);
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
      // Groups added since open are discarded; snapshot groups come back.
      final currentExercises = await _readGroups(w.sessionId);
      final snapshotIds = {
        for (final e in _openedExercises) e.plannedExerciseId,
      };
      for (final e in currentExercises) {
        if (!snapshotIds.contains(e.plannedExerciseId)) {
          await _plannedSessionRepo.deletePlannedExercise(e.plannedExerciseId);
        }
      }
      // Each snapshot group returns to the state it was opened in — its own
      // archive flag, not a blanket un-archive (2026-10-26): a review's read
      // also hands back groups that were already removed before it began, and
      // a discard must leave those exactly as it found them.
      for (final e in _openedExercises) {
        if (e.isArchived) continue;
        await _plannedSessionRepo.restorePlannedExercise(
          e.plannedExerciseId,
          exerciseOrder: e.exerciseOrder,
        );
      }
      // Rows added since open are discarded.
      final current = await _readSets(w.sessionId);
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
        // Removed when the editor opened: its card was red and inert, so
        // nothing on it could have changed — and the rollback leaves it that
        // way rather than resurrecting a removal the pass did not make.
        if (s.isArchived) continue;
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
        await _plannedSessionRepo.restorePlannedSet(
          s.plannedSetId,
          setNumber: s.setNumber,
        );
      }
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
    // The host is not told (2026-10-26): every screen that opens this editor
    // reloads its own list once the route it pushed is gone, and a reload
    // fired from here lands mid-pop — the discard read as two reloads racing
    // the transition. The rollback itself is still written before the pop, so
    // the post-pop reload reads the rolled-back rows.
    closeWorkoutEditor(notifyHost: false);
  }

  void closeWorkoutEditor({bool notifyHost = true}) {
    // Clear editing state SYNCHRONOUSLY — dispose() commits pending
    // name/notes drafts, and a delayed clear would let a discarded draft
    // get written after the guard pops.
    undoHistory.clear();
    state.value = state.value.copyWith(clearEditingWorkout: true);
    // When closing without saving (discard), still refresh the workout list
    // so that a newly-created-then-discarded workout shows its name correctly
    // and exercises added/removed during editing are reflected.
    //
    // [notifyHost] is the caller's verdict on that: the discard path leaves
    // the refresh to the opener's post-pop reload, which is already coming.
    if (notifyHost) _host?.onContentsChanged();
  }

  Future<void> deletePlannedSession({bool notifyHost = true}) async {
    if (!_canDelete) return;
    final w = state.value.editingWorkout;
    if (w == null) return;
    // Archive BEFORE clearing the editor — closeWorkoutEditor's list refetch
    // would otherwise race ahead and keep the deleted workout listed.
    await _plannedSessionRepo.deletePlannedSession(w.sessionId);
    closeWorkoutEditor(notifyHost: notifyHost);
  }

  // ── Session name/notes — auto-commit on blur/change ─────────────────────
  void setWorkoutNameDraft(String v) => state.value = state.value.copyWith(
    workoutNameDraft: v,
    workoutUnsavedChanges: true,
  );
  void setWorkoutNotesDraft(String v) => state.value = state.value.copyWith(
    workoutNotesDraft: v,
    workoutUnsavedChanges: true,
  );

  /// Whether anything is still unsaved after an auto-commit — pending set
  /// drafts, or name/notes drafts that differ from the persisted workout.
  /// Auto-committed fields must clear the dirty flag or the back guard prompts
  /// "Discard/Save" for already-saved data.
  bool _workoutStillDirty(PlannedSession w) {
    if (state.value.workoutSetDrafts.values.any((l) => l.isNotEmpty)) {
      return true;
    }
    if (state.value.workoutNameDraft.trim() != w.name) return true;
    if (state.value.workoutNotesDraft.trim() != (w.notes ?? '')) return true;
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
        : s.workoutExerciseSlots
                  .map((sl) => sl.exerciseOrder)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    final box = UndoBox<String>();
    final activeBefore = s.activeSlotIndex;

    Future<void> forward() async {
      final cur = state.value;
      final workout = cur.editingWorkout;
      if (workout == null) return;
      try {
        final group = await _plannedSessionRepo.createPlannedExercise(
          _userId,
          workout.sessionId,
          exerciseId: exerciseId,
          exerciseOrder: nextOrder,
        );
        box.value = group.plannedExerciseId;
        final slots = [
          ...cur.workoutExerciseSlots,
          PlanExerciseSlot(
            exerciseOrder: nextOrder,
            exerciseId: exerciseId,
            plannedExerciseId: group.plannedExerciseId,
          ),
        ];
        final exercises = [...cur.workoutPlannedExercises, group];
        final drafts = Map<String, List<int>>.from(cur.workoutSetDrafts);
        drafts
            .putIfAbsent(group.plannedExerciseId, () => [])
            .add(_nextDraftId++);
        state.value = cur.copyWith(
          workoutPlannedExercises: exercises,
          workoutExerciseSlots: slots,
          workoutSetDrafts: drafts,
          activeSlotIndex: slots.length - 1,
          workoutUnsavedChanges: true,
        );
        loadNotesFor(exerciseId);
      } catch (e) {
        state.value = state.value.copyWith(error: friendlyError(e));
      }
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final id = box.value;
          if (id != null) {
            await _plannedSessionRepo.deletePlannedExercise(id);
          }
          final cur = state.value;
          final drafts = Map<String, List<int>>.from(cur.workoutSetDrafts)
            ..remove(id);
          state.value = cur.copyWith(
            workoutExerciseSlots: [
              for (final sl in cur.workoutExerciseSlots)
                if (sl.exerciseId != exerciseId) sl,
            ],
            workoutPlannedExercises: [
              for (final e in cur.workoutPlannedExercises)
                if (e.plannedExerciseId != id) e,
            ],
            workoutSetDrafts: drafts,
            activeSlotIndex: activeBefore,
            workoutUnsavedChanges: true,
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

  /// Removes the exercise slot at [index] from the editing workout and
  /// archives its group + planned sets.  Active-index is clamped so the tab
  /// bar never points past the new end.
  Future<void> removePlannedExerciseGroup(int index) async {
    if (!_canDelete) return;
    final s = state.value;
    final workout = s.editingWorkout;
    if (workout == null ||
        index < 0 ||
        index >= s.workoutExerciseSlots.length) {
      return;
    }
    final slot = s.workoutExerciseSlots[index];
    final plannedExerciseId = slot.plannedExerciseId;
    final activeBefore = s.activeSlotIndex;
    final draftIdsBefore = s.workoutSetDrafts[plannedExerciseId] ?? const [];

    // Captures for the un-archive inverse (soft-deleted rows keep their ids
    // and values — only the flags and order columns change).
    final capturedExercise = plannedExerciseId == null
        ? null
        : s.workoutPlannedExercises
              .where((e) => e.plannedExerciseId == plannedExerciseId)
              .firstOrNull;
    final capturedSets = plannedExerciseId == null
        ? const <PlannedSessionExerciseSet>[]
        : [
            for (final ps in s.workoutPlannedSessionExerciseSets)
              if (ps.plannedExerciseId == plannedExerciseId) ps,
          ];

    Future<void> forward() async {
      final cur = state.value;
      final workout = cur.editingWorkout;
      if (workout == null) return;
      final idx = cur.workoutExerciseSlots.indexWhere(
        (sl) => sl.plannedExerciseId == plannedExerciseId,
      );
      if (idx == -1) return;
      final curSlot = cur.workoutExerciseSlots[idx];

      final peId = curSlot.plannedExerciseId;
      if (peId != null) {
        await _plannedSessionRepo.deletePlannedExercise(peId);
      }

      final exercises = await _readGroups(workout.sessionId);
      final plannedSets = await _readSets(workout.sessionId);
      final slots = _slotsFromExercises(exercises);

      int newActive;
      if (_includeArchived) {
        // Inside a review the group is still on the card — that is the whole
        // point of removing it here — so the card does not shrink under the
        // finger: the list keeps its length and the active tab keeps its
        // place, whichever one was removed (2026-10-26).
        newActive = slots.isEmpty
            ? 0
            : cur.activeSlotIndex.clamp(0, slots.length - 1);
      } else {
        final reduced = [...cur.workoutExerciseSlots]..removeAt(idx);
        newActive = cur.activeSlotIndex;
        if (newActive >= reduced.length) {
          newActive = (reduced.length - 1).clamp(0, reduced.length);
        }
      }

      final drafts = Map<String, List<int>>.from(cur.workoutSetDrafts)
        ..remove(curSlot.plannedExerciseId ?? '');

      state.value = cur.copyWith(
        workoutPlannedExercises: exercises,
        workoutExerciseSlots: slots,
        activeSlotIndex: newActive,
        workoutPlannedSessionExerciseSets: plannedSets,
        workoutSetDrafts: drafts,
        workoutUnsavedChanges: true,
      );
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final wid = workout.sessionId;
          // Un-archive the group and its sets, restoring captured order —
          // the `discardWorkoutChanges` precedent's raw-SQL pass.
          if (capturedExercise != null) {
            await _plannedSessionRepo.restorePlannedExercise(
              capturedExercise.plannedExerciseId,
              exerciseOrder: capturedExercise.exerciseOrder,
            );
          }
          for (final pset in capturedSets) {
            await _plannedSessionRepo.restorePlannedSet(
              pset.plannedSetId,
              setNumber: pset.setNumber,
            );
          }
          final exercises = await _readGroups(wid);
          final plannedSets = await _readSets(wid);
          final cur = state.value;
          final slots = _slotsFromExercises(exercises);
          // A review's read already holds the restored group — the insert is
          // the planner's own way of putting back one its read omits
          // (2026-10-26).
          if (!slots.any((sl) => sl.plannedExerciseId == plannedExerciseId)) {
            slots.insert(
              index.clamp(0, slots.length),
              PlanExerciseSlot(
                exerciseOrder: index + 1,
                exerciseId: slot.exerciseId,
                plannedExerciseId: plannedExerciseId,
              ),
            );
          }
          final drafts = Map<String, List<int>>.from(cur.workoutSetDrafts);
          if (plannedExerciseId != null) {
            drafts[plannedExerciseId] = List.of(draftIdsBefore);
          }
          state.value = cur.copyWith(
            workoutPlannedExercises: exercises,
            workoutExerciseSlots: slots,
            activeSlotIndex: activeBefore,
            workoutPlannedSessionExerciseSets: plannedSets,
            workoutSetDrafts: drafts,
            workoutUnsavedChanges: true,
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

  /// Puts back a group this pass removed (2026-10-28): the floor's trash
  /// lists the pass's own removals, a row opens one for reading on the card
  /// it already stands on, and this is the Restore button under it — the live
  /// session's view-then-restore flow, over the pass's staged store.
  ///
  /// The archived rows keep their ids, values and order columns, so restoring
  /// is the removal's inverse: un-archive the group and every set under it,
  /// then re-read. Recorded on the undo stack because the live session's
  /// Restore is undoable too — the inverse archives the group again.
  Future<void> restorePlannedExerciseGroup(int index) async {
    final s = state.value;
    final workout = s.editingWorkout;
    if (workout == null ||
        index < 0 ||
        index >= s.workoutExerciseSlots.length) {
      return;
    }
    final slot = s.workoutExerciseSlots[index];
    final plannedExerciseId = slot.plannedExerciseId;
    if (plannedExerciseId == null || !slot.deleted) return;

    // The rows are still in state: inside a review the reads bring archived
    // groups (and their sets) back, hidden at open only when they predate
    // the pass.
    final capturedExercise = s.workoutPlannedExercises
        .where((e) => e.plannedExerciseId == plannedExerciseId)
        .firstOrNull;
    final capturedSets = [
      for (final ps in s.workoutPlannedSessionExerciseSets)
        if (ps.plannedExerciseId == plannedExerciseId) ps,
    ];

    Future<void> forward() async {
      final wid = state.value.editingWorkout?.sessionId;
      if (wid == null) return;
      if (capturedExercise != null) {
        await _plannedSessionRepo.restorePlannedExercise(
          plannedExerciseId,
          exerciseOrder: capturedExercise.exerciseOrder,
        );
      }
      for (final pset in capturedSets) {
        await _plannedSessionRepo.restorePlannedSet(
          pset.plannedSetId,
          setNumber: pset.setNumber,
        );
      }
      final exercises = await _readGroups(wid);
      final plannedSets = await _readSets(wid);
      state.value = state.value.copyWith(
        workoutPlannedExercises: exercises,
        workoutExerciseSlots: _slotsFromExercises(exercises),
        workoutPlannedSessionExerciseSets: plannedSets,
        workoutUnsavedChanges: true,
      );
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final cur = state.value;
          final idx = cur.workoutExerciseSlots.indexWhere(
            (sl) => sl.plannedExerciseId == plannedExerciseId,
          );
          if (idx == -1) return;
          _suppressHistory = true;
          try {
            await removePlannedExerciseGroup(idx);
          } finally {
            _suppressHistory = false;
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
    // Captures for the inverse (the old slot order by planned id).
    final orderBefore = [
      for (final sl in s.workoutExerciseSlots) sl.plannedExerciseId,
    ];

    Future<void> forward() async {
      final cur = state.value;
      final wid = cur.editingWorkout?.sessionId;
      if (wid == null) return;
      final slots = [...cur.workoutExerciseSlots];
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
      // Renumber every slot's order 1..N in the new list order —
      // pair-swapping only survives adjacent moves, and a non-adjacent drag
      // would otherwise persist a different order than the one shown.
      final renumbered = [
        for (var i = 0; i < slots.length; i++)
          PlanExerciseSlot(
            exerciseOrder: i + 1,
            exerciseId: slots[i].exerciseId,
            plannedExerciseId: slots[i].plannedExerciseId,
            deleted: slots[i].deleted,
          ),
      ];
      state.value = cur.copyWith(
        workoutExerciseSlots: renumbered,
        activeSlotIndex: newActive,
      );
      await _plannedSessionRepo.renumberExerciseOrders(wid, [
        for (var i = 0; i < slots.length; i++) (slots[i].exerciseOrder, i),
      ]);
      final exercises = await _readGroups(wid);
      final sets = await _readSets(wid);
      state.value = state.value.copyWith(
        workoutPlannedExercises: exercises,
        workoutExerciseSlots: _slotsFromExercises(exercises),
        workoutPlannedSessionExerciseSets: sets,
      );
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final wid = state.value.editingWorkout?.sessionId;
          if (wid == null) return;
          final byId = {
            for (final sl in state.value.workoutExerciseSlots)
              sl.plannedExerciseId: sl,
          };
          final restored = [
            for (final id in orderBefore)
              if (byId[id] != null) byId[id]!,
          ];
          state.value = state.value.copyWith(workoutExerciseSlots: restored);
          await _plannedSessionRepo.renumberExerciseOrders(wid, [
            for (var i = 0; i < restored.length; i++)
              (restored[i].exerciseOrder, i),
          ]);
          final exercises = await _readGroups(wid);
          state.value = state.value.copyWith(
            workoutPlannedExercises: exercises,
            workoutExerciseSlots: _slotsFromExercises(exercises),
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

  /// Hold-and-drag reorder of one exercise group's target rows.
  ///
  /// [oldIndex] and [newIndex] count that group's REAL rows only, and
  /// [newIndex] arrives already adjusted for the row being lifted out
  /// (`onReorderItem`). Draft rows sit past the end and cannot be dropped
  /// into — they are virtual until saved, and a drop there means "last real
  /// set".
  ///
  /// The renumber lands locally first so the grid settles on the drop's own
  /// frame, then the write, then a re-read: the read is what proves the new
  /// numbering is the one stored, which matters here because
  /// `fetchNormalizedPlannedSets` renumbers from the same column on every
  /// open.
  Future<void> reorderPlannedSets(
    String plannedExerciseId,
    int oldIndex,
    int newIndex,
  ) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    final rows = <PlannedSessionExerciseSet>[
      for (final s in state.value.workoutPlannedSessionExerciseSets)
        if (s.plannedExerciseId == plannedExerciseId) s,
    ]..sort((a, b) => a.setNumber.compareTo(b.setNumber));
    if (rows.length < 2) return;
    if (newIndex >= rows.length) newIndex = rows.length - 1;
    if (oldIndex == newIndex || oldIndex < 0 || oldIndex >= rows.length) {
      return;
    }

    final idsBefore = [for (final r in rows) r.plannedSetId];

    Future<void> forward() async {
      final wid = state.value.editingWorkout?.sessionId;
      if (wid == null) return;
      final current = <PlannedSessionExerciseSet>[
        for (final s in state.value.workoutPlannedSessionExerciseSets)
          if (s.plannedExerciseId == plannedExerciseId) s,
      ]..sort((a, b) => a.setNumber.compareTo(b.setNumber));
      if (current.length < 2 || newIndex >= current.length) return;
      current.insert(newIndex, current.removeAt(oldIndex));
      final renumbered = <String, PlannedSessionExerciseSet>{
        for (var i = 0; i < current.length; i++)
          current[i].plannedSetId: current[i].copyWith(setNumber: i + 1),
      };
      state.value = state.value.copyWith(
        workoutPlannedSessionExerciseSets: [
          for (final s in state.value.workoutPlannedSessionExerciseSets)
            renumbered[s.plannedSetId] ?? s,
        ],
        workoutUnsavedChanges: true,
      );

      try {
        await _plannedSessionRepo.renumberPlannedSets([
          for (final s in current) s.plannedSetId,
        ]);
        final sets = await _readSets(wid);
        state.value = state.value.copyWith(
          workoutPlannedSessionExerciseSets: sets,
          workoutUnsavedChanges: true,
        );
      } catch (e) {
        state.value = state.value.copyWith(error: friendlyError(e));
      }
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          await _plannedSessionRepo.renumberPlannedSets(idsBefore);
          final wid = state.value.editingWorkout?.sessionId;
          if (wid != null) {
            final sets = await _readSets(wid);
            state.value = state.value.copyWith(
              workoutPlannedSessionExerciseSets: sets,
              workoutUnsavedChanges: true,
            );
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
      final sets = await _readSets(workout.sessionId);
      state.value = state.value.copyWith(
        workoutPlannedSessionExerciseSets: sets,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  void addDraftPlannedSessionExerciseSet(String plannedExerciseId) {
    // "+ ADD SET" adds a virtual draft row — visible immediately and a REAL
    // change (marks the editor dirty, so the guard prompts on back and the
    // Save button appears). The draft materializes as a row on input, or as
    // an empty row on explicit Save (empty sets are valid).
    final box = UndoBox<int>();

    Future<void> forward() async {
      final drafts = Map<String, List<int>>.from(state.value.workoutSetDrafts);
      final id = _nextDraftId++;
      box.value = id;
      drafts.putIfAbsent(plannedExerciseId, () => []).add(id);
      state.value = state.value.copyWith(
        workoutSetDrafts: drafts,
        workoutUnsavedChanges: true,
      );
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final id = box.value;
          if (id == null) return;
          final drafts = Map<String, List<int>>.from(
            state.value.workoutSetDrafts,
          );
          drafts[plannedExerciseId]?.remove(id);
          state.value = state.value.copyWith(
            workoutSetDrafts: drafts,
            workoutUnsavedChanges: true,
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
    unawaited(forward());
  }

  void removeDraftPlannedSessionExerciseSet(
    String plannedExerciseId,
    int draftId,
  ) {
    if (!_canDelete) return;
    Future<void> forward() async {
      final drafts = Map<String, List<int>>.from(state.value.workoutSetDrafts);
      drafts[plannedExerciseId]?.remove(draftId);
      state.value = state.value.copyWith(
        workoutSetDrafts: drafts,
        workoutUnsavedChanges: true,
      );
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final drafts = Map<String, List<int>>.from(
            state.value.workoutSetDrafts,
          );
          drafts.putIfAbsent(plannedExerciseId, () => []).add(draftId);
          state.value = state.value.copyWith(
            workoutSetDrafts: drafts,
            workoutUnsavedChanges: true,
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
    unawaited(forward());
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

  Future<void> undo() async {
    if (_undoInFlight || !undoHistory.canUndo) return;
    _undoInFlight = true;
    try {
      await flushPendingCommits();
      await undoHistory.undo();
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
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
      state.value = state.value.copyWith(error: friendlyError(e));
    }
    _undoInFlight = false;
    state.value = state.value.copyWith();
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
      final sets = await _readSets(workout.sessionId);
      state.value = state.value.copyWith(
        workoutPlannedSessionExerciseSets: sets,
      );
      return true;
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
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
      final sets = await _readSets(workout.sessionId);
      state.value = state.value.copyWith(
        workoutPlannedSessionExerciseSets: sets,
        workoutUnsavedChanges: true,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  /// Inserts a new planned set copying [ps] — the grid row's swipe
  /// Duplicate. The row passes the text on screen as [targetWeight] /
  /// [targetReps] overrides (targets are free text, and the copy must carry
  /// what the user just typed, not the stale row values — 2026-10-13).
  Future<void> duplicatePlannedSessionExerciseSet(
    PlannedSessionExerciseSet ps, {
    String? targetWeight,
    String? targetReps,
  }) async {
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    final exerciseId = ps.exerciseId ?? '';
    final existing = state.value.plannedSetsFor(ps.plannedExerciseId);
    final setNumber =
        existing.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) + 1;
    final box = UndoBox<String>();

    Future<void> forward() async {
      final wid = state.value.editingWorkout?.sessionId;
      if (wid == null) return;
      try {
        final created = await _plannedSessionRepo.createPlannedSet(
          _userId,
          ps.plannedExerciseId,
          plannedSessionId: wid,
          exerciseId: exerciseId,
          variationId: ps.variationId,
          setNumber: setNumber,
          targetWeight: targetWeight ?? ps.targetWeight,
          targetReps: targetReps ?? ps.targetReps,
          targetNotes: ps.targetNotes,
        );
        box.value = created.plannedSetId;
        final sets = await _readSets(wid);
        state.value = state.value.copyWith(
          workoutPlannedSessionExerciseSets: sets,
          workoutUnsavedChanges: true,
        );
      } catch (e) {
        state.value = state.value.copyWith(error: friendlyError(e));
      }
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          final id = box.value;
          if (id == null) return;
          await _plannedSessionRepo.deletePlannedSet(id);
          final wid = state.value.editingWorkout?.sessionId;
          if (wid != null) {
            final sets = await _readSets(wid);
            state.value = state.value.copyWith(
              workoutPlannedSessionExerciseSets: sets,
              workoutUnsavedChanges: true,
            );
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

  Future<void> deletePlannedSessionExerciseSet(String setId) async {
    if (!_canDelete) return;
    final workout = state.value.editingWorkout;
    if (workout == null) return;
    final captured = state.value.workoutPlannedSessionExerciseSets
        .where((s) => s.plannedSetId == setId)
        .firstOrNull;

    Future<void> forward() async {
      final wid = state.value.editingWorkout?.sessionId;
      if (wid == null) return;
      await _plannedSessionRepo.deletePlannedSet(setId);
      final sets = await _readSets(wid);
      state.value = state.value.copyWith(
        workoutPlannedSessionExerciseSets: sets,
        workoutUnsavedChanges: true,
      );
    }

    _recordUndo(
      UndoAction(
        inverse: () async {
          if (captured == null) return;
          // Soft-deleted row keeps its id — un-archive and restore the number.
          await _plannedSessionRepo.restorePlannedSet(
            captured.plannedSetId,
            setNumber: captured.setNumber,
          );
          final wid = state.value.editingWorkout?.sessionId;
          if (wid != null) {
            final sets = await _readSets(wid);
            state.value = state.value.copyWith(
              workoutPlannedSessionExerciseSets: sets,
              workoutUnsavedChanges: true,
            );
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
        error: friendlyError(e),
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
        error: friendlyError(e),
      );
      return null;
    }
  }

  // ── Notes (per-exercise, cross-session — same dim_exercise_note data session uses) ──

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

  List<ExerciseNote> notesFor(String exerciseId) =>
      state.value.notesByExercise[exerciseId] ?? const [];

  Future<void> loadNotesFor(String exerciseId) async {
    try {
      final notes = await _noteRepo.fetchNotes(_userId, exerciseId);
      final map = Map<String, List<ExerciseNote>>.from(state.value.notesByExercise);
      map[exerciseId] = notes;
      state.value = state.value.copyWith(notesByExercise: map);
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  /// One batch notes read for the open workout's exercise slots — the
  /// per-slot loop's replacement on open (2026-10-13).
  Future<void> loadNotesForSlots() async {
    final ids = [
      for (final slot in state.value.workoutExerciseSlots) slot.exerciseId,
    ];
    if (ids.isEmpty) return;
    try {
      final byExercise = await _noteRepo.fetchNotesForExercises(
        _userId,
        ids,
      );
      state.value = state.value.copyWith(notesByExercise: byExercise);
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  Future<void> addNote(String exerciseId, String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _noteRepo.createNote(_userId, exerciseId, text.trim());
      await loadNotesFor(exerciseId);
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  Future<void> toggleNotePin(String exerciseId, String exerciseNoteId) async {
    final note = notesFor(
      exerciseId,
    ).firstWhereOrNull((l) => l.exerciseNoteId == exerciseNoteId);
    if (note == null) return;
    try {
      await _noteRepo.setPinned(
        _userId,
        exerciseId,
        exerciseNoteId,
        !note.pinned,
      );
      await loadNotesFor(exerciseId);
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  Future<void> deleteNote(String exerciseId, String exerciseNoteId) async {
    try {
      await _noteRepo.deleteNote(exerciseNoteId);
      await loadNotesFor(exerciseId);
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  Future<void> updateNoteText(
    String exerciseId,
    String exerciseNoteId,
    String text,
  ) async {
    if (text.trim().isEmpty) return;
    try {
      await _noteRepo.updateNote(
        _userId,
        exerciseId,
        exerciseNoteId,
        text.trim(),
      );
      await loadNotesFor(exerciseId);
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
  }

  // ── History (read-only past sets, for reference while planning) ──────────

  List<ExerciseHistorySession> historyFor(String exerciseId) =>
      state.value.historyByExercise[exerciseId] ?? const [];

  /// The exercise's whole PR feed, oldest first — the planner floor's trophy
  /// opens the same PR History sheet the session surfaces do (2026-10-26).
  /// A plan has no session to narrow against, so the caller passes no set ids
  /// and no start; the sheet's shelves read everything as history.
  List<PrEvent> prHistoryFor(String exerciseId) => [
    for (final event in state.value.allPrEvents)
      if (event.exerciseId == exerciseId) event,
  ];

  /// How many PRs the exercise ever landed — the tile's count, read off the
  /// same feed its door opens, so the number always names what is behind it.
  int prCountFor(String exerciseId) =>
      state.value.allPrEvents.where((e) => e.exerciseId == exerciseId).length;

  /// The exercise's notes shelf, all of it — the planner's counterpart of the
  /// session floor's session-scoped gain (2026-10-26).
  int noteCountFor(String exerciseId) => notesFor(exerciseId).length;

  Future<void> loadHistoryIfNeeded() async {
    if (state.value.pastSetsLoaded) return;
    try {
      final pastSets = await _sessionRepo.loadPastSetsTimeline(_userId);
      state.value = state.value.copyWith(
        historyByExercise: groupHistoryByExercise(pastSets),
        // Derived here, once, off the same read — the planner's doors and
        // sheets must not each walk the whole timeline (2026-10-26).
        allPrEvents: prEvents(pastSets),
        // The raw rows too: a goal's completion is read off sets, exactly
        // the way the G badge reads it (2026-10-27).
        goalTimeline: pastSets,
        pastSetsLoaded: true,
      );
    } catch (e) {
      state.value = state.value.copyWith(error: friendlyError(e));
    }
    // Goals ride along, non-fatal (the session VMs' rule, 2026-10-20): the
    // bullseye is an extra on the floor, never a blocker for the plan.
    await loadGoals();
  }

  /// The owner's goals, any scope — the same read the session VMs take
  /// (2026-10-27). A failed read leaves the bullseye at 0.
  Future<void> loadGoals() async {
    try {
      final goals = [
        for (final option in await _programRepo.fetchGoalOptions(_userId))
          option.goal,
      ];
      state.value = state.value.copyWith(goals: goals);
    } catch (_) {
      state.value = state.value.copyWith(goals: const []);
    }
  }

  // ── Goals (the planner floor's bullseye, 2026-10-27) ─────────────────────

  List<Goal> goalsForExercise(String exerciseId) => [
    for (final goal in state.value.goals)
      if (goal.exerciseId == exerciseId) goal,
  ];

  /// How many of the exercise's goals still stand — the bullseye's number.
  /// Ownership is [goalCompletionSet]'s call, the same rule the goals sheet
  /// and the `G` badge use, over this editor's timeline.
  int openGoalsFor(String exerciseId) {
    var open = 0;
    for (final goal in goalsForExercise(exerciseId)) {
      if (goalCompletionSet(goal: goal, sets: state.value.goalTimeline) ==
          null) {
        open++;
      }
    }
    return open;
  }

  /// The exercise ordering the New goal form reads, derived off the same
  /// timeline the planner already loaded.
  Map<String, DateTime> get lastUsedByExercise =>
      lastUsedByEntity(state.value.goalTimeline);

  /// Writes a standalone goal from the floor's New goal form — the live and
  /// viewer VMs' write, filed against this editor's own library (2026-10-27).
  /// False means the write failed and the form stays open to say so.
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
      state.value = state.value.copyWith(error: friendlyError(e));
      return false;
    }
    // Patch in place — the open sheet rebuilds through its Listenable, so
    // the row appears with no reload.
    state.value = state.value.copyWith(goals: [...state.value.goals, goal]);
    return true;
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
