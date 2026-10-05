import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:powersync/powersync.dart';

/// On-device test of the REAL program repository against a REAL PowerSync
/// SQLite DB — the exact local write path the app executes. Run with:
///
///   flutter test integration_test/program_repo_test.dart -d DEVICE
///
/// The network half is a fake: `createProgram` and `createProgramBlock` write
/// to Supabase REST first, and the integration harness has no signed-in
/// session. That is what [ProgramRemote] is for — the fake records what would
/// have been sent, so both halves of a create are assertable: the row the
/// server is given, and the row the device can read.
///
/// The bug this file exists for (smoke, 2026-10-03): a newly created block
/// showed nothing until the app was left and re-entered. Both creates are
/// REST-first and wrote no local row, while every read in the UI is local — so
/// the editor's own reload-on-pop read back a table that had never been told
/// the row existed, and the optimistic append in the view model was overwritten
/// by that reload.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';
  const programId = 'p1';

  late Directory dir;
  late PowerSyncDatabase db;
  late _FakeRemote remote;
  late ProgramRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.setDatabaseForTesting(db);
    remote = _FakeRemote();
    repo = ProgramRepository(remote: remote);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('a created block is readable locally before anything syncs', () async {
    final block = await repo.createProgramBlock(
      userId,
      programId: programId,
      name: 'Hypertrophy',
      targetSessions: 8,
    );

    expect(remote.blocks.single['block_id'], block.blockId,
        reason: 'the payload and the returned block must name the same row — '
            'the mirror is an upsert onto the server\'s row, not a second row '
            'beside it');

    final blocks = await repo.fetchBlocks(programId);
    expect(blocks, hasLength(1),
        reason: 'the reported bug, in one assertion: fetchBlocks reads the '
            'LOCAL table, so without the mirror the block was missing until a '
            'download landed — and the screen that just created it reloads '
            'through exactly this call');
    expect(blocks.single.blockId, block.blockId);
    expect(blocks.single.name, 'Hypertrophy');
    expect(blocks.single.targetSessions, 8);
  });

  test('a second block appends after the mirrored first', () async {
    final first = await repo.createProgramBlock(userId, programId: programId);
    final second = await repo.createProgramBlock(userId, programId: programId);

    expect(first.blockOrder, 1);
    expect(second.blockOrder, 2,
        reason: 'order is read back as MAX(block_order) from the local table, '
            'so an unmirrored first block makes the second claim order 1 too — '
            'two blocks that both render first, persistently');
    expect(
      (await repo.fetchBlocks(programId)).map((b) => b.name),
      ['Block 1', 'Block 2'],
      reason: 'auto-names bump against the same local list — without the '
          'mirror the second block is proposed as "Block 1" again',
    );
  });

  test('a created program is readable locally before anything syncs', () async {
    final program = await repo.createProgram(userId, name: 'Base');

    expect(remote.programs.single['program_id'], program.programId);

    final programs = await repo.fetchPrograms(userId);
    expect(programs.map((p) => p.programId), contains(program.programId),
        reason: 'the library reads locally, so the wizard\'s new program has '
            'to be in this list the moment the wizard hands back');
    expect((await repo.fetchProgram(program.programId))!.name, 'Base');
  });

  test('auto-generated names bump against the mirrored rows', () async {
    await repo.createProgram(userId);
    final second = await repo.createProgram(userId);

    expect(second.name, 'New Program 2',
        reason: 'the bump reads the local mirror — without it every unnamed '
            'program is proposed as "New Program" and the library fills with '
            'identically-named rows');
  });

  test('a remote that refuses the insert fails the create and writes nothing',
      () async {
    remote.failInsert = true;

    await expectLater(
      repo.createProgramBlock(userId, programId: programId),
      throwsA(isA<StateError>()),
    );
    expect(await repo.fetchBlocks(programId), isEmpty,
        reason: 'REST-first is the contract: a block the server refused must '
            'not exist here either — a local-only row would make the first '
            '"assign a workout" upload fail on a server that never saw it');
  });
}

/// Stands in for Supabase REST, recording what the repository would have sent.
class _FakeRemote implements ProgramRemote {
  final programs = <Map<String, dynamic>>[];
  final blocks = <Map<String, dynamic>>[];
  bool failInsert = false;

  @override
  Future<List<Map<String, dynamic>>> fetchPrograms(String userId) async => [];

  @override
  Future<Map<String, dynamic>?> fetchProgram(String programId) async => null;

  @override
  Future<void> insertProgram(Map<String, dynamic> row) async {
    if (failInsert) throw StateError('insert refused');
    programs.add(row);
  }

  @override
  Future<void> insertBlock(Map<String, dynamic> row) async {
    if (failInsert) throw StateError('insert refused');
    blocks.add(row);
  }
}
