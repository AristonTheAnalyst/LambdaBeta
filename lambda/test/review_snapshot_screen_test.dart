import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/program_content.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/features/programs/view/content_diff_sheet.dart';
import 'package:lambda/features/programs/view/review_snapshot_screen.dart';

/// The snapshot's own tap-through: the changes sheet's exercise cards open
/// their exercise on the record BELOW the sheet — the cards switch the
/// workout they belong to, because a snapshot read is the one place besides
/// the editor where a tap has somewhere to land.
///
/// The card's promise is only kept if the workout it names actually moves its
/// tab, so this drives the whole path: a card for an exercise in the SECOND
/// workout, tabbed away on the body, opens with the sheet closing over it.
void main() {
  final names = {'e1': 'Bench', 'e2': 'Row', 'e3': 'Pull', 'e4': 'Curl'};

  ContentExercise cexercise({
    required String id,
    required String sessionId,
    required String exerciseId,
    required String weight,
    required String reps,
  }) => ContentExercise(
    plannedExerciseId: id,
    plannedSessionId: sessionId,
    userId: 'u1',
    exerciseId: exerciseId,
    exerciseOrder: 1,
    sets: [
      ContentSet(
        plannedSetId: '$id-s1',
        plannedExerciseId: id,
        plannedSessionId: sessionId,
        userId: 'u1',
        setNumber: 1,
        targetWeight: weight,
        targetReps: reps,
      ),
    ],
  );

  ContentSession cworkout(
    String id,
    String name, {
    required List<ContentExercise> exercises,
  }) => ContentSession(
    sessionId: id,
    userId: 'u1',
    name: name,
    exercises: exercises,
  );

  ProgramReview completedReview({
    required String id,
    required ProgramContent content,
  }) => ProgramReview(
    reviewId: id,
    userId: 'u1',
    programId: 'p1',
    kind: kReviewKindReview,
    createdDate: DateTime(2026, 10, 1),
    completedDate: DateTime(2026, 10, 5),
    outcome: kOutcomeReviewed,
    snapshotContent: content.encode(),
    snapshotHash: content.contentHash,
  );

  testWidgets('a changes card tap lands the record on that exercise', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // Two workouts, so the reveal has to pick the right one: the second
    // workout's new lift is the card the body has tabbed away.
    final before = ProgramContent(
      sessions: [
        cworkout(
          'w1',
          'Push A',
          exercises: [
            cexercise(
              id: 'pe-a1',
              sessionId: 'w1',
              exerciseId: 'e1',
              weight: '60',
              reps: '5',
            ),
          ],
        ),
        cworkout(
          'w2',
          'Pull B',
          exercises: [
            cexercise(
              id: 'pe-b1',
              sessionId: 'w2',
              exerciseId: 'e3',
              weight: '100',
              reps: '5',
            ),
          ],
        ),
      ],
    );
    final after = ProgramContent(
      sessions: [
        cworkout(
          'w1',
          'Push A',
          exercises: [
            cexercise(
              id: 'pe-a1',
              sessionId: 'w1',
              exerciseId: 'e1',
              weight: '60',
              reps: '5',
            ),
            cexercise(
              id: 'pe-a2',
              sessionId: 'w1',
              exerciseId: 'e2',
              weight: '80',
              reps: '8',
            ),
          ],
        ),
        cworkout(
          'w2',
          'Pull B',
          exercises: [
            cexercise(
              id: 'pe-b1',
              sessionId: 'w2',
              exerciseId: 'e3',
              weight: '100',
              reps: '5',
            ),
            cexercise(
              id: 'pe-b2',
              sessionId: 'w2',
              exerciseId: 'e4',
              weight: '40',
              reps: '12',
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewSnapshotScreen(
          review: completedReview(id: 'r2', content: after),
          previous: completedReview(id: 'r1', content: before),
          exerciseNames: names,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Every card opens on its first exercise: Pull B shows Pull, not Curl.
    expect(find.text('60'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('40'), findsNothing);

    await tester.tap(find.text('Changes'));
    await tester.pumpAndSettle();
    expect(find.text(kReviewChangesTitle), findsOneWidget);

    // The card is the only place 'Curl' is written: a workout card shows its
    // ACTIVE exercise's name alone, and Pull B is still on Pull.
    expect(find.text('Curl'), findsOneWidget);
    await tester.ensureVisible(find.text('Curl'));
    await tester.tap(find.text('Curl'));
    await tester.pumpAndSettle();

    // The sheet closed itself and the record is on the exercise it named:
    // Pull B switched to Curl (40 on screen, Pull's 100 tabbed away), and
    // the other workout held still.
    expect(find.text(kReviewChangesTitle), findsNothing);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('100'), findsNothing);
    expect(find.text('60'), findsOneWidget);
  });
}
