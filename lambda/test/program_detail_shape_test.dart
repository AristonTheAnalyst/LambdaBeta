import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program.dart';
import 'package:lambda/data/models/program_block.dart';
import 'package:lambda/data/models/program_run.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/features/programs/view/program_detail_screen.dart';
import 'package:lambda/features/programs/viewmodel/program_detail_viewmodel.dart';

import 'support/fake_program_repos.dart';

/// Which faces a program has, and which block it can begin.
///
/// The shape rule, rendered: a simple program is a list of workouts and has no
/// Blocks tab; a blocked one is a sequence of phases and has no Workouts tab.
/// Both are read from `uses_blocks` and never from whether the block list
/// happens to be empty — a blocked program with no blocks yet is a real state,
/// and it is the one that has to say what it is waiting for.
///
/// The second half is the sequencing rule as the user meets it: exactly one
/// block is offered a Begin, and the block behind the one being run is told
/// why it has to wait.
Program testProgram({bool usesBlocks = false, int? defaultTargetSessions}) =>
    Program(
      programId: 'p1',
      userId: 'u1',
      name: 'Base',
      usesBlocks: usesBlocks,
      defaultTargetSessions: defaultTargetSessions,
      createdDate: DateTime(2026, 1, 1),
      updatedDate: DateTime(2026, 1, 1),
    );

ProgramBlock testBlock(String id, {String name = '', int order = 1}) =>
    ProgramBlock(
      blockId: id,
      userId: 'u1',
      programId: 'p1',
      name: name.isEmpty ? id : name,
      blockOrder: order,
      targetWeeks: 8,
    );

ProgramRun testRun({
  String id = 'r1',
  String? blockId,
  bool isCurrent = false,
  DateTime? endedDate,
}) =>
    ProgramRun(
      programRunId: id,
      programId: 'p1',
      userId: 'u1',
      startedDate: DateTime(2026, 2, 1),
      isCurrent: isCurrent,
      endedDate: endedDate,
      blockId: blockId,
    );

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required bool usesBlocks,
    List<ProgramBlock> blocks = const [],
    List<ProgramRun> runs = const [],
    bool isCurrent = false,
    ProgramRun? activeRun,
    ProgramRun? pausedRun,
    FakeProgramRunRepository? runRepo,
  }) async {
    final vm = ProgramDetailViewModel(
      lessonRepo: _FakeLessons(),
      // Null is fine for the tests that only look: nothing on a rendered row
      // reaches a repository. The one test that taps Begin must pass a fake,
      // or the write would go to the PowerSync database this host has not got.
      runRepo: runRepo,
      historyRepo: FakeProgramHistoryRepository(),
      achievementsDerivation: FakeAchievementsDerivation(),
      userId: 'u1',
    );
    vm.state.value = ProgramDetailState(
      program: testProgram(usesBlocks: usesBlocks),
      blocks: blocks,
      programRuns: runs,
      nameDraft: 'Base',
      isCurrent: isCurrent,
      activeRun: activeRun,
      pausedRun: pausedRun,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProgramDetailScreen(programId: 'p1', viewModel: vm),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the tabs are the shape', () {
    testWidgets('a simple program offers Workouts and Reviews — and no Blocks '
        'anywhere', (tester) async {
      await pumpScreen(tester, usesBlocks: false);

      expect(find.text('Workouts'), findsOneWidget);
      expect(find.text('Reviews'), findsOneWidget);
      expect(
        find.text('Blocks'),
        findsNothing,
        reason: 'a simple program has no phases, so the tab would be an empty '
            'room with an "add a block" button that makes it something else',
      );
    });

    testWidgets('a blocked program offers Blocks and Reviews — and no '
        'Workouts', (tester) async {
      await pumpScreen(tester, usesBlocks: true);

      expect(find.text('Blocks'), findsOneWidget);
      expect(find.text('Reviews'), findsOneWidget);
      expect(
        find.text('Workouts'),
        findsNothing,
        reason: 'a blocked program\'s workouts only exist inside its blocks — '
            'a second list of them would be a second ordering to disagree with',
      );
    });

    testWidgets('neither shape offers Goals — goals are not a program\'s', (
      tester,
    ) async {
      // Goals went standalone (2026-10-08) and live in the Library now: a goal
      // is a set to beat, in force everywhere the exercise is trained, so
      // filing it under one program was a scope nothing ever asked for.
      await pumpScreen(tester, usesBlocks: false);
      expect(find.text('Goals'), findsNothing);

      await pumpScreen(tester, usesBlocks: true);
      expect(find.text('Goals'), findsNothing);
    });

    testWidgets('a blocked program with no blocks still lands on Blocks',
        (tester) async {
      // Shape is `uses_blocks`, never the emptiness of the list: this is the
      // program that has to ask for its first block, so it opens where the
      // asking happens.
      await pumpScreen(tester, usesBlocks: true);

      expect(find.text('Blocks'), findsOneWidget);
      expect(find.textContaining('No blocks yet'), findsOneWidget);
      expect(find.text('Add a block to run this program.'), findsOneWidget);
    });

    testWidgets('a simple program is never told to add a block on the begin '
        'row', (tester) async {
      await pumpScreen(tester, usesBlocks: false);

      expect(find.text('Begin Program'), findsOneWidget);
      expect(find.text('Add a block to run this program.'), findsNothing);
    });
  });

  group('the block sequence decides which block can be begun', () {
    testWidgets('nothing run yet: the first block is the one offered Begin',
        (tester) async {
      await pumpScreen(
        tester,
        usesBlocks: true,
        blocks: [testBlock('b1', name: 'Accumulation'), testBlock('b2')],
      );

      expect(find.text('Begin'), findsOneWidget);
      // Exactly one: a second would mean a later phase is offering an act the
      // sequencing rule refuses.
      expect(
        find.text('Begin'),
        findsOneWidget,
        reason: 'only the block the sequence is on may be begun',
      );
      expect(find.textContaining('first.'), findsNothing);
    });

    testWidgets('the block after the one being run is told what it is waiting '
        'for', (tester) async {
      await pumpScreen(
        tester,
        usesBlocks: true,
        isCurrent: true,
        blocks: [testBlock('b1', name: 'Accumulation'), testBlock('b2')],
        runs: [testRun(blockId: 'b1', isCurrent: true)],
        activeRun: testRun(blockId: 'b1', isCurrent: true),
      );

      expect(find.text('End Accumulation first.'), findsOneWidget);
      expect(
        find.text('Begin'),
        findsNothing,
        reason: 'mid-phase the affordance is Resume (above), and beginning '
            'over it is Restart — neither is a second Begin button',
      );
    });

    testWidgets('a finished block moves the Begin to the next one',
        (tester) async {
      await pumpScreen(
        tester,
        usesBlocks: true,
        blocks: [testBlock('b1', name: 'Accumulation'), testBlock('b2')],
        runs: [testRun(blockId: 'b1', endedDate: DateTime(2026, 3, 1))],
      );

      expect(find.text('Begin'), findsOneWidget);
      // The row's own "End ... first" line is gone: block 1 is behind us.
      expect(find.textContaining('first.'), findsNothing);
    });

    testWidgets('a paused run holds the sequence where it was', (tester) async {
      await pumpScreen(
        tester,
        usesBlocks: true,
        blocks: [testBlock('b1', name: 'Accumulation'), testBlock('b2')],
        runs: [testRun(blockId: 'b1')],
        pausedRun: testRun(blockId: 'b1'),
      );

      expect(find.text('End Accumulation first.'), findsOneWidget);
      expect(find.text('Begin'), findsNothing);
    });

    testWidgets('the Begin it offers starts a run of that block',
        (tester) async {
      final runs = FakeProgramRunRepository();
      await pumpScreen(
        tester,
        usesBlocks: true,
        blocks: [
          testBlock('b1', name: 'Accumulation'),
          testBlock('b2', name: 'Intensification', order: 2),
        ],
        // Block 1 is behind us, so the sequence — and with it the Begin — has
        // moved to block 2. This is the only way to tell the two blocks apart
        // from the outside: without the run, block 1 would be the answer.
        runs: [testRun(blockId: 'b1', endedDate: DateTime(2026, 3, 1))],
        runRepo: runs,
      );

      // The row's Begin, the confirmation's Begin, then the sheet's: one word
      // for one act, asked three times.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Begin').last);
        await tester.pumpAndSettle();
      }

      expect(runs.starts, hasLength(1));
      expect(
        runs.starts.single.blockId,
        'b2',
        reason: 'the run records the block that was begun — a run begun from '
            'block 2 whose row says block 1 would scope its goals and its '
            'closing record to the wrong phase',
      );
      expect(runs.starts.single.targetSessions, isNull,
          reason: 'the block owns the length; a run of it carries no count of '
              'its own');
    });
  });
}

/// Only here because `LessonRepository`'s constructor evaluates the global
/// `ps.db` — the one repository that cannot be default-constructed off-device.
class _FakeLessons implements LessonRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
