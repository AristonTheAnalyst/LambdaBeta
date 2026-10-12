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

/// The past-session editor's debounce pipeline (2026-10-13): keystrokes
/// merge into one write per settle, the settle patches both the grid and the
/// timeline's copy of the row, PRs re-derive once, drafts survive, and no
/// timeline query rides on a keystroke.
class _FakeSessionRepo extends Fake implements SessionRepository {
  int updateSetCalls = 0;
  int timelineReads = 0;
  bool failUpdate = false;
  final updateLog = <({String setId, double? weight, bool clearWeight})>[];

  Session session({String id = 'w1'}) => Session(
    sessionId: id,
    userId: 'u1',
    createdDatetime: DateTime(2026, 10, 10),
    endDatetime: DateTime(2026, 10, 10, 10),
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
  Future<Session?> fetchSession(String sessionId) async => session();

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

  SessionDetailViewModel buildVm() {
    final vm = SessionDetailViewModel(
      sessionRepo: repo,
      exerciseRepo: _FakeExerciseRepo(),
      lessonRepo: FakeLessonRepository(),
      userId: 'u1',
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

  test('a keystroke storm merges into one write per settle, patching state', () {
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
      expect(repo.updateSetCalls, 0,
          reason: 'keystrokes merge — nothing writes inside the window');
      expect(repo.timelineReads, readsAfterLoad,
          reason: 'no timeline query rides on a keystroke');

      async.elapse(SessionDetailViewModel.kAutoCommitDebounce + const Duration(milliseconds: 10));
      async.flushMicrotasks();

      expect(repo.updateSetCalls, 1,
          reason: 'one write per settle, however many keystrokes fed it');
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
  });

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
      expect(repo.updateLog.single.weight, 20,
          reason: 'immediate merges the pending value and writes it');

      async.elapse(const Duration(seconds: 1));
      expect(repo.updateSetCalls, 1,
          reason: 'the debounce timer was cancelled — no second write');
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

      expect(vm.state.value.workoutSetDrafts[draftOrder], isNotEmpty,
          reason: 'the old clearSessionSetDrafts wipe per keystroke is gone — '
              'only structural reloads clear drafts');
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
      async.elapse(SessionDetailViewModel.kAutoCommitDebounce + const Duration(milliseconds: 10));
      async.flushMicrotasks();

      expect(repo.updateSetCalls, 1);
      expect(vm.state.value.error, isNotNull);
      expect(
        vm.state.value.setsFor(1).single.weight,
        0,
        reason: 'the patch runs only after a successful write — the grid '
            'keeps the pre-edit row',
      );
      vm.dispose();
    });
  });
}

class FakeLessonRepository extends Fake implements LessonRepository {
  @override
  Future<List<Lesson>> fetchLessons(String userId, String exerciseId) async =>
      [];
}
