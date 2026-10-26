import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/goal.dart';
import 'package:lambda/data/models/program_content.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/features/goals/view/goal_sheet.dart';
import 'package:lambda/features/programs/model/program_achievements.dart';
import 'package:lambda/shared/widgets/exercise_target_picker.dart';
import 'package:lambda/shared/widgets/glass_button.dart';

/// Multi-set goals (2026-10-26): a goal may list several rungs — "100 × 5,
/// then 110 × 3" — every one of which a session must meet with a **distinct**
/// set.
///
/// The storage rule keeps one shape per shape: a single-set goal keeps its pair
/// on `fact_goal`, a multi-set goal leaves those columns null and writes
/// `fact_goal_target` rows. [Goal.requirements] is the one reading of both, and
/// the evaluation is a bipartite match rather than a per-rung search, because
/// greedy assignment strands a hard rung behind an easy one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PastSetRow set(
    String id, {
    String exerciseId = 'bench',
    String? variationId,
    double? weight,
    int reps = 5,
    required DateTime date,
    int setNumber = 1,
  }) => PastSetRow(
    sessionExerciseSetId: id,
    sessionExerciseId: 'se-$id',
    sessionId: 'sess-$id',
    userId: 'u1',
    exerciseId: exerciseId,
    variationId: variationId,
    setNumber: setNumber,
    reps: [reps],
    weight: weight,
    sessionCreatedDate: date,
  );

  Goal goal({
    String id = 'g1',
    String? exerciseId = 'bench',
    String? variationId,
    num? weight,
    int? reps,
    List<GoalTargetSet> targets = const [],
    String? text,
  }) => Goal(
    goalId: id,
    userId: 'u1',
    text: text,
    exerciseId: exerciseId,
    variationId: variationId,
    targetWeight: weight,
    targetReps: reps,
    targets: targets,
  );

  final jan10 = DateTime(2026, 1, 10);
  final mar10 = DateTime(2026, 3, 10);
  final feb10 = DateTime(2026, 2, 10);
  final feb11 = DateTime(2026, 2, 11);
  final feb12 = DateTime(2026, 2, 12);

  group('Goal.requirements', () {
    test('a single-set goal reads its pair as one requirement', () {
      final g = goal(weight: 100, reps: 5);
      expect(g.isMultiSet, isFalse);
      expect(g.requirements, [const GoalTargetSet(weight: 100, reps: 5)]);
    });

    test('a multi-set goal reads its stored rungs', () {
      final g = goal(
        targets: const [
          GoalTargetSet(order: 1, weight: 100, reps: 5),
          GoalTargetSet(order: 2, weight: 110, reps: 3),
        ],
      );
      expect(g.isMultiSet, isTrue);
      expect(g.isExerciseGoal, isTrue);
      expect(g.requirements, hasLength(2));
      expect(g.requirements.last.weight, 110);
    });

    test('an exercise goal with no numbers has no requirements', () {
      final g = goal();
      expect(g.requirements, isEmpty);
      expect(g.isExerciseGoal, isTrue);
    });

    test('a free-text goal has no requirements', () {
      final g = goal(exerciseId: null, text: 'Get stronger');
      expect(g.requirements, isEmpty);
      expect(g.isExerciseGoal, isFalse);
    });

    test('GoalTargetSet compares by its numbers, not its position', () {
      expect(
        const GoalTargetSet(order: 1, weight: 100, reps: 5),
        const GoalTargetSet(order: 9, weight: 100, reps: 5),
      );
      expect(
        const GoalTargetSet(weight: 100, reps: 5),
        isNot(const GoalTargetSet(weight: 100, reps: 6)),
      );
      expect(
        GoalTargetSet.fromMap({
          'order': 2,
          'weight': '110',
          'reps': '3',
        }).weight,
        110,
      );
    });
  });

  group('goalWitnessSets', () {
    test('one requirement returns the earliest set that reaches it', () {
      final witnesses = goalWitnessSets(
        sets: [
          set('late', weight: 140, reps: 5, date: feb11),
          set('early', weight: 100, reps: 5, date: feb10),
        ],
        exerciseId: 'bench',
        variationId: null,
        requirements: const [GoalTargetSet(weight: 100, reps: 5)],
      );
      expect(witnesses!.single.sessionExerciseSetId, 'early');
    });

    test('a strong set that meets the easy rung first is re-paired to the hard '
        'one instead of stranding it', () {
      // Greedy in requirement order hands the only 140 set to the 100 rung,
      // and the 140 rung has nothing left. The match must re-pair.
      final witnesses = goalWitnessSets(
        sets: [
          set('heavy', weight: 140, reps: 1, date: feb10),
          set('light', weight: 100, reps: 1, date: feb11),
        ],
        exerciseId: 'bench',
        variationId: null,
        requirements: const [
          GoalTargetSet(order: 1, weight: 100, reps: 1),
          GoalTargetSet(order: 2, weight: 140, reps: 1),
        ],
      );
      expect(witnesses!.map((s) => s.sessionExerciseSetId).toSet(), {
        'heavy',
        'light',
      });
    });

    test('every rung needs its own set', () {
      final witnesses = goalWitnessSets(
        sets: [set('one', weight: 100, reps: 5, date: feb10)],
        exerciseId: 'bench',
        variationId: null,
        requirements: const [
          GoalTargetSet(order: 1, weight: 100, reps: 5),
          GoalTargetSet(order: 2, weight: 100, reps: 5),
        ],
      );
      expect(witnesses, isNull);
    });

    test('a variation is a scope of its own, null included', () {
      final paused = set(
        'paused',
        variationId: 'v-paused',
        weight: 140,
        reps: 5,
        date: feb10,
      );
      expect(
        goalWitnessSets(
          sets: [paused],
          exerciseId: 'bench',
          variationId: null,
          requirements: const [GoalTargetSet(weight: 100, reps: 5)],
        ),
        isNull,
      );
      expect(
        goalWitnessSets(
          sets: [paused],
          exerciseId: 'bench',
          variationId: 'v-paused',
          requirements: const [GoalTargetSet(weight: 100, reps: 5)],
        ),
        isNotNull,
      );
    });

    test('the window is half-open: from included, to excluded', () {
      final s = set('s', weight: 100, reps: 5, date: feb10);
      final requirements = const [GoalTargetSet(weight: 100, reps: 5)];
      expect(
        goalWitnessSets(
          sets: [s],
          exerciseId: 'bench',
          variationId: null,
          requirements: requirements,
          from: feb10,
          to: mar10,
        ),
        isNotNull,
      );
      expect(
        goalWitnessSets(
          sets: [s],
          exerciseId: 'bench',
          variationId: null,
          requirements: requirements,
          from: feb11,
        ),
        isNull,
      );
    });

    test('a set with no reps was never performed', () {
      final adopted = PastSetRow(
        sessionExerciseSetId: 'adopted',
        sessionExerciseId: 'se-adopted',
        sessionId: 'sess-adopted',
        userId: 'u1',
        exerciseId: 'bench',
        setNumber: 1,
        reps: const [],
        weight: 140,
        sessionCreatedDate: feb10,
      );
      expect(
        goalWitnessSets(
          sets: [adopted],
          exerciseId: 'bench',
          variationId: null,
          requirements: const [GoalTargetSet(weight: 100, reps: 1)],
        ),
        isNull,
      );
    });

    test('an exercise goal with no numbers is met by any performed set', () {
      final witnesses = goalWitnessSets(
        sets: [set('s', weight: 60, reps: 1, date: feb10)],
        exerciseId: 'bench',
        variationId: null,
        requirements: const [],
      );
      expect(witnesses!.single.sessionExerciseSetId, 's');
    });
  });

  group('multi-set evaluation', () {
    final requirements = const [
      GoalTargetSet(order: 1, weight: 100, reps: 5),
      GoalTargetSet(order: 2, weight: 110, reps: 3),
    ];

    test('a goal is achieved when every rung has its own set, and its '
        'evidence is the rung that finished it', () {
      final out = evaluateGoals(
        goals: [goal(targets: requirements)],
        sets: [
          set('rung1', weight: 100, reps: 5, date: feb10),
          set('rung2', weight: 110, reps: 3, date: feb12),
        ],
        from: jan10,
        to: mar10,
      ).single;

      expect(out.achieved, isTrue);
      expect(out.evidenceWeight, 110);
      expect(out.evidenceReps, 3);
      expect(out.evidenceDate, feb12);
    });

    test('one rung short is a miss, reported by the strongest set', () {
      final out = evaluateGoals(
        goals: [goal(targets: requirements)],
        sets: [
          set('rung1', weight: 100, reps: 5, date: feb10),
          set('near', weight: 108, reps: 3, date: feb12),
        ],
        from: jan10,
        to: mar10,
      ).single;

      expect(out.achieved, isFalse);
      expect(out.evidenceWeight, 108);
      expect(out.evidenceDate, feb12);
    });

    test('the badge marks every witness, and a shared set only once', () {
      final ids = goalAchievingSetIds(
        goals: [
          goal(targets: requirements),
          goal(id: 'g2', weight: 100, reps: 5),
        ],
        sets: [
          set('rung1', weight: 100, reps: 5, date: feb10),
          set('rung2', weight: 110, reps: 3, date: feb12),
        ],
      );
      expect(ids, {'rung1', 'rung2'});
    });
  });

  group('serialization', () {
    test('a frozen achievement carries its requirement list', () {
      final outcome = evaluateGoals(
        goals: [
          goal(
            targets: const [
              GoalTargetSet(order: 1, weight: 100, reps: 5),
              GoalTargetSet(order: 2, weight: 110, reps: 3),
            ],
          ),
        ],
        sets: [
          set('rung1', weight: 100, reps: 5, date: feb10),
          set('rung2', weight: 110, reps: 3, date: feb12),
        ],
        from: jan10,
        to: mar10,
      ).single;

      final map = outcome.toMap();
      expect(map['targets'], isA<List>());
      final round = GoalAchievement.fromMap(map);
      expect(round.goal.targets, hasLength(2));
      expect(
        round.goal.requirements.last,
        const GoalTargetSet(weight: 110, reps: 3),
      );
      expect(round.achieved, isTrue);
    });

    test('a single-set record writes the document it always wrote', () {
      final map = GoalAchievement(
        goal: goal(weight: 100, reps: 5),
        achieved: false,
      ).toMap();
      expect(map.containsKey('targets'), isFalse);
    });

    test('a whole achievements document round-trips its goals', () {
      final achievements = ProgramAchievements(
        from: jan10,
        until: mar10,
        goals: evaluateGoals(
          goals: [
            goal(
              targets: const [
                GoalTargetSet(order: 1, weight: 100, reps: 5),
                GoalTargetSet(order: 2, weight: 110, reps: 3),
              ],
            ),
          ],
          sets: [set('rung1', weight: 100, reps: 5, date: feb10)],
          from: jan10,
          to: mar10,
        ),
      );
      final decoded = ProgramAchievements.decode(achievements.encode())!;
      expect(decoded.goals.single.goal.targets, hasLength(2));
      expect(decoded.goals.single.achieved, isFalse);
    });

    test('ContentGoal round-trips the rungs and hands them to the model', () {
      const content = ContentGoal(
        goalId: 'g1',
        userId: 'u1',
        exerciseId: 'bench',
        targets: [
          GoalTargetSet(order: 1, weight: 100, reps: 5),
          GoalTargetSet(order: 2, weight: 110, reps: 3),
        ],
      );
      final round = ContentGoal.fromMap(content.toMap());
      expect(round.targets, hasLength(2));
      expect(round.toGoal().requirements, hasLength(2));

      final single = const ContentGoal(
        goalId: 'g2',
        userId: 'u1',
        exerciseId: 'bench',
        targetWeight: 100,
        targetReps: 5,
      );
      expect(single.toMap().containsKey('targets'), isFalse);
    });
  });

  group('labels', () {
    test('a single requirement reads exactly as the pair always did', () {
      expect(
        goalRequirementsValue(const [GoalTargetSet(weight: 100, reps: 5)]),
        '100 kg × 5',
      );
    });

    test('a list reads as rungs joined by a dot', () {
      expect(
        goalRequirementsValue(const [
          GoalTargetSet(weight: 100, reps: 5),
          GoalTargetSet(weight: 110, reps: 3),
        ]),
        '100 kg × 5 · 110 kg × 3',
      );
    });

    test('no numbers reads as nothing', () {
      expect(goalRequirementsValue(const []), '');
      expect(goalTargetsLabel('Bench', const [GoalTargetSet()]), 'Bench');
      expect(
        goalTargetsLabel('Bench', const [GoalTargetSet(weight: 100, reps: 5)]),
        'Bench — 100 kg × 5',
      );
    });
  });

  group('ExerciseTargetDraft', () {
    test('seeds, edits and clears the requirement rows', () {
      final draft = ExerciseTargetDraft();
      addTearDown(draft.dispose);
      draft.seed(
        exerciseId: 'e1',
        multiSet: true,
        targets: const [
          GoalTargetSet(order: 1, weight: 100, reps: 5),
          GoalTargetSet(order: 2, weight: 110, reps: 3),
        ],
      );

      expect(draft.multiSet, isTrue);
      expect(draft.rowCount, 2);
      expect(draft.statedTargets, const [
        GoalTargetSet(weight: 100, reps: 5),
        GoalTargetSet(weight: 110, reps: 3),
      ]);

      draft.addRow();
      expect(draft.rowCount, 3);
      draft.removeRowAt(1);
      expect(draft.rowCount, 2);
      expect(draft.statedTargets, const [GoalTargetSet(weight: 100, reps: 5)]);

      draft.reset();
      expect(draft.multiSet, isFalse);
      expect(draft.rowCount, 1);
      expect(draft.statedTargets, isEmpty);
    });

    test('a blank row is not a rung yet', () {
      final draft = ExerciseTargetDraft();
      addTearDown(draft.dispose);
      draft.seed(
        exerciseId: 'e1',
        multiSet: true,
        targets: const [GoalTargetSet(weight: 100, reps: 5)],
      );
      draft.addRow();
      expect(draft.rowCount, 2);
      expect(draft.statedTargets, hasLength(1));
    });

    test('removing the first row promotes the next into its cells', () {
      final draft = ExerciseTargetDraft();
      addTearDown(draft.dispose);
      draft.seed(
        exerciseId: 'e1',
        multiSet: true,
        targets: const [
          GoalTargetSet(weight: 100, reps: 5),
          GoalTargetSet(weight: 110, reps: 3),
        ],
      );
      draft.removeRowAt(0);
      expect(draft.rowCount, 1);
      expect(draft.weightCtrl.text, '110');
      expect(draft.repsCtrl.text, '3');
    });
  });

  // ── Widgets ──────────────────────────────────────────────────────────────

  final detailMap = {
    'bench': const ExerciseDetail(
      exercise: CustomExercise(
        exerciseId: 'bench',
        userId: 'u1',
        name: 'Bench',
      ),
    ),
  };

  Future<void> pumpPicker(
    WidgetTester tester, {
    required ExerciseTargetDraft draft,
    required Future<void> Function(ExerciseTarget target) onAdd,
    List<PastSetRow> pastSets = const [],
  }) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ExerciseTargetPicker(
              detailMap: detailMap,
              draft: draft,
              pastSets: pastSets,
              onAdd: onAdd,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a multi-set form composes one requirement per row', (
    tester,
  ) async {
    final draft = ExerciseTargetDraft();
    addTearDown(draft.dispose);
    final writes = <ExerciseTarget>[];
    await pumpPicker(
      tester,
      draft: draft,
      onAdd: (target) async => writes.add(target),
    );

    await tester.tap(find.byKey(const ValueKey('goal-exercise-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Multi-set'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('goal-set-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('goal-set-row-1')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('goal-kg-0')), '100');
    await tester.enterText(find.byKey(const ValueKey('goal-reps-0')), '5');
    await tester.tap(find.text('Add set'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('goal-kg-1')), '110');
    await tester.enterText(find.byKey(const ValueKey('goal-reps-1')), '3');

    await tester.tap(find.text('ADD'));
    await tester.pumpAndSettle();

    final target = writes.single;
    expect(target.weight, isNull, reason: 'a multi target has no single pair');
    expect(target.reps, isNull);
    expect(target.targets, const [
      GoalTargetSet(weight: 100, reps: 5),
      GoalTargetSet(weight: 110, reps: 3),
    ]);
  });

  testWidgets('the already-beat caption waits for every rung', (tester) async {
    final draft = ExerciseTargetDraft();
    addTearDown(draft.dispose);
    final pastSets = [
      set('hit1', weight: 100, reps: 5, date: feb10),
      set('hit2', weight: 110, reps: 3, date: feb12),
    ];
    await pumpPicker(
      tester,
      draft: draft,
      pastSets: pastSets,
      onAdd: (target) async {},
    );

    await tester.tap(find.byKey(const ValueKey('goal-exercise-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Multi-set'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('goal-kg-0')), '100');
    await tester.enterText(find.byKey(const ValueKey('goal-reps-0')), '5');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('goal-already-achieved')), findsOneWidget);

    await tester.tap(find.text('Add set'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('goal-kg-1')), '120');
    await tester.enterText(find.byKey(const ValueKey('goal-reps-1')), '1');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('goal-already-achieved')),
      findsNothing,
      reason: 'one unmatched rung leaves the goal standing',
    );

    await tester.enterText(find.byKey(const ValueKey('goal-kg-1')), '110');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('goal-already-achieved')), findsOneWidget);
  });

  testWidgets('a multi-set goal opens on its rungs and saves the list', (
    tester,
  ) async {
    final stored = const Goal(
      goalId: 'g1',
      userId: 'u1',
      text: 'Bench',
      exerciseId: 'e1',
      targets: [
        GoalTargetSet(order: 1, weight: 100, reps: 5),
        GoalTargetSet(order: 2, weight: 110, reps: 3),
      ],
    );
    final writes = <ExerciseTarget>[];
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showGoalSheet(
                  context,
                  goal: stored,
                  exerciseName: 'Bench',
                  detailMap: detailMap,
                  loadPastSets: () async => const [],
                  onSave: (target) async {
                    writes.add(target);
                    return Goal(
                      goalId: 'g1',
                      userId: 'u1',
                      text: target.exerciseName.isEmpty
                          ? 'Bench'
                          : target.exerciseName,
                      exerciseId: target.exerciseId,
                      variationId: target.variationId,
                      targets: target.targets,
                    );
                  },
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

    // Resting on the multi form: numbered rows, the stored rungs in their
    // cells, no toggle (the shape cannot change in a reading).
    expect(find.byKey(const ValueKey('goal-set-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('goal-set-row-1')), findsOneWidget);
    expect(find.text('Multi-set'), findsNothing);
    TextField cell(String key) =>
        tester.widget<TextField>(find.byKey(ValueKey(key)));
    expect(cell('goal-kg-0').controller!.text, '100');
    expect(cell('goal-reps-0').controller!.text, '5');
    expect(cell('goal-kg-1').controller!.text, '110');
    expect(cell('goal-reps-1').controller!.text, '3');

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('goal-reps-1')), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(GlassButton, 'SAVE'));
    await tester.pumpAndSettle();

    expect(writes, hasLength(1));
    expect(writes.single.weight, isNull);
    expect(writes.single.targets, const [
      GoalTargetSet(weight: 100, reps: 5),
      GoalTargetSet(weight: 110, reps: 2),
    ]);
  });
}
