import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/cache/past_sets_timeline_cache.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/lesson.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/planned_session_exercise_set.dart';
import 'package:lambda/data/models/program_progress.dart';
import 'package:lambda/data/models/session.dart';
import 'package:lambda/data/models/session_exercise.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:lambda/data/repositories/program_run_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/session/model/past_session_seed.dart';
import 'package:lambda/features/session/viewmodel/session_viewmodel.dart';

/// "From past session" (2026-10-26): a completed record seeds the next
/// session — its arrangement, its weights, its plan links, and never its
/// reps or notes. These tests pin the two halves that must agree: what
/// [PastSessionSeed] says Start will write, and what the view model actually
/// writes when Start is pressed.
void main() {
  SessionExercise exercise(String id, int order, {String? plannedId}) =>
      SessionExercise(
        sessionExerciseId: 'se-$id',
        sessionId: 'past',
        userId: 'u1',
        exerciseId: id,
        exerciseOrder: order,
        plannedExerciseId: plannedId,
      );

  SessionExerciseSet set({
    required String id,
    required String exerciseId,
    required int number,
    double? weight,
    // The record always performed something; the copy must never take it.
    List<num> reps = const [5],
    String? variationId,
    String? variationName,
    String? plannedSetId,
    String? sessionExerciseId,
  }) => SessionExerciseSet(
    sessionExerciseSetId: id,
    sessionExerciseId: sessionExerciseId ?? 'se-$exerciseId',
    sessionId: 'past',
    userId: 'u1',
    exerciseId: exerciseId,
    variationId: variationId,
    variationName: variationName,
    setNumber: number,
    weight: weight,
    reps: reps,
    plannedSetId: plannedSetId,
  );

  PlannedSessionExerciseSet target({
    required String id,
    required String exerciseId,
    required int number,
    String? weight,
    String? reps,
    String? variationId,
  }) => PlannedSessionExerciseSet(
    plannedSetId: id,
    plannedExerciseId: 'pe-$exerciseId',
    plannedSessionId: 'plan1',
    userId: 'u1',
    exerciseId: exerciseId,
    variationId: variationId,
    setNumber: number,
    targetWeight: weight,
    targetReps: reps,
  );

  PlannedSession plan() =>
      PlannedSession(sessionId: 'plan1', userId: 'u1', name: 'Push Day');

  Session pastSession({String? plannedSessionId, String? plannedName}) =>
      Session(
        sessionId: 'past',
        userId: 'u1',
        createdDatetime: DateTime(2026, 10, 20),
        endDatetime: DateTime(2026, 10, 20, 1),
        plannedSessionId: plannedSessionId,
        plannedSessionName: plannedName,
      );

  PastSessionSeed seedOf({
    required List<SessionExercise> exercises,
    required List<SessionExerciseSet> sets,
    PlannedSession? withPlan,
    String? plannedSessionId,
  }) => PastSessionSeed(
    source: pastSession(
      plannedSessionId: plannedSessionId,
      plannedName: 'Push Day',
    ),
    exercises: exercises,
    sets: sets,
    plan: withPlan,
  );

  group('PastSessionSeed', () {
    test('the record\'s arrangement decides the order, and its set order '
        'the rows inside it', () {
      // The exercise rows say B then A; the sets were written the other way
      // round, and out of set-number order. The record's tab order is the
      // exercise column — never the order a flat set read happens to hold.
      final seed = seedOf(
        exercises: [exercise('b', 1), exercise('a', 2)],
        sets: [
          set(id: 'a2', exerciseId: 'a', number: 2, weight: 70),
          set(id: 'b1', exerciseId: 'b', number: 1, weight: 40),
          set(id: 'a1', exerciseId: 'a', number: 1, weight: 65),
        ],
      );

      final groups = seed.exercisesToCopy(const {});

      expect([for (final g in groups) g.exerciseId], ['b', 'a']);
      expect(
        [for (final s in groups[1].sets) s.source.sessionExerciseSetId],
        ['a1', 'a2'],
      );
      // Weights ride the rows exactly as recorded.
      expect([for (final s in groups[1].sets) s.weight], [65, 70]);
    });

    test('an exercise with nothing performed is no tab, and a performed set '
        'whose exercise row is gone is never dropped', () {
      final seed = seedOf(
        exercises: [exercise('a', 1), exercise('empty', 2), exercise('b', 3)],
        sets: [
          set(id: 'a1', exerciseId: 'a', number: 1, weight: 60),
          set(id: 'b1', exerciseId: 'b', number: 1, weight: 40),
          // No exercise row holds this one any more (a sync round removed
          // it): the performance still belongs to the repeat.
          set(id: 'ghost1', exerciseId: 'ghost', number: 1, weight: 20),
        ],
      );

      final groups = seed.exercisesToCopy(const {});

      expect(
        [for (final g in groups) g.exerciseId],
        ['a', 'b', 'ghost'],
        reason: 'the record\'s order first, then anything it cannot arrange',
      );
    });

    test(
      'the variation is the record\'s unless the plan already names one',
      () {
        final planned = {
          'ps-named': target(
            id: 'ps-named',
            exerciseId: 'a',
            number: 1,
            variationId: 'incline',
          ),
          'ps-bare': target(id: 'ps-bare', exerciseId: 'a', number: 2),
        };
        final seed = seedOf(
          exercises: [exercise('a', 1, plannedId: 'pe-a')],
          sets: [
            set(
              id: 'named',
              exerciseId: 'a',
              number: 1,
              variationId: 'flat',
              plannedSetId: 'ps-named',
            ),
            set(
              id: 'bare',
              exerciseId: 'a',
              number: 2,
              variationId: 'flat',
              plannedSetId: 'ps-bare',
            ),
            set(
              id: 'free',
              exerciseId: 'a',
              number: 3,
              variationId: 'dumbbell',
            ),
          ],
        );

        final rows = seed.exercisesToCopy(planned).single.sets;

        expect(
          [for (final r in rows) r.variationId],
          [null, 'flat', 'dumbbell'],
          reason:
              'the plan\'s own variation is drawn by the card and adopted '
              'on first commit — copying it would be redundant, copying a '
              'different one would contradict the plan',
        );
        // The plan link itself is always copied: it is what puts the target
        // back under the row.
        expect(
          [for (final r in rows) r.plannedSetId],
          ['ps-named', 'ps-bare', null],
        );
        expect(seed.exercisesToCopy(planned).single.plannedExerciseId, 'pe-a');
      },
    );

    test('the name snapshot prefers the plan as it stands today', () {
      final live = seedOf(
        exercises: const [],
        sets: const [],
        withPlan: plan(),
        plannedSessionId: 'plan1',
      );
      expect(live.planName, 'Push Day');

      // The template is gone: the record's own snapshot still names what the
      // repeat follows.
      final gone = PastSessionSeed(
        source: Session(
          sessionId: 'past',
          userId: 'u1',
          createdDatetime: DateTime(2026, 10, 20),
          plannedSessionId: 'plan1',
          plannedSessionName: 'Old Push Day',
        ),
        exercises: const [],
        sets: const [],
      );
      expect(gone.planName, 'Old Push Day');
      expect(gone.plannedSessionId, 'plan1');

      // A freestyle record follows no plan at all.
      final freestyle = PastSessionSeed(
        source: pastSession(),
        exercises: const [],
        sets: const [],
      );
      expect(freestyle.planName, isNull);
      expect(freestyle.plannedSessionId, isNull);
    });
  });

  group('selecting and starting a past session', () {
    late _FakeSessionRepo sessions;
    late _FakePlannedSessionRepo plans;

    SessionViewModel buildVm() => SessionViewModel(
      sessionRepo: sessions,
      exerciseRepo: _EmptyExerciseRepo(),
      programRepo: _FakeProgramRepository(),
      programRunRepo: _NoRunProgramRepository(),
      lessonRepo: _FakeLessonRepository(),
      plannedSessionRepo: plans,
      waitForFirstSync: () async {},
      userId: 'u1',
      deviceId: 'dev-a',
    );

    setUp(() {
      PastSetsTimelineCache.loaderOverride = (u) async => const [];
      PastSetsTimelineCache.instance.invalidate();
      sessions = _FakeSessionRepo();
      plans = _FakePlannedSessionRepo()..workouts = [plan()];
    });

    tearDown(() {
      PastSetsTimelineCache.loaderOverride = null;
      PastSetsTimelineCache.instance.invalidate();
    });

    /// The record: Push Day, bench (planned, 2 targets) then row (a free
    /// tab), a third target never touched. Weights climb across the two
    /// bench sets, the row is freestyle.
    void seedRecord() {
      sessions.pastExercises = [
        exercise('bench', 1, plannedId: 'pe-bench'),
        exercise('row', 2),
      ];
      sessions.pastSets = [
        set(
          id: 'bench1',
          exerciseId: 'bench',
          number: 1,
          weight: 80,
          plannedSetId: 'ps-bench1',
        ),
        set(
          id: 'bench2',
          exerciseId: 'bench',
          number: 2,
          weight: 85,
          variationId: 'paused',
          plannedSetId: 'ps-bench2',
        ),
        set(id: 'row1', exerciseId: 'row', number: 1, weight: 60),
      ];
      plans.targets = [
        target(
          id: 'ps-bench1',
          exerciseId: 'bench',
          number: 1,
          weight: '80',
          reps: '5',
        ),
        target(
          id: 'ps-bench2',
          exerciseId: 'bench',
          number: 2,
          weight: '85',
          reps: '5',
        ),
      ];
    }

    test('selecting a planned record reads its arrangement, resolves its '
        'plan, and names the page after it', () {
      fakeAsync((async) {
        seedRecord();
        final vm = buildVm();
        async.flushMicrotasks();
        // The picker's default selection — the repeat must replace it.
        vm.selectStandaloneWorkout(plan());
        async.flushMicrotasks();

        vm.selectPastSession(
          SessionWithSets(
            session: pastSession(
              plannedSessionId: 'plan1',
              plannedName: 'Push Day',
            ),
            sets: sessions.pastSets,
          ),
        );
        async.flushMicrotasks();

        final seed = vm.pastSessionSeed;
        expect(seed, isNotNull);
        expect(seed!.plan?.sessionId, 'plan1');
        expect(seed.plannedSessionId, 'plan1');
        expect(
          [for (final e in seed.exercises) e.exerciseId],
          ['bench', 'row'],
        );
        // The plan rides underneath: its targets are the guides the card
        // will ghost into the empty rep cells.
        expect(vm.plannedExerciseOrder, ['bench']);
        expect(vm.plannedSetsByExercise['bench'], hasLength(2));
        expect(vm.selectedStandaloneWorkout?.sessionId, 'plan1');
        expect(vm.selectedPlannedSession, isNull);

        vm.dispose();
      });
    });

    test('selecting a freestyle record leaves no plan selected', () {
      fakeAsync((async) {
        seedRecord();
        final vm = buildVm();
        async.flushMicrotasks();

        vm.selectPastSession(
          SessionWithSets(session: pastSession(), sets: sessions.pastSets),
        );
        async.flushMicrotasks();

        expect(vm.pastSessionSeed, isNotNull);
        expect(vm.pastSessionSeed!.plan, isNull);
        expect(vm.selectedPlannedSession, isNull);
        expect(vm.selectedStandaloneWorkout, isNull);
        expect(vm.plannedExerciseOrder, isEmpty);

        vm.dispose();
      });
    });

    test('Start copies the record: same order, real weights, empty reps, the '
        'plan links, and no run', () {
      fakeAsync((async) {
        seedRecord();
        final vm = buildVm();
        async.flushMicrotasks();

        vm.selectPastSession(
          SessionWithSets(
            session: pastSession(
              plannedSessionId: 'plan1',
              plannedName: 'Push Day',
            ),
            sets: sessions.pastSets,
          ),
        );
        async.flushMicrotasks();
        vm.startWorkout();
        async.flushMicrotasks();

        // The session row: the record's plan, today's live name, no run.
        expect(sessions.created, isNotNull);
        expect(sessions.created!.plannedSessionId, 'plan1');
        expect(sessions.created!.plannedSessionName, 'Push Day');
        expect(sessions.created!.programRunId, isNull);

        // The tab layer: the record's order, renumbered from 1, its plan
        // links kept for the planned tab.
        expect(
          [for (final e in sessions.insertedExercises) e.exerciseId],
          ['bench', 'row'],
        );
        expect(
          [for (final e in sessions.insertedExercises) e.exerciseOrder],
          [1, 2],
        );
        expect(sessions.insertedExercises.first.plannedExerciseId, 'pe-bench');
        expect(sessions.insertedExercises.last.plannedExerciseId, isNull);

        // The rows: kg copied, reps never, variation copied where the plan
        // does not name one, links kept.
        final rows = sessions.insertedSets;
        expect(rows, hasLength(3));
        expect([for (final r in rows) r.weight], [80, 85, 60]);
        expect(
          [for (final r in rows) r.reps],
          [[], [], []],
          reason:
              'a rep count is today\'s performance — the record\'s was '
              'that day\'s',
        );
        expect([for (final r in rows) r.variationId], [null, 'paused', null]);
        expect(
          [for (final r in rows) r.plannedSetId],
          ['ps-bench1', 'ps-bench2', null],
        );
        expect([for (final r in rows) r.setNumber], [1, 2, 1]);

        // The seed is spent, the live session is a normal one.
        expect(vm.pastSessionSeed, isNull);
        expect(vm.currentWorkoutId, isNotNull);
        expect(vm.sets, hasLength(3));

        vm.dispose();
      });
    });

    test('a freestyle record copies flat — no plan id, no name, no guides', () {
      fakeAsync((async) {
        seedRecord();
        final vm = buildVm();
        async.flushMicrotasks();

        vm.selectPastSession(
          SessionWithSets(session: pastSession(), sets: sessions.pastSets),
        );
        async.flushMicrotasks();
        vm.startWorkout();
        async.flushMicrotasks();

        expect(sessions.created!.plannedSessionId, isNull);
        expect(sessions.created!.plannedSessionName, isNull);
        expect(sessions.created!.programRunId, isNull);
        expect([for (final r in sessions.insertedSets) r.weight], [80, 85, 60]);
        expect(
          [for (final r in sessions.insertedSets) r.variationId],
          [null, 'paused', null],
          reason: 'with no plan naming a variation, the record\'s own rides',
        );
        expect(
          [for (final r in sessions.insertedSets) r.plannedSetId],
          ['ps-bench1', 'ps-bench2', null],
          reason:
              'the links are the record\'s own rows — kept, though a '
              'freestyle session draws no target off them',
        );

        vm.dispose();
      });
    });

    test('picking a template clears the seed, and so does clearing the '
        'selection', () {
      fakeAsync((async) {
        seedRecord();
        final vm = buildVm();
        async.flushMicrotasks();

        vm.selectPastSession(
          SessionWithSets(session: pastSession(), sets: sessions.pastSets),
        );
        async.flushMicrotasks();
        expect(vm.pastSessionSeed, isNotNull);

        vm.selectStandaloneWorkout(plan());
        async.flushMicrotasks();
        expect(vm.pastSessionSeed, isNull);

        vm.selectPastSession(
          SessionWithSets(session: pastSession(), sets: sessions.pastSets),
        );
        async.flushMicrotasks();
        vm.clearTemplateSelection();
        expect(vm.pastSessionSeed, isNull);

        vm.dispose();
      });
    });

    test('a tab switch does not re-choose the template under a seed', () {
      fakeAsync((async) {
        seedRecord();
        final vm = buildVm();
        async.flushMicrotasks();

        // A standalone record: the program's auto-selection must not step in
        // front of it when the tab comes back.
        vm.selectPastSession(
          SessionWithSets(
            session: pastSession(
              plannedSessionId: 'plan1',
              plannedName: 'Push Day',
            ),
            sets: sessions.pastSets,
          ),
        );
        async.flushMicrotasks();
        expect(vm.selectedStandaloneWorkout?.sessionId, 'plan1');

        // The program gains a workout between visits; refreshProgram would
        // normally pick it as the template — a seeded page keeps its own.
        plans.workouts = [
          plan(),
          PlannedSession(sessionId: 'plan2', userId: 'u1', name: 'Pull Day'),
        ];
        vm.refreshProgram();
        async.flushMicrotasks();

        expect(vm.pastSessionSeed, isNotNull);
        expect(vm.selectedStandaloneWorkout?.sessionId, 'plan1');
        expect(vm.plannedExerciseOrder, ['bench']);

        vm.dispose();
      });
    });
  });
}

/// The database as the repeat sees it: the record's reads, the session
/// Start writes, and the inserted rows the reload reads back.
class _FakeSessionRepo extends Fake implements SessionRepository {
  List<SessionExercise> pastExercises = const [];
  List<SessionExerciseSet> pastSets = const [];

  final insertedExercises = <SessionExercise>[];
  final insertedSets = <SessionExerciseSet>[];
  ({
    String? programRunId,
    String? plannedSessionId,
    String? plannedSessionName,
  })?
  created;

  @override
  Future<String?> getActiveSessionId(String userId, {String? deviceId}) async =>
      null;

  @override
  Future<Session?> fetchSession(String sessionId) async => null;

  @override
  Future<List<PastSetRow>> loadPastSetsTimeline(String userId) async => [];

  @override
  Future<List<({String sessionId, DateTime createdDatetime})>>
  loadCompletedSessionStamps(String userId) async => [];

  @override
  Future<List<SessionExercise>> loadSessionExercises(String sessionId) async =>
      pastExercises;

  @override
  Future<String> createSession(
    String userId, {
    String? preNotes,
    String? programRunId,
    String? plannedSessionId,
    String? plannedSessionName,
    int? preFeeling,
    String? deviceId,
  }) async {
    created = (
      programRunId: programRunId,
      plannedSessionId: plannedSessionId,
      plannedSessionName: plannedSessionName,
    );
    return 'new1';
  }

  @override
  Future<SessionExercise> insertSessionExercise({
    required String sessionId,
    required String userId,
    required int exerciseOrder,
    String? exerciseId,
    String? plannedExerciseId,
  }) async {
    final row = SessionExercise(
      sessionExerciseId: 'nse-${insertedExercises.length}',
      sessionId: sessionId,
      userId: userId,
      exerciseId: exerciseId,
      exerciseOrder: exerciseOrder,
      plannedExerciseId: plannedExerciseId,
    );
    insertedExercises.add(row);
    return row;
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
    final row = SessionExerciseSet(
      sessionExerciseSetId: 'nset-${insertedSets.length}',
      sessionExerciseId: sessionExerciseId,
      sessionId: sessionId,
      userId: userId,
      exerciseId: insertedExercises
          .firstWhere((e) => e.sessionExerciseId == sessionExerciseId)
          .exerciseId,
      variationId: variationId,
      setNumber: setNumber,
      weight: weight,
      reps: reps,
      notes: notes,
      plannedSetId: plannedSetId,
    );
    insertedSets.add(row);
    return row;
  }

  /// The reload after Start reads the new session back — the rows it just
  /// wrote, exactly like the real database would answer.
  @override
  Future<List<SessionExerciseSet>> loadSetsForSession(String sessionId) async =>
      sessionId == 'new1' ? insertedSets : const [];

  @override
  Stream<List<SessionExerciseSet>> watchSetsForSession(String sessionId) =>
      const Stream.empty();

  @override
  Stream<List<SessionExercise>> watchSessionExercises(String sessionId) =>
      const Stream.empty();

  @override
  Stream<List<Session>> watchActiveSessions(String userId) =>
      const Stream.empty();
}

class _FakePlannedSessionRepo extends Fake implements PlannedSessionRepository {
  List<PlannedSession> workouts = const [];
  List<PlannedSessionExerciseSet> targets = const [];

  @override
  Future<List<PlannedSession>> fetchPlannedSessions(
    String userId, {
    String? programId,
    String? blockId,
  }) async => workouts;

  @override
  Future<PlannedSession?> fetchPlannedSessionById(String sessionId) async =>
      workouts.where((w) => w.sessionId == sessionId).firstOrNull;

  @override
  Future<List<PlannedSessionExerciseSet>> readNormalizedPlannedSession(
    String sessionId, {
    bool includeArchived = false,
  }) async => targets;
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

class _NoRunProgramRepository extends Fake implements ProgramRunRepository {
  @override
  Future<ProgramProgress?> getProgress(String userId) async => null;
}

class _FakeLessonRepository extends Fake implements LessonRepository {
  @override
  Future<List<Lesson>> fetchLessons(String userId, String exerciseId) async =>
      const [];
}
