import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/session/viewmodel/session_viewmodel.dart';
import 'package:powersync/powersync.dart';

/// The debounce's no-data-loss guarantee, end-to-end (2026-10-13).
///
/// Typing "1" → "10" → "100" then ending the session IMMEDIATELY (no blur,
/// no pause) must persist the final value — the flush that runs before the
/// prune cancels the debounce timer and writes the merged values. And the
/// whole burst must queue exactly ONE upload op for the set (the seed's
/// insert plus one update) — per-keystroke commits would have queued four.
///
///   flutter test integration_test/session_debounce_repo_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';

  late Directory dir;
  late PowerSyncDatabase db;
  late SessionRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps_debounce');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    repo = SessionRepository();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  /// The upload ops queued for one set — counted by the op payload carrying
  /// the set's id (column names in ps_crud vary across PowerSync versions,
  /// the payload's JSON does not).
  Future<int> setCrudOps(String setId) async {
    final rows = await db.getAll(
      'SELECT COUNT(*) AS c FROM ps_crud WHERE data LIKE ?',
      ['%$setId%'],
    );
    return rows.single['c']! as int;
  }

  test('a typed burst flushed by finishSession persists as one op', () async {
    // Seed an active session with one exercise and one empty set.
    final sessionId = await repo.createSession(userId);
    final group = await repo.insertSessionExercise(
      sessionId: sessionId,
      userId: userId,
      exerciseOrder: 1,
      exerciseId: 'ex-bench',
    );
    await repo.insertSet(
      sessionExerciseId: group.sessionExerciseId,
      sessionId: sessionId,
      userId: userId,
      setNumber: 1,
      reps: const [],
    );
    final seededSetId = (await repo.loadSetsForSession(sessionId))
        .single
        .sessionExerciseSetId;
    final opsBefore = await setCrudOps(seededSetId); // the seed's insert

    // The VM restores the active session from the swapped database; the
    // first-sync wait and the user id are seams (the harness has neither
    // a live sync connection nor a Supabase session).
    final vm = SessionViewModel(
      waitForFirstSync: () async {},
      userId: userId,
    );
    // Give _init's guarded stages (restore included) their turns.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(vm.currentWorkoutId, sessionId,
        reason: 'the restore must find the seeded active session');

    final set = vm.sets.single;
    vm.updateSetField(set, weight: 1, immediate: false);
    vm.updateSetField(set, weight: 10, immediate: false);
    vm.updateSetField(set, weight: 100, immediate: false);

    // End immediately — no blur, no debounce window elapsed. finishSession
    // flushes the pending merge before pruning and stamping.
    await vm.finishSession();
    vm.dispose();

    final stored = await repo.loadSetsForSession(sessionId);
    expect(stored.single.weight, 100,
        reason: 'the last keystroke survives ending the session with no '
            'blur — flush-before-prune is the no-data-loss guarantee');
    expect(stored.single.reps, isEmpty);
    expect(await setCrudOps(seededSetId), opsBefore + 1,
        reason: 'three keystrokes queue ONE upload op — the merge writes '
            'once per settle');
  });
}
