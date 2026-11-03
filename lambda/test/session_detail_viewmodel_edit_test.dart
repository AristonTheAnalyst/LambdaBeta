import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/cache/past_sets_timeline_cache.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/goal.dart';
import 'package:lambda/data/models/exercise_note.dart';
import 'package:lambda/data/models/session.dart';
import 'package:lambda/data/models/session_exercise.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/exercise_note_repository.dart';
import 'package:lambda/data/repositories/program_history_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/logs/viewmodel/session_detail_viewmodel.dart';
import 'package:lambda/shared/widgets/exercise_target_picker.dart';
import 'support/fake_coach_repository.dart';

/// The past-session editor's debounce pipeline (2026-10-13): keystrokes
/// merge into one write per settle, the settle patches both the grid and the
/// timeline's copy of the row, PRs re-derive once, drafts survive, and no
/// timeline query rides on a keystroke.
class _FakeSessionRepo extends Fake implements SessionRepository {
  int updateSetCalls = 0;
  int timelineReads = 0;
  bool failUpdate = false;
  final updateLog = <({String setId, double? weight, bool clearWeight})>[];

  /// Records this test opens by id, when it needs a session other than the
  /// default one.
  final sessionsById = <String, Session>{};

  Session session({String id = 'w1', String? plannedSessionId}) => Session(
    sessionId: id,
    userId: 'u1',
    createdDatetime: DateTime(2026, 10, 10),
    endDatetime: DateTime(2026, 10, 10, 10),
    plannedSessionId: plannedSessionId,
  );

  final rows = <String, SessionExerciseSet>{};

  SessionExerciseSet row(
    String setId, {
    double? weight = 0,
    List<num> reps = const [5],
  }) => SessionExerciseSet(
    sessionExerciseSetId: setId,
    sessionExerciseId: 'se1',
    sessionId: 'w1',
    userId: 'u1',
    exerciseId: 'ex1',
    setNumber: 1,
    weight: weight,
    reps: reps,
  );

  @override
  Future<Session?> fetchSession(String sessionId) async =>
      sessionsById[sessionId] ?? session(id: sessionId);

  @override
  Future<List<SessionExercise>> loadSessionExercises(String sessionId) async =>
      [
        const SessionExercise(
          sessionExerciseId: 'se1',
          sessionId: 'w1',
          userId: 'u1',
          exerciseOrder: 1,
          exerciseId: 'ex1',
        ),
      ];

  @override
  Future<List<SessionExerciseSet>> loadSetsForSession(String sessionId) async =>
      rows.values.toList();

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
    if (failUpdate) {
      updateSetCalls++;
      throw StateError('write failed');
    }
    updateSetCalls++;
    // The real repo invalidates the shared cache on every fact write — the
    // settle's timeline re-read depends on it.
    PastSetsTimelineCache.instance.invalidate();
    updateLog.add((setId: setId, weight: weight, clearWeight: clearWeight));
    final existing = rows[setId] ?? row(setId);
    rows[setId] = SessionExerciseSet(
      sessionExerciseSetId: existing.sessionExerciseSetId,
      sessionExerciseId: existing.sessionExerciseId,
      sessionId: existing.sessionId,
      userId: existing.userId,
      exerciseId: existing.exerciseId,
      setNumber: existing.setNumber,
      weight: clearWeight ? null : (weight ?? existing.weight),
      reps: clearReps ? const [] : (reps ?? existing.reps),
    );
  }

  @override
  Future<SessionExercise> insertSessionExercise({
    required String sessionId,
    required String userId,
    required int exerciseOrder,
    String? exerciseId,
    String? plannedExerciseId,
  }) async => SessionExercise(
    sessionExerciseId: 'se-${exerciseId ?? 'new'}',
    sessionId: sessionId,
    userId: userId,
    exerciseOrder: exerciseOrder,
    exerciseId: exerciseId,
  );

  /// The cache reads through this — counted so a per-keystroke timeline
  /// read would show up.
  Future<List<PastSetRow>> timeline() async {
    timelineReads++;
    return [
      PastSetRow(
        sessionExerciseSetId: 's1',
        sessionExerciseId: 'se1',
        sessionId: 'w1',
        userId: 'u1',
        exerciseId: 'ex1',
        setNumber: 1,
        reps: const [5],
        sessionCreatedDate: DateTime(2026, 10, 10, 10),
        weight: 50,
      ),
    ];
  }
}

class _FakeExerciseRepo extends Fake implements ExerciseRepository {
  @override
  Future<Map<String, ExerciseDetail>> fetchExerciseDetailMap(
    String userId,
  ) async => {};

  @override
  Future<List<CustomVariation>> fetchVariations(String userId) async => [];
}

void main() {
  late _FakeSessionRepo repo;

  SessionDetailViewModel buildVm({
    _FakeProgramRepo? programs,
    _FakeHistoryRepo? history,
    bool readOnly = false,
  }) {
    final vm = SessionDetailViewModel(
      coachRepo: FakeCoachRepository(),
      sessionRepo: repo,
      exerciseRepo: _FakeExerciseRepo(),
      noteRepo: FakeExerciseNoteRepository(),
      programRepo: programs ?? _FakeProgramRepo(),
      historyRepo: history ?? _FakeHistoryRepo(const {}),
      userId: 'u1',
      readOnly: readOnly,
    );
    return vm;
  }

  setUp(() {
    repo = _FakeSessionRepo();
    PastSetsTimelineCache.loaderOverride = (u) => repo.timeline();
    PastSetsTimelineCache.instance.invalidate();
  });

  tearDown(() {
    PastSetsTimelineCache.loaderOverride = null;
    PastSetsTimelineCache.instance.invalidate();
  });

  test(
    'a keystroke storm merges into one write per settle, patching state',
    () {
      fakeAsync((async) {
        final vm = buildVm();
        vm.load('w1');
        async.flushMicrotasks();
        // Heavy context read the timeline once through the cache.
        expect(repo.timelineReads, 1);
        final readsAfterLoad = repo.timelineReads;

        repo.rows['s1'] = repo.row('s1');
        vm.load('w1');
        async.flushMicrotasks();
        final set = repo.row('s1');
        vm.quickUpdateSet(set, weight: 1, immediate: false);
        vm.quickUpdateSet(set, weight: 10, immediate: false);
        vm.quickUpdateSet(set, weight: 100, immediate: false);
        expect(
          repo.updateSetCalls,
          0,
          reason: 'keystrokes merge — nothing writes inside the window',
        );
        expect(
          repo.timelineReads,
          readsAfterLoad,
          reason: 'no timeline query rides on a keystroke',
        );

        async.elapse(
          SessionDetailViewModel.kAutoCommitDebounce +
              const Duration(milliseconds: 10),
        );
        async.flushMicrotasks();

        expect(
          repo.updateSetCalls,
          1,
          reason: 'one write per settle, however many keystrokes fed it',
        );
        expect(repo.updateLog.single.weight, 100);
        expect(
          vm.state.value.setsFor(1).single.weight,
          100,
          reason: 'the settle patches the grid row',
        );
        // The timeline's copy of the edited row carries the new value — the
        // history picker reads this map.
        final history = vm.state.value.historyByExercise['ex1']!;
        expect(
          history.first.sets.first.weight,
          100,
          reason: 'the settle patches the timeline copy too',
        );
        expect(
          vm.state.value.prEvents,
          isNotEmpty,
          reason: 'PRs re-derive once per settle',
        );
        vm.dispose();
      });
    },
  );

  test('an immediate edit writes now and cancels the armed timer', () {
    fakeAsync((async) {
      final vm = buildVm();
      vm.load('w1');
      async.flushMicrotasks();
      repo.rows['s1'] = repo.row('s1');
      vm.load('w1');
      async.flushMicrotasks();

      final set = repo.row('s1');
      vm.quickUpdateSet(set, weight: 10, immediate: false);
      vm.quickUpdateSet(set, weight: 20, immediate: true);
      async.flushMicrotasks();
      expect(repo.updateSetCalls, 1);
      expect(
        repo.updateLog.single.weight,
        20,
        reason: 'immediate merges the pending value and writes it',
      );

      async.elapse(const Duration(seconds: 1));
      expect(
        repo.updateSetCalls,
        1,
        reason: 'the debounce timer was cancelled — no second write',
      );
      vm.dispose();
    });
  });

  test('drafts survive a settle', () {
    fakeAsync((async) {
      final vm = buildVm();
      vm.load('w1');
      async.flushMicrotasks();
      vm.addExerciseGroup('ex2');
      async.flushMicrotasks();
      final draftOrder = vm.state.value.exerciseSlots.last.groupOrder;
      expect(vm.state.value.workoutSetDrafts[draftOrder], isNotEmpty);

      final set = repo.row('s1');
      vm.quickUpdateSet(set, weight: 5, immediate: true);
      async.flushMicrotasks();

      expect(
        vm.state.value.workoutSetDrafts[draftOrder],
        isNotEmpty,
        reason:
            'the old clearSessionSetDrafts wipe per keystroke is gone — '
            'only structural reloads clear drafts',
      );
      vm.dispose();
    });
  });

  test('a failed write patches nothing and surfaces the error', () {
    fakeAsync((async) {
      final vm = buildVm();
      vm.load('w1');
      async.flushMicrotasks();
      repo.rows['s1'] = repo.row('s1');
      vm.load('w1');
      async.flushMicrotasks();
      repo.failUpdate = true;

      final set = repo.row('s1');
      vm.quickUpdateSet(set, weight: 60, immediate: false);
      async.elapse(
        SessionDetailViewModel.kAutoCommitDebounce +
            const Duration(milliseconds: 10),
      );
      async.flushMicrotasks();

      expect(repo.updateSetCalls, 1);
      expect(vm.state.value.error, isNotNull);
      expect(
        vm.state.value.setsFor(1).single.weight,
        0,
        reason:
            'the patch runs only after a successful write — the grid '
            'keeps the pre-edit row',
      );
      vm.dispose();
    });
  });

  // ── A goal from the set under the thumb (2026-10-26) ─────────────────────
  // The record's row carries the same drawer door the live grid has, and ADD
  // writes the goal and folds it into the G badges IN PLACE: the record's own
  // set — which is what the form was asking about — wears its G without a
  // reload behind the sheet.

  test('a goal written from the record marks its set at once, no reload', () {
    fakeAsync((async) {
      final programs = _FakeProgramRepo();
      repo.rows['s1'] = repo.row('s1', weight: 100, reps: [3]);
      final vm = buildVm(programs: programs);
      vm.load('w1');
      async.flushMicrotasks();
      expect(vm.state.value.goalSetIds, isEmpty);
      final readsBefore = repo.timelineReads;

      var written = false;
      vm.createGoalFromTarget(
        const ExerciseTarget(
          exerciseId: 'ex1',
          exerciseName: 'Bench',
          weight: 100,
          reps: 3,
        ),
      ).then((ok) => written = ok);
      async.flushMicrotasks();

      expect(written, isTrue);
      final goal = programs.createdGoals.single;
      expect(goal.userId, 'u1', reason: 'the record is the user\'s own');
      expect(goal.variationId, isNull);
      expect(goal.targetWeight, 100);
      expect(goal.targetReps, 3);
      expect(goal.goalId, isNotEmpty);
      expect(
        vm.state.value.goalSetIds,
        contains('s1'),
        reason: 'the set that meets the target wears its G at once',
      );
      expect(
        repo.timelineReads,
        readsBefore,
        reason: 'the badge re-derives in place — no timeline read',
      );
      vm.dispose();
    });
  });

  // ── The sheets' review boundary (2026-10-26) ─────────────────────────────
  // A record a pass has covered carries the checkpoint its last review
  // closed on, so the two sheets can split their after-group. It is asked
  // of the review history, read beside the page, and it belongs to the
  // record: a step onto another record drops it.

  test('a covered record carries its review checkpoint into the state', () {
    fakeAsync((async) {
      final boundary = DateTime(2026, 10, 22);
      final history = _FakeHistoryRepo({'plan-a': boundary});
      repo.sessionsById['w1'] = repo.session(plannedSessionId: 'plan-a');

      final vm = buildVm(history: history);
      vm.load('w1');
      async.flushMicrotasks();

      expect(
        history.asked,
        ['plan-a'],
        reason: 'the question is about the template the record followed, '
            'which is what a review\'s set holds',
      );
      expect(vm.state.value.reviewCheckpoint, boundary);
      vm.dispose();
    });
  });

  test('a step onto a record no pass covered leaves no boundary', () {
    fakeAsync((async) {
      repo.sessionsById['w1'] = repo.session(plannedSessionId: 'plan-a');
      repo.sessionsById['w2'] = repo.session(
        id: 'w2',
        plannedSessionId: 'plan-b',
      );
      final history = _FakeHistoryRepo({'plan-a': DateTime(2026, 10, 22)});

      final vm = buildVm(history: history);
      vm.load('w1');
      async.flushMicrotasks();
      expect(vm.state.value.reviewCheckpoint, isNotNull);

      vm.walkTo('w2');
      async.flushMicrotasks();

      expect(
        vm.state.value.reviewCheckpoint,
        isNull,
        reason: 'the boundary belongs to the record on screen, not the one '
            'left behind',
      );
      vm.dispose();
    });
  });

  test('a freestyle record asks nothing, and so does a friend\'s', () {
    fakeAsync((async) {
      final history = _FakeHistoryRepo({'plan-a': DateTime(2026, 10, 22)});

      final freestyle = buildVm(history: history);
      freestyle.load('w1');
      async.flushMicrotasks();
      expect(
        history.asked,
        isEmpty,
        reason: 'a freestyle session is never part of a review\'s set',
      );
      expect(freestyle.state.value.reviewCheckpoint, isNull);
      freestyle.dispose();

      repo.sessionsById['w1'] = repo.session(plannedSessionId: 'plan-a');
      final friend = buildVm(history: history, readOnly: true);
      friend.load('w1');
      async.flushMicrotasks();
      expect(
        history.asked,
        isEmpty,
        reason: 'a friend\'s reviews never reach this device — the reader '
            'asks nothing of them',
      );
      expect(friend.state.value.reviewCheckpoint, isNull);
      friend.dispose();
    });
  });
}

/// The review history behind the sheets' boundary, answered from a map of
/// planned session id → where that workout's last completed pass closed, and
/// recording what it was asked so the freestyle and friend paths can prove
/// they ask nothing.
class _FakeHistoryRepo extends Fake implements ProgramHistoryRepository {
  _FakeHistoryRepo(this.boundaries);

  final Map<String, DateTime> boundaries;
  final asked = <String>[];

  @override
  Future<DateTime?> checkpointForSet(
    String userId, {
    required List<String> sessionIds,
    DateTime? fallback,
  }) async {
    asked.addAll(sessionIds);
    for (final id in sessionIds) {
      final at = boundaries[id];
      if (at != null) return at;
    }
    return fallback;
  }
}

class FakeExerciseNoteRepository extends Fake implements ExerciseNoteRepository {
  @override
  Future<List<ExerciseNote>> fetchNotes(String userId, String exerciseId) async =>
      [];
}

/// The goal write behind the record's drawer door — recorded, and answered by
/// the same read the heavy context makes, so a later load sees its own row.
class _FakeProgramRepo extends Fake implements ProgramRepository {
  final createdGoals = <Goal>[];

  @override
  Future<void> createGoal(String userId, Goal goal) async {
    createdGoals.add(goal);
  }

  @override
  Future<List<({Goal goal, String? programName, String? blockName})>>
  fetchGoalOptions(String userId) async => [
    for (final goal in createdGoals)
      (goal: goal, programName: null, blockName: null),
  ];
}
