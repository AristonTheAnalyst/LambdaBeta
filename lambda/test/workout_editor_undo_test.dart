import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/planned_session_exercise.dart';
import 'package:lambda/data/models/planned_session_exercise_set.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/exercise_note_repository.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/programs/viewmodel/workout_editor_viewmodel.dart';

/// The planner's undo/redo (2026-10-13): dim rows soft-delete, so the
/// inverses un-archive with captured order; inserts are re-archived by the
/// boxed fresh ids; typed edits never enter the stack.
class _FakePlanRepo extends Fake implements PlannedSessionRepository {
  final exercises = <String, PlannedSessionExercise>{};
  final sets = <String, PlannedSessionExerciseSet>{};
  final archivedExercises = <String, PlannedSessionExercise>{};
  final archivedSets = <String, PlannedSessionExerciseSet>{};
  int deleteExerciseCalls = 0;
  int deleteSetCalls = 0;
  int restoreExerciseCalls = 0;
  int restoreSetCalls = 0;

  PlannedSessionExercise ex(
    String id, {
    int order = 1,
    String? exerciseId = 'ex1',
  }) => PlannedSessionExercise(
    plannedExerciseId: id,
    plannedSessionId: 'ps1',
    userId: 'u1',
    exerciseId: exerciseId,
    exerciseOrder: order,
  );

  PlannedSessionExerciseSet pset(String id, {int number = 1}) =>
      PlannedSessionExerciseSet(
        plannedSetId: id,
        plannedExerciseId: 'pe1',
        plannedSessionId: 'ps1',
        userId: 'u1',
        setNumber: number,
        targetWeight: '60',
        targetReps: '10',
      );

  @override
  Future<PlannedSession?> fetchPlannedSessionById(String sessionId) async =>
      PlannedSession(sessionId: sessionId, userId: 'u1', name: 'Push Day');

  @override
  Future<PlannedSessionExercise> createPlannedExercise(
    String userId,
    String plannedSessionId, {
    String? exerciseId,
    required int exerciseOrder,
  }) async {
    final id = 'pe-${exercises.length + archivedExercises.length + 1}';
    exercises[id] = ex(id, exerciseId: exerciseId, order: exerciseOrder);
    return exercises[id]!;
  }

  @override
  Future<void> deletePlannedExercise(String plannedExerciseId) async {
    deleteExerciseCalls++;
    final e = exercises.remove(plannedExerciseId);
    if (e != null) archivedExercises[plannedExerciseId] = e;
  }

  @override
  Future<void> restorePlannedExercise(
    String plannedExerciseId, {
    required int exerciseOrder,
  }) async {
    restoreExerciseCalls++;
    final e = archivedExercises.remove(plannedExerciseId);
    if (e != null) {
      exercises[plannedExerciseId] = ex(
        plannedExerciseId,
        exerciseId: e.exerciseId,
        order: exerciseOrder,
      );
    }
  }

  @override
  Future<void> restorePlannedSet(
    String plannedSetId, {
    required int setNumber,
  }) async {
    restoreSetCalls++;
    final s = archivedSets.remove(plannedSetId);
    if (s != null) {
      sets[plannedSetId] = PlannedSessionExerciseSet(
        plannedSetId: plannedSetId,
        plannedExerciseId: s.plannedExerciseId,
        plannedSessionId: s.plannedSessionId,
        userId: s.userId,
        setNumber: setNumber,
        targetWeight: s.targetWeight,
        targetReps: s.targetReps,
      );
    }
  }

  @override
  Future<PlannedSessionExerciseSet> createPlannedSet(
    String userId,
    String plannedExerciseId, {
    required String plannedSessionId,
    String? exerciseId,
    String? variationId,
    required int setNumber,
    String? targetWeight,
    String? targetReps,
    String? targetNotes,
  }) async {
    final id = 'pset-${sets.length + archivedSets.length + 1}';
    sets[id] = PlannedSessionExerciseSet(
      plannedSetId: id,
      plannedExerciseId: plannedExerciseId,
      plannedSessionId: plannedSessionId,
      userId: userId,
      setNumber: setNumber,
      targetWeight: targetWeight,
      targetReps: targetReps,
    );
    return sets[id]!;
  }

  @override
  Future<void> deletePlannedSet(String plannedSetId) async {
    deleteSetCalls++;
    final s = sets.remove(plannedSetId);
    if (s != null) archivedSets[plannedSetId] = s;
  }

  @override
  Future<List<PlannedSessionExercise>> fetchPlannedExercises(
    String plannedSessionId, {
    bool includeArchived = false,
  }) async => [
    for (final e in [...exercises.values]
      ..sort((a, b) => a.exerciseOrder.compareTo(b.exerciseOrder)))
      if (includeArchived || !e.isArchived) e,
  ];

  @override
  Future<List<PlannedSessionExerciseSet>> fetchPlannedSets(
    String plannedSessionId, {
    bool includeArchived = false,
  }) async => [
    for (final s in sets.values)
      if (includeArchived || !s.isArchived) s,
  ];

  @override
  Future<List<PlannedSessionExerciseSet>> readNormalizedPlannedSession(
    String plannedSessionId, {
    bool includeArchived = false,
  }) async => fetchPlannedSets(
    plannedSessionId,
    includeArchived: includeArchived,
  );

  @override
  Future<void> renumberExerciseOrders(
    String plannedSessionId,
    List<(int, int)> orders,
  ) async {}

  @override
  Future<void> renumberPlannedSets(List<String> orderedSetIds) async {}
}

class _FakeExerciseRepo extends Fake implements ExerciseRepository {
  @override
  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
    String userId,
  ) async => {};

  @override
  Future<List<CustomVariation>> fetchVariations(String userId) async => [];
}

class _FakeExerciseNoteRepo extends Fake implements ExerciseNoteRepository {}

void main() {
  late _FakePlanRepo repo;

  WorkoutEditorViewModel buildVm() => WorkoutEditorViewModel(
    exerciseRepo: _FakeExerciseRepo(),
    noteRepo: _FakeExerciseNoteRepo(),
    workoutRepo: FakeSessionRepo(),
    workoutPlanRepo: repo,
    userId: 'u1',
  );

  setUp(() => repo = _FakePlanRepo());

  test('adding an exercise group is undoable — the group archives again', () {
    fakeAsync((async) async {
      final vm = buildVm();
      await vm.openStandaloneWorkout('ps1');
      async.flushMicrotasks();

      await vm.addPlannedExerciseGroup('ex2');
      async.flushMicrotasks();
      expect(vm.state.value.workoutExerciseSlots, hasLength(1));
      expect(vm.canUndo, isTrue);

      await vm.undo();
      async.flushMicrotasks();
      expect(vm.state.value.workoutExerciseSlots, isEmpty);
      expect(
        repo.deleteExerciseCalls,
        1,
        reason: 'the inverse archives the created group',
      );
      vm.dispose();
    });
  });

  test('removing an exercise group is undoable — the group un-archives', () {
    fakeAsync((async) async {
      final vm = buildVm();
      repo.exercises['pe1'] = repo.ex('pe1');
      repo.sets['ps1'] = repo.pset('ps1');
      await vm.openStandaloneWorkout('ps1');
      async.flushMicrotasks();
      expect(vm.state.value.workoutExerciseSlots, hasLength(1));

      await vm.removePlannedExerciseGroup(0);
      async.flushMicrotasks();
      expect(vm.state.value.workoutExerciseSlots, isEmpty);
      expect(repo.deleteExerciseCalls, 1);

      await vm.undo();
      async.flushMicrotasks();
      expect(
        vm.state.value.workoutExerciseSlots,
        hasLength(1),
        reason: 'the inverse un-archives the group with its captured order',
      );
      expect(repo.restoreExerciseCalls, 1);
      expect(repo.restoreSetCalls, 1);
      vm.dispose();
    });
  });

  test('deleting a planned set is undoable — the row un-archives', () {
    fakeAsync((async) async {
      final vm = buildVm();
      repo.exercises['pe1'] = repo.ex('pe1');
      repo.sets['ps1'] = repo.pset('ps1');
      await vm.openStandaloneWorkout('ps1');
      async.flushMicrotasks();

      await vm.deletePlannedSessionExerciseSet('ps1');
      async.flushMicrotasks();
      expect(vm.state.value.workoutPlannedSessionExerciseSets, isEmpty);

      await vm.undo();
      async.flushMicrotasks();
      expect(vm.state.value.workoutPlannedSessionExerciseSets, hasLength(1));
      expect(repo.restoreSetCalls, 1);
      vm.dispose();
    });
  });

  test('duplicating a set is undoable — the copy archives', () {
    fakeAsync((async) async {
      final vm = buildVm();
      repo.exercises['pe1'] = repo.ex('pe1');
      repo.sets['ps1'] = repo.pset('ps1');
      await vm.openStandaloneWorkout('ps1');
      async.flushMicrotasks();

      await vm.duplicatePlannedSessionExerciseSet(repo.sets['ps1']!);
      async.flushMicrotasks();
      expect(vm.state.value.workoutPlannedSessionExerciseSets, hasLength(2));

      await vm.undo();
      async.flushMicrotasks();
      expect(vm.state.value.workoutPlannedSessionExerciseSets, hasLength(1));
      expect(repo.deleteSetCalls, 1);
      vm.dispose();
    });
  });

  test('draft add/remove are undoable map edits', () {
    fakeAsync((async) async {
      final vm = buildVm();
      await vm.openStandaloneWorkout('ps1');
      async.flushMicrotasks();

      vm.addDraftPlannedSessionExerciseSet('pe1');
      expect(vm.state.value.workoutSetDrafts['pe1'], hasLength(1));
      await vm.undo();
      async.flushMicrotasks();
      expect(vm.state.value.workoutSetDrafts['pe1'] ?? const [], isEmpty);

      vm.removeDraftPlannedSessionExerciseSet('pe1', 1);
      await vm.undo();
      async.flushMicrotasks();
      expect(vm.state.value.workoutSetDrafts['pe1'] ?? const [], isNotEmpty);
      vm.dispose();
    });
  });

  test('typed set edits never enter the history', () {
    fakeAsync((async) async {
      final vm = buildVm();
      repo.exercises['pe1'] = repo.ex('pe1');
      repo.sets['ps1'] = repo.pset('ps1');
      await vm.openStandaloneWorkout('ps1');
      async.flushMicrotasks();

      await vm.quickUpdatePlannedSessionExerciseSet(
        repo.sets['ps1']!,
        weight: '70',
      );
      async.flushMicrotasks();
      expect(vm.canUndo, isFalse);
      vm.dispose();
    });
  });

  test('closing the editor clears the history', () {
    fakeAsync((async) async {
      final vm = buildVm();
      await vm.openStandaloneWorkout('ps1');
      async.flushMicrotasks();
      await vm.addPlannedExerciseGroup('ex2');
      async.flushMicrotasks();
      expect(vm.canUndo, isTrue);

      vm.closeWorkoutEditor();
      expect(vm.canUndo, isFalse);
      vm.dispose();
    });
  });
}

class FakeSessionRepo extends Fake implements SessionRepository {}
