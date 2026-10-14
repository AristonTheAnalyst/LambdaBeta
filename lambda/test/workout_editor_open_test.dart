import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/lesson.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/planned_session_exercise.dart';
import 'package:lambda/data/models/planned_session_exercise_set.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/programs/viewmodel/workout_editor_viewmodel.dart';

/// The workout editor's open economy (2026-10-13): one row by id (never the
/// whole standalone list), the read-only normalizing read (zero repair
/// writes on open), and one batched lessons read for all the slots.
class _FakePlanRepo extends Fake implements PlannedSessionRepository {
  int byIdReads = 0;
  int listReads = 0;
  int normalizedReads = 0;
  int writingNormalizedReads = 0;
  int lessonBatchReads = 0;

  @override
  Future<PlannedSession?> fetchPlannedSessionById(String sessionId) async {
    byIdReads++;
    return PlannedSession(sessionId: sessionId, userId: 'u1', name: 'Push Day');
  }

  @override
  Future<List<PlannedSession>> fetchPlannedSessions(
    String userId, {
    String? blockId,
    String? programId,
  }) async {
    listReads++;
    return const [];
  }

  @override
  Future<List<PlannedSessionExercise>> fetchPlannedExercises(
    String plannedSessionId,
  ) async => const [
    PlannedSessionExercise(
      plannedExerciseId: 'pe1',
      plannedSessionId: 'ps1',
      userId: 'u1',
      exerciseId: 'ex1',
      exerciseOrder: 1,
    ),
  ];

  @override
  Future<List<PlannedSessionExerciseSet>> fetchPlannedSets(
    String plannedSessionId,
  ) async => const [
    PlannedSessionExerciseSet(
      plannedSetId: 'pset1',
      plannedExerciseId: 'pe1',
      plannedSessionId: 'ps1',
      userId: 'u1',
      setNumber: 1,
      targetWeight: '60',
      targetReps: '10',
    ),
  ];

  @override
  Future<List<PlannedSessionExerciseSet>> readNormalizedPlannedSession(
    String plannedSessionId,
  ) async {
    normalizedReads++;
    return fetchPlannedSets(plannedSessionId);
  }

  @override
  Future<List<PlannedSessionExerciseSet>> fetchNormalizedPlannedSets(
    String plannedSessionId,
  ) async {
    writingNormalizedReads++;
    return fetchPlannedSets(plannedSessionId);
  }
}

class _FakeLessonRepo extends Fake implements LessonRepository {
  int batchReads = 0;

  @override
  Future<Map<String, List<Lesson>>> fetchLessonsForExercises(
    String userId,
    List<String> exerciseIds,
  ) async {
    batchReads++;
    return {for (final id in exerciseIds) id: const []};
  }

  @override
  Future<List<Lesson>> fetchLessons(String userId, String exerciseId) async =>
      const [];
}

class _FakeExerciseRepo extends Fake implements ExerciseRepository {
  @override
  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
    String userId,
  ) async => const {};

  @override
  Future<List<CustomVariation>> fetchVariations(String userId) async => const [];
}

class _FakeSessionRepo extends Fake implements SessionRepository {}

void main() {
  late _FakePlanRepo planRepo;

  setUp(() => planRepo = _FakePlanRepo());

  WorkoutEditorViewModel buildVm() => WorkoutEditorViewModel(
    exerciseRepo: _FakeExerciseRepo(),
    lessonRepo: _FakeLessonRepo(),
    workoutRepo: _FakeSessionRepo(),
    workoutPlanRepo: planRepo,
    userId: 'u1',
  );

  test('opening a standalone workout reads one row, normalized read-only', () async {
    final vm = buildVm();
    await vm.openStandaloneWorkout('ps1');

    expect(planRepo.listReads, 0,
        reason: 'the whole standalone list is never read to find one id');
    expect(planRepo.byIdReads, 1);
    expect(planRepo.normalizedReads, 1,
        reason: 'the open path normalizes in memory');
    expect(planRepo.writingNormalizedReads, 0,
        reason: 'zero repair writes on open — the writing variant stays on '
            'the save path only');
    expect(vm.state.value.workoutPlannedSessionExerciseSets, hasLength(1));
    expect(vm.state.value.workoutExerciseSlots, hasLength(1));
    vm.dispose();
  });

  test('opening batches the lessons read across the slots', () async {
    final lessons = _FakeLessonRepo();
    final vm = WorkoutEditorViewModel(
      exerciseRepo: _FakeExerciseRepo(),
      lessonRepo: lessons,
      workoutRepo: _FakeSessionRepo(),
      workoutPlanRepo: planRepo,
      userId: 'u1',
    );
    await vm.openStandaloneWorkout('ps1');

    expect(lessons.batchReads, 1,
        reason: 'one IN(...) read for all the slots, not one per exercise');
    vm.dispose();
  });
}
