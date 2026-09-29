import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:powersync/powersync.dart';

/// What opening a template does to it — and, mostly, what it must not do.
///
/// Every surface that opens a template reads its sets through
/// `fetchNormalizedPlannedSets`: the planner on open and the session preview on
/// select. That read repairs the order it hands back, and nothing else. It used
/// to also prune rows with no target data, on the theory that such a row was a
/// legacy keep-alive stub — but a row with no target data is exactly what
/// `WorkoutEditorViewModel.saveWorkout` writes for an untouched set, so Save
/// followed by a reopen deleted the exercise the user had just added. These
/// tests hold that shut from the repository side, where the pruning lived.
///
///   flutter test integration_test/planned_session_repo_test.dart -d DEVICE
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';

  late Directory dir;
  late PowerSyncDatabase db;
  late PlannedSessionRepository planned;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.setDatabaseForTesting(db);
    planned = PlannedSessionRepository();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  /// The group rows as the database holds them — unfiltered, so a row the read
  /// archived on its way past is still visible here.
  Future<List<Map<String, Object?>>> groupRows(String sessionId) => db.getAll(
        'SELECT planned_exercise_id, exercise_order, is_archived '
        'FROM dim_planned_session_exercise WHERE planned_session_id = ? '
        'ORDER BY exercise_order',
        [sessionId],
      );

  test('an exercise saved with only empty sets survives the next open',
      () async {
    final session = await planned.createPlannedSession(userId, name: 'Push');
    final group = await planned.createPlannedExercise(
      userId,
      session.sessionId,
      exerciseId: 'ex-bench',
      exerciseOrder: 1,
    );

    // Save, with every set left blank. This is what the editor does on an
    // explicit Save — one empty row per untouched draft — and the empty row is
    // deliberate: the user added an exercise and said so by saving. Every
    // target column is null, which is the shape the read once read as a stub.
    await planned.createPlannedSet(
      userId,
      group.plannedExerciseId,
      plannedSessionId: session.sessionId,
      exerciseId: 'ex-bench',
      setNumber: 1,
    );

    // Reopen. The planner and the session preview both come through here.
    final sets = await planned.fetchNormalizedPlannedSets(session.sessionId);
    expect(sets, hasLength(1));
    expect(sets.single.plannedExerciseId, group.plannedExerciseId);
    expect(sets.single.targetWeight, isNull);
    expect(sets.single.targetReps, isNull,
        reason: 'the row is empty — that is what makes it the case worth '
            'keeping: a filled-in set was never at risk');

    final rows = await groupRows(session.sessionId);
    expect(rows, hasLength(1));
    expect(rows.single['is_archived'], 0,
        reason: 'an exercise with nothing in it yet is still an exercise the '
            'user added; the read is not entitled to decide otherwise');
    expect(rows.single['planned_exercise_id'], group.plannedExerciseId);
  });

  test('an exercise whose sets were all deleted is not deleted with them',
      () async {
    final session = await planned.createPlannedSession(userId, name: 'Push');
    final group = await planned.createPlannedExercise(
      userId,
      session.sessionId,
      exerciseId: 'ex-bench',
      exerciseOrder: 1,
    );
    final set = await planned.createPlannedSet(
      userId,
      group.plannedExerciseId,
      plannedSessionId: session.sessionId,
      setNumber: 1,
      targetWeight: '70',
      targetReps: '5',
    );

    // The user's own delete — the swipe on the row, not a read.
    await planned.deletePlannedSet(set.plannedSetId);

    final sets = await planned.fetchNormalizedPlannedSets(session.sessionId);
    expect(sets, isEmpty);
    expect((await groupRows(session.sessionId)).single['is_archived'], 0,
        reason: 'deleting the sets is what was asked for. A group left with '
            'none is the state the user left it in, and the empty exercise '
            'card is how they see it — and how they get back to it');
  });

  test('the read renumbers in place, and gives a setless group its own slot',
      () async {
    final session = await planned.createPlannedSession(userId, name: 'Push');
    // Orders with a gap where a group was once deleted, and a group in the
    // middle of the sequence that has no sets at all.
    final first = await planned.createPlannedExercise(
      userId,
      session.sessionId,
      exerciseId: 'ex-bench',
      exerciseOrder: 1,
    );
    final between = await planned.createPlannedExercise(
      userId,
      session.sessionId,
      exerciseId: 'ex-row',
      exerciseOrder: 2,
    );
    final last = await planned.createPlannedExercise(
      userId,
      session.sessionId,
      exerciseId: 'ex-pulldown',
      exerciseOrder: 4,
    );

    for (final setNumber in [1, 4]) {
      await planned.createPlannedSet(
        userId,
        first.plannedExerciseId,
        plannedSessionId: session.sessionId,
        setNumber: setNumber,
        targetWeight: '70',
        targetReps: '5',
      );
    }
    await planned.createPlannedSet(
      userId,
      last.plannedExerciseId,
      plannedSessionId: session.sessionId,
      setNumber: 2,
      targetWeight: '50',
      targetReps: '10',
    );

    final sets = await planned.fetchNormalizedPlannedSets(session.sessionId);
    expect(sets.map((s) => s.plannedExerciseId),
        [first.plannedExerciseId, first.plannedExerciseId, last.plannedExerciseId]);
    expect(sets.map((s) => s.setNumber), [1, 2, 1],
        reason: 'set_number counts within a group by first appearance, so the '
            'gap a deleted row left closes and the planner\'s counts match the '
            'preview\'s rows again');

    final orders = {
      for (final r in await groupRows(session.sessionId))
        r['planned_exercise_id']: r['exercise_order'],
    };
    expect(orders[first.plannedExerciseId], 1);
    expect(orders[between.plannedExerciseId], 2,
        reason: 'a group with no sets is still a group: it keeps its place, '
            'and the group after it moves past rather than onto it');
    expect(orders[last.plannedExerciseId], 3);
  });
}
