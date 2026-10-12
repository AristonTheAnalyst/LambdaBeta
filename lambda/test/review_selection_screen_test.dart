import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/reviews/view/review_selection_screen.dart';
import 'package:lambda/features/reviews/viewmodel/reviews_viewmodel.dart';
import 'package:lambda/shared/widgets/glass_button.dart';

/// The picker the name sheet hands off to: which workouts, which goals.
///
/// The screen's contract is one answer, delivered in the order the rows were
/// shown — not the order they were ticked — and a Start that never arms
/// without a workout, because a review is walked and goals cannot be walked.
/// Each test pins one clause of that.
void main() {
  final lastReview = DateTime.now().subtract(const Duration(days: 12));
  final workouts = [
    ReviewableWorkout(
      sessionId: 'w1',
      label: 'Push Day',
      finished: 3,
      lastReview: lastReview,
      lastLogged: DateTime.now().subtract(const Duration(days: 2)),
    ),
    ReviewableWorkout(sessionId: 'w2', label: 'Pull Day'),
  ];
  final goals = [
    const ReviewableGoal(
      goalId: 'g1',
      exerciseName: 'Bench press',
      target: '100 kg × 5',
    ),
    const ReviewableGoal(
      goalId: 'g2',
      exerciseName: 'Squat',
      target: '140 kg × 3',
    ),
  ];

  late ReviewSelection? result;

  Future<void> openScreen(
    WidgetTester tester, {
    List<ReviewableWorkout>? offered,
    List<ReviewableGoal> offeredGoals = const [],
  }) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<ReviewSelection>(
                    MaterialPageRoute(
                      builder: (_) => ReviewSelectionScreen(
                        name: 'End of block 1',
                        workouts: offered ?? workouts,
                        goals: offeredGoals,
                      ),
                    ),
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

  GlassButton startButton(WidgetTester tester) => tester.widget<GlassButton>(
    find.widgetWithText(GlassButton, 'Start review'),
  );

  testWidgets('each workout states the window and its count', (tester) async {
    await openScreen(tester, offeredGoals: goals);

    expect(find.text('Push Day'), findsOneWidget);
    expect(find.text('12 days since last review'), findsOneWidget);
    expect(find.text('3 workouts finished since last review'), findsOneWidget);
    // A workout with no review behind it says so, and counts lifetime ones.
    expect(find.text('No reviews yet'), findsOneWidget);
    expect(find.text('0 workouts finished'), findsOneWidget);
    // The card is the name, those two lines and the tick: where the workout
    // lives and how big it is are not part of it any more, and an unticked
    // row wears no circle — the exercise selector's own reading.
    expect(find.text('Upper Lower'), findsNothing);
    expect(find.text('5 EXERCISES'), findsNothing);
    expect(find.byIcon(Icons.circle_outlined), findsNothing);
    // A goal row is its name, its target and a tick, nothing beside them:
    // goals carry no scope while they are unattached (2026-10-08), so no
    // chip names one.
    expect(find.text('Bench press'), findsOneWidget);
    expect(find.text('100 kg × 5'), findsOneWidget);
    expect(find.text('Bench press — 100 kg × 5'), findsNothing);
  });

  testWidgets('Start is dead until a workout is ticked — goals never arm it', (
    tester,
  ) async {
    await openScreen(tester, offeredGoals: goals);
    expect(startButton(tester).disabled, isTrue);
    expect(find.text('Pick what to review'), findsOneWidget);

    // A goal alone is not a review: there is nothing to walk.
    await tester.tap(find.text('Squat'));
    await tester.pump();
    expect(startButton(tester).disabled, isTrue);
    expect(
      find.textContaining('A review needs at least one workout'),
      findsOneWidget,
    );

    await tester.tap(find.text('Push Day'));
    await tester.pump();
    expect(startButton(tester).disabled, isFalse);
    expect(find.text('1 workout · 1 goal'), findsOneWidget);
  });

  testWidgets('the answer comes back in picker order, not tick order', (
    tester,
  ) async {
    await openScreen(tester);

    // Ticked bottom-up on purpose: the review's landing reads back in the
    // order the user was shown, never the order their finger moved.
    await tester.tap(find.text('Pull Day'));
    await tester.pump();
    await tester.tap(find.text('Push Day'));
    await tester.pump();
    // The selector's own tick, once per ticked row.
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));

    await tester.tap(find.text('Start review'));
    await tester.pumpAndSettle();
    expect(result!.sessionIds, ['w1', 'w2']);
  });

  testWidgets('goals tick and untick like workouts', (tester) async {
    await openScreen(tester, offeredGoals: goals);

    await tester.tap(find.text('Push Day'));
    await tester.pump();
    await tester.tap(find.text('Bench press'));
    await tester.pump();
    await tester.tap(find.text('Squat'));
    await tester.pump();
    // ...and the second one changes its mind.
    await tester.tap(find.text('Squat'));
    await tester.pump();

    await tester.tap(find.text('Start review'));
    await tester.pumpAndSettle();
    expect(result!.sessionIds, ['w1']);
    expect(result!.goalIds, ['g1']);
  });

  testWidgets('with nothing to offer it says so, and Start stays dead', (
    tester,
  ) async {
    await openScreen(tester, offered: const []);
    expect(find.text('Nothing to review yet'), findsOneWidget);
    expect(startButton(tester).disabled, isTrue);
  });

  testWidgets('backing out answers nothing', (tester) async {
    await openScreen(tester);
    await tester.tap(find.text('Push Day'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
