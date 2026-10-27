import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/session/viewmodel/session_viewmodel.dart';
import 'package:powersync/powersync.dart';

/// Deleting ONE exercise in a live session may take that exercise's rows and
/// nothing else (2026-10-27).
///
/// A 2026-10-26 report from a two-device session said deleting one exercise
/// wiped every OTHER exercise's sets, and that newly added sets were cleared
/// again — on an older build. No local path here can reach another exercise:
/// the hard delete is scoped by `session_exercise_id`, and a planned slot
/// flags only its own rows. What CAN read like that report is a whole-session
/// delete (a Cancel on the other device): the live grid's read INNER JOINs
/// `fact_session_exercise`, so once a session-exercise row is gone its sets
/// stop drawing — and a set inserted under a vanished row never draws at all.
/// These tests pin the local scoping so a regression is caught here first; the
/// two-device reading needs the repro protocol, not a guess.
///
///   flutter test integration_test/session_exercise_delete_scope_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';
  const deviceId = 'dev-test';

  late Directory dir;
  late PowerSyncDatabase db;
  late SessionRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps_del_scope');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    repo = SessionRepository();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<int> rowCount(String table, String column, String id) async {
    final rows = await db.getAll(
      'SELECT COUNT(*) AS c FROM $table WHERE $column = ?',
      [id],
    );
    return rows.single['c'] as int;
  }

  Future<String> seedExercise({
    required String sessionId,
    required String exerciseId,
    required int order,
    String? plannedExerciseId,
    String? plannedSetId,
  }) async {
    final group = await repo.insertSessionExercise(
      sessionId: sessionId,
      userId: userId,
      exerciseOrder: order,
      exerciseId: exerciseId,
      plannedExerciseId: plannedExerciseId,
    );
    await repo.insertSet(
      sessionExerciseId: group.sessionExerciseId,
      sessionId: sessionId,
      userId: userId,
      setNumber: 1,
      weight: 60,
      reps: const [5],
      plannedSetId: plannedSetId,
    );
    return group.sessionExerciseId;
  }

  test('deleting a freestyle exercise leaves every other exercise alone, and '
      'the next set added still draws', () async {
    final sessionId = await repo.createSession(userId, deviceId: deviceId);
    final benchSe = await seedExercise(
      sessionId: sessionId,
      exerciseId: 'ex-bench',
      order: 1,
    );
    final squatSe = await seedExercise(
      sessionId: sessionId,
      exerciseId: 'ex-squat',
      order: 2,
    );

    final vm = SessionViewModel(
      waitForFirstSync: () async {},
      userId: userId,
      deviceId: deviceId,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(vm.sets, hasLength(2));
    expect(vm.exerciseSlots, hasLength(2));

    // The selector's remove on the first exercise — a freestyle slot dies
    // hard.
    await vm.removeExerciseSlot(0);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(
      vm.sets.map((s) => s.exerciseId),
      everyElement('ex-squat'),
      reason:
          'the report said every other exercise\'s sets went with it — '
          'only the removed exercise may leave the grid',
    );
    expect(
      await rowCount('fact_session_exercise', 'session_exercise_id', benchSe),
      0,
    );
    expect(
      await rowCount(
        'fact_session_exercise_set',
        'session_exercise_id',
        benchSe,
      ),
      0,
    );
    expect(
      await rowCount('fact_session_exercise', 'session_exercise_id', squatSe),
      1,
    );
    expect(
      await rowCount(
        'fact_session_exercise_set',
        'session_exercise_id',
        squatSe,
      ),
      1,
      reason: 'the other exercise keeps its set row, untouched',
    );

    // "+ ADD SET" on the surviving exercise — the second half of the
    // report: a new set must stay on the grid, not be cleared again.
    await vm.addDraftSet('ex-squat');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(
      await rowCount(
        'fact_session_exercise_set',
        'session_exercise_id',
        squatSe,
      ),
      2,
      reason: 'the tap wrote a real row under the LIVE exercise row',
    );
    expect(
      vm.sets.where((s) => s.exerciseId == 'ex-squat').length,
      2,
      reason:
          'the grid reads the row back — a set inserted under a vanished '
          'session-exercise row would never draw (the reported '
          '"cleared again")',
    );
    vm.dispose();
  });

  test('removing a planned exercise flags its own rows only', () async {
    final sessionId = await repo.createSession(userId, deviceId: deviceId);
    final benchSe = await seedExercise(
      sessionId: sessionId,
      exerciseId: 'ex-bench',
      order: 1,
      plannedExerciseId: 'pe1',
      plannedSetId: 'ps1',
    );
    final squatSe = await seedExercise(
      sessionId: sessionId,
      exerciseId: 'ex-squat',
      order: 2,
    );

    final vm = SessionViewModel(
      waitForFirstSync: () async {},
      userId: userId,
      deviceId: deviceId,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await vm.removeExerciseSlot(0);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final benchRows = await db.getAll(
      'SELECT is_deleted FROM fact_session_exercise_set '
      'WHERE session_exercise_id = ?',
      [benchSe],
    );
    expect(
      benchRows.single['is_deleted'],
      1,
      reason: 'a planned exercise soft-deletes its rows',
    );
    expect(
      await rowCount('fact_session_exercise', 'session_exercise_id', benchSe),
      1,
      reason: 'its session-exercise row stays — the trash lists it',
    );
    final squatRows = await db.getAll(
      'SELECT is_deleted FROM fact_session_exercise_set '
      'WHERE session_exercise_id = ?',
      [squatSe],
    );
    expect(
      squatRows.single['is_deleted'],
      0,
      reason: 'the other exercise is not flagged, not removed, not touched',
    );
    expect(
      vm.sets.map((s) => s.exerciseId),
      everyElement('ex-squat'),
      reason: 'only the flagged exercise leaves the active grid',
    );
    vm.dispose();
  });
}
