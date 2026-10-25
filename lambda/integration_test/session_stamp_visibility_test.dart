import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/session/viewmodel/session_viewmodel.dart';
import 'package:powersync/powersync.dart';

/// The date bar walks the same sequence the logs list draws (2026-10-25).
///
/// A completed session that carries no performed work — no set at all, or
/// only flagged rows — is on neither: the list has no card to show, and the
/// walk must not step onto a record that cannot be opened. The row stays in
/// the database; only the three completed-session reads skip it. The live
/// floor's older step reads the same stamps as the viewer's arrows, so
/// proving the repository read proves both.
///
///   flutter test integration_test/session_stamp_visibility_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';

  late Directory dir;
  late PowerSyncDatabase db;
  late SessionRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps_stamps');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    repo = SessionRepository();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  /// Backdates a session, so the walk's order is the test's and not the
  /// clock's — every row here is written within the same few milliseconds.
  Future<void> stamp(String sessionId, String iso) => db.execute(
    'UPDATE fact_session SET created_datetime = ? WHERE session_id = ?',
    [iso, sessionId],
  );

  /// One completed session holding a single logged set.
  Future<String> completedWithSet(String iso) async {
    final id = await repo.createSession(userId);
    final group = await repo.insertSessionExercise(
      sessionId: id,
      userId: userId,
      exerciseOrder: 1,
      exerciseId: 'ex-bench',
    );
    await repo.insertSet(
      sessionExerciseId: group.sessionExerciseId,
      sessionId: id,
      userId: userId,
      setNumber: 1,
      weight: 50,
      reps: const [5],
    );
    await repo.endSession(id);
    await stamp(id, iso);
    return id;
  }

  test('an empty or fully-flagged completed session is on no walk', () async {
    final older = await completedWithSet('2026-10-01T10:00:00.000Z');
    final newer = await completedWithSet('2026-10-02T10:00:00.000Z');

    // The reported record, in the middle of the stack: completed, newest of
    // the lot by creation time, and holding nothing.
    final empty = await repo.createSession(userId);
    await repo.endSession(empty);
    await stamp(empty, '2026-10-03T10:00:00.000Z');

    // ...and one whose only set was deleted after the fact — every card it
    // could draw is gone too, so it leaves the same reads.
    final flagged = await completedWithSet('2026-10-04T10:00:00.000Z');
    await db.execute(
      'UPDATE fact_session_exercise_set SET is_deleted = 1 '
      'WHERE session_exercise_id IN ('
      '  SELECT session_exercise_id FROM fact_session_exercise '
      '  WHERE session_id = ?)',
      [flagged],
    );

    // The rows are all still there, in that order — the skip is in the
    // reads, not in the data.
    final all = await db.getAll(
      'SELECT session_id FROM fact_session '
      'WHERE user_id = ? AND end_datetime IS NOT NULL '
      'ORDER BY created_datetime DESC',
      [userId],
    );
    expect(all.map((r) => r['session_id']), [flagged, empty, newer, older]);

    // The list, the derived timeline and the walk are one sequence: newest
    // first, performed work only.
    final listed = [
      for (final w in await repo.loadSessionsWithSets(userId))
        w.session.sessionId,
    ];
    final timeline = {
      for (final r in await repo.loadPastSetsTimeline(userId)) r.sessionId,
    };
    final walked = [
      for (final s in await repo.loadCompletedSessionStamps(userId))
        s.sessionId,
    ];
    expect(listed, [newer, older]);
    expect(timeline, {newer, older});
    expect(walked, listed, reason: 'the bar and the list walk the same stack');

    // The live floor's older step reads those stamps: from a session started
    // after all of these it lands on the newest record with work — never on
    // the empty one sitting between.
    final live = await repo.createSession(userId, deviceId: 'dev-test');
    final vm = SessionViewModel(
      waitForFirstSync: () async {},
      userId: userId,
      deviceId: 'dev-test',
    );
    addTearDown(vm.dispose);
    // `_loadPreviousSession` runs unawaited once the session is adopted; the
    // step is chrome, so it lands whenever the read does.
    for (var i = 0; i < 60 && vm.previousSessionId == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(vm.currentWorkoutId, live);
    expect(
      vm.previousSessionId,
      newer,
      reason: 'the empty record is not a page the floor can step onto',
    );
  });
}
