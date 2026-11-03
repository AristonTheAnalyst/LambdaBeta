import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/repositories/session_repository.dart';
import 'package:lambda/features/logs/viewmodel/session_detail_viewmodel.dart';
import 'package:lambda/features/session/viewmodel/session_viewmodel.dart';
import 'package:powersync/powersync.dart';

/// Soft-delete of planned rows, end to end (2026-10-13, reworked
/// 2026-10-14): flagging a planned set persists `is_deleted = 1` and hides
/// the row from the active grid, restoring un-flags it, and the flagged row
/// SURVIVES endSession — with its exercise row — so the past-session viewer
/// can show what was deleted and restore it. The derived reads (the
/// timeline, the all-sessions list) filter flagged rows out; the session's
/// own read returns them so the viewer's partition can show them.
///
///   flutter test integration_test/soft_delete_restore_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';

  late Directory dir;
  late PowerSyncDatabase db;
  late SessionRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps_softdel');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    repo = SessionRepository();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<int> flaggedCount(String setId) async {
    final rows = await db.getAll(
      'SELECT is_deleted FROM fact_session_exercise_set WHERE session_exercise_set_id = ?',
      [setId],
    );
    return rows.isEmpty ? -1 : rows.single['is_deleted'] as int;
  }

  test(
    'flag, hide, restore, and flagged rows survive the ended session',
    () async {
      // Seed an active session with a planned-linked exercise row and set —
      // stamped with this (fake) device, since the restore only resumes the
      // device's OWN session (2026-10-15).
      final sessionId = await repo.createSession(userId, deviceId: 'dev-test');
      final group = await repo.insertSessionExercise(
        sessionId: sessionId,
        userId: userId,
        exerciseOrder: 1,
        exerciseId: 'ex-bench',
        plannedExerciseId: 'pe1',
      );
      final set = await repo.insertSet(
        sessionExerciseId: group.sessionExerciseId,
        sessionId: sessionId,
        userId: userId,
        setNumber: 1,
        reps: const [],
        plannedSetId: 'ps1',
      );

      // The VM restores the session and partitions the row into active sets.
      final vm = SessionViewModel(
        waitForFirstSync: () async {},
        userId: userId,
        deviceId: 'dev-test',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(vm.sets.single.sessionExerciseSetId, set.sessionExerciseSetId);
      expect(vm.deletedSets, isEmpty);

      // Delete it — planned rows flag instead of removing.
      await vm.deleteSetById(set.sessionExerciseSetId);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        await flaggedCount(set.sessionExerciseSetId),
        1,
        reason: 'the row persists, flagged',
      );
      expect(
        vm.sets,
        isEmpty,
        reason: 'the flagged row leaves the active grid',
      );
      expect(
        vm.deletedPlannedExercises,
        isNotEmpty,
        reason: 'the exercise is recorded as deleted',
      );
      expect(vm.deletedPlannedExerciseEntries.map((e) => e.id), [
        group.sessionExerciseId,
      ], reason: 'the trash menu holds it, addressable by session-exercise id');

      // Restore — the trash menu's row (index 0) un-flags.
      await vm.restoreDeletedPlannedExerciseAt(0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await flaggedCount(set.sessionExerciseSetId), 0);
      expect(vm.sets, isNotEmpty);

      // Flag again, then finish: the flagged row SURVIVES (2026-10-14) —
      // marked done, ready for the past-session viewer to show and restore.
      await vm.deleteSetById(set.sessionExerciseSetId);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await vm.finishSession();
      vm.dispose();

      expect(
        await flaggedCount(set.sessionExerciseSetId),
        1,
        reason: 'flagged rows are historic facts now — the prune keeps them',
      );
      final seRows = await db.getAll(
        'SELECT COUNT(*) AS c FROM fact_session_exercise WHERE session_exercise_id = ?',
        [group.sessionExerciseId],
      );
      expect(
        seRows.single['c'],
        1,
        reason:
            'the exercise row survives too — it carries the identity '
            'and the number',
      );
      final ended = await db.getAll(
        'SELECT end_datetime FROM fact_session WHERE session_id = ?',
        [sessionId],
      );
      expect(
        ended.single['end_datetime'],
        isNotNull,
        reason: 'the session itself is completed',
      );

      // The derived reads exclude it: the timeline never sees a deleted set…
      final timeline = await repo.loadPastSetsTimeline(userId);
      expect(
        timeline.where(
          (r) => r.sessionExerciseSetId == set.sessionExerciseSetId,
        ),
        isEmpty,
        reason:
            'a deleted set is not performed work — PRs and history '
            'derivations must not see it',
      );
      // …and the all-sessions list (the logs list's counts) excludes it too.
      final withSets = await repo.loadSessionsWithSets(userId);
      expect(
        withSets
            .expand((w) => w.sets)
            .where((s) => s.sessionExerciseSetId == set.sessionExerciseSetId),
        isEmpty,
      );
      // The session's OWN read returns it — the viewer's partition is what
      // shows it red.
      final ownRows = await repo.loadSetsForSession(sessionId);
      expect(
        ownRows.single.sessionExerciseSetId,
        set.sessionExerciseSetId,
        reason: 'loadSetsForSession deliberately returns flagged rows',
      );
      expect(ownRows.single.isDeleted, isTrue);

      // The past-session editor loads the completed session through the same
      // read — the deleted exercise arrives as a red, restorable entry.
      final logsVm = SessionDetailViewModel(userId: userId);
      await logsVm.load(sessionId);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        logsVm.state.value.exerciseSlots.single.deleted,
        isTrue,
        reason: 'the viewer sees the deletion, at its number',
      );
      expect(logsVm.hasDeletedExercises, isTrue);

      await logsVm.restoreDeletedExercise(0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(logsVm.state.value.exerciseSlots.single.deleted, isFalse);
      expect(
        await flaggedCount(set.sessionExerciseSetId),
        0,
        reason: 'the restore un-flags — the set is performed history again',
      );
      final restored = await repo.loadPastSetsTimeline(userId);
      expect(
        restored.where(
          (r) => r.sessionExerciseSetId == set.sessionExerciseSetId,
        ),
        isNotEmpty,
        reason:
            'the restored row is a performed set again — the timeline '
            'sees it',
      );
      logsVm.dispose();
    },
  );

  test(
    'Finish prunes a weight-only planned row; a performed row survives',
    () async {
      // Start records a plan's single-number weight into the row (2026-10-23)
      // — so the weight column can no longer mean "the user touched this".
      // A rep is the performance: no reps, no variation, no notes = a hint,
      // pruned at Finish. User-added rows are never pruned.
      final sessionId = await repo.createSession(userId, deviceId: 'dev-test');
      final group = await repo.insertSessionExercise(
        sessionId: sessionId,
        userId: userId,
        exerciseOrder: 1,
        exerciseId: 'ex-bench',
        plannedExerciseId: 'pe1',
      );
      Future<String> addRow({
        String? plannedSetId,
        double? weight,
        List<num> reps = const [],
        String? variationId,
      }) async => (await repo.insertSet(
        sessionExerciseId: group.sessionExerciseId,
        sessionId: sessionId,
        userId: userId,
        setNumber: 1,
        weight: weight,
        reps: reps,
        variationId: variationId,
        plannedSetId: plannedSetId,
      )).sessionExerciseSetId;

      // The adopted plan weight, never performed.
      final untouched = await addRow(plannedSetId: 'ps1', weight: 60);
      // Performed: reps typed, weight still the plan's.
      final performed = await addRow(
        plannedSetId: 'ps2',
        weight: 60,
        reps: const [9],
      );
      // A variation is a real choice — the row persists.
      final varied = await addRow(plannedSetId: 'ps3', variationId: 'v1');
      // A user-added empty row is a deliberate act — it persists.
      final userAdded = await addRow();

      Future<int> rowCount(String setId) async {
        final rows = await db.getAll(
          'SELECT COUNT(*) AS c FROM fact_session_exercise_set '
          'WHERE session_exercise_set_id = ?',
          [setId],
        );
        return rows.single['c'] as int;
      }

      final vm = SessionViewModel(
        waitForFirstSync: () async {},
        userId: userId,
        deviceId: 'dev-test',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(vm.sets, hasLength(4));

      await vm.finishSession();
      vm.dispose();

      expect(
        await rowCount(untouched),
        0,
        reason: 'a weight with no reps is an adopted hint, not a set',
      );
      expect(
        await rowCount(performed),
        1,
        reason: 'a typed rep is the performance — the row is kept',
      );
      expect(await rowCount(varied), 1);
      expect(
        await rowCount(userAdded),
        1,
        reason: 'only PLAN-linked rows are pruned',
      );
      final kept = await db.getAll(
        'SELECT reps FROM fact_session_exercise_set '
        'WHERE session_exercise_set_id = ?',
        [performed],
      );
      expect(kept.single['reps'], '[9]');
    },
  );
}
