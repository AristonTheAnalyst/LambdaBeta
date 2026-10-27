import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/cache/past_sets_timeline_cache.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/session_exercise.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/models/session.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/exercise_note_repository.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:lambda/data/repositories/program_run_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/session/viewmodel/session_viewmodel.dart';

/// The live session's undo/redo + soft-delete behaviour (2026-10-13):
/// planned deletes flag instead of removing (and undo un-flags), added
/// exercises wear the plus, deleted planned exercises surface as
/// minus-marked entries, and history clears with the session.
class _FakeSessionRepo extends Fake implements SessionRepository {
  String? activeSessionId = 'w1';
  int deleteSetCalls = 0;
  int deleteSessionExerciseCalls = 0;
  final updateLog = <({String setId, bool isDeleted, bool clearIsDeleted})>[];
  final insertLog = <({double? weight, List<num> reps, int setNumber})>[];
  final deletedIds = <String>[];
  final reorderLog = <List<String>>[];

  final rows = <String, SessionExerciseSet>{};
  final exercises = <String, SessionExercise>{};
  final _setsCtl = StreamController<List<SessionExerciseSet>>.broadcast();
  final _exCtl = StreamController<List<SessionExercise>>.broadcast();

  SessionExerciseSet row({
    required String setId,
    double? weight = 0,
    List<num> reps = const [],
    String? plannedSetId,
    String sessionExerciseId = 'se1',
    String exerciseId = 'ex1',
    int setNumber = 1,
    bool isDeleted = false,
  }) => SessionExerciseSet(
    sessionExerciseSetId: setId,
    sessionExerciseId: sessionExerciseId,
    sessionId: activeSessionId!,
    userId: 'u1',
    setNumber: setNumber,
    weight: weight,
    reps: reps,
    exerciseId: exerciseId,
    plannedSetId: plannedSetId,
    isDeleted: isDeleted,
  );

  void seedExercise(String id, String exerciseId, {String? plannedExerciseId}) {
    exercises[id] = SessionExercise(
      sessionExerciseId: id,
      sessionId: activeSessionId!,
      userId: 'u1',
      exerciseOrder: exercises.length + 1,
      exerciseId: exerciseId,
      plannedExerciseId: plannedExerciseId,
    );
  }

  @override
  Future<String> createSession(
    String userId, {
    String? preNotes,
    String? programRunId,
    String? plannedSessionId,
    String? plannedSessionName,
    int? preFeeling,
    String? deviceId,
  }) async => activeSessionId ?? 'w1';

  @override
  Future<String?> getActiveSessionId(String userId, {String? deviceId}) async =>
      activeSessionId;

  /// What the switch's still-live re-check reads. Null (the default) means
  /// "no answer" — the guard then lets the switch through.
  Session? fetchedSession;

  @override
  Future<Session?> fetchSession(String sessionId) async => fetchedSession;

  @override
  Future<List<PastSetRow>> loadPastSetsTimeline(String userId) async => [];

  @override
  Future<List<SessionExerciseSet>> loadSetsForSession(String sessionId) async =>
      rows.values.toList();

  @override
  Future<List<SessionExercise>> loadSessionExercises(String sessionId) async =>
      exercises.values.toList();

  @override
  Stream<List<SessionExerciseSet>> watchSetsForSession(String sessionId) =>
      _setsCtl.stream;

  @override
  Stream<List<SessionExercise>> watchSessionExercises(String sessionId) =>
      _exCtl.stream;

  void emit() {
    _setsCtl.add(rows.values.toList());
    _exCtl.add(exercises.values.toList());
  }

  @override
  Future<void> updateSet(
    String setId, {
    double? weight,
    bool clearWeight = false,
    List<num>? reps,
    bool clearReps = false,
    String? variationId,
    bool clearVariation = false,
    String? notes,
    bool clearNotes = false,
    bool isDeleted = false,
    bool clearIsDeleted = false,
  }) async {
    updateLog.add((
      setId: setId,
      isDeleted: isDeleted,
      clearIsDeleted: clearIsDeleted,
    ));
    final existing = rows[setId] ?? row(setId: setId);
    rows[setId] = SessionExerciseSet(
      sessionExerciseSetId: existing.sessionExerciseSetId,
      sessionExerciseId: existing.sessionExerciseId,
      sessionId: existing.sessionId,
      userId: existing.userId,
      setNumber: existing.setNumber,
      weight: clearWeight ? null : (weight ?? existing.weight),
      reps: clearReps ? [] : (reps ?? existing.reps),
      variationId: clearVariation
          ? null
          : (variationId ?? existing.variationId),
      notes: clearNotes ? null : (notes ?? existing.notes),
      exerciseId: existing.exerciseId,
      plannedSetId: existing.plannedSetId,
      isDeleted: clearIsDeleted ? false : (isDeleted || existing.isDeleted),
    );
    emit();
  }

  @override
  Future<SessionExerciseSet> insertSet({
    required String sessionExerciseId,
    required String sessionId,
    required String userId,
    String? variationId,
    required int setNumber,
    double? weight,
    required List<num> reps,
    String? notes,
    String? plannedSetId,
  }) async {
    insertLog.add((weight: weight, reps: reps, setNumber: setNumber));
    final setId = 'new-${rows.length + 1}';
    rows[setId] = row(
      setId: setId,
      weight: weight,
      reps: reps,
      sessionExerciseId: sessionExerciseId,
      setNumber: setNumber,
      plannedSetId: plannedSetId,
    );
    emit();
    return rows[setId]!;
  }

  @override
  Future<void> deleteSet(String setId) async {
    deleteSetCalls++;
    deletedIds.add(setId);
    rows.remove(setId);
    emit();
  }

  @override
  Future<SessionExercise> insertSessionExercise({
    required String sessionId,
    required String userId,
    required int exerciseOrder,
    String? exerciseId,
    String? plannedExerciseId,
  }) async {
    final id = 'se-${exercises.length + 1}';
    seedExercise(id, exerciseId ?? 'ex?', plannedExerciseId: plannedExerciseId);
    emit();
    return exercises[id]!;
  }

  @override
  Future<void> deleteSessionExercise(String sessionExerciseId) async {
    deleteSessionExerciseCalls++;
    exercises.remove(sessionExerciseId);
    for (final e in rows.entries.toList()) {
      if (e.value.sessionExerciseId == sessionExerciseId) rows.remove(e.key);
    }
    emit();
  }

  @override
  Future<void> deleteSession(String sessionId) async =>
      deletedSessions.add(sessionId);

  @override
  Future<void> cancelSession(String sessionId) async =>
      deletedSessions.add(sessionId);

  @override
  Future<void> endSession(String sessionId) async => endedSessionId = sessionId;

  @override
  Future<void> reorderSets(
    String sessionId,
    List<String> orderedSetIds,
  ) async {}

  @override
  Future<void> reorderSessionExercises(
    String sessionId,
    List<String> orderedSessionExerciseIds,
  ) async => reorderLog.add(orderedSessionExerciseIds);

  // ── The foreign-session seams (2026-10-15) ────────────────────────────────
  final deletedSessions = <String>[];
  String? endedSessionId;
  final claimed = <({String sessionId, String deviceId})>[];
  final _activeCtl = StreamController<List<Session>>.broadcast();

  @override
  Stream<List<Session>> watchActiveSessions(String userId) => _activeCtl.stream;

  void emitActive(List<Session> sessions) => _activeCtl.add(sessions);

  @override
  Future<void> claimSession(String sessionId, String deviceId) async =>
      claimed.add((sessionId: sessionId, deviceId: deviceId));

  void disposeCtl() {
    _setsCtl.close();
    _exCtl.close();
    _activeCtl.close();
  }
}

class _FakeExerciseRepo extends Fake implements ExerciseRepository {
  @override
  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
    String userId,
  ) async => {
    for (final (id, name) in const [
      ('ex1', 'Bench Press'),
      ('ex2', 'Back Squat'),
    ])
      id: ExerciseDetail(
        exercise: CustomExercise(exerciseId: id, userId: userId, name: name),
      ),
  };

  @override
  Future<List<CustomVariation>> fetchVariations(String userId) async => [];
}

void main() {
  late _FakeSessionRepo repo;

  SessionViewModel buildVm() => SessionViewModel(
    sessionRepo: repo,
    exerciseRepo: _FakeExerciseRepo(),
    programRepo: FakeProgramRepository(),
    programRunRepo: FakeProgramRunRepository(),
    noteRepo: FakeExerciseNoteRepository(),
    plannedSessionRepo: FakePlannedSessionRepository(),
    waitForFirstSync: () async {},
    userId: 'u1',
    // This device's id — the seam that makes "mine" and "theirs" tellable
    // apart in the foreign-session tests (2026-10-15).
    deviceId: 'dev-a',
  );

  Session foreignSession(String id) => Session(
    sessionId: id,
    userId: 'u1',
    createdDatetime: DateTime(2026, 10, 15, 9, 30),
    deviceId: 'dev-b',
  );

  setUp(() {
    repo = _FakeSessionRepo();
    // _init draws its timeline through the shared cache; these suites
    // have no database, so the cache reads through the seam (2026-10-25).
    PastSetsTimelineCache.loaderOverride = (u) async => const <PastSetRow>[];
    PastSetsTimelineCache.instance.invalidate();
  });

  tearDown(() {
    repo.disposeCtl();
    PastSetsTimelineCache.loaderOverride = null;
    PastSetsTimelineCache.instance.invalidate();
  });

  /// Seeds one planned exercise with two planned rows + restores it, so the
  /// soft-delete paths have slots and marks to work with.
  (SessionViewModel, _FakeSessionRepo) vmWithPlannedRows() {
    repo.seedExercise('se1', 'ex1', plannedExerciseId: 'pe1');
    repo.rows['s1'] = repo.row(
      setId: 's1',
      plannedSetId: 'ps1',
      weight: 40,
      reps: [5],
    );
    repo.rows['s2'] = repo.row(
      setId: 's2',
      plannedSetId: 'ps2',
      weight: 50,
      reps: [5],
      setNumber: 2,
    );
    final vm = buildVm();
    fakeAsync((async) async {
      vm.startWorkout();
      async.flushMicrotasks();
    });
    return (vm, repo);
  }

  /// Three planned exercises, one filled row each — three tabs (ex1, ex2,
  /// ex3) from the seed itself, so there is a MIDDLE tab to delete from. No
  /// `addExerciseSlot` in here: that path binds an empty draft row, which
  /// would keep a tab from folding.
  (SessionViewModel, _FakeSessionRepo) vmWithThreeTabs() {
    repo.seedExercise('se1', 'ex1', plannedExerciseId: 'pe1');
    repo.rows['s1'] = repo.row(
      setId: 's1',
      plannedSetId: 'ps1',
      weight: 40,
      reps: [5],
    );
    repo.seedExercise('se2', 'ex2', plannedExerciseId: 'pe2');
    repo.rows['s2'] = repo.row(
      setId: 's2',
      plannedSetId: 'ps2',
      weight: 60,
      reps: [5],
      sessionExerciseId: 'se2',
      exerciseId: 'ex2',
    );
    repo.seedExercise('se3', 'ex3', plannedExerciseId: 'pe3');
    repo.rows['s3'] = repo.row(
      setId: 's3',
      plannedSetId: 'ps3',
      weight: 70,
      reps: [5],
      sessionExerciseId: 'se3',
      exerciseId: 'ex3',
    );
    final vm = buildVm();
    fakeAsync((async) async {
      vm.startWorkout();
      async.flushMicrotasks();
    });
    return (vm, repo);
  }

  /// The bar's exercises in order — the arrangement under test.
  List<String> tabOrder(SessionViewModel vm) => [
    for (final s in vm.exerciseSlots) s.exerciseIds.first,
  ];

  test('deleting a planned set flags it; undo restores it', () {
    fakeAsync((async) async {
      final (vm, _) = vmWithPlannedRows();
      vm.deleteSetById('s1');
      async.flushMicrotasks();

      expect(
        repo.rows['s1']!.isDeleted,
        isTrue,
        reason: 'a planned delete flags, never removes',
      );
      expect(vm.sets.map((s) => s.sessionExerciseSetId), isNot(contains('s1')));
      expect(vm.deletedSets.map((s) => s.sessionExerciseSetId), contains('s1'));

      await vm.undo();
      async.flushMicrotasks();
      expect(
        repo.rows['s1']!.isDeleted,
        isFalse,
        reason: 'undo of a planned delete is the cheap un-flag',
      );
      expect(vm.sets.map((s) => s.sessionExerciseSetId), contains('s1'));
      vm.dispose();
    });
  });

  test('deleting the last planned row folds the tab into a trash entry', () {
    fakeAsync((async) async {
      final (vm, _) = vmWithPlannedRows();
      vm.deleteSetById('s1');
      vm.deleteSetById('s2');
      async.flushMicrotasks();

      expect(
        vm.exerciseSlots,
        isEmpty,
        reason: 'no active rows left — the tab folds',
      );
      expect(vm.deletedPlannedExercises.map((e) => e.exerciseId), [
        'ex1',
      ], reason: 'the exercise is recorded as deleted');
      expect(
        vm.deletedPlannedExerciseEntries,
        [(id: 'se1', name: 'Bench Press')],
        reason:
            'the trash menu lists it, named, before the stream even '
            're-emits',
      );

      await vm.restoreDeletedPlannedExerciseAt(0);
      async.flushMicrotasks();
      expect(
        vm.exerciseSlots,
        isNotEmpty,
        reason: 'the trash restore brings the exercise back',
      );
      expect(
        vm.exerciseSlots.single.planned,
        isTrue,
        reason: 'the restored tab keeps its planned flag',
      );
      expect(
        vm.sets.every((s) => s.plannedSetId != null),
        isTrue,
        reason: 'the sets come back with their planned links intact',
      );
      expect(vm.deletedPlannedExerciseEntries, isEmpty);
      vm.dispose();
    });
  });

  test('the trash menu lists most-recently-deleted first, and restores the '
      'one picked — not just the last', () {
    fakeAsync((async) async {
      final (vm, _) = vmWithPlannedRows();
      // A second planned exercise, deleted first, so the menu's order and
      // the pick are not accidentally the same thing.
      repo.seedExercise('se2', 'ex2', plannedExerciseId: 'pe2');
      repo.rows['s3'] = repo.row(
        setId: 's3',
        plannedSetId: 'ps3',
        weight: 60,
        reps: [5],
        sessionExerciseId: 'se2',
        exerciseId: 'ex2',
      );
      repo.emit();
      vm.addExerciseSlot('ex2');
      async.flushMicrotasks();
      vm.removeExerciseSlot(
        vm.exerciseSlots.indexWhere((s) => s.exerciseIds.contains('ex2')),
      );
      vm.removeExerciseSlot(
        vm.exerciseSlots.indexWhere((s) => s.exerciseIds.contains('ex1')),
      );
      async.flushMicrotasks();

      expect(vm.deletedPlannedExerciseEntries.map((e) => e.name), [
        'Bench Press',
        'Back Squat',
      ], reason: 'ex1 went last — the menu reads newest deletion first');

      // Pick the second row: the older deletion, NOT the most recent one.
      await vm.restoreDeletedPlannedExerciseAt(1);
      async.flushMicrotasks();

      expect(vm.exerciseSlots.single.exerciseIds, [
        'ex2',
      ], reason: 'the row picked is the one that comes back');
      expect(vm.deletedPlannedExerciseEntries.map((e) => e.name), [
        'Bench Press',
      ], reason: 'the pick leaves the menu, the rest stay');

      // And the pick is one undo step, like every other restore.
      await vm.undo();
      async.flushMicrotasks();
      expect(vm.exerciseSlots, isEmpty);
      expect(vm.deletedPlannedExerciseEntries.map((e) => e.name), [
        'Bench Press',
        'Back Squat',
      ]);
      vm.dispose();
    });
  });

  test('a restored exercise returns to the tab it was deleted from, not the '
      'end of the bar', () {
    fakeAsync((async) async {
      final (vm, _) = vmWithThreeTabs();
      expect(tabOrder(vm), ['ex1', 'ex2', 'ex3']);

      // Delete the MIDDLE tab — the only place where "put it back where it
      // was" and "put it at the end" are different arrangements.
      vm.removeExerciseSlot(1);
      async.flushMicrotasks();
      expect(tabOrder(vm), ['ex1', 'ex3']);
      expect(vm.deletedPlannedExerciseEntries.map((e) => e.name), [
        'Back Squat',
      ]);
      expect(
        repo.reorderLog.last,
        ['se1', 'se2', 'se3'],
        reason:
            'the deleted exercise keeps its NUMBER — the persisted '
            'arrangement is written over the full bar, holes included, so a '
            'restart re-seeds it at its old slot',
      );

      await vm.restoreDeletedPlannedExerciseAt(0);
      async.flushMicrotasks();

      expect(
        tabOrder(vm),
        ['ex1', 'ex2', 'ex3'],
        reason:
            'delete + restore is a round trip: the tab lands back in its '
            'old slot, not at the end',
      );
      expect(
        vm.activeSlotIndex,
        1,
        reason: 'and the restored tab is the one on screen',
      );
      expect(
        repo.reorderLog.last,
        ['se1', 'se2', 'se3'],
        reason:
            'the restored arrangement is persisted, so it is also what a '
            'restart re-seeds',
      );
      vm.dispose();
    });
  });

  test('a tab folded by deleting its last planned set returns to its slot '
      'too', () {
    fakeAsync((async) async {
      final (vm, _) = vmWithThreeTabs();

      // The other road into the trash: the middle exercise's only set goes,
      // so its tab folds into a minus entry.
      vm.deleteSetById('s2');
      async.flushMicrotasks();
      expect(tabOrder(vm), ['ex1', 'ex3']);

      await vm.restoreDeletedPlannedExerciseAt(0);
      async.flushMicrotasks();
      expect(tabOrder(vm), ['ex1', 'ex2', 'ex3']);
      expect(vm.activeSlotIndex, 1);
      expect(repo.reorderLog.last, ['se1', 'se2', 'se3']);
      vm.dispose();
    });
  });

  test('the trash menu VIEWS a deleted exercise — the restore is its own '
      'button', () {
    fakeAsync((async) async {
      final (vm, _) = vmWithThreeTabs();
      vm.removeExerciseSlot(1);
      async.flushMicrotasks();
      expect(tabOrder(vm), ['ex1', 'ex3']);

      // Opening it does NOT restore — the row is a reading.
      await vm.viewDeletedPlannedExerciseAt(0);
      async.flushMicrotasks();
      expect(vm.deletedViewSeId, 'se2');
      expect(tabOrder(vm), [
        'ex1',
        'ex3',
      ], reason: 'looking is not writing — nothing came back');
      expect(vm.deletedViewSets.map((s) => s.sessionExerciseSetId), [
        's2',
      ], reason: 'the rows it kept are what the card shows, red');

      // Leaving the view restores nothing either.
      vm.exitDeletedView();
      expect(vm.deletedViewSeId, isNull);
      expect(vm.deletedPlannedExerciseEntries, hasLength(1));

      // The Restore button under the card is the write.
      await vm.viewDeletedPlannedExerciseAt(0);
      async.flushMicrotasks();
      await vm.restoreViewedDeletedExercise();
      async.flushMicrotasks();
      expect(
        vm.deletedViewSeId,
        isNull,
        reason: 'the restore leaves the view — it is a tab again',
      );
      expect(tabOrder(vm), [
        'ex1',
        'ex2',
        'ex3',
      ], reason: 'the button brings it back at its slot');
      expect(vm.deletedPlannedExerciseEntries, isEmpty);
      vm.dispose();
    });
  });

  test('a tab switch leaves the deleted view', () {
    fakeAsync((async) async {
      final (vm, _) = vmWithThreeTabs();
      vm.removeExerciseSlot(1);
      async.flushMicrotasks();
      await vm.viewDeletedPlannedExerciseAt(0);
      async.flushMicrotasks();
      expect(vm.deletedViewSeId, isNotNull);

      await vm.tapTab(0);
      async.flushMicrotasks();
      expect(
        vm.deletedViewSeId,
        isNull,
        reason: 'the tab tapped is what is on screen now',
      );
      expect(tabOrder(vm), [
        'ex1',
        'ex3',
      ], reason: 'still not restored — only the view ended');
      vm.dispose();
    });
  });

  test('a user-added set under a PLANNED exercise flags too — its Restore '
      'brings back everything underneath it', () {
    fakeAsync((async) async {
      final (vm, _) = vmWithPlannedRows();
      // A set the user added to the planned exercise itself.
      repo.rows['s3'] = repo.row(
        setId: 's3',
        setNumber: 3,
        plannedSetId: null,
        weight: 30,
        reps: [8],
      );
      repo.emit();
      async.flushMicrotasks();
      expect(vm.sets.map((s) => s.sessionExerciseSetId), contains('s3'));

      vm.deleteSetById('s3');
      async.flushMicrotasks();
      expect(
        repo.rows.containsKey('s3'),
        isTrue,
        reason:
            'under a planned exercise nothing is destroyed by a '
            'delete — the plan is the thing being restored against',
      );
      expect(repo.rows['s3']!.isDeleted, isTrue);
      expect(repo.deleteSetCalls, 0);
      expect(
        vm.deletedSetsForExercise('ex1').map((s) => s.sessionExerciseSetId),
        contains('s3'),
      );
      expect(
        vm.activeSlotHasDeletedSets,
        isTrue,
        reason: 'the Restore under the card lights',
      );

      await vm.restoreDeletedSetsForActiveExercise();
      async.flushMicrotasks();
      expect(repo.rows['s3']!.isDeleted, isFalse);
      expect(vm.sets.map((s) => s.sessionExerciseSetId), contains('s3'));
      expect(
        vm.exerciseSlots,
        hasLength(1),
        reason: 'the exercise never left the bar — no tab was added',
      );

      // One undo puts the deletion back, and takes no tab with it.
      await vm.undo();
      async.flushMicrotasks();
      expect(repo.rows['s3']!.isDeleted, isTrue);
      expect(vm.exerciseSlots, hasLength(1));
      vm.dispose();
    });
  });

  test('deleting a planned exercise keeps its user-added sets too — the '
      'restore brings everything back', () {
    fakeAsync((async) async {
      final (vm, _) = vmWithPlannedRows();
      repo.rows['s3'] = repo.row(
        setId: 's3',
        setNumber: 3,
        weight: 30,
        reps: [8],
      );
      repo.emit();
      async.flushMicrotasks();

      await vm.removeExerciseSlot(0);
      async.flushMicrotasks();
      expect(
        repo.rows.containsKey('s3'),
        isTrue,
        reason: 'the user row flags — it is not destroyed',
      );
      expect(repo.rows['s3']!.isDeleted, isTrue);
      expect(repo.deleteSetCalls, 0);

      // The trash view shows every row it kept, planned and user alike.
      await vm.viewDeletedPlannedExerciseAt(0);
      async.flushMicrotasks();
      expect(
        vm.deletedViewSets.map((s) => s.sessionExerciseSetId),
        containsAll(['s1', 's2', 's3']),
      );

      await vm.restoreViewedDeletedExercise();
      async.flushMicrotasks();
      expect(repo.rows['s3']!.isDeleted, isFalse);
      expect(
        vm.sets.map((s) => s.sessionExerciseSetId),
        containsAll(['s1', 's2', 's3']),
        reason: 'everything underneath the deleted exercise came back',
      );
      vm.dispose();
    });
  });

  test('an undo leaves the deleted view — it can never rewrite what is '
      'being read', () {
    fakeAsync((async) async {
      final (vm, _) = vmWithThreeTabs();
      vm.removeExerciseSlot(1);
      async.flushMicrotasks();
      await vm.viewDeletedPlannedExerciseAt(0);
      async.flushMicrotasks();
      expect(vm.deletedViewSeId, isNotNull);

      // The stats bar greys the pair inside the view, so this is the belt
      // under that: a programmatic undo closes the view before it runs.
      await vm.undo();
      async.flushMicrotasks();
      expect(
        vm.deletedViewSeId,
        isNull,
        reason: 'the view never survives an action that can rewrite it',
      );
      expect(tabOrder(vm), [
        'ex1',
        'ex2',
        'ex3',
      ], reason: 'and the undo itself still did its work — the tab is back');
      vm.dispose();
    });
  });

  // ── Another device's live session (2026-10-15) ─────────────────────────────

  test('a live session from another device is OFFERED, never adopted — and '
      'mine is never called foreign', () {
    fakeAsync((async) async {
      final vm = buildVm();
      async.flushMicrotasks();
      expect(vm.currentWorkoutId, 'w1', reason: 'mine, resumed at launch');

      repo.emitActive([foreignSession('w-b')]);
      async.flushMicrotasks();
      expect(vm.foreignActiveSessions.map((s) => s.sessionId), ['w-b']);
      expect(
        vm.currentWorkoutId,
        'w1',
        reason: 'nothing was adopted — the notice offers, the user picks',
      );

      // My own session is never foreign…
      repo.emitActive([
        foreignSession('w-b'),
        Session(
          sessionId: 'w1',
          userId: 'u1',
          createdDatetime: DateTime(2026, 10, 15, 8),
          deviceId: 'dev-a',
        ),
      ]);
      async.flushMicrotasks();
      expect(vm.foreignActiveSessions.map((s) => s.sessionId), ['w-b']);

      // …and neither is the session currently on screen, whatever its row
      // says (a switch claims it, or an old client wrote no device id).
      repo.emitActive([
        Session(
          sessionId: 'w1',
          userId: 'u1',
          createdDatetime: DateTime(2026, 10, 15, 8),
        ),
        Session(
          sessionId: 'w-old',
          userId: 'u1',
          createdDatetime: DateTime(2026, 10, 15, 7),
        ),
      ]);
      async.flushMicrotasks();
      expect(
        vm.foreignActiveSessions.map((s) => s.sessionId),
        ['w-old'],
        reason:
            'a row with no device id reads as another device\'s — the '
            'safe reading',
      );

      // Stay dismisses them for the rest of the run.
      vm.dismissForeignSession('w-old');
      expect(vm.foreignActiveSessions, isEmpty);
      repo.emitActive([
        Session(
          sessionId: 'w-old',
          userId: 'u1',
          createdDatetime: DateTime(2026, 10, 15, 7),
        ),
      ]);
      async.flushMicrotasks();
      expect(
        vm.foreignActiveSessions,
        isEmpty,
        reason: 'a dismissed session does not come back to ask again',
      );
      vm.dispose();
    });
  });

  test('Switch with no session of mine adopts it and claims it', () {
    fakeAsync((async) async {
      repo.activeSessionId = null;
      final vm = buildVm();
      async.flushMicrotasks();
      expect(vm.currentWorkoutId, isNull);

      repo.emitActive([foreignSession('w-b')]);
      async.flushMicrotasks();
      expect(vm.foreignActiveSessions, hasLength(1));

      await vm.switchToForeignSession('w-b', completeMine: false);
      async.flushMicrotasks();
      expect(vm.currentWorkoutId, 'w-b');
      expect(repo.claimed, [
        (sessionId: 'w-b', deviceId: 'dev-a'),
      ], reason: 'the row is claimed, so the next launch resumes it HERE');
      expect(vm.foreignActiveSessions, isEmpty);
      expect(repo.endedSessionId, isNull);
      expect(
        repo.deletedSessions,
        isEmpty,
        reason: 'there was no session of mine to trade',
      );
      vm.dispose();
    });
  });

  test('Switch with mine in progress COMPLETES mine — ended and filed, '
      'never discarded', () {
    fakeAsync((async) async {
      final vm = buildVm();
      async.flushMicrotasks();
      expect(vm.currentWorkoutId, 'w1');

      repo.emitActive([foreignSession('w-b')]);
      async.flushMicrotasks();

      await vm.switchToForeignSession('w-b', completeMine: true);
      async.flushMicrotasks();
      expect(
        repo.endedSessionId,
        'w1',
        reason: 'complete ends the session — it lands in the logs',
      );
      expect(repo.deletedSessions, isEmpty, reason: 'complete never discards');
      expect(vm.currentWorkoutId, 'w-b');
      expect(repo.claimed, [(sessionId: 'w-b', deviceId: 'dev-a')]);
      vm.dispose();
    });
  });

  test('Switch with mine in progress CANCELS mine — discarded outright', () {
    fakeAsync((async) async {
      final vm = buildVm();
      async.flushMicrotasks();

      repo.emitActive([foreignSession('w-b')]);
      async.flushMicrotasks();

      await vm.switchToForeignSession('w-b', completeMine: false);
      async.flushMicrotasks();
      expect(repo.deletedSessions, [
        'w1',
      ], reason: 'cancel discards the session and its sets');
      expect(
        repo.endedSessionId,
        isNull,
        reason: 'cancel never files it in the logs',
      );
      expect(vm.currentWorkoutId, 'w-b');
      vm.dispose();
    });
  });

  test('a session that ENDED while it was being previewed is not adopted', () {
    fakeAsync((async) async {
      final vm = buildVm();
      async.flushMicrotasks();
      expect(vm.currentWorkoutId, 'w1');

      repo.emitActive([foreignSession('w-b')]);
      async.flushMicrotasks();

      // The other device finished it while the user was reading the preview.
      repo.fetchedSession = Session(
        sessionId: 'w-b',
        userId: 'u1',
        createdDatetime: DateTime(2026, 10, 15, 9, 30),
        endDatetime: DateTime(2026, 10, 15, 10),
        deviceId: 'dev-b',
      );
      final switched = await vm.switchToForeignSession(
        'w-b',
        completeMine: false,
      );
      async.flushMicrotasks();
      expect(switched, isFalse);
      expect(
        vm.currentWorkoutId,
        'w1',
        reason: 'mine is untouched — nothing was swapped',
      );
      expect(repo.deletedSessions, isEmpty);
      expect(repo.endedSessionId, isNull);
      expect(repo.claimed, isEmpty);
      vm.dispose();
    });
  });

  test('a user-added row still hard-deletes, and undo re-inserts it', () {
    fakeAsync((async) async {
      final (vm, _) = vmWithPlannedRows();
      vm.addExerciseSlot('ex2');
      async.flushMicrotasks();
      final addedId = vm.sets
          .map((s) => s.sessionExerciseSetId)
          .firstWhere((id) => repo.rows[id]?.plannedSetId == null);
      vm.deleteSetById(addedId);
      async.flushMicrotasks();
      expect(
        repo.rows.containsKey(addedId),
        isFalse,
        reason: 'non-planned rows hard-delete as before',
      );

      await vm.undo();
      async.flushMicrotasks();
      expect(
        vm.sets.map((s) => s.sessionExerciseSetId),
        isNot(contains(addedId)),
        reason: 'the re-inserted row gets a fresh id',
      );
      expect(
        vm.sets.any((s) => s.exerciseId == 'ex2' && s.plannedSetId == null),
        isTrue,
        reason: 'the row is back in the grid under its exercise',
      );
      vm.dispose();
    });
  });

  test('adding an exercise is undoable', () {
    fakeAsync((async) async {
      final (vm, _) = vmWithPlannedRows();
      vm.addExerciseSlot('ex2');
      async.flushMicrotasks();
      expect(vm.exerciseSlots.map((s) => s.exerciseIds.first), contains('ex2'));

      await vm.undo();
      async.flushMicrotasks();
      expect(
        vm.exerciseSlots.map((s) => s.exerciseIds.first),
        isNot(contains('ex2')),
      );
      expect(
        repo.deleteSessionExerciseCalls,
        1,
        reason: 'the inverse deletes the created exercise row',
      );
      vm.dispose();
    });
  });

  test('history clears when the session ends or cancels', () {
    fakeAsync((async) async {
      final (vm, _) = vmWithPlannedRows();
      vm.addExerciseSlot('ex2');
      async.flushMicrotasks();
      expect(vm.canUndo, isTrue);

      await vm.cancelSession();
      async.flushMicrotasks();
      expect(
        vm.canUndo,
        isFalse,
        reason: 'a new session starts with an empty history',
      );
      expect(vm.canRedo, isFalse);
      vm.dispose();
    });
  });

  test('undo and redo pair across a soft delete', () {
    fakeAsync((async) async {
      final (vm, _) = vmWithPlannedRows();
      vm.deleteSetById('s1');
      async.flushMicrotasks();

      await vm.undo();
      async.flushMicrotasks();
      expect(repo.rows['s1']!.isDeleted, isFalse);

      await vm.redo();
      async.flushMicrotasks();
      expect(
        repo.rows['s1']!.isDeleted,
        isTrue,
        reason: 'redo re-runs the forward (flag again)',
      );
      vm.dispose();
    });
  });
}

class FakeProgramRepository extends Fake implements ProgramRepository {}

class FakeProgramRunRepository extends Fake implements ProgramRunRepository {}

class FakeExerciseNoteRepository extends Fake implements ExerciseNoteRepository {}

class FakePlannedSessionRepository extends Fake
    implements PlannedSessionRepository {}
