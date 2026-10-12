import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:powersync/powersync.dart';

/// On-device test of `hardDeleteProgram` against a REAL PowerSync SQLite DB.
/// Run with:
///
///   flutter test integration_test/program_hard_delete_repo_test.dart -d DEVICE
///
/// Host `flutter test` cannot load `libpowersync.dylib`, so this cannot be a
/// `test/` unit test.
///
/// This proves the *local* result — every dependent row gone, sessions kept
/// but unlinked, other programs untouched. It cannot prove the server-side
/// statement order, because PowerSync's local SQLite declares no foreign keys
/// so nothing here refuses a delete. That order is what the NO ACTION edges in
/// the cloud schema police; it is checked separately against the real
/// constraints.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';
  const p1 = 'p1';
  const p2 = 'p2';

  late Directory dir;
  late PowerSyncDatabase db;
  late ProgramRepository programs;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    programs = ProgramRepository();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  /// Every fact and dim row that hangs off a program, so `_count` can assert
  /// on all of them the same way.
  const dependentTables = [
    'dim_program_block',
    'fact_program_run',
    'fact_program_review',
    'fact_goal',
    'dim_planned_session_program',
  ];

  test('hard-deletes the program and every row that hangs off it', () async {
    await _seedProgram(db, userId, p1);

    for (final table in dependentTables) {
      expect(await _count(db, table, 'program_id', p1), 1,
          reason: '$table should have been seeded for $p1');
    }

    await programs.hardDeleteProgram(p1);

    expect(await _count(db, 'dim_program', 'program_id', p1), 0);
    for (final table in dependentTables) {
      expect(await _count(db, table, 'program_id', p1), 0,
          reason: '$table outlived the program');
    }

    // Matched on block rather than program — a program_id-only delete would
    // leave this one behind, and then the block delete would fail on the FK.
    expect(await _countAll(db, 'fact_goal'), 0,
        reason: 'the block-scoped goal with a null program_id survived');
  });

  test('a logged session survives, unlinked from the run', () async {
    await _seedProgram(db, userId, p1);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      '''
      INSERT INTO fact_session
        (id, session_id, user_id, pre_notes, post_notes, created_datetime,
         end_datetime, planned_session_id, planned_session_name,
         program_run_id, post_feeling, pre_feeling)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      ['s1', 's1', userId, null, null, now, now, null, 'Day 1', 'r-$p1',
       null, null],
    );

    expect(await programs.programSessionCount(p1), 1);

    await programs.hardDeleteProgram(p1);

    // The row is still there — this is the whole point of SET NULL — and it
    // no longer claims a run that does not exist.
    final rows = await db.getAll(
      'SELECT session_id, program_run_id FROM fact_session WHERE session_id = ?',
      ['s1'],
    );
    expect(rows, hasLength(1));
    expect(rows.first['program_run_id'], isNull);
  });

  test('another program and its rows are left alone', () async {
    await _seedProgram(db, userId, p1);
    await _seedProgram(db, userId, p2);

    await programs.hardDeleteProgram(p1);

    expect(await _count(db, 'dim_program', 'program_id', p2), 1);
    for (final table in dependentTables) {
      expect(await _count(db, table, 'program_id', p2), 1,
          reason: '$table lost $p2 rows while deleting $p1');
    }
  });
}

/// One of everything that points at a program, built so that the two edges the
/// delete order exists to respect are both present: a review carrying a
/// `program_run_id`, and a run carrying a `block_id`. Seeding only one of them
/// would leave the interesting ordering untested.
Future<void> _seedProgram(
  PowerSyncDatabase db,
  String userId,
  String programId,
) async {
  final now = DateTime.now().toUtc().toIso8601String();

  await db.execute(
    '''
    INSERT INTO dim_program
      (id, program_id, user_id, program_name, program_description,
       date_archived, program_created_date, program_updated_date)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [programId, programId, userId, 'Program $programId', null, now, now, now],
  );

  final blockId = 'b-$programId';
  await db.execute(
    '''
    INSERT INTO dim_program_block
      (id, block_id, user_id, program_id, name, notes, block_order,
       target_weeks, target_days, target_sessions, start_date, end_date,
       date_archived, created_date, updated_date)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [blockId, blockId, userId, programId, 'Block', null, 1, null, null, null,
     null, null, null, now, now],
  );

  final runId = 'r-$programId';
  await db.execute(
    '''
    INSERT INTO fact_program_run
      (id, program_run_id, program_id, user_id, target_sessions, target_weeks,
       end_date, started_date, ended_date, is_current, progression_mode,
       block_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [runId, runId, programId, userId, null, null, null, now, null, 0, 'order',
     blockId],
  );

  // A close review carrying the run — this is the row that makes the delete
  // order interesting, because the review points at the run that points at the
  // block. The snapshot columns are the ones the model added in the reviews
  // rework; a close always carries one.
  await db.execute(
    '''
    INSERT INTO fact_program_review
      (id, review_id, user_id, program_id, block_id, program_run_id, kind,
       title, notes, scheduled_for, completed_date, outcome, snapshot_content,
       snapshot_hash, achievements_json, created_date)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    ['v-$programId', 'v-$programId', userId, programId, blockId, runId,
     kReviewKindClose, 'Close', null, null, now, kOutcomeClosed, '{}',
     'hash', null, now],
  );

  await db.execute(
    '''
    INSERT INTO fact_goal
      (id, goal_id, program_run_id, user_id, goal_text, custom_exercise_id,
       program_id, block_id, custom_variation_id, target_weight, target_reps,
       goal_created_date)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    ['g-$programId', 'g-$programId', runId, userId, 'Squat 100', null,
     programId, blockId, null, null, null, now],
  );

  // Scoped to this program's block but with NO program_id. The server forbids
  // this shape (fact_goal_block_scope_check: block_id implies program_id), but
  // it is inserted here on purpose — this DB declares no constraints, and
  // createGoal writes the two scope columns independently, so the delete has to
  // cope with a row the server would reject.
  await db.execute(
    '''
    INSERT INTO fact_goal
      (id, goal_id, program_run_id, user_id, goal_text, custom_exercise_id,
       program_id, block_id, custom_variation_id, target_weight, target_reps,
       goal_created_date)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    ['gb-$programId', 'gb-$programId', null, userId, 'Block-only goal', null,
     null, blockId, null, null, null, now],
  );

  final linkId = 'l-$programId';
  await db.execute(
    '''
    INSERT INTO dim_planned_session_program
      (id, planned_session_program_id, program_id, planned_session_id, user_id,
       sequence_order, day_of_week, week_offset, block_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [linkId, linkId, programId, 'ps-$programId', userId, 1, null, null,
     blockId],
  );
}

Future<int> _count(
  PowerSyncDatabase db,
  String table,
  String column,
  String value,
) async {
  final rows = await db.getAll(
    'SELECT COUNT(*) c FROM $table WHERE $column = ?',
    [value],
  );
  final v = rows.first['c'];
  return v is int ? v : int.tryParse('$v') ?? 0;
}

Future<int> _countAll(PowerSyncDatabase db, String table) async {
  final rows = await db.getAll('SELECT COUNT(*) c FROM $table');
  final v = rows.first['c'];
  return v is int ? v : int.tryParse('$v') ?? 0;
}
