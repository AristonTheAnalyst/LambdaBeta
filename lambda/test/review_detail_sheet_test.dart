import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/data/models/program_content.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/features/programs/model/program_content_diff.dart';
import 'package:lambda/features/programs/view/review_detail_sheet.dart';

/// What a completed checkpoint shows the program WAS, per shape and per scope.
///
/// The directive splits the two program shapes at the review: a simple program
/// is reviewed as its workouts, a blocked one as its phases — each carrying the
/// workouts in it AND its own targets. This asserts the sheet actually says
/// that, because the split is easy to lose: rendering every workout flat would
/// still show all the content while answering a different question, and a
/// block's goals would drift to the program level where they would read as
/// being in force through every phase.
///
/// Every case here is a COMPLETED review, because that is the only kind this
/// sheet renders — an open one is a pass to be taken, not a record to be read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bundled typefaces: Flutter's test font gives every glyph the same
  // square advance, so a goal line measures wider than a device draws it.
  setUpAll(() async {
    await _loadFont(AppFonts.uiFamily, const [
      'assets/fonts/Manrope-400.ttf',
      'assets/fonts/Manrope-600.ttf',
      'assets/fonts/Manrope-800.ttf',
    ]);
    await _loadFont(AppFonts.monoFamily, const [
      'assets/fonts/JetBrainsMono-400.ttf',
      'assets/fonts/JetBrainsMono-700.ttf',
    ]);
  });

  final names = {'e1': 'Bench', 'e2': 'Row'};

  ContentSession session(
    String id,
    String name, {
    String? blockId,
    List<ContentSet> sets = const [],
  }) => ContentSession(
    sessionId: id,
    userId: 'u1',
    name: name,
    blockId: blockId,
    exercises: [
      ContentExercise(
        plannedExerciseId: '$id-x',
        plannedSessionId: id,
        userId: 'u1',
        exerciseOrder: 1,
        exerciseId: id == 's1' ? 'e1' : 'e2',
        sets: sets,
      ),
    ],
  );

  /// Opens the checkpoint the way the history panel does: a completed review,
  /// fed by the snapshot it froze.
  Future<void> pumpSheet(
    WidgetTester tester, {
    required ProgramContent content,
    String? blockId,
    String? sessionId,
    bool usesBlocks = false,
    ContentDiff? change,
    VoidCallback? onViewChanges,
    VoidCallback? onViewWorkouts,
  }) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showReviewDetailSheet(
                  context,
                  review: completedReview(
                    blockId: blockId,
                    sessionId: sessionId,
                    content: content,
                  ),
                  usesBlocks: usesBlocks,
                  change: change,
                  onViewChanges: onViewChanges,
                  onViewWorkouts: onViewWorkouts,
                  exerciseNames: names,
                ),
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

  testWidgets('a simple program is read as its workouts, in order, with what '
      'each holds', (tester) async {
    await pumpSheet(
      tester,
      content: ProgramContent(
        sessions: [session('s1', 'Push A'), session('s2', 'Pull A')],
        goals: const [
          ContentGoal(
            goalId: 'g1',
            userId: 'u1',
            exerciseId: 'e1',
            targetWeight: 100,
            targetReps: 1,
            text: 'Bench',
          ),
        ],
      ),
    );

    expect(find.text('WHAT IT WAS'), findsOneWidget);

    // Program order is the order the program is trained in, which is the one
    // thing a plan can be wrong about without any content being wrong.
    final push = tester.getTopLeft(find.text('Push A')).dy;
    final pull = tester.getTopLeft(find.text('Pull A')).dy;
    expect(push, lessThan(pull));

    // Each workout says what is in it, not just that it exists.
    expect(find.text('1 exercise · Bench'), findsOneWidget);
    expect(find.text('1 exercise · Row'), findsOneWidget);

    // The goal is the program's own, and every simple program goal is — a
    // "Whole program" heading would invent a scope the shape cannot have.
    expect(find.text('Whole program'), findsNothing);
    expect(find.text('Bench — 100 kg × 1 rep'), findsOneWidget);
  });

  testWidgets('a blocked program is read as its phases — each with its own '
      'workouts and its own goals', (tester) async {
    await pumpSheet(
      tester,
      usesBlocks: true,
      content: ProgramContent(
        blocks: const [
          ContentBlock(
            blockId: 'b1',
            name: 'Accumulation',
            blockOrder: 1,
            targetWeeks: 4,
          ),
          ContentBlock(
            blockId: 'b2',
            name: 'Intensification',
            blockOrder: 2,
            targetWeeks: 3,
          ),
        ],
        sessions: [
          session('s1', 'Push A', blockId: 'b1'),
          session('s2', 'Pull A', blockId: 'b2'),
        ],
        goals: const [
          ContentGoal(
            goalId: 'g1',
            userId: 'u1',
            blockId: 'b1',
            text: 'Sleep eight hours',
          ),
          ContentGoal(
            goalId: 'g2',
            userId: 'u1',
            exerciseId: 'e1',
            targetWeight: 100,
            targetReps: 1,
            text: 'Bench',
          ),
        ],
      ),
    );

    final acc = tester.getTopLeft(find.text('Accumulation')).dy;
    final push = tester.getTopLeft(find.text('Push A')).dy;
    final intens = tester.getTopLeft(find.text('Intensification')).dy;
    final pull = tester.getTopLeft(find.text('Pull A')).dy;

    // Blocks in program order, each holding its own workouts — a flat list of
    // all workouts would answer "what am I doing" but not "what phase is
    // this", which is the question a blocked program is reviewed on.
    expect(acc, lessThan(push));
    expect(push, lessThan(intens));
    expect(intens, lessThan(pull));

    // A phase's length is part of what it is.
    expect(find.text('4 weeks'), findsOneWidget);
    expect(find.text('3 weeks'), findsOneWidget);

    // The block's own goal sits under the block, above the next one — filed
    // where it is in force, not flattened to the program.
    final blockGoal = tester.getTopLeft(find.text('Sleep eight hours')).dy;
    expect(blockGoal, greaterThan(acc));
    expect(blockGoal, lessThan(intens));

    // The program's own goal is named as such, below every block.
    final whole = tester.getTopLeft(find.text('Whole program')).dy;
    expect(whole, greaterThan(pull));
    expect(find.text('Bench — 100 kg × 1 rep'), findsOneWidget);
  });

  testWidgets('a block-scoped review is read as that block alone', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      usesBlocks: true,
      blockId: 'b1',
      content: ProgramContent(
        blocks: const [
          ContentBlock(blockId: 'b1', name: 'Accumulation', blockOrder: 1),
          ContentBlock(blockId: 'b2', name: 'Intensification', blockOrder: 2),
        ],
        sessions: [
          session('s1', 'Push A', blockId: 'b1'),
          session('s2', 'Pull A', blockId: 'b2'),
        ],
        goals: const [
          ContentGoal(
            goalId: 'g1',
            userId: 'u1',
            blockId: 'b1',
            text: 'Sleep eight hours',
          ),
          ContentGoal(
            goalId: 'g2',
            userId: 'u1',
            blockId: 'b2',
            text: 'Row 100',
          ),
          ContentGoal(
            goalId: 'g3',
            userId: 'u1',
            exerciseId: 'e1',
            targetWeight: 100,
            targetReps: 1,
            text: 'Bench',
          ),
        ],
      ),
    );

    // The block under review, and nothing of the phase after it: a review of
    // block 1 that laid out block 2 would bury the thing being decided.
    expect(find.text('Accumulation'), findsOneWidget);
    expect(find.text('Push A'), findsOneWidget);
    expect(find.text('Intensification'), findsNothing);
    expect(find.text('Pull A'), findsNothing);
    expect(find.text('Row 100'), findsNothing);

    // Both levels of goal, each where it belongs: the block's own, and the
    // program's — which IS in force in this block, so a review of the block
    // that hid it would report a phase with no target.
    expect(find.text('Sleep eight hours'), findsOneWidget);
    expect(find.text('Bench — 100 kg × 1 rep'), findsOneWidget);
    expect(find.text('Whole program · in force here'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Sleep eight hours')).dy,
      lessThan(tester.getTopLeft(find.text('Bench — 100 kg × 1 rep')).dy),
    );
  });

  testWidgets('a workout-scoped review is read as that workout, down to what '
      'each set asked for', (tester) async {
    await pumpSheet(
      tester,
      usesBlocks: true,
      sessionId: 's1',
      content: ProgramContent(
        blocks: const [
          ContentBlock(blockId: 'b1', name: 'Accumulation', blockOrder: 1),
        ],
        sessions: [
          session(
            's1',
            'Push A',
            blockId: 'b1',
            sets: const [
              ContentSet(
                plannedSetId: 'x1',
                plannedExerciseId: 's1-x',
                plannedSessionId: 's1',
                userId: 'u1',
                setNumber: 1,
                targetWeight: '60',
                targetReps: '8',
              ),
              ContentSet(
                plannedSetId: 'x2',
                plannedExerciseId: 's1-x',
                plannedSessionId: 's1',
                userId: 'u1',
                setNumber: 2,
                targetWeight: '60',
                targetReps: '8',
              ),
              ContentSet(
                plannedSetId: 'x3',
                plannedExerciseId: 's1-x',
                plannedSessionId: 's1',
                userId: 'u1',
                setNumber: 3,
                targetReps: 'AMRAP',
              ),
            ],
          ),
          session('s2', 'Pull A', blockId: 'b1'),
        ],
      ),
    );

    // The workout under review, and the phase it sits in — which is context,
    // not scope, so it is named and nothing else of the block is listed.
    expect(find.text('Push A'), findsOneWidget);
    expect(find.text('Accumulation'), findsOneWidget);
    expect(find.text('Pull A'), findsNothing);

    // The whole reason a workout can be reviewed on its own: the numbers. A
    // plan is free text by design, so a target that is not a number survives
    // as written.
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('60 × 8  ·  60 × 8  ·  AMRAP'), findsOneWidget);

    // Goals belong to the block and the program, never to a workout — and a
    // sheet that listed them here would read as though this workout owned
    // them.
    expect(find.text('WHAT IT WAS'), findsOneWidget);
    expect(find.text('Whole program'), findsNothing);
    expect(find.text('This block'), findsNothing);
  });

  testWidgets('a workout no block holds still shows, because an archived phase '
      'must not shrink the program', (tester) async {
    await pumpSheet(
      tester,
      usesBlocks: true,
      content: ProgramContent(
        blocks: const [
          ContentBlock(blockId: 'b1', name: 'Accumulation', blockOrder: 1),
        ],
        sessions: [
          session('s1', 'Push A', blockId: 'b1'),
          session('s2', 'Old day'),
        ],
      ),
    );

    expect(find.text('Unfiled'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Old day')).dy,
      greaterThan(tester.getTopLeft(find.text('Unfiled')).dy),
    );
  });

  testWidgets('a dismissal carries no snapshot, and says so rather than '
      'showing a blank', (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showReviewDetailSheet(
                  context,
                  review: ProgramReview(
                    reviewId: 'r1',
                    userId: 'u1',
                    programId: 'p1',
                    kind: kReviewKindReview,
                    createdDate: DateTime(2026, 10, 1),
                    completedDate: DateTime(2026, 10, 5),
                    outcome: kOutcomeDismissed,
                  ),
                  exerciseNames: names,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // "Not now" is an answer, so there is nothing to show — and a blank panel
    // under a heading would read as a loading failure rather than as one.
    expect(find.text('Dismissed'.toUpperCase()), findsOneWidget);
    expect(
      find.textContaining('Nothing was recorded'),
      findsOneWidget,
    );
  });

  testWidgets('what a checkpoint changed leads, and offers the whole diff', (
    tester,
  ) async {
    var wantedDiff = 0;
    await pumpSheet(
      tester,
      content: ProgramContent(sessions: [session('s1', 'Push A')]),
      change: const ContentDiff([
        ContentChange(
          entity: ContentEntity.set,
          kind: ContentChangeKind.edited,
          id: 'x1',
          label: 'Set 1',
          detail: '60 × 5 → 65 × 5',
        ),
      ]),
      onViewChanges: () => wantedDiff++,
    );

    expect(find.text('WHAT CHANGED'), findsOneWidget);
    expect(find.text('~1'), findsOneWidget);
    expect(find.text('changed Set 1 — 60 × 5 → 65 × 5'), findsOneWidget);

    await tester.tap(find.text('All'));
    expect(wantedDiff, 1);
  });

  testWidgets('a first checkpoint has nothing to compare against, so it does '
      'not claim anything changed', (tester) async {
    await pumpSheet(
      tester,
      content: ProgramContent(sessions: [session('s1', 'Push A')]),
    );

    // No predecessor is not the same as no changes — "no content changes"
    // would be a claim about a comparison that never happened.
    expect(find.text('WHAT CHANGED'), findsNothing);
    expect(find.text('no content changes'), findsNothing);
  });

  testWidgets('a review that cannot be drilled into offers no actions', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      content: ProgramContent(sessions: [session('s1', 'Push A')]),
    );

    expect(find.text('View workouts'), findsNothing);
    expect(find.text('Changes'), findsNothing);
  });
}

/// A completed checkpoint of [content] — the only kind the detail sheet reads.
ProgramReview completedReview({
  required ProgramContent content,
  String? blockId,
  String? sessionId,
}) => ProgramReview(
  reviewId: 'r1',
  userId: 'u1',
  programId: 'p1',
  blockId: blockId,
  sessionId: sessionId,
  kind: kReviewKindReview,
  createdDate: DateTime(2026, 10, 1),
  completedDate: DateTime(2026, 10, 5),
  outcome: kOutcomeReviewed,
  snapshotContent: content.encode(),
  snapshotHash: content.contentHash,
);

/// Registers a bundled typeface under the family name the app asks for.
Future<void> _loadFont(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final asset in assets) {
    loader.addFont(rootBundle.load(asset));
  }
  await loader.load();
}
