import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/data/models/custom_exercise.dart';
import 'package:lambda/data/models/exercise_detail.dart';
import 'package:lambda/data/models/program_block.dart';
import 'package:lambda/features/programs/view/program_detail_screen.dart';
import 'package:lambda/features/programs/viewmodel/program_detail_viewmodel.dart';

import 'support/fake_program_repos.dart';

/// Where a goal can be filed, and which shape is allowed to ask.
///
/// The scope picker is the shape made visible in the Goals tab: a program with
/// blocks can hold a target that belongs to one of them, and a program without
/// them has exactly one scope — its own — so it is never offered a choice. It
/// is also the half of "blocks are made of workouts and goals" the block editor
/// does not cover: a phase's targets must be settable *before* the phase runs,
/// which is what the picker's presence with nothing running asserts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bundled typefaces: Flutter's test font gives every glyph the same
  // square advance, so the target row's weight × reps × Add measures far wider
  // than a device draws and reports an overflow the app never has.
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
  late ProgramDetailViewModel vm;

  final details = {
    'e1': const ExerciseDetail(
      exercise: CustomExercise(exerciseId: 'e1', userId: 'u1', name: 'Bench'),
    ),
  };

  setUp(() {
    programs = FakeProgramRepository();
    vm = ProgramDetailViewModel(
      repo: programs,
      runRepo: FakeProgramRunRepository(),
      workoutPlanRepo: FakePlannedSessions(),
      exerciseRepo: FakeExercises(),
      lessonRepo: FakeLessons(),
      historyRepo: FakeProgramHistoryRepository(),
      achievementsDerivation: FakeAchievementsDerivation(),
      userId: 'u1',
    );
  });

  tearDown(() => vm.dispose());

  /// The Goals tab of a program, with nothing running.
  Future<void> openGoals(
    WidgetTester tester, {
    required bool usesBlocks,
    bool withBlocks = true,
  }) async {
    final blocks = usesBlocks && withBlocks
        ? <ProgramBlock>[
            testBlock(blockId: 'b1', name: 'Accumulation', order: 1),
            testBlock(blockId: 'b2', name: 'Intensification', order: 2),
          ]
        : <ProgramBlock>[];
    vm.state.value = ProgramDetailState(
      program: testProgram(usesBlocks: usesBlocks),
      blocks: blocks,
      exerciseDetailMap: details,
      nameDraft: 'Base',
    );
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ProgramDetailScreen(programId: 'p1', viewModel: vm)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goals'));
    await tester.pumpAndSettle();
  }

  testWidgets('a blocked program offers a scope with nothing running — every '
      'block, plus the program itself', (tester) async {
    await openGoals(tester, usesBlocks: true);

    // The button is there at all with no run active: a phase's targets are
    // settable before the phase, which the old run-gated picker could not do.
    final picker = find.text('Add to: Whole program');
    expect(picker, findsOneWidget);

    await tester.tap(picker);
    await tester.pumpAndSettle();

    // Every block, in order — not only a running one, and not only the next.
    expect(find.text('Whole program'), findsOneWidget);
    expect(find.text('Accumulation'), findsOneWidget);
    expect(find.text('Intensification'), findsOneWidget);
  });

  testWidgets('a simple program is never offered a scope', (tester) async {
    await openGoals(tester, usesBlocks: false);

    expect(
      find.textContaining('Add to:'),
      findsNothing,
      reason: 'a simple program has no blocks, so every goal it holds is its '
          'own — a picker with one option is a question with one answer',
    );
  });

  testWidgets('a scoped goal is filed against the block that was picked',
      (tester) async {
    await openGoals(tester, usesBlocks: true);

    await tester.tap(find.text('Add to: Whole program'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intensification'));
    await tester.pumpAndSettle();

    // The button now says what the next goal will be filed under — the choice
    // is visible before it is made.
    expect(find.text('Add to: Intensification'), findsOneWidget);

    // Add one target, through the same picker a user would.
    await tester.tap(find.text('Add a PR target…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'reps'), '5');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(programs.createdGoals, hasLength(1));
    expect(
      programs.createdGoals.single.blockId,
      'b2',
      reason: 'the goal carries the scope it was authored under — a target '
          'filed to the program instead would be in force during every block, '
          'and a target filed to b1 would chase the wrong phase',
    );
  });

  testWidgets('the scope resets to the program when a block is archived under '
      'it', (tester) async {
    await openGoals(tester, usesBlocks: true);

    await tester.tap(find.text('Add to: Whole program'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accumulation'));
    await tester.pumpAndSettle();
    expect(find.text('Add to: Accumulation'), findsOneWidget);

    // The block goes away while the screen is open — it is archived from the
    // block editor or another device. The scope reads back through the live
    // block list, so it stops naming a phase that no longer exists.
    vm.state.value = vm.state.value.copyWith(blocks: const []);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Add to:'),
      findsNothing,
      reason: 'with no blocks left there is no scope to pick, and the stale '
          'choice must not survive as a hidden selection',
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
