import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/goal.dart';
import 'package:lambda/data/models/session_exercise_set.dart';
import 'package:lambda/features/goals/view/goals_screen.dart';
import 'package:lambda/features/goals/viewmodel/goals_viewmodel.dart';

import 'support/fake_program_repos.dart';
import 'support/fake_session_repository.dart';

/// The goals library — every target the user is chasing, and the picker.
///
/// Goals live by themselves (2026-10-08): unattached, in the Library beside
/// Reviews, in force everywhere the exercise is trained. This replaced the
/// program's Goals tab, so the retired tab's test came with it — the add still
/// writes the user's own goal, on no scope — and the row behaviours the list
/// added are new: a lifetime standing, a tap that opens the sheet, and a ×
/// that deletes without being the row.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bundled typefaces: Flutter's test font gives every glyph the same
  // square advance, so rows and the target picker measure far wider than a
  // device draws them.
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

  late FakeProgramRepository programs;
  late FakeExercises exercises;
  late FakeSessionRepository sessions;
  late GoalsViewModel vm;

  final details = {
    'e1': const ExerciseDetail(
      exercise: CustomExercise(exerciseId: 'e1', userId: 'u1', name: 'Bench'),
    ),
  };

  Goal bench({String? description}) => Goal(
    goalId: 'g1',
    userId: 'u1',
    // The label's fallback — a goal outlives the exercise it names.
    text: 'Bench',
    description: description,
    exerciseId: 'e1',
    targetWeight: 100,
    targetReps: 5,
  );

  PastSetRow setRow({
    required String id,
    required String date,
    double? weight,
    List<num>? reps,
    String exerciseId = 'e1',
    String? variationId,
  }) => PastSetRow(
    sessionExerciseSetId: id,
    sessionExerciseId: 'se-$id',
    sessionId: 's-$id',
    userId: 'u1',
    exerciseId: exerciseId,
    variationId: variationId,
    setNumber: 1,
    weight: weight,
    reps: reps ?? const [5],
    sessionCreatedDate: DateTime.parse(date),
  );

  setUp(() {
    programs = FakeProgramRepository(goals: [bench()]);
    exercises = FakeExercises()..details = details;
    sessions = FakeSessionRepository();
    vm = GoalsViewModel(
      programRepository: programs,
      exerciseRepository: exercises,
      sessionRepository: sessions,
      userId: 'u1',
    );
  });

  tearDown(() => vm.dispose());

  Future<void> pumpGoals(WidgetTester tester) async {
    // The injected view model is not loaded by the screen — a host test owns
    // the state it hands in.
    await vm.load();
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: GoalsScreen(viewModel: vm)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders each goal with its lifetime standing', (tester) async {
    // A set that met the target, heavier than it — the interesting hit.
    sessions.timeline = [
      setRow(id: 's1', date: '2026-03-05', weight: 105, reps: [5]),
    ];
    await pumpGoals(tester);

    // The row is its name and its target as two elements (2026-10-10), never
    // the dash-joined string.
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('100 kg × 5 reps'), findsOneWidget);
    expect(find.text('Bench — 100 kg × 5 reps'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('Hit · 105 kg × 5 · 5 Mar'), findsOneWidget);
  });

  testWidgets('a goal nothing has met says so, rather than showing zeroes', (
    tester,
  ) async {
    await pumpGoals(tester);

    expect(find.text('Not attempted yet'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('an empty library says what a goal is', (tester) async {
    programs.goals = [];
    await pumpGoals(tester);

    expect(
      find.text("No goals set — add a PR target you'd like to hit."),
      findsOneWidget,
    );
  });

  testWidgets('adding a target writes the user\'s own goal, on no scope', (
    tester,
  ) async {
    programs.goals = [];
    await pumpGoals(tester);

    // Add one target, through the same picker a user would.
    await tester.tap(find.text('Add a PR target…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'kg'), '100');
    await tester.enterText(find.widgetWithText(TextField, 'reps'), '5');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(programs.createdGoals, hasLength(1));
    final goal = programs.createdGoals.single;
    expect(
      goal.programId,
      isNull,
      reason: 'a goal is a set to beat — filing it to a program would put it '
          'in force during runs it has nothing to do with',
    );
    expect(goal.blockId, isNull);
    expect(goal.text, 'Bench');

    // ...and it shows up in the list it was added from, with no reload: the
    // reload after a create reads the same library the list displays.
    expect(find.text('100 kg × 5 reps'), findsOneWidget);
  });

  testWidgets('the × deletes the goal and does not open the sheet', (
    tester,
  ) async {
    await pumpGoals(tester);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(programs.deletedGoals, ['g1']);
    expect(find.text('100 kg × 5 reps'), findsNothing);
    expect(
      find.text('NOTES'),
      findsNothing,
      reason: 'the × is the delete, not the row — one does not mean the other',
    );
  });

  testWidgets('tapping a goal opens its sheet, and typing reaches the repo', (
    tester,
  ) async {
    await pumpGoals(tester);

    await tester.tap(find.text('Bench'));
    await tester.pumpAndSettle();
    expect(find.text('NOTES'), findsOneWidget);

    await tester.tap(find.text('Add a note…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Beltless, pause on the chest',
    );
    await tester.pumpAndSettle();

    expect(programs.goalDescriptionWrites, [
      (goalId: 'g1', description: 'Beltless, pause on the chest'),
    ]);
    expect(
      vm.state.value.goals.single.description,
      'Beltless, pause on the chest',
      reason: 'the row mirrors the write, so the next open shows the notes',
    );
  });
}

/// Registers a bundled typeface under the family name the app asks for.
Future<void> _loadFont(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final asset in assets) {
    loader.addFont(rootBundle.load(asset));
  }
  await loader.load();
}
