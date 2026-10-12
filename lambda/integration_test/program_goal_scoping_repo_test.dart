import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lambda/core/powersync/database.dart' as ps;
import 'package:lambda/core/powersync/schema.dart';
import 'package:lambda/data/models/goal.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:lambda/features/programs/model/achievements_derivation.dart';
import 'package:powersync/powersync.dart';

/// On-device test of goal COLUMNS against the REAL schema and the REAL repos:
/// `program_id` / `block_id` / `custom_variation_id` on `fact_goal` and the
/// query that reads them, `goal_description` and the write that carries it,
/// and the union [AchievementsDerivation] composes from them.
///
///   flutter test integration_test/program_goal_scoping_repo_test.dart -d DEVICE
///
/// The host suite (`test/program_achievements_test.dart`) already pins
/// `Goal.appliesDuring` as a pure predicate. What it cannot pin is that the
/// predicate is fed the right rows: that `fetchGoals(programId:)` returns both
/// levels, that a block filter narrows to one, and that the columns survive a
/// real INSERT via the client schema declared in `schema.dart`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'u1';
  const programId = 'p1';
  const otherProgramId = 'p2';
  const blockA = 'b1';
  const blockB = 'b2';

  late Directory dir;
  late PowerSyncDatabase db;
  late ProgramRepository programs;
  late AchievementsDerivation derivation;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lambda_ps');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/test.db');
    await db.initialize();
    ps.swapDatabase(db);
    programs = ProgramRepository();
    derivation = AchievementsDerivation();
    await _insertProgram(db, userId, programId, 'Scoped');
    await _insertProgram(db, userId, otherProgramId, 'Other');
    await _insertBlock(db, userId, programId, blockA, 'Accumulation', 1);
    await _insertBlock(db, userId, programId, blockB, 'Peak', 2);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  /// A goal row written through the real repo, so every column the scoping
  /// depends on goes through the real INSERT and the real client schema.
  ///
  /// [program] is required and nullable rather than defaulting: null is a real
  /// scope here (a standalone goal), so a default could not be told apart from
  /// "the caller did not say".
  Future<Goal> addGoal(
    String id, {
    required String? program,
    String? blockId,
    String? exerciseId,
    String? variationId,
    num? weight,
    int? reps,
    String? text,
    String? description,
  }) async {
    final goal = Goal(
      goalId: id,
      userId: userId,
      programId: program,
      blockId: blockId,
      text: text,
      description: description,
      exerciseId: exerciseId,
      variationId: variationId,
      targetWeight: weight,
      targetReps: reps,
    );
    await programs.createGoal(userId, goal);
    return goal;
  }

  test('a program query returns both levels, and reads them back intact',
      () async {
    await addGoal('g-program',
        program: programId, blockId: null, exerciseId: 'bench', weight: 100);
    await addGoal(
      'g-block',
      program: programId,
      blockId: blockA,
      exerciseId: 'squat',
      variationId: 'paused',
      weight: 140,
      reps: 1,
    );

    final all = await programs.fetchGoals(userId, programId: programId);

    expect(all.map((g) => g.goalId).toSet(), {'g-program', 'g-block'},
        reason: 'the program query is the union — filtering to one scope is '
            'the caller\'s job, because "what is in force" is a union');

    final block = all.firstWhere((g) => g.goalId == 'g-block');
    expect(block.blockId, blockA,
        reason: 'block_id must survive the round trip through the client '
            'schema — a column missing from schema.dart writes to nowhere');
    expect(block.variationId, 'paused',
        reason: 'the variation narrows what counts as evidence');
    expect(block.targetWeight, 140);
    expect(block.targetReps, 1);

    final program = all.firstWhere((g) => g.goalId == 'g-program');
    expect(program.blockId, isNull);
    expect(program.variationId, isNull);
  });

  test('a block query narrows to that block, not to its program', () async {
    await addGoal('g-program',
        program: programId, blockId: null, exerciseId: 'bench', weight: 100);
    await addGoal('g-a',
        program: programId, blockId: blockA, exerciseId: 'squat', weight: 140);
    await addGoal('g-b',
        program: programId, blockId: blockB, exerciseId: 'deadlift', weight: 180);

    final a = await programs.fetchGoals(
      userId,
      programId: programId,
      blockId: blockA,
    );
    expect(a.map((g) => g.goalId).toList(), ['g-a'],
        reason: 'blockId is a filter only when paired with programId — here it '
            'narrows to the one block, excluding the program-level goal');

    expect(
      (await programs.fetchGoals(userId, programId: programId)).length,
      3,
      reason: 'the unfiltered read still sees all three',
    );
  });

  test('a goal of another program never leaks in', () async {
    await addGoal('g-mine',
        program: programId, blockId: null, exerciseId: 'bench', weight: 100);
    await addGoal(
      'g-theirs',
      program: otherProgramId,
      blockId: null,
      exerciseId: 'bench',
      weight: 100,
    );

    final mine = await programs.fetchGoals(userId, programId: programId);

    expect(mine.map((g) => g.goalId).toList(), ['g-mine'],
        reason: 'both programs have a bench goal; the scope is what separates '
            'them, and a query that forgot program_id would return both');
  });

  test('a scope-less goal is standalone, not a program goal', () async {
    await addGoal('g-free', program: null, blockId: null, text: 'get stronger');
    await addGoal('g-mine',
        program: programId, blockId: null, exerciseId: 'bench', weight: 100);

    final standalone = await programs.fetchGoals(userId);
    expect(standalone.map((g) => g.goalId).toList(), ['g-free'],
        reason: 'with no scope named, the query asks for goals with no scope '
            'rather than for everything the user owns');

    expect(
      (await programs.fetchGoals(userId, programId: programId))
          .map((g) => g.goalId)
          .toList(),
      ['g-mine'],
    );
  });

  test('a goal\'s notes round-trip, and blank reads as no notes at all',
      () async {
    await addGoal(
      'g-noted',
      program: null,
      exerciseId: 'bench',
      weight: 100,
      description: 'Beltless, pause on the chest',
    );

    final read = (await programs.fetchGoals(userId)).single;
    expect(read.description, 'Beltless, pause on the chest',
        reason: 'goal_description has to survive the round trip through the '
            'client schema — a column missing from schema.dart writes nowhere, '
            'and the sheet would read back empty every time');
    expect(
      (await programs.fetchGoalOptionsByIds(['g-noted']))
          .single
          .goal
          .description,
      'Beltless, pause on the chest',
      reason: 'the review ceremony reads goals by id, and its sheet edits the '
          'same notes',
    );

    await programs.updateGoalDescription('g-noted', '  Hips slow off the floor ');
    expect(
      (await programs.fetchGoals(userId)).single.description,
      'Hips slow off the floor',
      reason: 'the update is local-only — PowerSync uploads it — and trims',
    );

    await programs.updateGoalDescription('g-noted', '   ');
    expect((await programs.fetchGoals(userId)).single.description, isNull,
        reason: 'blank is one spelling of "no notes", never an empty string');
  });

  test('the derivation reports the goals in force for a block run', () async {
    await addGoal('g-program',
        program: programId, blockId: null, exerciseId: 'bench', weight: 100);
    await addGoal('g-a',
        program: programId, blockId: blockA, exerciseId: 'squat', weight: 140);

    // A blockless read: only the program-level goal is being chased.
    final blockless = await derivation.derive(
      userId: userId,
      from: DateTime(2000),
      programId: programId,
    );
    expect(blockless.goals.map((g) => g.goal.goalId).toList(), ['g-program'],
        reason: 'a blockless run is not running b1, so its goals are not in '
            'force — the behaviour of every program before blocks existed');

    // Inside block A: the union.
    final inA = await derivation.derive(
      userId: userId,
      from: DateTime(2000),
      programId: programId,
      blockId: blockA,
    );
    expect(
      inA.goals.map((g) => g.goal.goalId).toSet(),
      {'g-program', 'g-a'},
      reason: 'a program-level target is chased inside every one of its '
          'blocks — a union with the block\'s own, never a filter',
    );

    // Inside block B: A's goal drops out, the program's stays.
    final inB = await derivation.derive(
      userId: userId,
      from: DateTime(2000),
      programId: programId,
      blockId: blockB,
    );
    expect(inB.goals.map((g) => g.goal.goalId).toList(), ['g-program']);
  });
}

Future<void> _insertProgram(
  PowerSyncDatabase db,
  String userId,
  String programId,
  String name,
) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    '''
    INSERT INTO dim_program
      (id, program_id, user_id, program_name, program_description,
       date_archived, program_created_date, program_updated_date)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [programId, programId, userId, name, null, null, now, now],
  );
}

/// Written directly for the same reason every other fixture here is:
/// `createProgramBlock` is REST-first (the block must exist server-side before
/// a run or an assignment can reference it), and what is under test is the
/// local read path.
Future<void> _insertBlock(
  PowerSyncDatabase db,
  String userId,
  String programId,
  String blockId,
  String name,
  int order,
) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    '''
    INSERT INTO dim_program_block
      (id, block_id, user_id, program_id, name, notes, block_order,
       target_weeks, target_sessions, start_date, end_date, date_archived,
       created_date, updated_date)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [blockId, blockId, userId, programId, name, null, order, null, null, null,
     null, null, now, now],
  );
}
