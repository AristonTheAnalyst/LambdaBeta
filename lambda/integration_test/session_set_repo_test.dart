import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:powersync/powersync.dart';

/// Clearing a set's reps has to reach the row.
///
/// A null `reps` was dropped from the UPDATE for as long as `updateSet` has
/// existed (the clause only fired when reps were present), so a cleared cell
/// left the stored `[20]` in place — and the PR engine, which reads the row
/// honestly, kept the PR the user had just deleted. This pins the write, not
/// the engine: the engine was never wrong about what it was given.
///
///   flutter test integration_test/session_set_repo_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';

  late Directory dir;
  late PowerSyncDatabase db;
  late SessionRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    repo = SessionRepository();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  /// The one set, as the database holds its reps — the raw column, not the
  /// repository's own reading of it.
  Future<Object?> storedReps(String setId) async {
    final rows = await db.getAll(
      'SELECT reps FROM fact_session_exercise_set '
      'WHERE session_exercise_set_id = ?',
      [setId],
    );
    return rows.single['reps'];
  }

  Future<String> seedSet() async {
    final sessionId = await repo.createSession(userId);
    final group = await repo.insertSessionExercise(
      sessionId: sessionId,
      userId: userId,
      exerciseOrder: 1,
      exerciseId: 'ex-bench',
    );
    final set = await repo.insertSet(
      sessionExerciseId: group.sessionExerciseId,
      sessionId: sessionId,
      userId: userId,
      setNumber: 1,
      reps: const [],
    );
    return set.sessionExerciseSetId;
  }

  test('clearReps empties the stored reps', () async {
    final setId = await seedSet();
    await repo.updateSet(setId, reps: [20], weight: 5);
    expect(await storedReps(setId), '[20]');

    await repo.updateSet(setId, clearReps: true);

    expect(await storedReps(setId), '[]',
        reason: 'the one empty-reps spelling the draft path writes — every '
            'never-filled row reads identically');
  });

  test('a null reps without clearReps leaves the row alone', () async {
    final setId = await seedSet();
    await repo.updateSet(setId, reps: [20]);

    // A weight-only edit: reps absent from the call must not empty the row.
    await repo.updateSet(setId, weight: 7.5);

    expect(await storedReps(setId), '[20]',
        reason: 'absent means "no opinion"; clearReps is the only way to say '
            'empty, so the two can never be confused');
  });
}
