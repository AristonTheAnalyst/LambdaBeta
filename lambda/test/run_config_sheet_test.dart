import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program_block.dart';
import 'package:lambda/data/models/program_run.dart';
import 'package:lambda/features/programs/view/run_config_sheet.dart';

/// What the begin/edit sheet asks, per shape.
///
/// The sheet is the one place a run's shape is acted on, so it is the place the
/// shape rule has to be impossible to get wrong: a simple program is asked for
/// a session count and nothing else, a blocked one is told which block it is
/// about to follow (never offered a choice — blocks are a sequence), and a
/// blocked one with no blocks cannot be begun at all. The three cases come
/// apart on `uses_blocks`, never on whether a block list happens to be empty.
ProgramBlock testBlock({
  String blockId = 'b1',
  String name = 'Accumulation',
  int? targetWeeks,
  int? targetDays,
  int? targetSessions,
}) =>
    ProgramBlock(
      blockId: blockId,
      userId: 'u1',
      programId: 'p1',
      name: name,
      blockOrder: 1,
      targetWeeks: targetWeeks,
      targetDays: targetDays,
      targetSessions: targetSessions,
    );

ProgramRun testRun({
  String programRunId = 'r1',
  String? blockId,
  int? targetSessions,
}) =>
    ProgramRun(
      programRunId: programRunId,
      programId: 'p1',
      userId: 'u1',
      startedDate: DateTime(2026, 2, 1),
      isCurrent: true,
      blockId: blockId,
      targetSessions: targetSessions,
    );

void main() {
  late RunConfigRequest? result;

  Future<void> openSheet(
    WidgetTester tester, {
    String programName = 'Base',
    ProgramBlock? block,
    bool usesBlocks = false,
    int? defaultTargetSessions,
    ProgramRun? run,
  }) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showRunConfigSheet(
                    context,
                    programName: programName,
                    block: block,
                    usesBlocks: usesBlocks,
                    defaultTargetSessions: defaultTargetSessions,
                    run: run,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapBegin(WidgetTester tester) async {
    await tester.tap(find.text('Begin'));
    await tester.pumpAndSettle();
  }

  group('a blocked program names the block rather than offering a picker', () {
    testWidgets('the block and its length are shown, and no count is asked',
        (tester) async {
      await openSheet(
        tester,
        usesBlocks: true,
        block: testBlock(targetWeeks: 8, targetDays: 3),
      );

      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Accumulation'), findsOneWidget);
      expect(find.text('8 weeks 3 days, as set on the block.'), findsOneWidget);
      expect(
        find.text('Number of sessions'),
        findsNothing,
        reason: 'the block owns the length — a count field here would be '
            'overruled the moment the run was read back',
      );
    });

    testWidgets('confirming returns the block and no session count',
        (tester) async {
      await openSheet(tester, usesBlocks: true, block: testBlock());
      await tapBegin(tester);

      expect(result, isNotNull);
      expect(result!.blockId, 'b1');
      expect(
        result!.targetSessions,
        isNull,
        reason: 'a block run carries no length of its own',
      );
    });

    testWidgets('an open-ended block says so instead of no length',
        (tester) async {
      await openSheet(tester, usesBlocks: true, block: testBlock());
      expect(
        find.text('Open-ended — end it by hand when the phase is done.'),
        findsOneWidget,
      );
    });

    testWidgets('with no blocks there is nothing to begin and nothing to type',
        (tester) async {
      await openSheet(tester, usesBlocks: true);

      expect(
        find.textContaining('Add a block to run this program'),
        findsOneWidget,
      );
      expect(find.text('Number of sessions'), findsNothing);

      await tapBegin(tester);
      expect(
        result,
        isNull,
        reason: 'the sheet stays open — a blocked program with no block has '
            'nothing to walk, so there is no run to configure',
      );
    });

    testWidgets('the Confirm button cannot be pressed with no block',
        (tester) async {
      await openSheet(tester, usesBlocks: true);
      // Tapping a disabled GlassButton is a no-op; the request staying null is
      // what "cannot be pressed" means here.
      await tapBegin(tester);
      expect(result, isNull);
      expect(find.text('Begin'), findsOneWidget,
          reason: 'the sheet is still up, not dismissed');
    });
  });

  group('a simple program is asked for a count and never about blocks', () {
    testWidgets('no Run section, and the count field is prefilled',
        (tester) async {
      await openSheet(tester, defaultTargetSessions: 12);

      expect(find.text('Number of sessions'), findsOneWidget);
      expect(find.text('Run'), findsNothing);
      expect(find.text('Duration'), findsNothing);
      expect(find.widgetWithText(TextField, '12'), findsOneWidget);
    });

    testWidgets('confirming returns the count and no block', (tester) async {
      await openSheet(tester, defaultTargetSessions: 12);
      await tapBegin(tester);

      expect(result, isNotNull);
      expect(result!.targetSessions, 12);
      expect(result!.blockId, isNull);
    });

    testWidgets('an empty count is not submittable', (tester) async {
      await openSheet(tester);
      await tapBegin(tester);
      expect(result, isNull);
    });

    testWidgets('a typed count is what comes back', (tester) async {
      await openSheet(tester);
      await tester.enterText(find.byType(TextField), '6');
      await tester.pumpAndSettle();
      await tapBegin(tester);
      expect(result!.targetSessions, 6);
    });
  });

  group('editing a run', () {
    testWidgets('a block run says the length is the block\'s and cannot be '
        'repointed', (tester) async {
      await openSheet(tester, usesBlocks: true, run: testRun(blockId: 'b1'));

      expect(
        find.text('Set by the block this run follows.'),
        findsOneWidget,
        reason: 'the run is under way — naming its own block is honest, and '
            'offering a different one would silently change what it counts',
      );
      expect(find.text('Run'), findsNothing);
      expect(find.text('Number of sessions'), findsNothing);
      expect(find.text('Save'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result!.blockId, 'b1');
      expect(result!.targetSessions, isNull);
    });

    testWidgets('a simple run opens on its own count, and Save waits for a '
        'change', (tester) async {
      await openSheet(tester, run: testRun(targetSessions: 8));
      expect(find.widgetWithText(TextField, '8'), findsOneWidget);

      // Unchanged: Save would write nothing, so it must not look pressable.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result, isNull);

      await tester.enterText(find.byType(TextField), '10');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result!.targetSessions, 10);
    });

    testWidgets('an old whole-program run of a blocked program is still '
        'editable', (tester) async {
      // A run begun before blocks were the only way in: it has no block, and
      // it still has to be fixable rather than being forced onto one.
      await openSheet(tester, usesBlocks: true, run: testRun(targetSessions: 5));

      expect(find.text('Number of sessions'), findsOneWidget);
      expect(find.text('Run'), findsNothing);
      expect(find.text('Duration'), findsNothing);
    });
  });

  testWidgets('cancel returns nothing', (tester) async {
    await openSheet(tester, defaultTargetSessions: 12);
    // Dismiss by tapping the barrier.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
