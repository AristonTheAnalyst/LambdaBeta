import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/cache/past_sets_timeline_cache.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/session.dart';
import 'package:lambda/data/models/session_exercise.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/logs/viewmodel/session_detail_viewmodel.dart';

/// The past-session editor's undo/redo (2026-10-13): structural actions
/// (groups, sets, reorders, drafts) push inverse/replay pairs; typed edits
/// never enter the stack.
class _FakeSessionRepo extends Fake implements SessionRepository {
  final rows = <String, SessionExerciseSet>{};
  final exercises = <String, SessionExercise>{};
  int insertSetCalls = 0;
  int deleteSetCalls = 0;
  int deleteSessionExerciseCalls = 0;
  int insertExerciseCalls = 0;
  int reorderSetsCalls = 0;
  final lastReorderIds = <String>[];

  Session session() => Session(
    sessionId: 'w1',
    userId: 'u1',
    createdDatetime: DateTime(2026, 10, 10),
    endDatetime: DateTime(2026, 10, 10, 10),
  );

  SessionExerciseSet row(
    String setId, {
    double? weight = 40,
    List<num> reps = const [5],
    int setNumber = 1,
    String sessionExerciseId = 'se1',
    String exerciseId = 'ex1',
    String? plannedSetId,
    bool isDeleted = false,
  }) => SessionExerciseSet(
    sessionExerciseSetId: setId,
    sessionExerciseId: sessionExerciseId,
    sessionId: 'w1',
    userId: 'u1',
    exerciseId: exerciseId,
    setNumber: setNumber,
    weight: weight,
    reps: reps,
    plannedSetId: plannedSetId,
    isDeleted: isDeleted,
  );

  @override
  Future<void> updateSet(
    String setId, {
    String? variationId,
    double? weight,
    List<num>? reps,
    String? notes,
    bool clearVariation = false,
    bool clearWeight = false,
    bool clearReps = false,
    bool clearNotes = false,
    bool isDeleted = false,
    bool clearIsDeleted = false,
  }) async {
    final existing = rows[setId];
    if (existing == null) return;
    rows[setId] = SessionExerciseSet(
      sessionExerciseSetId: existing.sessionExerciseSetId,
      sessionExerciseId: existing.sessionExerciseId,
      sessionId: existing.sessionId,
      userId: existing.userId,
      exerciseId: existing.exerciseId,
      variationId: clearVariation
          ? null
          : (variationId ?? existing.variationId),
      setNumber: existing.setNumber,
      weight: clearWeight ? null : (weight ?? existing.weight),
      reps: clearReps ? const [] : (reps ?? existing.reps),
      notes: clearNotes ? null : (notes ?? existing.notes),
      plannedSetId: existing.plannedSetId,
      isDeleted: clearIsDeleted ? false : (isDeleted || existing.isDeleted),
    );
  }

  @override
  Future<Session?> fetchSession(String sessionId) async => session();

  @override
  Future<List<SessionExercise>> loadSessionExercises(String sessionId) async {
    if (exercises.isEmpty) {
      exercises['se1'] = const SessionExercise(
        sessionExerciseId: 'se1',
        sessionId: 'w1',
        userId: 'u1',
        exerciseOrder: 1,
        exerciseId: 'ex1',
      );
    }
    return exercises.values.toList();
  }

  @override
  Future<List<SessionExerciseSet>> loadSetsForSession(String sessionId) async =>
      rows.values.toList();

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
    insertSetCalls++;
    final id = 'new-${rows.length + 1}';
    rows[id] = row(
      id,
      weight: weight,
      reps: reps,
      setNumber: setNumber,
      sessionExerciseId: sessionExerciseId,
      plannedSetId: plannedSetId,
    );
    return rows[id]!;
  }

  @override
  Future<void> deleteSet(String setId) async {
    deleteSetCalls++;
    rows.remove(setId);
  }

  @override
  Future<SessionExercise> insertSessionExercise({
    required String sessionId,
    required String userId,
    required int exerciseOrder,
    String? exerciseId,
    String? plannedExerciseId,
  }) async {
    insertExerciseCalls++;
    final id = 'se-${exercises.length + 1}';
    exercises[id] = SessionExercise(
      sessionExerciseId: id,
      sessionId: sessionId,
      userId: userId,
      exerciseOrder: exerciseOrder,
      exerciseId: exerciseId,
    );
    return exercises[id]!;
  }

  @override
  Future<void> deleteSessionExercise(String sessionExerciseId) async {
    deleteSessionExerciseCalls++;
    exercises.remove(sessionExerciseId);
  }

  @override
  Future<void> reorderSets(String sessionId, List<String> orderedSetIds) async {
    reorderSetsCalls++;
    lastReorderIds
      ..clear()
      ..addAll(orderedSetIds);
  }

  @override
  Future<void> reorderSessionExercises(
    String sessionId,
    List<String> orderedSessionExerciseIds,
  ) async {
    lastExerciseOrder
      ..clear()
      ..addAll(orderedSessionExerciseIds);
  }

  final lastExerciseOrder = <String>[];
}

class _FakeExerciseRepo extends Fake implements ExerciseRepository {
  @override
  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
    String userId,
  ) async => {
    for (final (id, name) in const [
      ('ex1', 'Bench Press'),
      ('ex2', 'Back Squat'),
      ('ex3', 'Overhead Press'),
    ])
      id: ExerciseDetail(
        exercise: CustomExercise(exerciseId: id, userId: userId, name: name),
      ),
  };

  @override
  Future<List<CustomVariation>> fetchVariations(String userId) async => [];
}

class _FakeLessonRepo extends Fake implements LessonRepository {}

void main() {
  late _FakeSessionRepo repo;

  SessionDetailViewModel buildVm() => SessionDetailViewModel(
    sessionRepo: repo,
    exerciseRepo: _FakeExerciseRepo(),
    lessonRepo: _FakeLessonRepo(),
    userId: 'u1',
  );

  setUp(() {
    repo = _FakeSessionRepo();
    PastSetsTimelineCache.loaderOverride = (u) async => [
      PastSetRow(
        sessionExerciseSetId: 's1',
        sessionExerciseId: 'se1',
        sessionId: 'w1',
        userId: u,
        exerciseId: 'ex1',
        setNumber: 1,
        reps: const [5],
        sessionCreatedDate: DateTime(2026, 10, 10, 10),
        weight: 40,
      ),
    ];
    PastSetsTimelineCache.instance.invalidate();
  });

  tearDown(() {
    PastSetsTimelineCache.loaderOverride = null;
    PastSetsTimelineCache.instance.invalidate();
  });

  test('deleting a set is undoable — the row comes back', () {
    fakeAsync((async) async {
      final vm = buildVm();
      repo.rows['s1'] = repo.row('s1', weight: 60, reps: [5]);
      vm.load('w1');
      async.flushMicrotasks();

      await vm.deleteSetCascade('s1', 'ex1');
      async.flushMicrotasks();
      expect(repo.rows.containsKey('s1'), isFalse);
      expect(vm.canUndo, isTrue);

      await vm.undo();
      async.flushMicrotasks();
      expect(
        vm.state.value.setsFor(1).any((s) => s.weight == 60),
        isTrue,
        reason: 'the inverse re-inserts the row with its values (fresh id)',
      );
      vm.dispose();
    });
  });

  test('adding an exercise group is undoable', () {
    fakeAsync((async) async {
      final vm = buildVm();
      vm.load('w1');
      async.flushMicrotasks();

      await vm.addExerciseGroup('ex2');
      async.flushMicrotasks();
      expect(vm.state.value.exerciseSlots, hasLength(2));

      await vm.undo();
      async.flushMicrotasks();
      expect(vm.state.value.exerciseSlots, hasLength(1));
      expect(repo.deleteSessionExerciseCalls, 1);
      vm.dispose();
    });
  });

  test('reordering sets is undoable', () {
    fakeAsync((async) async {
      final vm = buildVm();
      repo.rows['s1'] = repo.row('s1', setNumber: 1);
      repo.rows['s2'] = repo.row('s2', setNumber: 2);
      vm.load('w1');
      async.flushMicrotasks();

      vm.reorderSets(1, 0, 1);
      async.flushMicrotasks();
      expect(vm.state.value.setsFor(1).map((s) => s.setNumber), isNot([1, 2]));

      await vm.undo();
      async.flushMicrotasks();
      expect(
        vm.state.value.setsFor(1).map((s) => s.setNumber),
        containsAll([1, 2]),
        reason: 'the inverse renumbers back to the captured order',
      );
      vm.dispose();
    });
  });

  test('typed edits never enter the history', () {
    fakeAsync((async) async {
      final vm = buildVm();
      repo.rows['s1'] = repo.row('s1', weight: 60, reps: [5]);
      vm.load('w1');
      async.flushMicrotasks();

      vm.quickUpdateSet(repo.rows['s1']!, weight: 70, immediate: true);
      async.flushMicrotasks();
      expect(
        vm.canUndo,
        isFalse,
        reason: 'undo covers structure, not typed values',
      );
      vm.dispose();
    });
  });

  test('starting edit mode clears the history', () {
    fakeAsync((async) async {
      final vm = buildVm();
      vm.load('w1');
      async.flushMicrotasks();
      await vm.addExerciseGroup('ex2');
      async.flushMicrotasks();
      expect(vm.canUndo, isTrue);

      vm.startEditing();
      expect(vm.canUndo, isFalse);
      vm.dispose();
    });
  });

  // ── The historic trash (2026-10-14) ────────────────────────────────────────

  test('a planned set soft-deletes in the editor — flagged, red, and the '
      'group folds when it was the last active row', () {
    fakeAsync((async) async {
      final vm = buildVm();
      repo.rows['s1'] = repo.row('s1', plannedSetId: 'ps1');
      repo.rows['s2'] = repo.row('s2', setNumber: 2, plannedSetId: 'ps2');
      vm.load('w1');
      async.flushMicrotasks();

      await vm.deleteSetCascade('s1', 'ex1');
      async.flushMicrotasks();
      expect(
        repo.rows['s1']!.isDeleted,
        isTrue,
        reason: 'a planned row flags instead of vanishing',
      );
      expect(
        vm.state.value.exerciseSlots.single.deleted,
        isFalse,
        reason: 's2 is still performed — the exercise is not deleted',
      );
      expect(
        vm.state.value
            .setsFor(1)
            .firstWhere((s) => s.sessionExerciseSetId == 's1')
            .isDeleted,
        isTrue,
        reason: 'the red row stays in the grid',
      );

      await vm.deleteSetCascade('s2', 'ex1');
      async.flushMicrotasks();
      expect(
        vm.state.value.exerciseSlots.single.deleted,
        isTrue,
        reason: 'no active rows left — the group folds to deleted',
      );
      expect(vm.hasDeletedExercises, isTrue);
      expect(vm.deletedExerciseEntries.single.name, 'Bench Press');

      // Restore: un-flag both, the slot is an ordinary tab again.
      await vm.restoreDeletedExercise(0);
      async.flushMicrotasks();
      expect(repo.rows['s1']!.isDeleted, isFalse);
      expect(repo.rows['s2']!.isDeleted, isFalse);
      expect(vm.state.value.exerciseSlots.single.deleted, isFalse);
      expect(vm.deletedExerciseEntries, isEmpty);

      // One undo puts it back in the trash.
      await vm.undo();
      async.flushMicrotasks();
      expect(repo.rows['s1']!.isDeleted, isTrue);
      expect(vm.state.value.exerciseSlots.single.deleted, isTrue);
      vm.dispose();
    });
  });

  test('the trash lists deleted exercises in arrangement order — the number '
      'they held', () {
    fakeAsync((async) async {
      final vm = buildVm();
      // Three planned exercises; the MIDDLE one is deleted, so "order" and
      // "newest first" are not the same arrangement.
      repo.exercises['se1'] = const SessionExercise(
        sessionExerciseId: 'se1',
        sessionId: 'w1',
        userId: 'u1',
        exerciseOrder: 1,
        exerciseId: 'ex1',
      );
      repo.exercises['se2'] = const SessionExercise(
        sessionExerciseId: 'se2',
        sessionId: 'w1',
        userId: 'u1',
        exerciseOrder: 2,
        exerciseId: 'ex2',
      );
      repo.exercises['se3'] = const SessionExercise(
        sessionExerciseId: 'se3',
        sessionId: 'w1',
        userId: 'u1',
        exerciseOrder: 3,
        exerciseId: 'ex3',
      );
      repo.rows['s1'] = repo.row('s1', plannedSetId: 'ps1');
      repo.rows['s2'] = repo.row(
        's2',
        sessionExerciseId: 'se2',
        exerciseId: 'ex2',
        plannedSetId: 'ps2',
      );
      repo.rows['s3'] = repo.row(
        's3',
        sessionExerciseId: 'se3',
        exerciseId: 'ex3',
        plannedSetId: 'ps3',
      );
      vm.load('w1');
      async.flushMicrotasks();
      expect(vm.state.value.exerciseSlots, hasLength(3));

      await vm.removeExerciseGroup(1);
      async.flushMicrotasks();
      expect(
        vm.state.value.exerciseSlots[1].deleted,
        isTrue,
        reason: 'the deleted exercise keeps its slot, at its number',
      );
      expect(vm.deletedExerciseEntries.single.name, 'Back Squat');
      expect(vm.deletedExerciseEntries.single.slotIndex, 1);
      expect(
        repo.deleteSessionExerciseCalls,
        0,
        reason:
            'the exercise row survives — it carries the identity and '
            'the number',
      );
      expect(repo.lastExerciseOrder, [
        'se1',
        'se2',
        'se3',
      ], reason: 'the persisted arrangement keeps the deleted one in place');

      // The trash row views it…
      vm.viewDeletedExerciseAt(0);
      expect(vm.state.value.activeSlotIndex, 1);

      // …and the Restore brings the group back at its number.
      await vm.restoreDeletedExerciseAt(0);
      async.flushMicrotasks();
      expect(vm.state.value.exerciseSlots[1].deleted, isFalse);
      expect(repo.rows['s2']!.isDeleted, isFalse);
      vm.dispose();
    });
  });

  test('a user-added set under a planned exercise flags in the editor too — '
      'and the Restore under the card brings it back', () {
    fakeAsync((async) async {
      final vm = buildVm();
      repo.exercises['se1'] = const SessionExercise(
        sessionExerciseId: 'se1',
        sessionId: 'w1',
        userId: 'u1',
        exerciseOrder: 1,
        exerciseId: 'ex1',
        plannedExerciseId: 'pe1',
      );
      repo.rows['s1'] = repo.row('s1', plannedSetId: 'ps1');
      // The user's own addition, under the plan-linked exercise.
      repo.rows['s2'] = repo.row('s2', setNumber: 2, plannedSetId: null);
      vm.load('w1');
      async.flushMicrotasks();

      await vm.deleteSetCascade('s2', 'ex1');
      async.flushMicrotasks();
      expect(
        repo.rows.containsKey('s2'),
        isTrue,
        reason:
            'under a planned exercise the editor flags too — nothing '
            'is destroyed',
      );
      expect(repo.rows['s2']!.isDeleted, isTrue);
      expect(
        vm.state.value.exerciseSlots.single.deleted,
        isFalse,
        reason: 's1 keeps the exercise alive',
      );

      await vm.restoreDeletedExercise(0);
      async.flushMicrotasks();
      expect(
        repo.rows['s2']!.isDeleted,
        isFalse,
        reason: 'the Restore under the card un-flags everything under it',
      );
      vm.dispose();
    });
  });

  test('a fully user-added group still removes entirely — nothing planned '
      'to keep', () {
    fakeAsync((async) async {
      final vm = buildVm();
      vm.load('w1');
      async.flushMicrotasks();
      await vm.addExerciseGroup('ex2');
      async.flushMicrotasks();
      expect(vm.state.value.exerciseSlots, hasLength(2));

      await vm.removeExerciseGroup(1);
      async.flushMicrotasks();
      expect(
        vm.state.value.exerciseSlots,
        hasLength(1),
        reason: 'no planned rows — the group goes, as it always did',
      );
      expect(repo.deleteSessionExerciseCalls, 1);
      vm.dispose();
    });
  });
}
