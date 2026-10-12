import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/cache/past_sets_timeline_cache.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:powersync/powersync.dart';

/// The timeline cache's freshness contract, end-to-end (2026-10-13): a
/// memoized read is served until a repository write invalidates, and the
/// next read after that write sees the new rows — the same guarantee every
/// screen in the app leans on, with the real triggers and real SQL.
///
///   flutter test integration_test/timeline_cache_freshness_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';

  late Directory dir;
  late PowerSyncDatabase db;
  late SessionRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps_cache');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    repo = SessionRepository();
    PastSetsTimelineCache.instance.invalidate();
  });

  tearDown(() async {
    PastSetsTimelineCache.instance.invalidate();
    await db.close();
    await dir.delete(recursive: true);
  });

  test('a repo write invalidates — the next read sees the new row', () async {
    final sessionId = await repo.createSession(userId);
    await repo.endSession(sessionId); // timeline reads completed rows only
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
      weight: 40,
      reps: const [5],
    );

    final first = await PastSetsTimelineCache.instance.get(userId);
    expect(
      first.firstWhere((r) => r.sessionExerciseSetId == set.sessionExerciseSetId).weight,
      40,
    );

    // A second read rides the memoized copy — and then a write busts it.
    final memoized = await PastSetsTimelineCache.instance.get(userId);
    expect(identical(first, memoized), isTrue,
        reason: 'no write in between — the cache serves the same rows');

    await repo.updateSet(set.sessionExerciseSetId, weight: 50);

    final after = await PastSetsTimelineCache.instance.get(userId);
    expect(
      after.firstWhere((r) => r.sessionExerciseSetId == set.sessionExerciseSetId).weight,
      50,
      reason: 'the write invalidated — the fresh read sees the edit',
    );
  });
}
