import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/reviews/view/review_scope_sheet.dart';
import 'package:lambda/features/reviews/viewmodel/reviews_viewmodel.dart';
import 'package:lambda/shared/widgets/glass_button.dart';

import 'support/fake_program_repos.dart';

/// Changing what a running pass covers.
///
/// The sheet's contract: it opens on the scope the pass already has, shows
/// only the half whose tile opened it — the other rides along untouched,
/// order and all — every tick writes through as it is made, a pass can never
/// be left with no workouts, and an id the rows cannot show is kept rather
/// than dropped. Each test pins one clause.
void main() {
  // One review finished twelve days ago — the window every count below is
  // measured over, the same moment on every row.
  final lastReview = DateTime.now().subtract(const Duration(days: 12));
  final workouts = [
    ReviewableWorkout(
      sessionId: 'w1',
      label: 'Push Day',
      finished: 5,
      lastReview: lastReview,
    ),
    ReviewableWorkout(
      sessionId: 'w2',
      label: 'Pull Day',
      finished: 3,
      lastReview: lastReview,
    ),
    ReviewableWorkout(
      sessionId: 'w3',
      label: 'Legs',
      lastReview: lastReview,
    ),
  ];
  final goals = [
    const ReviewableGoal(
      goalId: 'g1',
      exerciseName: 'Bench Press',
      target: '100 kg × 5',
      targetWeight: 100,
      targetReps: 5,
    ),
    const ReviewableGoal(
      goalId: 'g2',
      exerciseName: 'Squat',
      target: '140 kg × 3',
      targetWeight: 140,
      targetReps: 3,
    ),
  ];

  late FakeProgramHistoryRepository repo;
  late ReviewScopeEdit? result;

  setUp(() {
    repo = FakeProgramHistoryRepository();
    result = null;
  });

  Future<void> openSheet(
    WidgetTester tester, {
    List<String> sessionIds = const ['w1'],
    List<String> goalIds = const [],
    ReviewScopeSection section = ReviewScopeSection.workouts,
    List<ReviewableWorkout>? offered,
    List<ReviewableGoal>? offeredGoals,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showReviewScopeSheet(
                    context,
                    reviewId: 'r1',
                    userId: 'u1',
                    sessionIds: sessionIds,
                    goalIds: goalIds,
                    section: section,
                    loadWorkouts: () async => offered ?? workouts,
                    loadGoals: () async => offeredGoals ?? goals,
                    repository: repo,
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

  testWidgets('opens on the scope the pass already has', (tester) async {
    await openSheet(tester, sessionIds: ['w2'], goalIds: ['g1']);

    // The heading is the section word itself — "In this review" and its
    // count line are gone (2026-10-10).
    expect(find.text('WORKOUTS'), findsOneWidget);
    expect(find.text('In this review'), findsNothing);
    expect(find.textContaining('1 workout ·'), findsNothing);
    // Each row states the window and how much is in this workout: how long
    // since the last review, how many of this one since — those two lines
    // and the name are all the card carries.
    expect(find.text('12 days since last review'), findsNWidgets(3));
    expect(find.text('5 workouts finished since last review'), findsOneWidget);
    expect(find.text('0 workouts finished since last review'), findsOneWidget);
    // Nothing is written by opening: the sheet edits, it does not begin.
    expect(repo.scopeCalls, isEmpty);
  });

  testWidgets('a tick writes through as it is made, the other half riding '
      'along', (tester) async {
    await openSheet(tester, sessionIds: ['w1'], goalIds: ['g1']);

    await tester.tap(find.text('Legs'));
    await tester.pumpAndSettle();

    expect(repo.scopeCalls, hasLength(1));
    expect(repo.scopeCalls.single.reviewId, 'r1');
    // The order is the rows' order, not the tick order, and the goals half —
    // not shown in this visit — rides along untouched rather than being
    // dropped by a workout edit.
    expect(repo.scopeCalls.single.sessionIds, ['w1', 'w3']);
    expect(repo.scopeCalls.single.goalIds, ['g1']);
  });

  testWidgets('the workouts tile opens the workouts alone', (tester) async {
    await openSheet(tester, sessionIds: ['w1'], goalIds: ['g1']);

    expect(find.text('WORKOUTS'), findsOneWidget);
    expect(find.text('GOALS'), findsNothing);
    expect(find.text('Bench Press'), findsNothing);
  });

  testWidgets('the goals tile opens the goals alone, and the workouts come '
      'back as held', (tester) async {
    await openSheet(
      tester,
      sessionIds: ['w2', 'w1'],
      goalIds: ['g1'],
      section: ReviewScopeSection.goals,
    );

    expect(find.text('GOALS'), findsOneWidget);
    expect(find.text('WORKOUTS'), findsNothing);
    expect(find.text('Push Day'), findsNothing);

    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();

    // The workouts half, which this visit never showed, is handed back
    // exactly as the pass held it: neither dropped nor reordered into the
    // loader's order.
    expect(repo.scopeCalls.single.goalIds, ['g1', 'g2']);
    expect(repo.scopeCalls.single.sessionIds, ['w2', 'w1']);
  });

  testWidgets('a goal row states its name and its target as two things', (
    tester,
  ) async {
    // The dash is gone: the exercise is the title and the target is its own
    // right-aligned element, so the values line up down the list (2026-10-10).
    await openSheet(
      tester,
      goalIds: ['g1'],
      section: ReviewScopeSection.goals,
    );

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('100 kg × 5'), findsOneWidget);
    expect(find.text('Bench Press — 100 kg × 5'), findsNothing);
  });

  testWidgets('the tick is the exercise selector\'s own', (tester) async {
    // The same reading as the add-exercise modal: a green tick on the rows
    // that are in, nothing at all on the rows that are not.
    await openSheet(tester, sessionIds: ['w1']);

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.circle_outlined), findsNothing);

    await tester.tap(find.text('Pull Day'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    expect(find.byIcon(Icons.circle_outlined), findsNothing);
  });

  testWidgets('the last workout cannot be taken out, and the sheet says why', (
    tester,
  ) async {
    await openSheet(tester, sessionIds: ['w1']);

    await tester.tap(find.text('Push Day'));
    await tester.pumpAndSettle();

    // Refused, not silently ignored — and refused before the write, so the
    // row was never asked to hold a pass with nothing to walk.
    expect(repo.scopeCalls, isEmpty);
    expect(
      find.textContaining('A review needs at least one workout'),
      findsOneWidget,
    );

    // The refusal is a state, not a dead end: adding one lifts it.
    await tester.tap(find.text('Pull Day'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A review needs at least one workout'), findsNothing);
  });

  testWidgets('goals can all be taken out — only workouts are load-bearing', (
    tester,
  ) async {
    await openSheet(
      tester,
      sessionIds: ['w1'],
      goalIds: ['g1'],
      section: ReviewScopeSection.goals,
    );

    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();

    expect(repo.scopeCalls.single.goalIds, isEmpty);
    // The workouts half was never on screen; the write still carries it.
    expect(repo.scopeCalls.single.sessionIds, ['w1']);
  });

  testWidgets('a workout the rows cannot show is kept, not dropped', (
    tester,
  ) async {
    // `w9` was in the pass and is no longer on offer — deleted since. The
    // scope is edited, not rebuilt from today's picker, so it stays.
    await openSheet(tester, sessionIds: ['w1', 'w9']);

    await tester.tap(find.text('Pull Day'));
    await tester.pumpAndSettle();

    expect(repo.scopeCalls.single.sessionIds, ['w1', 'w2', 'w9']);
  });

  testWidgets('a refused write rolls the tick back and says so', (
    tester,
  ) async {
    await openSheet(tester, sessionIds: ['w1']);
    repo.failScopeWrite = true;

    await tester.tap(find.text('Pull Day'));
    await tester.pumpAndSettle();

    // The row did not take the tick, so the sheet must not keep it either:
    // a tick the pass does not have is a lie the landing would keep showing.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(
      find.textContaining('Could not update the review'),
      findsOneWidget,
    );
  });

  testWidgets('the search narrows the goals list to what it names', (
    tester,
  ) async {
    // A goal list can run long enough that finding one is the visit's real
    // work — the sheet carries its own search for that (2026-10-10).
    await openSheet(
      tester,
      goalIds: ['g1'],
      section: ReviewScopeSection.goals,
    );

    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'squat');
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsNothing);
    expect(find.text('Squat'), findsOneWidget);

    // Nothing on offer matches: the sheet says so rather than showing an
    // empty list.
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No goals match'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);
  });

  testWidgets('the search narrows the workouts list to what it names', (
    tester,
  ) async {
    await openSheet(tester, sessionIds: ['w1']);

    expect(find.text('Push Day'), findsOneWidget);
    expect(find.text('Legs'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'pull');
    await tester.pumpAndSettle();
    expect(find.text('Pull Day'), findsOneWidget);
    expect(find.text('Push Day'), findsNothing);
    expect(find.text('Legs'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No workouts match'), findsOneWidget);
  });

  testWidgets('the sort re-reads the list, and a tick writes in the order it '
      'shows', (tester) async {
    await openSheet(tester, sessionIds: ['w1']);

    // The default is the loader's recency order — opening changes nothing.
    expect(
      tester.getTopLeft(find.text('Push Day')).dy,
      lessThan(tester.getTopLeft(find.text('Pull Day')).dy),
    );

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A–Z'));
    await tester.pumpAndSettle();

    // The pick closed the menu — not the sheet. (The scrim belonged to the
    // menu; a tap outside was never what put the menu away.)
    expect(find.text('Legs'), findsOneWidget);

    expect(
      tester.getTopLeft(find.text('Legs')).dy,
      lessThan(tester.getTopLeft(find.text('Pull Day')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Pull Day')).dy,
      lessThan(tester.getTopLeft(find.text('Push Day')).dy),
    );

    // A tick stores the scope in the order the user is reading: the sort is
    // the scope's order, not just the screen's.
    await tester.tap(find.text('Legs'));
    await tester.pumpAndSettle();
    expect(repo.scopeCalls.single.sessionIds, ['w3', 'w1']);
  });

  testWidgets('the filter splits the goals by whether the pass holds them', (
    tester,
  ) async {
    await openSheet(
      tester,
      goalIds: ['g1'],
      section: ReviewScopeSection.goals,
    );

    // "In this review" is what the pass already holds.
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In this review'));
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Squat'), findsNothing);

    // "Not in this review" is what is still to add...
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not in this review'));
    await tester.pumpAndSettle();
    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Bench Press'), findsNothing);

    // ...and it reads the live ticks: ticking the offered goal takes it out
    // of the list it was offered by.
    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();
    expect(repo.scopeCalls.single.goalIds, ['g1', 'g2']);
    expect(find.text('Squat'), findsNothing);
    expect(find.textContaining('No goals with this filter'), findsOneWidget);
  });

  testWidgets('the goals can be ordered by their target', (tester) async {
    await openSheet(tester, section: ReviewScopeSection.goals);

    // A–Z is the default reading.
    expect(
      tester.getTopLeft(find.text('Bench Press')).dy,
      lessThan(tester.getTopLeft(find.text('Squat')).dy),
    );

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heaviest target'));
    await tester.pumpAndSettle();

    // Picking a criterion lands it in its natural reading — heaviest first.
    expect(
      tester.getTopLeft(find.text('Squat')).dy,
      lessThan(tester.getTopLeft(find.text('Bench Press')).dy),
    );
  });

  testWidgets('tapping the search box takes the focus the keyboard follows', (
    tester,
  ) async {
    await openSheet(tester, section: ReviewScopeSection.goals);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
      reason: 'a search box nothing can focus is not a search box — the '
          'keyboard is what focus summons',
    );
  });

  testWidgets('Done answers what was edited, and a dismissal answers nothing', (
    tester,
  ) async {
    await openSheet(tester, sessionIds: ['w1'], goalIds: ['g1']);
    await tester.tap(find.text('Legs'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(GlassButton, 'Done'));
    await tester.pumpAndSettle();

    expect(result!.sessionIds, ['w1', 'w3']);
    expect(result!.goalIds, ['g1']);

    // Opened and closed without a tick: nothing changed, so nothing is
    // claimed — the caller must not read null as an empty scope.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(GlassButton, 'Done'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
