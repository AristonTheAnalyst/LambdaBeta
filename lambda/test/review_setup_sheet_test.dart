import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/programs/view/review_setup_sheet.dart';
import 'package:lambda/features/programs/viewmodel/program_history_viewmodel.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';

/// What the review set-up wizard asks, and how it is answered.
///
/// The sheet is two steps — which workouts, then what to call the pass — and
/// the risks this file guards are the things that made scope a problem before:
/// the two steps collapsing back into one, a row that *navigates* instead of
/// ticking (one tap should never open a ceremony), and a preselected set (the
/// run's length-reached prompt) the user could not edit. The set itself is
/// load-bearing — it is the whole scope — so the sheet must hand it back in
/// the order the picker listed it, not in the order the rows were ticked.
void main() {
  const pushA = WorkoutOption(
    sessionId: 's1',
    label: 'Push A',
    blockId: 'b1',
    blockName: 'Accumulation',
    exerciseCount: 4,
  );
  const pushB = WorkoutOption(
    sessionId: 's2',
    label: 'Push B',
    blockId: 'b1',
    blockName: 'Accumulation',
    exerciseCount: 3,
  );
  const pull = WorkoutOption(
    sessionId: 's3',
    label: 'Pull',
    blockId: 'b2',
    blockName: 'Intensification',
    exerciseCount: 5,
  );
  const lonesome = WorkoutOption(
    sessionId: 's9',
    label: 'Full Body',
    exerciseCount: 6,
  );

  /// What the sheet popped, once it pops.
  ReviewSetupRequest? result;

  Future<void> pumpSheet(
    WidgetTester tester, {
    List<WorkoutOption> workouts = const [pushA],
    List<String> preselectedIds = const [],
  }) async {
    result = null;
    tester.view.physicalSize = const Size(1206, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showReviewSetupSheet(
                    context,
                    workouts: workouts,
                    preselectedIds: preselectedIds,
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

  /// Taps a workout row — a tick, not a navigation.
  Future<void> tick(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).hitTestable().first);
    await tester.pumpAndSettle();
  }

  Future<void> typeName(WidgetTester tester, String text) async {
    await tester.enterText(
      find
          .descendant(
            of: find.byType(LambdaInput),
            matching: find.byType(TextField),
          )
          .first,
      text,
    );
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.text('Start review').hitTestable().first);
    await tester.pumpAndSettle();
  }

  testWidgets('the wizard opens on the workout question alone — the name is a '
      'step away, not a field on the same screen', (tester) async {
    await pumpSheet(tester);

    expect(find.text('Start a review'), findsOneWidget);
    expect(find.text('STEP 1 OF 2'), findsOneWidget);
    expect(find.text('Which workouts'), findsOneWidget);

    // Step 1 asks exactly one thing. The name input, the submit action and
    // the way back all belong to the step that has the set in hand.
    expect(find.text('Push A'), findsOneWidget);
    expect(find.byType(LambdaInput), findsNothing);
    expect(find.text('Start review'), findsNothing);
    expect(find.text('STEP 2 OF 2'), findsNothing);
  });

  testWidgets('rows tick instead of navigating, and the confirm counts what '
      'is ticked — nothing is submitted by touching a row', (tester) async {
    await pumpSheet(tester, workouts: const [pushA, pushB]);

    // Nothing ticked: the confirm is offered as a count and does nothing.
    expect(find.text('Review 0 workouts'), findsOneWidget);
    await tester.tap(
      find.text('Review 0 workouts').hitTestable().first,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('STEP 1 OF 2'),
      findsOneWidget,
      reason: 'an empty set is not a review — the wizard must not advance',
    );

    await tick(tester, 'Push A');
    expect(find.text('Review 1 workout'), findsOneWidget);
    await tick(tester, 'Push B');
    expect(find.text('Review 2 workouts'), findsOneWidget);

    // A second tap on a ticked row drops it back out.
    await tick(tester, 'Push B');
    expect(find.text('Review 1 workout'), findsOneWidget);
  });

  testWidgets('confirming moves to the name step, which says what is being '
      'named', (tester) async {
    await pumpSheet(tester);
    await tick(tester, 'Push A');
    await confirm(tester, 'Review 1 workout');

    expect(find.text('STEP 2 OF 2'), findsOneWidget);
    expect(find.text('Reviewing Push A'), findsOneWidget);

    // The workout list is behind us — the step is about the name.
    expect(find.text('Which workouts'), findsNothing);
  });

  testWidgets('a set of several is named by its count, not by its first '
      'workout', (tester) async {
    await pumpSheet(tester, workouts: const [pushA, pushB]);
    await tick(tester, 'Push A');
    await tick(tester, 'Push B');
    await confirm(tester, 'Review 2 workouts');

    expect(find.text('Reviewing 2 workouts'), findsOneWidget);
  });

  testWidgets('the review starts unnamed when the name is skipped — naming '
      'is a convenience, not a condition', (tester) async {
    await pumpSheet(tester);
    await tick(tester, 'Push A');
    await confirm(tester, 'Review 1 workout');
    await start(tester);

    expect(result, isNotNull);
    expect(result!.sessionIds, ['s1']);
    expect(result!.title, isNull);
  });

  testWidgets('a name comes back trimmed, and a blank one is no name at all', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tick(tester, 'Push A');
    await confirm(tester, 'Review 1 workout');
    await typeName(tester, '  End of block 1  ');
    await start(tester);
    expect(result!.title, 'End of block 1');

    await pumpSheet(tester);
    await tick(tester, 'Push A');
    await confirm(tester, 'Review 1 workout');
    await typeName(tester, '   ');
    await start(tester);
    expect(
      result!.title,
      isNull,
      reason: 'spaces are not a name, and the row must not carry them',
    );
  });

  testWidgets('Back returns to the workout question with the ticks intact — '
      'stepping back must not throw the set away', (tester) async {
    await pumpSheet(tester, workouts: const [pushA, pushB]);
    await tick(tester, 'Push A');
    await tick(tester, 'Push B');
    await confirm(tester, 'Review 2 workouts');
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('STEP 1 OF 2'), findsOneWidget);
    expect(find.text('Which workouts'), findsOneWidget);
    expect(
      find.text('Review 2 workouts'),
      findsOneWidget,
      reason: 'coming back to re-read the list is not dropping the choices',
    );
    expect(result, isNull);
  });

  testWidgets('workouts are grouped under their block, in the program\'s own '
      'order', (tester) async {
    await pumpSheet(tester, workouts: const [pushA, pushB, pull]);

    expect(find.text('ACCUMULATION'), findsOneWidget);
    expect(find.text('INTENSIFICATION'), findsOneWidget);
    expect(find.text('Push A'), findsOneWidget);
    expect(find.text('Pull'), findsOneWidget);
  });

  testWidgets('a blockless program is one ungrouped list — the workout name is '
      'not repeated as its own heading', (tester) async {
    await pumpSheet(tester, workouts: const [lonesome]);

    expect(find.text('FULL BODY'), findsNothing);
    expect(find.text('Full Body'), findsOneWidget);
  });

  testWidgets('a preselected set arrives ticked and stays editable — the run '
      'prompt starts the list, it does not fix it', (tester) async {
    await pumpSheet(
      tester,
      workouts: const [pushA, pushB, pull],
      preselectedIds: const ['s1', 's3'],
    );

    expect(
      find.text('Review 2 workouts'),
      findsOneWidget,
      reason: 'the preselection counts before anything is touched',
    );

    // Dropping a preselected workout is one tap, same as adding one.
    await tick(tester, 'Pull');
    expect(find.text('Review 1 workout'), findsOneWidget);
  });

  testWidgets('the set comes back in the picker\'s order, not tick order — '
      'the review reads like the program afterwards', (tester) async {
    await pumpSheet(
      tester,
      workouts: const [pushA, pushB, pull],
      preselectedIds: const ['s3', 's1'],
    );
    await confirm(tester, 'Review 2 workouts');
    await start(tester);

    expect(result!.sessionIds, ['s1', 's3']);
  });

  testWidgets('a program with nothing in it says why, and offers no confirm — '
      'a review of nothing is not offered', (tester) async {
    await pumpSheet(tester, workouts: const []);

    expect(find.text('Nothing to review yet'), findsOneWidget);
    expect(find.text('Which workouts'), findsNothing);
    expect(find.text('Review 0 workouts'), findsNothing);
  });
}
