import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:powersync/powersync.dart';

/// On-device test of copy-on-add against a REAL PowerSync SQLite DB. Run with:
///
///   flutter test integration_test/program_copy_repo_test.dart -d DEVICE
///
/// Host `flutter test` cannot load `libpowersync.dylib`, so this cannot be a
/// `test/` unit test — and it would be a weak one anyway, since the whole
/// feature is a SQL-level guarantee about which rows exist where.
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
    ps.setDatabaseForTesting(db);
    planned = PlannedSessionRepository();
    programs = ProgramRepository();
    await _insertProgram(db, userId, programId);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('importing a library workout makes an independent copy that points home',
      () async {
    final library = await _libraryWorkout(planned, userId, 'Bench Day');

    final copyId = await programs.importWorkoutIntoProgram(
      userId,
      programId: programId,
      sourceSessionId: library.sessionId,
    );
    final copy = await planned.fetchPlannedSessionById(copyId);

    expect(copy, isNotNull);
    expect(copy!.baseSessionId, library.sessionId,
        reason: 'lineage names the ORIGINAL, so push-back has somewhere to go');
    expect(copy.isCopy, isTrue);
    expect(copy.name, 'Bench Day',
        reason: 'importing is the normal path — no "(Copy)" suffix noise');

    // Content came across whole: one group, one target set, values intact.
    final copyGroups = await planned.fetchPlannedExercises(copyId);
    final copySets = await planned.fetchPlannedSets(copyId);
    expect(copyGroups.single.exerciseId, 'ex-bench');
    expect(copySets.single.targetWeight, '70');
    expect(copySets.single.plannedSetId, isNot(library.setId),
        reason: 'the target row is a copy, not the same row re-pointed');

    // The library lists the original and NOT the copy — a workout in a program
    // is not a library workout, however it got there.
    final libraryList = await planned.fetchPlannedSessions(userId);
    expect(libraryList.map((s) => s.sessionId), contains(library.sessionId));
    expect(libraryList.map((s) => s.sessionId), isNot(contains(copyId)));

    final programList = await programs.fetchPlannedSessions(programId);
    expect(programList.map((s) => s.sessionId), [copyId]);

    // Import is a structural change to the program.
    final row = await db.getAll(
      'SELECT program_updated_date FROM dim_program WHERE program_id = ?',
      [programId],
    );
    expect(row.single['program_updated_date'], isNotNull);
  });

  test('editing the copy leaves the original byte-identical', () async {
    final library = await _libraryWorkout(planned, userId, 'Bench Day');
    final copyId = await programs.importWorkoutIntoProgram(
      userId,
      programId: programId,
      sourceSessionId: library.sessionId,
    );

    // Retarget, rename, and drop the group: everything a user would do to the
    // workout now that it lives in their program.
    final copySets = await planned.fetchPlannedSets(copyId);
    await planned.updatePlannedSet(copySets.single.plannedSetId,
        targetWeight: '150');
    await planned.updatePlannedSession(copyId, name: 'Heavy Bench');
    await planned.deletePlannedExercise(
        (await planned.fetchPlannedExercises(copyId)).single.plannedExerciseId);

    // The original is untouched in every particular.
    final source = await planned.fetchPlannedSessionById(library.sessionId);
    expect(source!.name, 'Bench Day');
    expect(source.baseSessionId, isNull,
        reason: 'the original is the origin, not a copy of its own copy');
    final sourceGroups = await planned.fetchPlannedExercises(library.sessionId);
    final sourceSets = await planned.fetchPlannedSets(library.sessionId);
    expect(sourceGroups.single.plannedExerciseId, library.groupId);
    expect(sourceSets.single.targetWeight, '70',
        reason: 'the library is a SOURCE — this is the whole point');

    // And the original is still a library workout.
    expect(
      (await planned.fetchPlannedSessions(userId)).map((s) => s.sessionId),
      contains(library.sessionId),
    );
  });

  test('pushing back updates the library original, not a second copy',
      () async {
    final library = await _libraryWorkout(planned, userId, 'Bench Day');
    final copyId = await programs.importWorkoutIntoProgram(
      userId,
      programId: programId,
      sourceSessionId: library.sessionId,
    );

    final copySets = await planned.fetchPlannedSets(copyId);
    await planned.updatePlannedSet(copySets.single.plannedSetId,
        targetWeight: '150');
    await planned.updatePlannedSession(copyId, name: 'Heavy Bench');

    await programs.pushWorkoutToLibrary(userId, copyId);

    // The original took the copy's contents AND its name — the point of
    // pushing back is that the library now reads like the workout the user
    // actually improved.
    final base = await planned.fetchPlannedSessionById(library.sessionId);
    expect(base!.name, 'Heavy Bench');
    final baseSets = await planned.fetchPlannedSets(library.sessionId);
    expect(baseSets.single.targetWeight, '150');

    // Overwritten, not appended: the replaced rows are archived, so exactly one
    // live target remains.
    expect(baseSets.length, 1);
    expect(
      (await planned.fetchPlannedSessions(userId)).length,
      1,
      reason: 'no second library workout was minted',
    );

    // The copy still points at the same base — pushing twice is idempotent.
    expect((await planned.fetchPlannedSessionById(copyId))!.baseSessionId,
        library.sessionId);
  });

  test('pushing back a program-authored workout creates the original once',
      () async {
    // A workout authored inside the program: it has no base, because it did
    // not come from the library.
    final authored = await planned.createPlannedSession(userId, name: 'Authored');
    await planned.createProgramLink(
      userId,
      programId: programId,
      plannedSessionId: authored.sessionId,
      sequenceOrder: 1,
    );
    final group = await planned.createPlannedExercise(
      userId,
      authored.sessionId,
      exerciseId: 'ex-row',
      exerciseOrder: 1,
    );
    await planned.createPlannedSet(
      userId,
      group.plannedExerciseId,
      plannedSessionId: authored.sessionId,
      setNumber: 1,
      targetWeight: '60',
      targetReps: '10',
    );
    expect((await planned.fetchPlannedSessionById(authored.sessionId))!.isCopy,
        isFalse);

    await programs.pushWorkoutToLibrary(userId, authored.sessionId);

    // A library original now exists with the workout's contents, and the
    // program workout is linked to it.
    final libraryList = await planned.fetchPlannedSessions(userId);
    final created = libraryList.singleWhere((s) => s.name == 'Authored');
    expect(created.baseSessionId, isNull);
    expect((await planned.fetchPlannedSets(created.sessionId)).single.targetWeight,
        '60');
    expect((await planned.fetchPlannedSessionById(authored.sessionId))!.baseSessionId,
        created.sessionId,
        reason: 'the link is what makes a SECOND push an update');
    expect(libraryList.length, 1);

    // Push again after improving it: still one library workout.
    final sets = await planned.fetchPlannedSets(authored.sessionId);
    await planned.updatePlannedSet(sets.single.plannedSetId,
        targetWeight: '80');
    await programs.pushWorkoutToLibrary(userId, authored.sessionId);

    expect((await planned.fetchPlannedSessions(userId)).length, 1);
    expect((await planned.fetchPlannedSets(created.sessionId)).single.targetWeight,
        '80');
  });

  test('a library workout is not a thing you can push to the library',
      () async {
    final library = await _libraryWorkout(planned, userId, 'Bench Day');
    await expectLater(
      programs.pushWorkoutToLibrary(userId, library.sessionId),
      throwsA(isA<StateError>()),
      reason: 'the library is the destination, not the source',
    );
  });

  test('duplicating a program inherits lineage rather than inventing it',
      () async {
    final library = await _libraryWorkout(planned, userId, 'Bench Day');
    final copyId = await programs.importWorkoutIntoProgram(
      userId,
      programId: programId,
      sourceSessionId: library.sessionId,
    );

    final secondProgramId = await programs.duplicateProgram(userId, programId);

    final copied = (await programs.fetchPlannedSessions(secondProgramId)).single;
    expect(copied.name, 'Bench Day');
    expect(copied.sessionId, isNot(copyId), reason: 'a fresh copy, fresh ids');
    expect(copied.baseSessionId, library.sessionId,
        reason: 'a copy of a copy is still a copy of the SAME library workout '
            '— pointing at the first copy would make the other program the '
            'original, and pushing back would overwrite a workout in a '
            'program the user was not even looking at');
  });
}

/// One exercise group with one target set, plus the ids the assertions need.
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
