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
    ps.swapDatabase(db);
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

  // ── Recency (2026-10-26) ────────────────────────────────────────────────
  // The library listing leads with the workout trained most recently, then
  // the newest-created never-logged ones — the review picker's rule, now one
  // comparator both reads share. A program listing keeps its sequence order.

  test('the library list leads with the workout last trained', () async {
    Future<void> stamp(String sessionId, DateTime created) => db.execute(
      'UPDATE dim_planned_session SET created_date = ? WHERE session_id = ?',
      [created.toUtc().toIso8601String(), sessionId],
    );
    Future<void> log(String id, String plannedSessionId, DateTime at) =>
        db.execute(
          '''
          INSERT INTO fact_session
            (id, session_id, user_id, created_datetime, end_datetime,
             planned_session_id)
          VALUES (?, ?, ?, ?, ?, ?)
          ''',
          [
            id,
            id,
            userId,
            at.toUtc().toIso8601String(),
            at.toUtc().toIso8601String(),
            plannedSessionId,
          ],
        );

    final oldest = await planned.createPlannedSession(userId, name: 'Oldest');
    final middle = await planned.createPlannedSession(userId, name: 'Middle');
    final newest = await planned.createPlannedSession(userId, name: 'Newest');
    await stamp(oldest.sessionId, DateTime(2026, 10, 1));
    await stamp(middle.sessionId, DateTime(2026, 10, 2));
    await stamp(newest.sessionId, DateTime(2026, 10, 3));

    expect(
      (await planned.fetchPlannedSessions(userId)).map((s) => s.name),
      ['Newest', 'Middle', 'Oldest'],
      reason: 'nothing logged yet — newest created leads',
    );

    await log('w1', middle.sessionId, DateTime(2026, 10, 5));
    expect(
      (await planned.fetchPlannedSessions(userId)).map((s) => s.name),
      ['Middle', 'Newest', 'Oldest'],
      reason: 'the logged workout leads; the rest stay newest-created first',
    );

    await log('w2', oldest.sessionId, DateTime(2026, 10, 6));
    expect(
      (await planned.fetchPlannedSessions(userId)).map((s) => s.name),
      ['Oldest', 'Middle', 'Newest'],
      reason: 'the most recent session decides, not the creation date',
    );

    // An open session is still a use — a template in the middle of being
    // trained is the most recently used one.
    await db.execute(
      '''
      INSERT INTO fact_session
        (id, session_id, user_id, created_datetime, end_datetime,
         planned_session_id)
      VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        'w3',
        'w3',
        userId,
        DateTime(2026, 10, 7).toUtc().toIso8601String(),
        null,
        newest.sessionId,
      ],
    );
    expect(
      (await planned.fetchPlannedSessions(userId)).map((s) => s.name),
      ['Newest', 'Oldest', 'Middle'],
    );
  });

  test('a program listing keeps its sequence order, not recency', () async {
    final first = await planned.createPlannedSession(userId, name: 'First');
    final second = await planned.createPlannedSession(userId, name: 'Second');
    for (final (i, s) in [second, first].indexed) {
      await db.execute(
        '''
        INSERT INTO dim_planned_session_program
          (id, planned_session_program_id, program_id, planned_session_id,
           user_id, sequence_order)
        VALUES (?, ?, ?, ?, ?, ?)
        ''',
        ['link-$i', 'link-$i', 'p1', s.sessionId, userId, i + 1],
      );
    }
    // Recency would put First on top; sequence order must not.
    await db.execute(
      '''
      INSERT INTO fact_session
        (id, session_id, user_id, created_datetime, end_datetime,
         planned_session_id)
      VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        'w1',
        'w1',
        userId,
        DateTime(2026, 10, 9).toUtc().toIso8601String(),
        DateTime(2026, 10, 9).toUtc().toIso8601String(),
        first.sessionId,
      ],
    );

    expect(
      (await planned.fetchPlannedSessions(userId, programId: 'p1'))
          .map((s) => s.name),
      ['Second', 'First'],
      reason: 'a program\'s workouts are the plan\'s shape, not a usage list',
    );
  });
}
