import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/models/custom_variation.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/features/goals/view/goal_sheet.dart';
import 'package:lambda/shared/widgets/exercise_target_picker.dart';

/// The New goal sheet opened from a session set (2026-10-26).
///
/// The goals screen hands the form a long-lived draft, so a dismissal keeps
/// what was typed. A session door has nothing to resume — its meaning is
/// "from THIS set" — so it hands a [seed] instead and the sheet owns the
/// draft: the form opens on that row and dies with the sheet, and the next
/// set opens on its own values rather than the last one's.
void main() {
  final details = {
    'e1': const ExerciseDetail(
      exercise: CustomExercise(exerciseId: 'e1', userId: 'u1', name: 'Bench'),
    ),
    'e2': const ExerciseDetail(
      exercise: CustomExercise(exerciseId: 'e2', userId: 'u1', name: 'Squat'),
    ),
  };
  const variations = [
    CustomVariation(
      variationId: 'v1',
      userId: 'u1',
      name: 'Paused',
    ),
  ];

  /// A host that opens the sheet on whatever [seed] it is given — the two
  /// opens are the same host, exactly as one session surface opens it twice.
  Future<List<ExerciseTarget>> openSheet(
    WidgetTester tester, {
    required List<ExerciseTarget> seeds,
  }) async {
    final writes = <ExerciseTarget>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                for (var i = 0; i < seeds.length; i++)
                  TextButton(
                    onPressed: () => showAddGoalSheet(
                      context,
                      detailMap: details,
                      variations: variations,
                      lastUsed: const {},
                      pastSets: const <PastSetRow>[],
                      seed: seeds[i],
                      onAdd: (target) async {
                        writes.add(target);
                        return true;
                      },
                    ),
                    child: Text('open $i'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < seeds.length; i++) {
      await tester.tap(find.text('open $i'));
      await tester.pumpAndSettle();
      if (i < seeds.length - 1) {
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      }
    }
    return writes;
  }

  String fieldText(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

  testWidgets('the form opens on the set: exercise, variation, weight, reps', (
    tester,
  ) async {
    await openSheet(
      tester,
      seeds: [
        const ExerciseTarget(
          exerciseId: 'e1',
          exerciseName: 'Bench',
          variationId: 'v1',
          weight: 100,
          reps: 3,
        ),
      ],
    );

    // The exercise is already picked, the numbers already typed: the door's
    // promise is that the row is the starting point, not a blank form.
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('Pick exercise'), findsNothing);
    expect(find.text('Paused'), findsOneWidget);
    expect(fieldText(tester, 'goal-kg'), '100');
    expect(fieldText(tester, 'goal-reps'), '3');
    // Nothing is typed for the goal's own notes: the row's set notes are not
    // the target's reason.
    expect(find.text('Why this goal, or what to watch…'), findsOneWidget);
  });

  testWidgets('ADD writes exactly the seeded target', (tester) async {
    final writes = await openSheet(
      tester,
      seeds: [
        const ExerciseTarget(
          exerciseId: 'e1',
          exerciseName: 'Bench',
          variationId: 'v1',
          weight: 100,
          reps: 3,
        ),
      ],
    );

    await tester.tap(find.text('ADD'));
    await tester.pumpAndSettle();

    expect(writes, hasLength(1));
    expect(writes.single.exerciseId, 'e1');
    expect(writes.single.variationId, 'v1');
    expect(writes.single.weight, 100);
    expect(writes.single.reps, 3);
    // Written and confirmed without closing, the goals screen's own reading.
    expect(find.text('Added Bench — 100 kg × 3'), findsOneWidget);
    expect(
      fieldText(tester, 'goal-kg'),
      '',
      reason: 'the form clears for the next goal',
    );
  });

  testWidgets('a second open starts on the second set — no draft carried over', (
    tester,
  ) async {
    await openSheet(
      tester,
      seeds: [
        const ExerciseTarget(
          exerciseId: 'e1',
          exerciseName: 'Bench',
          weight: 100,
          reps: 3,
        ),
        const ExerciseTarget(
          exerciseId: 'e2',
          exerciseName: 'Squat',
          weight: 140,
          reps: 5,
        ),
      ],
    );

    // The second open — after the first sheet closed — is the second set,
    // never the first form resumed.
    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Bench'), findsNothing);
    expect(fieldText(tester, 'goal-kg'), '140');
    expect(fieldText(tester, 'goal-reps'), '5');
  });
}
