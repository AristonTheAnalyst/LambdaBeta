import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/data/models/goal.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/features/goals/view/exercise_goals_sheet.dart';

/// The exercise goals sheet (2026-10-26) — the floor's bullseye door.
///
/// It lists the exercise's goals on the PR History sheet's furniture: open
/// goals by default, a status filter for the answered ones, and the app's
/// sort button for the order. A met goal wears the success ink the `G` badge
/// wears; an open one the content ink.

Goal _goal({
  required String id,
  num? weight,
  int? reps,
  DateTime? targetDate,
  String? variationId,
  List<GoalTargetSet> targets = const [],
}) => Goal(
  goalId: id,
  userId: 'u1',
  exerciseId: 'ex1',
  targetWeight: weight,
  targetReps: reps,
  targets: targets,
  targetDate: targetDate,
  createdDate: DateTime(2026, 10, 1),
  variationId: variationId,
);

PastSetRow _set({
  required String id,
  required double weight,
  required int reps,
  DateTime? date,
  String? variationId,
}) => PastSetRow(
  sessionExerciseSetId: id,
  sessionExerciseId: 'se-$id',
  sessionId: 'session-$id',
  userId: 'u1',
  exerciseId: 'ex1',
  setNumber: 1,
  reps: [reps],
  weight: weight,
  variationId: variationId,
  sessionCreatedDate: date ?? DateTime(2026, 10, 1),
);

/// Open: 100 × 5 by 1 Nov, plus a multi-set 110 × 3 that nothing reaches.
final _openGoal = _goal(
  id: 'g-open',
  weight: 100,
  reps: 5,
  targetDate: DateTime(2026, 11, 1),
);
final _multiGoal = _goal(
  id: 'g-multi',
  targetDate: DateTime(2026, 12, 1),
  targets: const [
    GoalTargetSet(order: 1, weight: 100, reps: 5),
    GoalTargetSet(order: 2, weight: 110, reps: 3),
  ],
);
// Achieved: 60 × 5, met by the 65 × 5 on 1 Oct.
final _metGoal = _goal(
  id: 'g-met',
  weight: 60,
  reps: 5,
  targetDate: DateTime(2026, 9, 30),
);
final _sets = [_set(id: 's1', weight: 65, reps: 5)];

Future<void> _openSheet(
  WidgetTester tester, {
  List<Goal>? goals,
  List<PastSetRow>? sets,
  Map<String, String> variationNames = const {},
  VoidCallback? onNewGoal,
}) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final notifier = ChangeNotifier();
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showExerciseGoalsSheet(
                context,
                exerciseName: 'Bench Press',
                listenable: notifier,
                goalsFor: () => goals ?? [_openGoal, _multiGoal, _metGoal],
                setsFor: () => sets ?? _sets,
                variationNames: variationNames,
                onNewGoal: onNewGoal,
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

Finder _entry(String id) => find.byKey(ValueKey('exercise-goal-entry-$id'));

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  testWidgets('the sheet names the exercise and counts its goals', (
    tester,
  ) async {
    await _openSheet(tester);
    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('BENCH PRESS'), findsOneWidget);
    // Three goals, one of them met: the open filter is in force.
    expect(find.text('2 of 3 goals'), findsOneWidget);
  });

  testWidgets('open is the default — a met goal waits behind the filter', (
    tester,
  ) async {
    await _openSheet(tester);
    expect(_entry('g-open'), findsOneWidget);
    expect(_entry('g-multi'), findsOneWidget);
    expect(_entry('g-met'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('exercise-goals-status-filter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('All goals'));
    await tester.pumpAndSettle();

    expect(_entry('g-met'), findsOneWidget);
    expect(find.text('3 goals'), findsOneWidget);
  });

  testWidgets('a met goal wears the success ink and states its day', (
    tester,
  ) async {
    await _openSheet(tester);
    await tester.tap(
      find.byKey(const ValueKey('exercise-goals-status-filter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Achieved'));
    await tester.pumpAndSettle();

    expect(_entry('g-open'), findsNothing);
    expect(_entry('g-met'), findsOneWidget);
    expect(find.text('Completed 1 Oct 2026'), findsOneWidget);
    expect(_colorOf(tester, '60 kg × 5'), AppColors.success);

    // The open goals keep the content ink.
    await tester.tap(
      find.byKey(const ValueKey('exercise-goals-status-filter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(_colorOf(tester, '100 kg × 5'), AppColors.primary);
  });

  testWidgets('the sort button orders by the criterion it is handed', (
    tester,
  ) async {
    await _openSheet(tester);
    await tester.tap(
      find.byKey(const ValueKey('exercise-goals-status-filter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('All goals'));
    await tester.pumpAndSettle();

    // Target date, the default: November before December before the met
    // September goal's… 30 Sep is the soonest deadline of the three.
    expect(
      tester.getTopLeft(_entry('g-met')).dy,
      lessThan(tester.getTopLeft(_entry('g-open')).dy),
    );

    await tester.tap(find.byKey(const ValueKey('exercise-goals-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weight'));
    await tester.pumpAndSettle();

    // Heaviest first: the multi-set goal's top rung (110) leads.
    final multi = tester.getTopLeft(_entry('g-multi')).dy;
    final open = tester.getTopLeft(_entry('g-open')).dy;
    final met = tester.getTopLeft(_entry('g-met')).dy;
    expect(multi, lessThan(open));
    expect(open, lessThan(met));
  });

  testWidgets('the New goal door is drawn only where the host offers one', (
    tester,
  ) async {
    await _openSheet(tester);
    expect(find.byKey(const ValueKey('exercise-goals-add')), findsNothing);

    await _openSheet(tester, onNewGoal: () {});
    expect(find.byKey(const ValueKey('exercise-goals-add')), findsOneWidget);
  });

  testWidgets('an exercise with no goals says so', (tester) async {
    await _openSheet(tester, goals: const []);
    expect(find.text('No goals for this exercise yet'), findsOneWidget);
    expect(find.text('0 goals'), findsOneWidget);
  });
}
