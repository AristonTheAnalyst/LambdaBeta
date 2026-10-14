import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
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
  }) async => activeSessionId ?? 'w1';

  @override
  Future<String?> getActiveSessionId(String userId) async => activeSessionId;

  @override
  Future<Session?> fetchSession(String sessionId) async => null;

  @override
  Future<List<PastSetRow>> loadPastSetsTimeline(String userId) async => [];

  @override
  Future<List<SessionExerciseSet>> loadSetsForSession(String sessionId) async {
    loadSetsCalls++;
    return rows.values.toList();
  }

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
      variationId: clearVariation ? null : (variationId ?? existing.variationId),
      notes: clearNotes ? null : (notes ?? existing.notes),
      exerciseId: existing.exerciseId,
    );
    // The re-emit the real watch stream would deliver after the write.
    _setsCtl.add(rows.values.toList());
  }

  int insertSetCalls = 0;
  final insertLog = <({double? weight, List<num> reps, int setNumber})>[];

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
    insertLog.add((weight: weight, reps: reps, setNumber: setNumber));
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
      expect(repo.updateSetCalls, 0,
          reason: 'keystrokes merge — nothing writes inside the window');
      expect(repo.loadSetsCalls, pullsAfterStart,
          reason: 'no reload per keystroke');

      async.elapse(SessionViewModel.kAutoCommitDebounce + const Duration(milliseconds: 10));
      async.flushMicrotasks();

      expect(repo.updateSetCalls, 1,
          reason: 'one write per settle, however many keystrokes fed it');
      expect(repo.updateLog.single.weight, 100,
          reason: 'the merged write carries the latest value');
      expect(repo.loadSetsCalls, pullsAfterStart,
          reason: 'the settle does not reload — the watch stream re-emitted '
              'the authoritative rows');
      expect(vm.sets.single.weight, 100,
          reason: 'the fake watch re-emit landed the row in the VM');
      vm.dispose();
    });
  });

  test('an immediate write lands now and the armed timer never fires again', () {
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
      expect(repo.updateLog.single.weight, 20,
          reason: 'immediate merges the pending value and writes it');

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(repo.updateSetCalls, 1,
          reason: 'the debounce timer was cancelled — no second write');
      vm.dispose();
    });
  });

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
      async.elapse(SessionViewModel.kAutoCommitDebounce + const Duration(milliseconds: 10));
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

      expect(repo.insertSetCalls, 1,
          reason: 'the swipe Duplicate lands exactly one insert');
      expect(repo.insertLog.single.weight, 60);
      expect(repo.insertLog.single.reps, [10]);
      expect(repo.insertLog.single.setNumber, 2,
          reason: 'the copy takes the next set number');
      expect(vm.sets.length, 2,
          reason: 'the copy is in the grid after the reload');
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
      expect(vm.sessionPrEvents, isNotEmpty,
          reason: 'the stream listener recomputes PRs — 100×5 with no prior '
              'history is a first PR');
      expect(vm.isPrSet('s1'), isTrue);
      expect(notifies, greaterThan(0));
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
