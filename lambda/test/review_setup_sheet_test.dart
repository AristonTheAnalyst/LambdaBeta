import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/features/programs/view/review_setup_sheet.dart';
import 'package:lambda/features/programs/viewmodel/program_history_viewmodel.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';

/// What the review set-up sheet asks, and what it deliberately does not.
///
/// The sheet draws one distinction — **now** or **later** — and the whole
/// reason it exists as a single sheet is that both answers write the same row.
/// The risk the file guards is the two modes bleeding into each other: asking
/// a user who is about to open the plan for a rationale and a due date, or
/// letting a scheduled checkpoint silently capture the program as it stands.
/// The other risk is the scope: a review with no scope names nothing, and a
/// scope that names nothing cannot be written (the DB's CHECK refuses it), so
/// the primary action has to wait rather than fail at the write.
void main() {
  const program = ScopeOption(
    kind: ReviewScopeKind.program,
    label: 'Whole program',
  );
  const accumulation = ScopeOption(
    kind: ReviewScopeKind.block,
    label: 'Accumulation',
    blockId: 'b1',
  );
  const pushA = ScopeOption(
    kind: ReviewScopeKind.session,
    label: 'Push A · Accumulation',
    blockId: 'b1',
    sessionId: 's1',
  );

  /// What the sheet popped, once it pops.
  ReviewSetupRequest? result;

  Future<void> pumpSheet(
    WidgetTester tester, {
    List<ScopeOption> scopes = const [program],
    bool usesBlocks = false,
    String? initialBlockId,
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
                    scopes: scopes,
                    usesBlocks: usesBlocks,
                    initialBlockId: initialBlockId,
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

  /// Picks [label] out of the picker on the field labelled [field].
  Future<void> pick(WidgetTester tester, String field, String label) async {
    await tester.tap(find.text(field).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> typeInto(WidgetTester tester, String label, String text) async {
    await tester.enterText(
      find
          .descendant(
            of: find
                .ancestor(of: find.text(label), matching: find.byType(LambdaInput))
                .first,
            matching: find.byType(TextField),
          )
          .first,
      text,
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.text('Start review').hitTestable().first);
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet opens on "now", asking only what a review being '
      'taken now needs', (tester) async {
    await pumpSheet(tester);

    // The action says what it does. "Review" would leave the user unsure
    // whether they were about to start one or read one.
    expect(find.text('Start review'), findsOneWidget);

    // The scope is already answered — a program is the one scope every
    // program has, so "whole program" is the default rather than a question.
    expect(find.text('Program'), findsOneWidget);

    // Everything a future prompt would need is absent: a date for a review
    // happening immediately is meaningless, and notes are captured at the end
    // (they are the record, not the intent).
    expect(find.text('On'), findsNothing);
    expect(find.text('Notes'), findsNothing);
    expect(find.text('Checkpoint'), findsNothing);
    expect(find.text('Title (optional)'), findsOneWidget);
  });

  testWidgets('"Schedule" turns the same sheet into a prompt for later',
      (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('Schedule').first);
    await tester.pumpAndSettle();

    // The kind, the day and the rationale — the three things a checkpoint
    // written for later has to carry, because the person reading it is not the
    // person who wrote it.
    expect(find.text('Checkpoint'), findsOneWidget);
    expect(find.text('Planned change'), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);

    // 'Schedule' twice is the segment and the button: the action relabelled,
    // and the action-for-now is gone.
    expect(find.text('Schedule'), findsNWidgets(2));
    expect(find.text('Start review'), findsNothing);
  });

  testWidgets('a program with no blocks and no workouts offers the program '
      'scope alone — a picker that opens empty is worse than no picker', (
    tester,
  ) async {
    await pumpSheet(tester);

    expect(find.text('Program'), findsOneWidget);
    expect(find.text('Block'), findsNothing);
    expect(find.text('Workout'), findsNothing);
  });

  testWidgets('a blocked program offers its blocks — the scope the phases it '
      'is actually trained in can be reviewed at', (tester) async {
    await pumpSheet(tester, scopes: const [program, accumulation]);

    expect(find.text('Block'), findsOneWidget);

    // No workouts in the list yet, so nothing to review one at a time.
    expect(find.text('Workout'), findsNothing);
  });

  testWidgets('a program with workouts offers the workout scope too', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      scopes: const [program, accumulation, pushA],
      usesBlocks: true,
    );

    expect(find.text('Block'), findsOneWidget);
    expect(find.text('Workout'), findsOneWidget);
  });

  testWidgets('a block scope waits for a block to be picked — the row cannot '
      'be written half-scoped, so the action cannot fire', (tester) async {
    await pumpSheet(tester, scopes: const [program, accumulation], usesBlocks: true);
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a block'), findsOneWidget);

    await submit(tester);
    expect(result, isNull, reason: 'nothing named, nothing to review');

    await pick(tester, 'Choose a block', 'Accumulation');
    await submit(tester);

    expect(result, isNotNull);
    expect(result!.scope.kind, ReviewScopeKind.block);
    expect(result!.scope.blockId, 'b1');
    expect(result!.scope.sessionId, isNull);
    expect(result!.mode, ReviewStartMode.now);
  });

  testWidgets('a workout scope carries the workout AND the block it is filed '
      'under, which is what keeps it visible in the timeline', (tester) async {
    await pumpSheet(
      tester,
      scopes: const [program, accumulation, pushA],
      usesBlocks: true,
    );
    await tester.tap(find.text('Workout'));
    await tester.pumpAndSettle();

    await pick(tester, 'Choose a workout', 'Push A · Accumulation');
    await submit(tester);

    expect(result!.scope.kind, ReviewScopeKind.session);
    expect(result!.scope.sessionId, 's1');
    expect(result!.scope.blockId, 'b1');
  });

  testWidgets('an initial block prefills the scope rather than deciding it — '
      'the timeline filter is where the user was looking, not what they chose', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      scopes: const [program, accumulation, pushA],
      usesBlocks: true,
      initialBlockId: 'b1',
    );

    // Already open on the block, and named — no tap was needed.
    expect(find.text('Accumulation'), findsOneWidget);

    // Still a choice: the other scopes are one tap away.
    expect(find.text('Program'), findsOneWidget);
    expect(find.text('Workout'), findsOneWidget);

    await submit(tester);
    expect(result!.scope.blockId, 'b1');
  });

  testWidgets('an initial block that names nothing falls through to the '
      'program, which is the one scope every program has', (tester) async {
    await pumpSheet(
      tester,
      scopes: const [program, accumulation],
      usesBlocks: true,
      initialBlockId: 'deleted-block',
    );

    expect(find.text('Accumulation'), findsNothing);
    await submit(tester);

    expect(result!.scope.kind, ReviewScopeKind.program);
    expect(result!.scope.blockId, isNull);
  });

  testWidgets('a review taken now carries no date, no notes and no proposal — '
      'there is nothing to prompt for and nothing to propose', (tester) async {
    await pumpSheet(tester);
    await typeInto(tester, 'Title (optional)', 'End of block 1');
    await submit(tester);

    expect(result!.title, 'End of block 1');
    expect(result!.scheduledFor, isNull);
    expect(result!.notes, isNull);
    // The program as it stands IS what the reviewer is looking at; capturing it
    // as a proposal would attach a description to the thing in front of them.
    expect(result!.isChange, isFalse);
  });

  testWidgets('a scheduled change captures the program and the reason for it',
      (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('Schedule').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Planned change'));
    await tester.pumpAndSettle();

    await typeInto(tester, 'Title', 'Swap the bench variation');
    await typeInto(tester, 'Notes', 'Shoulders have been grumbling.');
    await tester.tap(find.text('Schedule').last);
    await tester.pumpAndSettle();

    expect(result!.mode, ReviewStartMode.scheduled);
    expect(result!.isChange, isTrue);
    expect(result!.title, 'Swap the bench variation');
    expect(result!.notes, 'Shoulders have been grumbling.');
    // A default date, not a null one: the prompt needs a day, and the sheet
    // offers one the user can change rather than blocking on a picker.
    expect(result!.scheduledFor, isNotNull);
  });
}
