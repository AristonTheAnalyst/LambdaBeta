import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/core/utils/block_length.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:powersync/powersync.dart';

/// On-device test of blocks against a REAL PowerSync SQLite DB. Run with:
///
///   flutter test integration_test/program_block_repo_test.dart -d DEVICE
///
/// Host `flutter test` cannot load `libpowersync.dylib`, so this cannot be a
/// `test/` unit test. The subject is a set of SQL-level guarantees — which join
/// rows point at which block, and whether a duplicated block's workouts are
/// fresh rows — so a fake would assert nothing worth knowing.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';
  const programId = 'p1';

  late Directory dir;
  late PowerSyncDatabase db;
  late PlannedSessionRepository planned;
  late ProgramRepository programs;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    planned = PlannedSessionRepository();
    programs = ProgramRepository();
    await _insertProgram(db, userId, programId);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('a block holds exactly the workouts assigned to it', () async {
    final blockA = await _insertBlock(db, userId, programId, 'Accumulation', 1);
    final blockB = await _insertBlock(db, userId, programId, 'Intensification', 2);

    final one = await _imported(programs, planned, userId, 'Squat Day');
    final two = await _imported(programs, planned, userId, 'Bench Day');
    final three = await _imported(programs, planned, userId, 'Deadlift Day');

    // Membership is written on the join rows, in one statement for the batch.
    final links = await planned.fetchProgramLinks(programId);
    final byName = {
      for (final l in links) l.plannedSessionId: l.plannedSessionProgramId,
    };
    await planned.assignLinksToBlock(
      programId,
      [byName[one]!, byName[two]!],
      blockA,
    );
    await planned.assignLinksToBlock(programId, [byName[three]!], blockB);

    final aLinks = await planned.fetchProgramLinks(programId, blockId: blockA);
    expect(aLinks.length, 2);
    expect(aLinks.every((l) => l.blockId == blockA), isTrue);
    final aSessions =
        await planned.fetchPlannedSessions(userId, programId: programId, blockId: blockA);
    expect(aSessions.map((s) => s.name), containsAll(['Squat Day', 'Bench Day']));
    expect(aSessions.map((s) => s.name), isNot(contains('Deadlift Day')));

    final bLinks = await planned.fetchProgramLinks(programId, blockId: blockB);
    expect(bLinks.length, 1);
    expect(bLinks.single.plannedSessionId, three);

    // No blockId means UNFILTERED — the whole program, for the ungrouped pass.
    final all = await planned.fetchProgramLinks(programId);
    expect(all.length, 3);
    expect(all.where((l) => l.blockId == null), isEmpty,
        reason: 'every workout was assigned, so nothing is left ungrouped');
  });

  test('reordering blocks never touches a workout\'s order', () async {
    final a = await _insertBlock(db, userId, programId, 'A', 1);
    final b = await _insertBlock(db, userId, programId, 'B', 2);
    final c = await _insertBlock(db, userId, programId, 'C', 3);

    final workout = await _imported(programs, planned, userId, 'Squat Day');
    final before = (await planned.fetchProgramLinks(programId)).single;
    expect(before.sequenceOrder, isNotNull);

    await programs.reorderBlocks(programId, [c, a, b]);

    expect((await programs.fetchBlocks(programId)).map((x) => x.blockId), [c, a, b]);
    final after = (await planned.fetchProgramLinks(programId)).single;
    expect(after.sequenceOrder, before.sequenceOrder,
        reason: 'block_order is scoped to blocks; sequence_order stays '
            'program-global so reordering phases never renumbers training');
    expect(after.plannedSessionId, workout);
  });

  test('archiving a block returns its workouts to the program, undeleted',
      () async {
    final block = await _insertBlock(db, userId, programId, 'Accumulation', 1);
    final one = await _imported(programs, planned, userId, 'Squat Day');
    final two = await _imported(programs, planned, userId, 'Bench Day');
    final links = await planned.fetchProgramLinks(programId);
    await planned.assignLinksToBlock(
      programId,
      links.map((l) => l.plannedSessionProgramId).toList(),
      block,
    );

    await programs.archiveBlock(block);

    expect(await programs.fetchBlocks(programId), isEmpty);
    final archived = await programs.fetchArchivedBlocks(programId);
    expect(archived.single.blockId, block);
    expect(archived.single.isArchived, isTrue);

    // A block is a grouping, not a container: removing the phase must not
    // remove the training.
    final stillThere = await planned.fetchPlannedSessions(userId, programId: programId);
    expect(stillThere.map((s) => s.sessionId), containsAll([one, two]));
    final unassigned = await planned.fetchProgramLinks(programId);
    expect(unassigned.length, 2);
    expect(unassigned.every((l) => l.blockId == null), isTrue,
        reason: 'membership is cleared, so they render in the ungrouped pass');

    // Restoring the block does NOT restore what it held — the membership was
    // cleared on archive and cannot be reconstructed.
    await programs.reactivateBlock(block);
    expect((await programs.fetchBlocks(programId)).single.blockId, block);
    expect(
      (await planned.fetchProgramLinks(programId)).every((l) => l.blockId == null),
      isTrue,
    );
  });

  test('a block has one length, and only a weeks block has an end', () async {
    final block = await _insertBlock(db, userId, programId, 'Accumulation', 1);
    final start = DateTime.utc(2026, 10, 1);
    final end = DateTime.utc(2026, 11, 12);

    await programs.updateBlock(
      block,
      name: 'Accumulation I',
      notes: 'High volume',
      targetWeeks: 6,
      startDate: start,
      endDate: end,
    );
    var row = (await programs.fetchBlock(block))!;
    expect(row.name, 'Accumulation I');
    expect(row.notes, 'High volume');
    expect(row.targetWeeks, 6);
    expect(row.startDate, start);
    expect(row.endDate, end);

    // A nullable parameter cannot say "leave alone" and "set to null" at once,
    // which is what the clear flags are for.
    await programs.updateBlock(block, targetWeeks: 8);
    row = (await programs.fetchBlock(block))!;
    expect(row.targetWeeks, 8);
    expect(row.notes, 'High volume');
    expect(row.endDate, end,
        reason: 'the end is the caller\'s projection to send — a length write '
            'does not invent dates of its own');

    // Switching unit drops the other one AND the calendar end. Sessions mode
    // has no end date, and a block claiming two lengths has two answers to
    // "is this phase over?".
    await programs.updateBlock(block, targetSessions: 24);
    row = (await programs.fetchBlock(block))!;
    expect(row.targetSessions, 24);
    expect(row.targetWeeks, isNull);
    expect(row.endDate, isNull);

    // And it does not come back: a length survives only as the unit it is
    // written in. `dim_program_block_length_check` is the server-side backstop
    // for the same rule; this is the app-side half, and it has to hold on its
    // own because the local PowerSync schema declares columns, not constraints.
    await programs.updateBlock(block, targetWeeks: 6, endDate: end);
    row = (await programs.fetchBlock(block))!;
    expect(row.targetWeeks, 6);
    expect(row.targetSessions, isNull);
    expect(row.endDate, end);

    await programs.updateBlock(
      block,
      clearNotes: true,
      clearWeeks: true,
      clearSessions: true,
      clearStartDate: true,
      clearEndDate: true,
    );
    row = (await programs.fetchBlock(block))!;
    expect(row.notes, isNull);
    expect(row.targetWeeks, isNull);
    expect(row.targetSessions, isNull);
    expect(row.startDate, isNull);
    expect(row.endDate, isNull);
    expect(row.name, 'Accumulation I', reason: 'clearing targets is not a rename');
  });

  test('a weeks length carries a days remainder, exactly', () async {
    final block = await _insertBlock(db, userId, programId, 'Accumulation', 1);
    final start = DateTime.utc(2026, 10, 1);
    const eightWeeksThreeDays = 59;

    // `8 weeks 3 days` is ONE length of 59 days, and the end the editor sends is
    // that projection — not the 56 days the weeks alone would give. This is the
    // whole point of the column: a phase that ends on a Wednesday stores a
    // Wednesday.
    await programs.updateBlock(
      block,
      targetWeeks: 8,
      targetDays: 3,
      startDate: start,
      endDate: endDateFor(start, 8, 3),
    );
    var row = (await programs.fetchBlock(block))!;
    expect(row.targetWeeks, 8);
    expect(row.targetDays, 3);
    expect(row.endDate, DateTime.utc(2026, 11, 29));
    expect(
      row.endDate!.difference(start).inDays,
      eightWeeksThreeDays,
      reason: 'the projection is 7 × weeks + days, not 7 × weeks',
    );

    // And it round-trips: reading the length back off the projection returns the
    // same pair. That is what makes the editor's two date fields exact inverses
    // — pick an end and the length is computed, not rounded.
    expect(
      lengthBetween(startDate: row.startDate, endDate: row.endDate),
      (weeks: 8, days: 3),
    );

    // A sub-week block. `target_weeks = 0` was unwritable while the column's own
    // CHECK required it to be positive; the rule moved to the total, so three
    // days is now a length and "no weeks" is spelled by the remaining nulls.
    await programs.updateBlock(block, targetWeeks: 0, targetDays: 3);
    row = (await programs.fetchBlock(block))!;
    expect(row.targetWeeks, 0);
    expect(row.targetDays, 3);

    // A zero remainder is absent, not a second unit — the same null-means-absent
    // rule the rest of the schema follows.
    await programs.updateBlock(block, clearTargetDays: true);
    row = (await programs.fetchBlock(block))!;
    expect(row.targetDays, isNull);
    expect(row.targetWeeks, 0, reason: 'clearing the remainder is not the weeks');

    // The remainder belongs to the weeks length, so it goes wherever that goes:
    // nothing reads `target_days` without weeks to remain from, which is why the
    // server has a CHECK for it and why the repo settles it here instead.
    await programs.updateBlock(block, targetWeeks: 6, targetDays: 2);
    await programs.updateBlock(block, targetSessions: 24);
    row = (await programs.fetchBlock(block))!;
    expect(row.targetSessions, 24);
    expect(row.targetWeeks, isNull);
    expect(row.targetDays, isNull,
        reason: 'the remainder is part of the weeks length, not of the block');

    await programs.updateBlock(block, targetWeeks: 6, targetDays: 2);
    await programs.updateBlock(block, clearWeeks: true);
    row = (await programs.fetchBlock(block))!;
    expect(row.targetWeeks, isNull);
    expect(row.targetDays, isNull,
        reason: 'clearing the weeks takes the remainder with it — a remainder '
            'with no weeks to remain from is a value nothing can read');
  });

  test('duplicating a block makes fresh copies of its workouts', () async {
    final library = await _libraryWorkout(planned, userId, 'Squat Day');
    final copyId = await programs.importWorkoutIntoProgram(
      userId,
      programId: programId,
      sourceSessionId: library.sessionId,
    );
    final block = await _insertBlock(
      db,
      userId,
      programId,
      'Accumulation',
      1,
      targetWeeks: 8,
      targetDays: 3,
    );
    final link = (await planned.fetchProgramLinks(programId)).single;
    await planned.assignLinksToBlock(
      programId,
      [link.plannedSessionProgramId],
      block,
    );

    final newBlockId = await programs.duplicateBlock(userId, block);

    final blocks = await programs.fetchBlocks(programId);
    expect(blocks.length, 2);
    final copy = blocks.singleWhere((b) => b.blockId == newBlockId);
    expect(copy.name, 'Accumulation (Copy)');
    expect(copy.blockOrder, 2, reason: 'appended, never inserted over the original');
    // Both halves of the length, because `duplicateBlock` names its INSERT
    // columns by hand — the one place a new column goes missing in silence.
    expect(copy.targetWeeks, 8);
    expect(copy.targetDays, 3);

    final copyLinks =
        await planned.fetchProgramLinks(programId, blockId: newBlockId);
    expect(copyLinks.length, 1);
    final copiedSessionId = copyLinks.single.plannedSessionId;
    expect(copiedSessionId, isNot(copyId),
        reason: 'a duplicated block is a new phase — a fresh workout, not a '
            'second link to the same one');

    final copied = (await planned.fetchPlannedSessionById(copiedSessionId))!;
    expect(copied.name, 'Squat Day');
    expect(copied.baseSessionId, library.sessionId,
        reason: 'lineage points at the LIBRARY original, not at the block\'s '
            'first copy — push-back must still have one destination');

    // Content came across whole, as new rows.
    final originalGroups = await planned.fetchPlannedExercises(copyId);
    final copyGroups = await planned.fetchPlannedExercises(copiedSessionId);
    expect(copyGroups.single.exerciseId, originalGroups.single.exerciseId);
    expect(copyGroups.single.plannedExerciseId,
        isNot(originalGroups.single.plannedExerciseId));

    final originalSets = await planned.fetchPlannedSets(copyId);
    final copySets = await planned.fetchPlannedSets(copiedSessionId);
    expect(copySets.single.targetWeight, '70');
    expect(copySets.single.plannedSetId, isNot(originalSets.single.plannedSetId));

    // Editing one leaves the other byte-identical — the whole point.
    await planned.updatePlannedSet(copySets.single.plannedSetId, targetWeight: '90');
    expect(
      (await planned.fetchPlannedSets(copyId)).single.targetWeight,
      '70',
      reason: 'the source block\'s workout is untouched by its copy\'s edit',
    );
    expect(
      (await planned.fetchPlannedSets(copiedSessionId)).single.targetWeight,
      '90',
    );
  });

  test('duplicating a program copies its blocks and remaps membership',
      () async {
    final library = await _libraryWorkout(planned, userId, 'Squat Day');
    final sessionId = await programs.importWorkoutIntoProgram(
      userId,
      programId: programId,
      sourceSessionId: library.sessionId,
    );
    final block = await _insertBlock(
      db,
      userId,
      programId,
      'Accumulation',
      1,
      targetWeeks: 8,
      targetDays: 3,
    );
    final link = (await planned.fetchProgramLinks(programId)).single;
    await planned.assignLinksToBlock(
      programId,
      [link.plannedSessionProgramId],
      block,
    );

    final newProgramId = await programs.duplicateProgram(userId, programId);

    final newBlocks = await programs.fetchBlocks(newProgramId);
    expect(newBlocks.length, 1);
    expect(newBlocks.single.name, 'Accumulation');
    expect(newBlocks.single.targetWeeks, 8);
    expect(newBlocks.single.targetDays, 3,
        reason: 'the copy carries the whole length. `duplicateProgram` writes '
            'its block INSERT columns by hand, so a column left out of that '
            'list is dropped here with nothing to notice it');
    expect(newBlocks.single.blockId, isNot(block),
        reason: 'the copy\'s block is its own row, or two programs would '
            'share a phase and editing one would change both');

    final newLinks = await planned.fetchProgramLinks(newProgramId);
    expect(newLinks.length, 1);
    expect(newLinks.single.blockId, newBlocks.single.blockId,
        reason: 'membership is remapped to the copied block, not carried over '
            'as the original\'s id — which would point across programs and be '
            'rejected by the composite FK');
    expect(newLinks.single.plannedSessionId, isNot(sessionId));

    // The source program is untouched.
    expect((await programs.fetchBlocks(programId)).single.blockId, block);
    expect(
      (await planned.fetchProgramLinks(programId)).single.blockId,
      block,
    );
  });

  test('archiving a program archives its blocks and frees its workouts',
      () async {
    final library = await _libraryWorkout(planned, userId, 'Squat Day');
    final sessionId = await programs.importWorkoutIntoProgram(
      userId,
      programId: programId,
      sourceSessionId: library.sessionId,
    );
    final block = await _insertBlock(db, userId, programId, 'Accumulation', 1);
    final link = (await planned.fetchProgramLinks(programId)).single;
    await planned.assignLinksToBlock(
      programId,
      [link.plannedSessionProgramId],
      block,
    );

    await programs.deleteProgram(programId);

    expect(await programs.fetchBlocks(programId), isEmpty);
    expect((await programs.fetchArchivedBlocks(programId)).single.blockId, block,
        reason: 'blocks are archived, not deleted — the revision and run '
            'history references them');

    // The link rows are gone, so the workouts are standalone again.
    final standalone = await planned.fetchPlannedSessions(userId);
    expect(standalone.map((s) => s.sessionId), contains(sessionId));
  });

  test('a block only accepts workouts of its own program', () async {
    // The composite (program_id, block_id) FK is a server-side guarantee: the
    // local PowerSync schema declares columns, not constraints. Asserted here
    // as the reasoning the REST-first create depends on — the block must exist
    // server-side before an assignment uploads.
    await _insertProgram(db, userId, 'p2');
    final otherBlock = await _insertBlock(db, userId, 'p2', 'Other', 1);
    final library = await _libraryWorkout(planned, userId, 'Squat Day');
    final sessionId = await programs.importWorkoutIntoProgram(
      userId,
      programId: programId,
      sourceSessionId: library.sessionId,
    );

    final link = (await planned.fetchProgramLinks(programId)).single;
    // Locally this UPDATE is unconstrained, so the interesting assertion is
    // that the join row carries the program it belongs to — the pair the
    // server checks.
    await planned.assignLinksToBlock(
      programId,
      [link.plannedSessionProgramId],
      otherBlock,
    );
    final row = await db.getAll(
      'SELECT program_id, block_id FROM dim_planned_session_program '
      'WHERE planned_session_id = ?',
      [sessionId],
    );
    expect(row.single['program_id'], programId);
    expect(row.single['block_id'], otherBlock);
  });
}

class _LibraryWorkout {
  const _LibraryWorkout({
    required this.sessionId,
    required this.groupId,
    required this.setId,
  });

  final String sessionId;
  final String groupId;
  final String setId;
}

/// Imports a library workout into the program and returns the new session id.
Future<String> _imported(
  ProgramRepository programs,
  PlannedSessionRepository planned,
  String userId,
  String name,
) async {
  final library = await _libraryWorkout(planned, userId, name);
  return programs.importWorkoutIntoProgram(
    userId,
    programId: 'p1',
    sourceSessionId: library.sessionId,
  );
}

/// A standalone library workout: 1 group (Bench) with 1 target set (70 × 5).
Future<_LibraryWorkout> _libraryWorkout(
  PlannedSessionRepository planned,
  String userId,
  String name,
) async {
  final session = await planned.createPlannedSession(userId, name: name);
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
  return _LibraryWorkout(
    sessionId: session.sessionId,
    groupId: group.plannedExerciseId,
    setId: set.plannedSetId,
  );
}

/// The `dim_program` row itself. `ProgramRepository.createProgram` writes
/// straight to Supabase so the program exists server-side before anything
/// references it; here the row is plain fixture data and the local insert is
/// the shortest path to it.
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

/// A `dim_program_block` row, for the same reason as [_insertProgram]:
/// `createProgramBlock` is REST-first, so the fixture is the local insert.
///
/// The length is optional because most tests are about membership, order or
/// archiving and care nothing about it. Where it is given, both halves are: a
/// remainder with no weeks to remain from is a row the server rejects.
Future<String> _insertBlock(
  PowerSyncDatabase db,
  String userId,
  String programId,
  String name,
  int order, {
  int? targetWeeks,
  int? targetDays,
}) async {
  final id = 'b-$programId-$order';
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    '''
    INSERT INTO dim_program_block
      (id, block_id, user_id, program_id, name, notes, block_order,
       target_weeks, target_days, target_sessions, start_date, end_date,
       date_archived, created_date, updated_date)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [id, id, userId, programId, name, null, order, targetWeeks, targetDays,
     null, null, null, null, now, now],
  );
  return id;
}
