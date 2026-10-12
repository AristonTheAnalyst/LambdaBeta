import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/core/utils/block_length.dart';
import 'package:lambda/data/models/program_history.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/program_history_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:lambda/data/repositories/program_run_repository.dart';
import 'package:powersync/powersync.dart';

/// A run follows a BLOCK, not the program.
///
/// The claim under test is that this is one change, not a parallel code path:
/// a block run is an ordinary run whose link list is narrowed, so the cursor,
/// the completion count and the week number all become block-relative without
/// any of them knowing about blocks. Everything else about a run — start, end,
/// one-current, the frozen record at close — is untouched.
///
///   flutter test integration_test/program_block_run_repo_test.dart -d DEVICE
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';
  const programId = 'p1';
  const blockId = 'b1';

  late Directory dir;
  late PowerSyncDatabase db;
  late PlannedSessionRepository planned;
  late ProgramRunRepository runs;
  late ProgramHistoryRepository history;

  /// Workout name → its generated session id. Names are for readability in the
  /// assertions; every id in the database is a uuid.
  final ids = <String, String>{};

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    planned = PlannedSessionRepository();
    runs = ProgramRunRepository();
    history = ProgramHistoryRepository();
    await _insertProgram(db, userId, programId);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  /// Two workouts in block 1, one in block 2, one unassigned — every case a
  /// block scope has to answer for.
  ///
  /// Block 1 declares no length and no dates unless a test asks for them: most
  /// of these tests are about the cursor, and a length would only be noise. The
  /// two lifecycle tests do ask, because a block's length is the whole subject
  /// there.
  Future<void> seed({
    int? blockWeeks,
    int? blockDays,
    int? blockSessions,
    DateTime? blockStart,
  }) async {
    await _insertBlock(
      db,
      userId,
      programId,
      blockId,
      'Accumulation',
      1,
      targetWeeks: blockWeeks,
      targetDays: blockDays,
      targetSessions: blockSessions,
      startDate: blockStart,
    );
    await _insertBlock(db, userId, programId, 'b2', 'Peak', 2);

    for (final (name, block, order) in [
      ('w1', blockId, 1),
      ('w2', null, 2), // in the program, in no block
      ('w3', blockId, 3),
      ('w4', 'b2', 4),
    ]) {
      final session = await planned.createPlannedSession(userId, name: name);
      ids[name] = session.sessionId;
      final link = await planned.createProgramLink(
        userId,
        programId: programId,
        plannedSessionId: session.sessionId,
        sequenceOrder: order,
      );
      if (block != null) {
        await planned.assignLinksToBlock(
          programId,
          [link.plannedSessionProgramId],
          block,
        );
      }
    }
  }

  test('a block run walks only its own block', () async {
    await seed();
    await _insertRun(db, userId, programId, runId: 'r1', blockId: blockId);

    final run = (await runs.getCurrentRun(userId))!;
    expect(run.blockId, blockId,
        reason: 'the run carries the block it is following');

    final program = (await ProgramRepository().fetchProgram(programId))!;
    final next = await runs.getNextPlannedSession(program: program, run: run);
    expect(next!.sessionId, ids['w1'],
        reason: 'the first link IN THE BLOCK, not the first in the program');

    // The cursor counts sessions logged against the RUN, so completing one
    // advances inside the block and stops at its end — w2 and w4 are never
    // reached, whichever order the program's links are in.
    await _insertSession(db, userId, runId: 'r1');
    final second = await runs.getNextPlannedSession(program: program, run: run);
    expect(second!.sessionId, ids['w3']);

    await _insertSession(db, userId, runId: 'r1');
    final third = await runs.getNextPlannedSession(program: program, run: run);
    expect(third!.sessionId, ids['w1'],
        reason: 'past the last link in the block the cycle wraps inside it');
  });

  test('a blockless run still walks the whole program', () async {
    await seed();
    await _insertRun(db, userId, programId, runId: 'r1');

    final run = (await runs.getCurrentRun(userId))!;
    expect(run.blockId, isNull);

    final program = (await ProgramRepository().fetchProgram(programId))!;
    final next = await runs.getNextPlannedSession(program: program, run: run);
    expect(next!.sessionId, ids['w1']);

    // w2 is the link the block run above steps over. Reaching it here is the
    // whole contrast: the block filter is a no-op for a blockless run, which
    // is what keeps every existing run behaving exactly as it always did.
    await _insertSession(db, userId, runId: 'r1');
    final second = await runs.getNextPlannedSession(program: program, run: run);
    expect(second!.sessionId, ids['w2']);
  });

  test('a block run measures itself against the block', () async {
    await seed();
    await _insertRun(
      db,
      userId,
      programId,
      runId: 'r1',
      blockId: blockId,
      progressionMode: 'order',
    );

    final progress = (await runs.getProgress(userId))!;
    expect(progress.isBlockRun, isTrue);
    expect(progress.block!.name, 'Accumulation');
    expect(progress.blockNumber, 1);
    expect(progress.totalBlocks, 2, reason: 'both blocks are active');
    expect(progress.blockLabel, 'Block 1 of 2 · Accumulation');
    expect(progress.totalWorkoutsInCycle, 2,
        reason: 'the cycle is the block, not the program — w2 and w4 are not '
            'part of what this run is working through');
    expect(progress.nextPlannedSession!.sessionId, ids['w1']);

    // The program-wide count is unchanged so a blockless caller — and the
    // session screen's kicker — reads exactly what it always did.
    final blockless = await planned.fetchPlannedSessions(
      userId,
      programId: programId,
    );
    expect(blockless.length, 4);
  });

  test('closing a block run freezes its record as a block end', () async {
    await seed();
    await _insertRun(
      db,
      userId,
      programId,
      runId: 'r1',
      blockId: blockId,
      progressionMode: 'order',
    );

    final achievements = '{"goals":[],"prs":[],"sessions":1}';
    final close = await history.closeRun(
      userId: userId,
      programId: programId,
      runId: 'r1',
      blockId: blockId,
      achievementsJson: achievements,
    );

    // `blockId` is the whole distinction — it used to be a `reason` string
    // kept in step with it, which could only ever disagree.
    expect(close.blockId, blockId,
        reason: 'a block ending is not the program ending');
    expect(close.programRunId, 'r1');

    // The record is written, not merely returned — a close whose review went
    // missing is the failure the shared transaction exists to prevent.
    final rows = await db.getAll(
      'SELECT review_id, kind, outcome, block_id, program_run_id, '
      'achievements_json, completed_date FROM fact_program_review '
      'WHERE program_id = ?',
      [programId],
    );
    expect(rows.length, 1);
    expect(rows.single['kind'], kReviewKindClose);
    expect(rows.single['outcome'], kOutcomeClosed);
    expect(rows.single['block_id'], blockId);
    expect(rows.single['program_run_id'], 'r1');
    expect(rows.single['achievements_json'], achievements,
        reason: 'the frozen record is what the panel showed — derived once, '
            'stored once, so the two can never disagree');
    expect(rows.single['completed_date'], isNotNull);

    // Its snapshot is a whole-program document even though the review is
    // scoped to the block — that is what keeps one document format and one
    // diff engine, and what lets a block's snapshot be compared against the
    // program-level one that follows it.
    expect(close.snapshot, isNotNull);
    expect(close.snapshot!.sessionCount, 4,
        reason: 'block_id is scope, not a filter on the document');
    expect(close.snapshotHash, isNotNull);
    expect(close.sessionId, isNull,
        reason: 'a close is a block-or-program review, never a workout one');
  });

  test('a block whose weeks have run out asks, and is not ended by a read',
      () async {
    // The real shape of a finished block run: the block declares eight weeks
    // and the run started nine weeks ago. Nothing writes an end date anywhere
    // — `endsAt` derives it from the run's ACTUAL start, which is what makes a
    // late start push the end out rather than eat into the phase.
    await seed(blockWeeks: 8);
    await _insertRun(
      db,
      userId,
      programId,
      runId: 'r1',
      blockId: blockId,
      progressionMode: 'frequency',
      startedDate: DateTime.now().subtract(const Duration(days: 63)),
    );

    final first = await runs.getProgress(userId);
    expect(first!.isLengthReached, isTrue, reason: 'eight weeks have elapsed');
    expect(first.endsAt, isNotNull,
        reason: 'derived from the block, with no end date on the row');
    expect(first.run.endDate, isNull,
        reason: 'the run row carries no length of its own');

    await runs.getProgress(userId);
    final rows = await db.getAll(
      'SELECT is_current, ended_date FROM fact_program_run '
      'WHERE program_run_id = ?',
      ['r1'],
    );
    expect(rows.single['is_current'], 1,
        reason: 'a read that mutates is the bug this asserts against — and a '
            'block run is a run, so it gets the same guarantee');
    expect(rows.single['ended_date'], isNull);

    // The prompt names the block, not the program: a finished phase and a
    // finished program are different things to be told. "Length reached", not
    // "finished" — carrying on is one of the answers the prompt offers.
    final due = await ProgramHistoryRepository().fetchDueItems(userId);
    final finished = due.where((d) => d.kind == kDueRunFinished).toList();
    expect(finished, hasLength(1));
    expect(finished.single.blockId, blockId);
    expect(finished.single.blockName, 'Accumulation');
    expect(finished.single.label, 'Block length reached');
  });

  test('a length of weeks and days runs out on its own day, not on the week',
      () async {
    // Eight weeks and three days is 59 days, and those three days are the whole
    // subject. At day 58 this phase is still running; at 59 it is over. Read as
    // whole weeks — which is all the schema could say before — the length would
    // be 56 days, and the block would ask to be ended three days before its own
    // last day.
    final today = DateTime.now().toUtc();
    final midnight = DateTime.utc(today.year, today.month, today.day);
    final start = midnight.subtract(const Duration(days: 58));

    await seed(blockWeeks: 8, blockDays: 3);
    await _insertRun(
      db,
      userId,
      programId,
      runId: 'r1',
      blockId: blockId,
      progressionMode: 'frequency',
      startedDate: start,
    );

    final running = (await runs.getProgress(userId))!;
    expect(
      running.endsAt!.difference(running.run.startedDate).inDays,
      59,
      reason: 'endsAt projects the whole length from the run\'s own start: '
          '7 × 8 + 3. A remainder is not decoration on the week count',
    );
    expect(running.endsAt, endDateFor(start, 8, 3));
    expect(running.isLengthReached, isFalse,
        reason: 'day 58 of 59. Whole weeks would have finished this block two '
            'days ago, which is the reporting bug the column exists to fix');

    // The same run, one day older, is over — and nothing but the clock moved.
    // Rewriting `started_date` rather than inserting a second run is deliberate:
    // `is_current` is unique per user, and the point here is the boundary, not
    // a second run.
    await db.execute(
      'UPDATE fact_program_run SET started_date = ? WHERE program_run_id = ?',
      [midnight.subtract(const Duration(days: 59)).toIso8601String(), 'r1'],
    );

    final over = (await runs.getProgress(userId))!;
    expect(over.isLengthReached, isTrue,
        reason: 'the last day is day 59 — not 56, and not 60');
    expect(
      (await ProgramHistoryRepository().fetchDueItems(userId))
          .where((d) => d.kind == kDueRunFinished)
          .single
          .blockName,
      'Accumulation',
      reason: 'and the prompt is the same one a week-length block gets, named '
          'the same way — a remainder changes the day, not the lifecycle',
    );
  });

  test('a block that has not started yet asks to begin', () async {
    // The other end of the same lifecycle. No run at all, and a block whose
    // planned start has arrived. The other block in the program has no start
    // date, so it stays quiet — which is the assertion that this is about the
    // block, not about the program having blocks.
    await seed(
      blockWeeks: 8,
      blockStart: DateTime.now().subtract(const Duration(days: 2)),
    );

    final due = await ProgramHistoryRepository().fetchDueItems(userId);
    final starts = due.where((d) => d.kind == kDueBlockStart).toList();
    expect(starts, hasLength(1));
    expect(starts.single.programId, programId);
    expect(starts.single.blockId, blockId);
    expect(starts.single.blockName, 'Accumulation');
    expect(starts.single.prompt, 'Accumulation is ready to begin.');
  });
}

Future<void> _insertProgram(
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
    [programId, programId, userId, 'Test Program', null, null, now, now],
  );
}

/// `ProgramRepository.createProgramBlock` writes to Supabase REST first, so the
/// row is fixture data here — the read paths under test are all local.
Future<void> _insertBlock(
  PowerSyncDatabase db,
  String userId,
  String programId,
  String blockId,
  String name,
  int order, {
  int? targetWeeks,
  int? targetDays,
  int? targetSessions,
  DateTime? startDate,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    '''
    INSERT INTO dim_program_block
      (id, block_id, user_id, program_id, name, notes, block_order,
       target_weeks, target_days, target_sessions, start_date, end_date,
       date_archived, created_date, updated_date)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [blockId, blockId, userId, programId, name, null, order, targetWeeks,
     targetDays, targetSessions, startDate?.toUtc().toIso8601String(), null,
     null, now, now],
  );
}

Future<void> _insertRun(
  PowerSyncDatabase db,
  String userId,
  String programId, {
  required String runId,
  String? blockId,
  String? progressionMode,
  DateTime? endDate,
  DateTime? startedDate,
}) async {
  await db.execute(
    '''
    INSERT INTO fact_program_run
      (id, program_run_id, program_id, user_id, target_sessions, target_weeks,
       end_date, started_date, ended_date, is_current, progression_mode,
       block_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      runId,
      runId,
      programId,
      userId,
      null,
      null,
      endDate?.toUtc().toIso8601String(),
      (startedDate ?? DateTime.now()).toUtc().toIso8601String(),
      null,
      1,
      progressionMode,
      blockId,
    ],
  );
}

/// A completed session attributed to the run — what the order cursor counts.
Future<void> _insertSession(
  PowerSyncDatabase db,
  String userId, {
  required String runId,
}) async {
  final id = 's-${DateTime.now().microsecondsSinceEpoch}';
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    '''
    INSERT INTO fact_session
      (id, session_id, user_id, created_datetime, end_datetime, program_run_id)
    VALUES (?, ?, ?, ?, ?, ?)
    ''',
    [id, id, userId, now, now, runId],
  );
}
