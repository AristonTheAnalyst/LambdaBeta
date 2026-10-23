import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/planned_session_exercise_set.dart';
import 'package:lambda/data/models/session_exercise.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/data/models/session.dart';
import 'package:lambda/data/repositories/exercise_repository.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:lambda/data/repositories/program_run_repository.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/session/viewmodel/session_viewmodel.dart';

/// The live-session commit pipeline (2026-10-13): keystrokes merge into one
/// debounced write per settle, the authoritative read comes from the watch
/// stream (no per-settle reload), and every flush point writes immediately.
///
/// The fake repo plays the database: `updateSet` records the call and then
/// re-emits the patched rows through the watch stream, exactly like the real
/// PowerSync triggers → watch flow.
class _FakeSessionRepo extends Fake implements SessionRepository {
  _FakeSessionRepo();

  String? activeSessionId = 'w1';
  int updateSetCalls = 0;
  int loadSetsCalls = 0;
  bool failUpdate = false;
  final updateLog = <({String setId, double? weight, bool clearWeight})>[];

  /// What the restore sees when it fetches the active session.
  Session? sessionRow;
  int endSessionCalls = 0;
  final updateNotesLog =
      <
        ({
          String? preNotes,
          String? postNotes,
          int? preFeeling,
          int? postFeeling,
        })
      >[];

  final rows = <String, SessionExerciseSet>{};
  final _setsCtl = StreamController<List<SessionExerciseSet>>.broadcast();
  final _exCtl = StreamController<List<SessionExercise>>.broadcast();

  SessionExerciseSet row({
    required String setId,
    double? weight = 0,
    List<num> reps = const [],
  }) => SessionExerciseSet(
    sessionExerciseSetId: setId,
    sessionExerciseId: 'se1',
    sessionId: activeSessionId!,
    userId: 'u1',
    setNumber: 1,
    weight: weight,
    reps: reps,
    exerciseId: 'ex1',
  );

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

  @override
  Future<Session?> fetchSession(String sessionId) async => sessionRow;

  @override
  Future<void> endSession(String sessionId) async => endSessionCalls++;

  @override
  Future<void> updateSessionNotes(
    String sessionId, {
    String? preNotes,
    String? postNotes,
    int? preFeeling,
    int? postFeeling,
  }) async {
    updateNotesLog.add((
      preNotes: preNotes,
      postNotes: postNotes,
      preFeeling: preFeeling,
      postFeeling: postFeeling,
    ));
  }

  @override
  Future<List<PastSetRow>> loadPastSetsTimeline(String userId) async => [];

  @override
  Future<List<SessionExerciseSet>> loadSetsForSession(String sessionId) async {
    loadSetsCalls++;
    return rows.values.toList();
  }

  /// The completed stack the floor's date bar walks, newest first.
  final completedStamps = <({String sessionId, DateTime createdDatetime})>[];

  @override
  Future<List<({String sessionId, DateTime createdDatetime})>>
  loadCompletedSessionStamps(String userId) async => completedStamps;

  @override
  Future<List<SessionExercise>> loadSessionExercises(String sessionId) async =>
      [];

  @override
  Stream<List<SessionExerciseSet>> watchSetsForSession(String sessionId) =>
      _setsCtl.stream;

  @override
  Stream<List<SessionExercise>> watchSessionExercises(String sessionId) =>
      _exCtl.stream;

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
    updateLog.add((setId: setId, weight: weight, clearWeight: clearWeight));
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
    );
    // The re-emit the real watch stream would deliver after the write.
    _setsCtl.add(rows.values.toList());
  }

  int insertSetCalls = 0;
  final insertLog =
      <({
        double? weight,
        List<num> reps,
        int setNumber,
        String? plannedSetId,
      })>[];

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
    insertLog.add((
      weight: weight,
      reps: reps,
      setNumber: setNumber,
      plannedSetId: plannedSetId,
    ));
    final setId = 'dup-${rows.length + 1}';
    rows[setId] = SessionExerciseSet(
      sessionExerciseSetId: setId,
      sessionExerciseId: sessionExerciseId,
      sessionId: sessionId,
      userId: userId,
      exerciseId: 'ex1',
      variationId: variationId,
      setNumber: setNumber,
      weight: weight,
      reps: reps,
      notes: notes,
    );
    _setsCtl.add(rows.values.toList());
    return rows[setId]!;
  }

  final insertedExercises =
      <({String? exerciseId, int exerciseOrder, String? plannedExerciseId})>[];

  @override
  Future<SessionExercise> insertSessionExercise({
    required String sessionId,
    required String userId,
    required int exerciseOrder,
    String? exerciseId,
    String? plannedExerciseId,
  }) async {
    insertedExercises.add((
      exerciseId: exerciseId,
      exerciseOrder: exerciseOrder,
      plannedExerciseId: plannedExerciseId,
    ));
    return SessionExercise(
      sessionExerciseId: 'se-${insertedExercises.length}',
      sessionId: sessionId,
      userId: userId,
      exerciseOrder: exerciseOrder,
      exerciseId: exerciseId,
      plannedExerciseId: plannedExerciseId,
    );
  }

  @override
  Future<void> deleteSession(String sessionId) async {}

  void disposeCtl() {
    _setsCtl.close();
    _exCtl.close();
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

  SessionViewModel buildVm() => SessionViewModel(
    sessionRepo: repo,
    exerciseRepo: _FakeExerciseRepo(),
    programRepo: FakeProgramRepository(),
    programRunRepo: FakeProgramRunRepository(),
    lessonRepo: FakeLessonRepository(),
    plannedSessionRepo: FakePlannedSessionRepository(),
    waitForFirstSync: () async {},
    userId: 'u1',
  );

  setUp(() {
    repo = _FakeSessionRepo();
  });

  tearDown(() {
    repo.disposeCtl();
  });

  test('a keystroke storm merges into one write per settle, no reloads', () {
    fakeAsync((async) {
      final vm = buildVm();
      async.flushMicrotasks(); // _init stages

      // Start the workout — the pulls it makes (restore + start) are the
      // only ones this session ever gets.
      vm.startWorkout();
      async.flushMicrotasks();
      final pullsAfterStart = repo.loadSetsCalls;
      expect(pullsAfterStart, greaterThan(0));

      final set = repo.row(setId: 's1');
      // "1" → "10" → "100": three keystrokes, no writes yet.
      vm.updateSetField(set, weight: 1, immediate: false);
      vm.updateSetField(set, weight: 10, immediate: false);
      vm.updateSetField(set, weight: 100, immediate: false);
      expect(
        repo.updateSetCalls,
        0,
        reason: 'keystrokes merge — nothing writes inside the window',
      );
      expect(
        repo.loadSetsCalls,
        pullsAfterStart,
        reason: 'no reload per keystroke',
      );

      async.elapse(
        SessionViewModel.kAutoCommitDebounce + const Duration(milliseconds: 10),
      );
      async.flushMicrotasks();

      expect(
        repo.updateSetCalls,
        1,
        reason: 'one write per settle, however many keystrokes fed it',
      );
      expect(
        repo.updateLog.single.weight,
        100,
        reason: 'the merged write carries the latest value',
      );
      expect(
        repo.loadSetsCalls,
        pullsAfterStart,
        reason:
            'the settle does not reload — the watch stream re-emitted '
            'the authoritative rows',
      );
      expect(
        vm.sets.single.weight,
        100,
        reason: 'the fake watch re-emit landed the row in the VM',
      );
      vm.dispose();
    });
  });

  test(
    'an immediate write lands now and the armed timer never fires again',
    () {
      fakeAsync((async) {
        final vm = buildVm();
        async.flushMicrotasks();
        vm.startWorkout();
        async.flushMicrotasks();

        final set = repo.row(setId: 's1');
        vm.updateSetField(set, weight: 10, immediate: false);
        vm.updateSetField(set, weight: 20, immediate: true);
        async.flushMicrotasks();
        expect(repo.updateSetCalls, 1);
        expect(
          repo.updateLog.single.weight,
          20,
          reason: 'immediate merges the pending value and writes it',
        );

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(
          repo.updateSetCalls,
          1,
          reason: 'the debounce timer was cancelled — no second write',
        );
        vm.dispose();
      });
    },
  );

  test('flushPendingCommits writes armed pending edits without waiting', () {
    fakeAsync((async) {
      final vm = buildVm();
      async.flushMicrotasks();
      vm.startWorkout();
      async.flushMicrotasks();

      final set = repo.row(setId: 's1');
      vm.updateSetField(set, weight: 42, immediate: false);
      expect(repo.updateSetCalls, 0);

      vm.flushPendingCommits();
      async.flushMicrotasks();
      expect(repo.updateSetCalls, 1);
      expect(repo.updateLog.single.weight, 42);

      async.elapse(const Duration(seconds: 1));
      expect(repo.updateSetCalls, 1, reason: 'flushed once, never again');
      vm.dispose();
    });
  });

  test('a failed write surfaces the error and drops the pending merge', () {
    fakeAsync((async) {
      final vm = buildVm();
      async.flushMicrotasks();
      vm.startWorkout();
      async.flushMicrotasks();
      repo.failUpdate = true;

      final set = repo.row(setId: 's1');
      vm.updateSetField(set, weight: 5, immediate: false);
      async.elapse(
        SessionViewModel.kAutoCommitDebounce + const Duration(milliseconds: 10),
      );
      async.flushMicrotasks();

      expect(repo.updateSetCalls, 1);
      expect(vm.error, isNotNull);
      // The DB never changed, so the stream never re-emitted — the VM still
      // holds the pre-write rows (automatic rollback via watch).
      expect(vm.sets, isEmpty);
      vm.dispose();
    });
  });

  test('duplicateSet inserts a copy with the on-screen values', () {
    fakeAsync((async) {
      final vm = buildVm();
      async.flushMicrotasks();
      vm.startWorkout();
      async.flushMicrotasks();

      repo.rows['s1'] = repo.row(setId: 's1', weight: 60, reps: [10]);
      repo._setsCtl.add(repo.rows.values.toList());
      async.flushMicrotasks();

      vm.duplicateSet(vm.sets.single, weight: 60, reps: [10]);
      async.flushMicrotasks();

      expect(
        repo.insertSetCalls,
        1,
        reason: 'the swipe Duplicate lands exactly one insert',
      );
      expect(repo.insertLog.single.weight, 60);
      expect(repo.insertLog.single.reps, [10]);
      expect(
        repo.insertLog.single.setNumber,
        2,
        reason: 'the copy takes the next set number',
      );
      expect(
        vm.sets.length,
        2,
        reason: 'the copy is in the grid after the reload',
      );
      vm.dispose();
    });
  });

  test('watch emissions recompute PRs and notify', () {
    fakeAsync((async) {
      final vm = buildVm();
      async.flushMicrotasks();
      vm.startWorkout();
      async.flushMicrotasks();

      var notifies = 0;
      vm.addListener(() => notifies++);

      // A frontier-beating row arriving through the stream (as the real
      // watch would deliver it) must flow into PR state.
      repo.rows['s1'] = repo.row(setId: 's1', weight: 100, reps: [5]);
      repo._setsCtl.add(repo.rows.values.toList());
      async.flushMicrotasks();

      expect(vm.sets.single.weight, 100);
      expect(
        vm.sessionPrEvents,
        isNotEmpty,
        reason:
            'the stream listener recomputes PRs — 100×5 with no prior '
            'history is a first PR',
      );
      expect(vm.isPrSet('s1'), isTrue);
      expect(notifies, greaterThan(0));
      vm.dispose();
    });
  });

  // ── Plan materialization (2026-10-23) ─────────────────────────────────────
  // "Record weight at start if it is a real value, but reps is always a
  // guide." The plan's single-number weight becomes the row's real weight (so
  // a repeat of the plan needs no typing); ranges and everything else stay on
  // the dim row as guides, and reps are never adopted.

  test('Start records a single-number planned weight; reps stay guides', () {
    fakeAsync((async) {
      final vm = buildVm();
      async.flushMicrotasks();

      PlannedSessionExerciseSet planned(
        String id,
        int number,
        String? weight,
        String? reps,
      ) => PlannedSessionExerciseSet(
        plannedSetId: id,
        plannedExerciseId: 'pe1',
        plannedSessionId: 'pw1',
        userId: 'u1',
        setNumber: number,
        exerciseId: 'ex1',
        targetWeight: weight,
        targetReps: reps,
      );

      vm.plannedExerciseOrder = ['ex1'];
      vm.plannedSetsByExercise = {
        'ex1': [
          planned('ps1', 1, '60', '8-12'),
          planned('ps2', 2, '60-70', 'AMRAP'),
        ],
      };

      vm.startWorkout();
      async.flushMicrotasks();

      expect(repo.insertedExercises.single.exerciseId, 'ex1');
      expect(repo.insertedExercises.single.plannedExerciseId, 'pe1');
      expect(repo.insertLog, hasLength(2));

      expect(repo.insertLog[0].weight, 60);
      expect(
        repo.insertLog[0].reps,
        isEmpty,
        reason: 'a planned rep range is a guide — never a logged rep',
      );
      expect(repo.insertLog[0].plannedSetId, 'ps1');

      expect(
        repo.insertLog[1].weight,
        isNull,
        reason: 'a planned weight range is a guide — never a logged weight',
      );
      expect(repo.insertLog[1].reps, isEmpty);
      vm.dispose();
    });
  });

  // ── Questionnaire bookends (2026-10-22) ───────────────────────────────────
  // The ratings pencil edits the same fields the prep/post pages collect, and
  // Done saves all four at once — so a restore must reseed the pre half or
  // Done would write blanks over what the prep page wrote.

  test('resuming a session reseeds its pre answers', () {
    fakeAsync((async) {
      repo.sessionRow = Session(
        sessionId: 'w1',
        userId: 'u1',
        createdDatetime: DateTime.utc(2026, 10, 22, 7),
        preNotes: 'Slept well',
        preFeeling: 4,
      );
      final vm = buildVm();
      async.flushMicrotasks();

      expect(vm.currentWorkoutId, 'w1');
      expect(
        vm.startNotes,
        'Slept well',
        reason: 'the pencil edits the field the prep page wrote at Start',
      );
      expect(vm.sessionFeeling, 4);
      vm.dispose();
    });
  });

  test('Done writes both bookends in one updateSessionNotes call', () {
    fakeAsync((async) {
      final vm = buildVm();
      async.flushMicrotasks();

      // The prep page's answers, captured at Start…
      vm.startNotes = 'Slept well';
      vm.setSessionFeeling(4);
      vm.startWorkout();
      async.flushMicrotasks();

      // …and post answers the pencil collected mid-session.
      vm.setEndFeeling(3);
      vm.endNotes = 'Rushed the last set';

      vm.finishSession();
      async.flushMicrotasks();
      expect(repo.endSessionCalls, 1);
      expect(
        vm.endFeeling,
        3,
        reason: 'the post page opens on the pencil\'s answer',
      );
      expect(vm.endNotes, 'Rushed the last set');

      vm.completePostQuestionnaire();
      async.flushMicrotasks();

      expect(
        repo.updateNotesLog,
        hasLength(1),
        reason: 'one write carries the whole questionnaire',
      );
      final write = repo.updateNotesLog.single;
      expect(write.preNotes, 'Slept well');
      expect(write.preFeeling, 4);
      expect(write.postNotes, 'Rushed the last set');
      expect(write.postFeeling, 3);
      vm.dispose();
    });
  });

  test('the live date bar opens the newest record this session did not '
      'walk over', () {
    fakeAsync((async) {
      final now = DateTime.now();
      repo.completedStamps.addAll([
        // A record stamped after this session began is not "before" it —
        // the walk reads the stack the session started on top of.
        (sessionId: 'future', createdDatetime: now.add(const Duration(days: 1))),
        (sessionId: 'h3', createdDatetime: now.subtract(const Duration(days: 1))),
        (sessionId: 'h2', createdDatetime: now.subtract(const Duration(days: 2))),
      ]);

      final vm = buildVm();
      async.flushMicrotasks();
      vm.startWorkout();
      async.flushMicrotasks();

      expect(vm.previousSessionId, 'h3');
      vm.dispose();
    });
  });
}

// ── Unused-surface fakes (the VM constructs them; these tests never touch
// their methods, so an accidental call fails loudly) ────────────────────────
class FakeProgramRepository extends Fake implements ProgramRepository {}

class FakeProgramRunRepository extends Fake implements ProgramRunRepository {}

class FakeLessonRepository extends Fake implements LessonRepository {}

class FakePlannedSessionRepository extends Fake
    implements PlannedSessionRepository {}
