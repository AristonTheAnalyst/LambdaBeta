import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/cache/past_sets_timeline_cache.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/program_progress.dart';
import 'package:lambda/data/models/session.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:lambda/data/repositories/program_run_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/session/viewmodel/session_viewmodel.dart';

/// The repository's standalone listing, in whatever order the fake hands it
/// out — deliberately NOT re-sorted, so the view model's own ordering is what
/// the tests read.
List<PlannedSession> plannedWorkouts = const [];

/// The Training template picker's recency order (2026-10-26): the workout
/// trained most recently leads, then the newest-created never-logged ones.
///
/// The repository reads its own list in that order, but the picker lives on a
/// page whose timeline is refreshed the moment a session ends — so the view
/// model re-applies the same rule from the timeline it already holds, and the
/// template that was just logged moves to the top without another read.
void main() {
  /// What the cache seam answers with — swapped between reads to stand in for
  /// a session that just ended.
  List<PastSetRow> timeline = const [];

  PastSetRow row({
    required String sessionId,
    String? plannedSessionId,
    required DateTime at,
  }) => PastSetRow(
    sessionExerciseSetId: 'set-$sessionId',
    sessionExerciseId: 'se-$sessionId',
    sessionId: sessionId,
    userId: 'u1',
    setNumber: 1,
    reps: const [5],
    sessionCreatedDate: at,
    plannedSessionId: plannedSessionId,
  );

  PlannedSession workout(String id, {DateTime? created}) =>
      PlannedSession(sessionId: id, userId: 'u1', name: id, createdDate: created);

  SessionViewModel buildVm() => SessionViewModel(
    sessionRepo: _IdleSessionRepo(),
    exerciseRepo: _EmptyExerciseRepo(),
    programRepo: _FakeProgramRepository(),
    programRunRepo: _NoRunProgramRepository(),
    lessonRepo: _FakeLessonRepository(),
    plannedSessionRepo: _FakePlannedSessionRepository(),
    waitForFirstSync: () async {},
    userId: 'u1',
    deviceId: 'dev-a',
  );

  List<String> orderOf(SessionViewModel vm) =>
      [for (final w in vm.standaloneWorkouts) w.sessionId];

  setUp(() {
    timeline = const [];
    plannedWorkouts = const [];
    PastSetsTimelineCache.loaderOverride = (u) async => timeline;
    PastSetsTimelineCache.instance.invalidate();
  });

  tearDown(() {
    PastSetsTimelineCache.loaderOverride = null;
    PastSetsTimelineCache.instance.invalidate();
  });

  test('the picker leads with the workout logged most recently', () {
    fakeAsync((async) {
      plannedWorkouts = [
        workout('t-new', created: DateTime(2026, 10, 20)),
        workout('t-old', created: DateTime(2026, 10, 1)),
      ];
      timeline = [
        row(
          sessionId: 's1',
          plannedSessionId: 't-old',
          at: DateTime(2026, 10, 5),
        ),
      ];

      final vm = buildVm();
      async.flushMicrotasks();

      expect(
        orderOf(vm),
        ['t-old', 't-new'],
        reason: 'logged beats newer-created; creation date only breaks ties',
      );
      vm.dispose();
    });
  });

  test('two never-logged workouts keep newest-created first', () {
    fakeAsync((async) {
      plannedWorkouts = [
        workout('t-a', created: DateTime(2026, 10, 20)),
        workout('t-b', created: DateTime(2026, 10, 1)),
      ];

      final vm = buildVm();
      async.flushMicrotasks();

      expect(orderOf(vm), ['t-a', 't-b']);
      vm.dispose();
    });
  });

  test('a session that just ended floats its template with no list re-read', () {
    fakeAsync((async) {
      // The repository's list never changes in this test: what moves the
      // template is the timeline the finish path refreshes.
      plannedWorkouts = [
        workout('t-a', created: DateTime(2026, 10, 20)),
        workout('t-b', created: DateTime(2026, 10, 1)),
      ];

      final vm = buildVm();
      async.flushMicrotasks();
      expect(orderOf(vm), ['t-a', 't-b']);

      timeline = [
        row(
          sessionId: 's1',
          plannedSessionId: 't-b',
          at: DateTime(2026, 10, 26),
        ),
      ];
      PastSetsTimelineCache.instance.invalidate();
      vm.refreshShownReflection(bumpVersion: false);
      async.flushMicrotasks();

      expect(
        orderOf(vm),
        ['t-b', 't-a'],
        reason: 'the timeline is the one source — the fetched list itself did '
            'not change',
      );
      vm.dispose();
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

/// No program run — the picker's list is the pure standalone case.
class _NoRunProgramRepository extends Fake implements ProgramRunRepository {
  @override
  Future<ProgramProgress?> getProgress(String userId) async => null;
}

class _FakeLessonRepository extends Fake implements LessonRepository {}

class _FakePlannedSessionRepository extends Fake
    implements PlannedSessionRepository {
  @override
  Future<List<PlannedSession>> fetchPlannedSessions(
    String userId, {
    String? programId,
    String? blockId,
  }) async => plannedWorkouts;
}
