import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/repositories/program_run_repository.dart';
import 'package:powersync/powersync.dart';

/// On-device test of the REAL run repository against a REAL PowerSync SQLite
/// DB — the exact local write path the app executes. Run with:
///
///   flutter test integration_test/program_run_repo_test.dart -d DEVICE
///
/// The network half is a fake: `startProgramRun` writes to Supabase REST first,
/// and the integration harness has no signed-in session. That is what
/// [ProgramRunRemote] is for — the fake records exactly what would have been
/// sent, so the assertions cover the *contract with the server* (the id, the
/// pause, the block) as well as the local mirror it leaves behind.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';
  const programId = 'p1';

  late Directory dir;
  late PowerSyncDatabase db;
  late _FakeRemote remote;
  late ProgramRunRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    remote = _FakeRemote();
    repo = ProgramRunRepository(remote: remote);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('a start is mirrored locally under the id the server was given',
      () async {
    final run = await repo.startProgramRun(userId, programId,
        targetSessions: 12, blockId: 'b1');

    expect(remote.inserted.single['program_run_id'], run.programRunId,
        reason: 'the payload and the returned run must name the same row — a '
            'divergence here is what made every later write address nothing');
    expect(remote.inserted.single['block_id'], 'b1');

    final rows = await db.getAll(
      'SELECT * FROM fact_program_run WHERE program_run_id = ?',
      [run.programRunId],
    );
    expect(rows, hasLength(1),
        reason: 'without the mirror the run is invisible until the next '
            'download — and a session logged in that window is attributed to '
            'no run at all');
    expect(rows.single['is_current'], 1);
    expect(rows.single['ended_date'], isNull);
    expect(rows.single['target_sessions'], 12);
    expect(rows.single['block_id'], 'b1');

    final current = await repo.getCurrentRun(userId);
    expect(current!.programRunId, run.programRunId);
  });

  test('starting a run pauses the replaced one, locally and on the server',
      () async {
    await _insertRun(db, userId, programId, runId: 'old-run');
    expect((await repo.getCurrentRun(userId))!.programRunId, 'old-run');

    await repo.startProgramRun(userId, programId, targetSessions: 4);

    final current = await db.getAll(
      'SELECT program_run_id FROM fact_program_run WHERE is_current = 1',
    );
    expect(current, hasLength(1),
        reason: 'the one-current rule is a unique index server-side — a '
            'second is_current row locally would upload as a violation');
    final old = await db.getAll(
      'SELECT is_current, ended_date FROM fact_program_run '
      'WHERE program_run_id = ?',
      ['old-run'],
    );
    // The Stage 1b rule, in the two columns themselves: stepped aside, not
    // finished. A stamped `ended_date` here would make the run history — it
    // could never be resumed, and the attempt would be over because someone
    // pressed Begin on something else.
    expect(old.single['is_current'], 0);
    expect(old.single['ended_date'], isNull,
        reason: 'paused runs are open runs: no end date is what makes a run '
            'resumable and what keeps it out of every "ended" read');
    expect(remote.paused.single, userId,
        reason: 'the server half must pause identically — a local-only pause '
            'would be overwritten by the next download, which still says the '
            'old run is current');
  });

  test('resuming a paused run leaves exactly one current row', () async {
    await _insertRun(db, userId, programId, runId: 'paused-run');
    await repo.pauseCurrentRun(userId);
    // A different program's run takes the slot in the meantime.
    await _insertRun(db, userId, 'p2', runId: 'live-run');

    await repo.resumeRun(userId, 'paused-run');

    final current = await db.getAll(
      'SELECT program_run_id FROM fact_program_run WHERE is_current = 1',
    );
    expect(current, hasLength(1),
        reason: 'the ordering is the whole transaction: the run holding the '
            'slot is stepped aside before this one steps up, or the server\'s '
            'one-current index refuses the upload');
    expect(current.single['program_run_id'], 'paused-run');

    final live = await db.getAll(
      'SELECT is_current, ended_date FROM fact_program_run '
      'WHERE program_run_id = ?',
      ['live-run'],
    );
    expect(live.single['is_current'], 0);
    expect(live.single['ended_date'], isNull,
        reason: 'the displaced run is paused, not ended — resuming one '
            'program must not destroy another');

    expect(await repo.fetchPausedRun(userId, programId: 'p2'), isNotNull,
        reason: 'the run that lost its place is what the card has to badge');
    expect(await repo.fetchPausedRun(userId, programId: programId), isNull,
        reason: 'the resumed run is current — it must not answer to a paused '
            'read as well');
  });

  test('a config edit lands on the mirrored row', () async {
    // The D1 symptom in one test: the edit filters by `program_run_id`, so an
    // id that matches no row is a silent no-op — the UI shows the new value
    // until the next reload, which reads the old one back.
    final run = await repo.startProgramRun(userId, programId, targetSessions: 6);

    await repo.updateRunConfig(run.programRunId, targetSessions: 9);

    final rows = await db.getAll(
      'SELECT target_sessions FROM fact_program_run WHERE program_run_id = ?',
      [run.programRunId],
    );
    expect(rows.single['target_sessions'], 9);
  });

  test('ending a run clears is_current and keeps the row', () async {
    final run = await repo.startProgramRun(userId, programId);

    await repo.endCurrentRun(userId);

    final rows = await db.getAll(
      'SELECT is_current, ended_date FROM fact_program_run '
      'WHERE program_run_id = ?',
      [run.programRunId],
    );
    expect(rows, hasLength(1), reason: 'ended runs are history, not deletions');
    expect(rows.single['is_current'], 0);
    expect(rows.single['ended_date'], isNotNull);
  });

  test('fetchRunById reads a mirrored run back', () async {
    final run = await repo.startProgramRun(userId, programId, blockId: 'b2');

    final fetched = await repo.fetchRunById(run.programRunId);

    expect(fetched!.programRunId, run.programRunId);
    expect(fetched.blockId, 'b2');
    expect(await repo.fetchRunById('nope'), isNull);
  });

  test('a remote that refuses the insert still fails the begin', () async {
    remote.failInsert = true;

    await expectLater(
      repo.startProgramRun(userId, programId),
      throwsA(isA<StateError>()),
    );
    final rows =
        await db.getAll('SELECT * FROM fact_program_run WHERE is_current = 1');
    expect(rows, isEmpty,
        reason: 'no run on the server means no run here either — a local-only '
            'row would look current while nothing knows about it');
  });
}

/// Stands in for Supabase REST, recording what the repository would have sent.
class _FakeRemote implements ProgramRunRemote {
  final inserted = <Map<String, dynamic>>[];
  final paused = <String>[];
  bool failInsert = false;
  Map<String, dynamic>? current;

  @override
  Future<Map<String, dynamic>?> fetchCurrentRun(String userId) async => current;

  @override
  Future<void> pauseCurrentRun(String userId) async {
    paused.add(userId);
    current = null;
  }

  @override
  Future<void> insertRun(Map<String, dynamic> row) async {
    if (failInsert) throw StateError('insert refused');
    inserted.add(row);
    current = row;
  }
}

Future<void> _insertRun(
  PowerSyncDatabase db,
  String userId,
  String programId, {
  required String runId,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    '''
    INSERT INTO fact_program_run
      (id, program_run_id, program_id, user_id, target_sessions, target_weeks,
       end_date, started_date, ended_date, is_current, progression_mode,
       block_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [runId, runId, programId, userId, null, null, null, now, null, 1, null, null],
  );
}
