import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/cache/past_sets_timeline_cache.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/lesson.dart';
import 'package:lambda/data/models/session.dart';
import 'package:lambda/data/models/session_exercise.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/logs/viewmodel/session_detail_viewmodel.dart';
import 'package:lambda/features/session/model/session_local_state.dart';
import 'package:lambda/features/session/viewmodel/session_viewmodel.dart';

import 'support/fake_program_repos.dart';
import 'support/fake_coach_repository.dart';

/// The date bar's two stacks (2026-10-23). EXERCISE — the default on both
/// session surfaces — walks the active exercise's own past performances,
/// swapping only the card's sets; SESSION walks whole records. The models
/// hold the walk: home (index 0) is the page on screen, older performances
/// at N, both ends holding. A selection is bound to the exercise it was
/// stepped on, so a structural change that puts another exercise on the
/// card reads as home.

// ── The viewer's record and its history ──────────────────────────────────────

class _FakeSessionRepo extends Fake implements SessionRepository {
  @override
  Future<Session?> fetchSession(String sessionId) async => Session(
    sessionId: sessionId,
    userId: 'u1',
    createdDatetime: DateTime(2026, 10, 10, 10),
    endDatetime: DateTime(2026, 10, 10, 11),
  );

  @override
  Future<List<SessionExercise>> loadSessionExercises(String sessionId) async => [
    const SessionExercise(
      sessionExerciseId: 'se1',
      sessionId: 'w1',
      userId: 'u1',
      exerciseOrder: 1,
      exerciseId: 'ex1',
    ),
    const SessionExercise(
      sessionExerciseId: 'se2',
      sessionId: 'w1',
      userId: 'u1',
      exerciseOrder: 2,
      exerciseId: 'ex2',
    ),
  ];

  @override
  Future<List<SessionExerciseSet>> loadSetsForSession(String sessionId) async =>
      [
        SessionExerciseSet(
          sessionExerciseSetId: 'set1',
          sessionExerciseId: 'se1',
          sessionId: sessionId,
          userId: 'u1',
          exerciseId: 'ex1',
          setNumber: 1,
          weight: 100,
          reps: const [5],
        ),
        SessionExerciseSet(
          sessionExerciseSetId: 'set2',
          sessionExerciseId: 'se2',
          sessionId: sessionId,
          userId: 'u1',
          exerciseId: 'ex2',
          setNumber: 1,
          weight: 50,
          reps: const [10],
        ),
      ];

  /// Newest first, as the shared cache answers: a later record (never
  /// walkable — the page keeps naming this one), this record, then two
  /// older performances of ex1 and one of ex2.
  Future<List<PastSetRow>> timeline() async => [
    _row('s-w2', exerciseId: 'ex1', sessionId: 'w2', date: DateTime(2026, 10, 12)),
    _row('s-w1', exerciseId: 'ex1', sessionId: 'w1', date: DateTime(2026, 10, 10)),
    _row('s-b', exerciseId: 'ex1', sessionId: 'w0b', date: DateTime(2026, 10, 5)),
    _row('s-a', exerciseId: 'ex1', sessionId: 'w0a', date: DateTime(2026, 9, 28)),
    _row('s-x', exerciseId: 'ex2', sessionId: 'w0b', date: DateTime(2026, 10, 5)),
  ];

  PastSetRow _row(
    String id, {
    required String exerciseId,
    required String sessionId,
    required DateTime date,
  }) => PastSetRow(
    sessionExerciseSetId: id,
    sessionExerciseId: 'se-$exerciseId',
    sessionId: sessionId,
    userId: 'u1',
    exerciseId: exerciseId,
    setNumber: 1,
    weight: 80,
    reps: const [5],
    sessionCreatedDate: date,
  );
}

class _FakeExerciseRepo extends Fake implements ExerciseRepository {
  @override
  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
    String userId,
  ) async => {};

  @override
  Future<List<CustomVariation>> fetchVariations(String userId) async => [];
}

class _FakeLessonRepo extends Fake implements LessonRepository {
  @override
  Future<List<Lesson>> fetchLessons(String userId, String exerciseId) async =>
      [];
}

// ── The live session's exercise and history ──────────────────────────────────

SessionExerciseSlot _slot(int id, String exerciseId) => SessionExerciseSlot(
  id: id,
  type: SessionSlotType.single,
  exerciseIds: [exerciseId],
);

ExerciseHistorySession _performance(
  String sessionId,
  DateTime date,
) => ExerciseHistorySession(
  date: date,
  sets: [
    PastSetRow(
      sessionExerciseSetId: 'p-$sessionId',
      sessionExerciseId: 'se',
      sessionId: sessionId,
      userId: 'u1',
      exerciseId: 'ex1',
      setNumber: 1,
      weight: 80,
      reps: const [5],
      sessionCreatedDate: date,
    ),
  ],
);

void main() {
  group('the past-session viewer', () {
    late _FakeSessionRepo repo;

    SessionDetailViewModel buildVm() => SessionDetailViewModel(
      coachRepo: FakeCoachRepository(),
      sessionRepo: repo,
      exerciseRepo: _FakeExerciseRepo(),
      lessonRepo: _FakeLessonRepo(),
      programRepo: FakeProgramRepository(),
      userId: 'u1',
    );

    setUp(() {
      repo = _FakeSessionRepo();
      PastSetsTimelineCache.loaderOverride = (u) => repo.timeline();
      PastSetsTimelineCache.instance.invalidate();
    });

    tearDown(() {
      PastSetsTimelineCache.loaderOverride = null;
      PastSetsTimelineCache.instance.invalidate();
    });

    /// Loads the record and lets the history wave land.
    SessionDetailViewModel loaded(FakeAsync async) {
      final vm = buildVm();
      vm.load('w1');
      async.flushMicrotasks();
      return vm;
    }

    test('defaults to EXERCISE, home, with only older performances walkable',
        () {
      fakeAsync((async) {
        final vm = loaded(async);
        final state = vm.state.value;

        expect(state.dateBarMode, SessionDateMode.exercise);
        expect(state.exerciseHistoryIndex, 0);
        expect(
          state.exerciseHistoryStack.map((h) => h.sets.first.sessionId),
          ['w0b', 'w0a'],
          reason: 'strictly older than the record, newest first — the '
              'record itself is home and a later session is not walkable',
        );
        expect(state.effectiveExerciseHistoryIndex, 0);
        expect(state.viewedHistorySession, isNull);
        vm.dispose();
      });
    });

    test('steps older through the stack, both ends holding', () async {
      fakeAsync((async) {
        final vm = loaded(async);
        expect(vm.state.value.exerciseHistoryStack, hasLength(2));

        vm.stepExerciseHistory(1);
        async.flushMicrotasks();
        expect(
          vm.state.value.viewedHistorySession!.sets.first.sessionId,
          'w0b',
        );
        expect(vm.state.value.effectiveExerciseHistoryIndex, 1);

        vm.stepExerciseHistory(1);
        async.flushMicrotasks();
        expect(
          vm.state.value.viewedHistorySession!.sets.first.sessionId,
          'w0a',
        );

        // Past the oldest end: the step is a no-op.
        vm.stepExerciseHistory(1);
        async.flushMicrotasks();
        expect(vm.state.value.effectiveExerciseHistoryIndex, 2);
        expect(
          vm.state.value.viewedHistorySession!.sets.first.sessionId,
          'w0a',
        );

        vm.stepExerciseHistory(-1);
        async.flushMicrotasks();
        expect(
          vm.state.value.viewedHistorySession!.sets.first.sessionId,
          'w0b',
        );

        // Back home: the record's own sets, not a performance.
        vm.stepExerciseHistory(-1);
        async.flushMicrotasks();
        expect(vm.state.value.effectiveExerciseHistoryIndex, 0);
        expect(vm.state.value.viewedHistorySession, isNull);

        // Past home toward newer: nothing.
        vm.stepExerciseHistory(-1);
        async.flushMicrotasks();
        expect(vm.state.value.effectiveExerciseHistoryIndex, 0);
        vm.dispose();
      });
    });

    test('a mode change returns the card home and SESSION steps nothing', () {
      fakeAsync((async) {
        final vm = loaded(async);
        vm.stepExerciseHistory(1);
        async.flushMicrotasks();
        expect(vm.state.value.viewedHistorySession, isNotNull);

        vm.toggleDateBarMode();
        final state = vm.state.value;
        expect(state.dateBarMode, SessionDateMode.session);
        expect(state.effectiveExerciseHistoryIndex, 0);
        expect(state.viewedHistorySession, isNull);

        // The arrows walk whole records in this mode; an exercise step
        // must not move the card.
        vm.stepExerciseHistory(1);
        async.flushMicrotasks();
        expect(vm.state.value.effectiveExerciseHistoryIndex, 0);
        expect(vm.state.value.viewedHistorySession, isNull);

        vm.toggleDateBarMode();
        expect(vm.state.value.dateBarMode, SessionDateMode.exercise);
        vm.dispose();
      });
    });

    test('the selection belongs to the exercise it was stepped on', () {
      fakeAsync((async) {
        final vm = loaded(async);
        vm.stepExerciseHistory(1);
        async.flushMicrotasks();
        expect(vm.state.value.exerciseHistoryForId, 'ex1');

        // The card moves to the other exercise without a tab tap (a
        // structural edit): the old position must not point at ex2's stack.
        vm.state.value = vm.state.value.copyWith(activeSlotIndex: 1);
        expect(vm.state.value.activeSlot?.exerciseId, 'ex2');
        expect(vm.state.value.effectiveExerciseHistoryIndex, 0);
        expect(vm.state.value.viewedHistorySession, isNull);
        vm.dispose();
      });
    });

    test('an in-place walk carries the reader\'s mode, not the record\'s',
        () {
      fakeAsync((async) {
        final vm = loaded(async);
        vm.toggleDateBarMode();
        expect(vm.state.value.dateBarMode, SessionDateMode.session);

        vm.walkTo('w0b');
        async.flushMicrotasks();
        expect(vm.state.value.session?.sessionId, 'w0b');
        expect(
          vm.state.value.dateBarMode,
          SessionDateMode.session,
          reason: 'a SESSION walk keeps walking sessions across the step',
        );
        expect(vm.state.value.effectiveExerciseHistoryIndex, 0);
        vm.dispose();
      });
    });
  });

  group('the live session', () {
    SessionViewModel buildVm() => SessionViewModel(
      sessionRepo: _FakeSessionRepo(),
      exerciseRepo: _FakeExerciseRepo(),
      programRepo: FakeProgramRepository(),
      programRunRepo: FakeProgramRunRepository(),
      lessonRepo: _FakeLessonRepo(),
      plannedSessionRepo: FakePlannedSessions(),
      waitForFirstSync: () async {},
      userId: 'u1',
      deviceId: 'device-1',
    );

    /// A started VM with the exercise stack seeded by hand — the walk is a
    /// pure projection of `exerciseSlots` and `historyByExercise`.
    SessionViewModel seeded() {
      final vm = buildVm();
      vm.exerciseSlots = [_slot(1, 'ex1'), _slot(2, 'ex2')];
      vm.activeSlotIndex = 0;
      vm.historyByExercise = {
        'ex1': [
          _performance('w0b', DateTime(2026, 10, 5)),
          _performance('w0a', DateTime(2026, 9, 28)),
        ],
        'ex2': [_performance('w0b', DateTime(2026, 10, 5))],
      };
      return vm;
    }

    test('defaults to EXERCISE walking the active exercise', () async {
      final vm = seeded();
      await pumpEventQueue();

      expect(vm.dateBarMode, SessionDateMode.exercise);
      expect(vm.exerciseHistoryIndex, 0);
      expect(vm.activeExerciseHistory, hasLength(2));
      expect(vm.viewedExerciseHistory, isNull);
      expect(vm.canStepExerciseOlder, isTrue);
      expect(vm.canStepExerciseNewer, isFalse);
      vm.dispose();
    });

    test('steps older and back, both ends holding', () async {
      final vm = seeded();
      await pumpEventQueue();

      await vm.stepExerciseHistory(1);
      expect(vm.viewedExerciseHistory!.sets.first.sessionId, 'w0b');
      expect(vm.canStepExerciseNewer, isTrue);

      await vm.stepExerciseHistory(1);
      expect(vm.viewedExerciseHistory!.sets.first.sessionId, 'w0a');
      await vm.stepExerciseHistory(1);
      expect(vm.exerciseHistoryIndex, 2, reason: 'the oldest end holds');

      await vm.stepExerciseHistory(-1);
      await vm.stepExerciseHistory(-1);
      expect(vm.viewedExerciseHistory, isNull);
      expect(vm.canStepExerciseNewer, isFalse);
      vm.dispose();
    });

    test('a mode change returns home and greys the exercise arrows', () async {
      final vm = seeded();
      await pumpEventQueue();
      await vm.stepExerciseHistory(1);

      vm.toggleDateBarMode();
      expect(vm.dateBarMode, SessionDateMode.session);
      expect(vm.viewedExerciseHistory, isNull);
      expect(vm.canStepExerciseOlder, isFalse);
      expect(vm.canStepExerciseNewer, isFalse);

      await vm.stepExerciseHistory(1);
      expect(vm.viewedExerciseHistory, isNull);

      vm.toggleDateBarMode();
      expect(vm.dateBarMode, SessionDateMode.exercise);
      expect(vm.exerciseHistoryIndex, 0);
      vm.dispose();
    });

    test('the selection belongs to the exercise it was stepped on', () async {
      final vm = seeded();
      await pumpEventQueue();
      await vm.stepExerciseHistory(1);
      expect(vm.viewedExerciseHistory!.sets.first.sessionId, 'w0b');

      // The card moves to another exercise (a picker tap or an undo): the
      // old position must read as home there, not as its own performance.
      vm.activeSlotIndex = 1;
      expect(vm.activeSlot!.activeExerciseId, 'ex2');
      expect(vm.viewedExerciseHistory, isNull);
      expect(vm.canStepExerciseNewer, isFalse);
      expect(vm.canStepExerciseOlder, isTrue, reason: 'ex2 has one to walk');
      vm.dispose();
    });
  });
}
