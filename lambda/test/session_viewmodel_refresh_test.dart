import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/cache/past_sets_timeline_cache.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/session.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:lambda/data/repositories/program_run_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/session/viewmodel/session_viewmodel.dart';

/// The Home browse's remount signal (2026-10-25).
///
/// `pastSetsVersion` keys `LogsScreen`, so a bump rebuilds the list at
/// offset 0 with its filters cleared. That is right when a session starts or
/// ends — nothing else re-read the list. It is wrong for a refresh that hangs
/// off the list's own reload (deleting a card, returning from the viewer):
/// the timeline is re-read, the reflection card and PR baselines are rebuilt,
/// and the browse stays exactly where the user left it.
void main() {
  /// What the cache seam answers with — swapped between reads to stand in for
  /// a write the repository made.
  List<PastSetRow> timeline = const [];

  PastSetRow row(String sessionId, String setId) => PastSetRow(
    sessionExerciseSetId: setId,
    sessionExerciseId: 'se-$sessionId',
    sessionId: sessionId,
    userId: 'u1',
    exerciseId: 'ex1',
    setNumber: 1,
    reps: const [5],
    sessionCreatedDate: DateTime(2026, 10, 1),
  );

  SessionViewModel buildVm() => SessionViewModel(
    sessionRepo: _IdleSessionRepo(),
    exerciseRepo: _EmptyExerciseRepo(),
    programRepo: _FakeProgramRepository(),
    programRunRepo: _FakeProgramRunRepository(),
    lessonRepo: _FakeLessonRepository(),
    plannedSessionRepo: _FakePlannedSessionRepository(),
    waitForFirstSync: () async {},
    userId: 'u1',
    deviceId: 'dev-a',
  );

  setUp(() {
    timeline = [row('w1', 's1')];
    PastSetsTimelineCache.loaderOverride = (u) async => timeline;
    PastSetsTimelineCache.instance.invalidate();
  });

  tearDown(() {
    PastSetsTimelineCache.loaderOverride = null;
    PastSetsTimelineCache.instance.invalidate();
  });

  test('a refresh behind the list keeps the browse mounted', () {
    fakeAsync((async) {
      final vm = buildVm();
      async.flushMicrotasks();
      final version = vm.pastSetsVersion;
      expect(vm.completedSessionCount, 1);

      // The write behind the refresh: w1 is gone, w2 landed.
      timeline = [row('w2', 's2')];
      PastSetsTimelineCache.instance.invalidate();
      vm.refreshShownReflection(bumpVersion: false);
      async.flushMicrotasks();

      expect(
        vm.pastSetsVersion,
        version,
        reason: 'a bump would remount the browse at offset 0',
      );
      expect(vm.completedSessionCount, 1);
      expect(
        vm.reflectionSession?.sessionId,
        'w2',
        reason: 'the reflection card still recomputes from the fresh read',
      );
    });
  });

  test('a session starting or ending still re-keys the browse', () {
    fakeAsync((async) {
      final vm = buildVm();
      async.flushMicrotasks();
      final version = vm.pastSetsVersion;

      timeline = [row('w1', 's1'), row('w2', 's2')];
      PastSetsTimelineCache.instance.invalidate();
      vm.refreshShownReflection();
      async.flushMicrotasks();

      expect(vm.pastSetsVersion, version + 1);
      expect(vm.completedSessionCount, 2);
    });
  });
}

/// No live session, no foreign sessions — the app as it launches.
class _IdleSessionRepo extends Fake implements SessionRepository {
  @override
  Future<String?> getActiveSessionId(
    String userId, {
    String? deviceId,
  }) async => null;

  @override
  Future<Session?> fetchSession(String sessionId) async => Session(
    sessionId: sessionId,
    userId: 'u1',
    createdDatetime: DateTime(2026, 10, 1),
  );
}

class _EmptyExerciseRepo extends Fake implements ExerciseRepository {
  @override
  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
    String userId,
  ) async => {};

  @override
  Future<List<CustomVariation>> fetchVariations(String userId) async => [];
}

class _FakeProgramRepository extends Fake implements ProgramRepository {}

class _FakeProgramRunRepository extends Fake implements ProgramRunRepository {}

class _FakeLessonRepository extends Fake implements LessonRepository {}

class _FakePlannedSessionRepository extends Fake
    implements PlannedSessionRepository {}
