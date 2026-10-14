import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/planned_session_program.dart';
import 'package:lambda/data/models/program_block.dart';
import 'package:lambda/features/programs/view/program_detail_screen.dart';
import 'package:lambda/features/programs/viewmodel/program_detail_viewmodel.dart';

import 'support/fake_program_repos.dart';

/// The workouts that belong to no block.
///
/// Archiving a block sets its workouts' `block_id` back to NULL, and a blocked
/// program has no Workouts tab — so without this group those rows exist only in
/// the database. It is the visible half of a behaviour that was already there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bundled typefaces, for the same reason the block editor's test loads
  // them: Flutter's test font gives every glyph the same square advance, so the
  // swipe drawer's labels measure far wider than they do on a device, wrap, and
  // report an overflow the device never draws.
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
  late FakePlannedSessions workouts;
  late ProgramDetailViewModel vm;

  final unfiled = PlannedSession(
    sessionId: 'w9',
    userId: 'u1',
    name: 'Left Over',
  );

  setUp(() {
    programs = FakeProgramRepository(programs: [testProgram(usesBlocks: true)]);
    workouts = FakePlannedSessions();
    vm = ProgramDetailViewModel(
      repo: programs,
      runRepo: FakeProgramRunRepository(),
      workoutPlanRepo: workouts,
      exerciseRepo: FakeExercises(),
      lessonRepo: FakeLessons(),
      userId: 'u1',
    );
  });

  tearDown(() => vm.dispose());

  /// The Blocks tab with one block and one workout that is in none of them.
  Future<void> pump(WidgetTester tester, {required bool usesBlocks}) async {
    vm.state.value = ProgramDetailState(
      program: testProgram(usesBlocks: usesBlocks),
      blocks: usesBlocks
          ? [testBlock(blockId: 'b1', name: 'Accumulation')]
          : const <ProgramBlock>[],
      plannedWorkouts: [unfiled],
      programLinks: const [
        PlannedSessionProgram(
          plannedSessionProgramId: 'l9',
          programId: 'p1',
          plannedSessionId: 'w9',
          userId: 'u1',
        ),
      ],
      nameDraft: 'Base',
    );
    // A phone-sized surface. The harness's 800×600 is shorter than the swipe
    // drawer's buttons, so it reports a vertical overflow no device would draw.
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ProgramDetailScreen(programId: 'p1', viewModel: vm)),
    );
    await tester.pumpAndSettle();
  }

  /// Swipes the row left far enough to open its drawer. The actions are drawn
  /// behind the card at rest, so tapping one without this hits the card.
  Future<void> reveal(WidgetTester tester) async {
    await tester.drag(find.text('Left Over'), const Offset(-200, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('an unfiled workout is shown under Unfiled, with both actions',
      (tester) async {
    await pump(tester, usesBlocks: true);

    expect(find.text('Unfiled'), findsOneWidget);
    expect(find.text('Left Over'), findsOneWidget);

    await reveal(tester);

    expect(find.byIcon(Icons.drive_file_move_outline), findsOneWidget,
        reason: 'filing it into a block is the fix the group exists to offer');
    expect(find.byIcon(Icons.delete_outline), findsOneWidget,
        reason: 'and removing it from the program is the other answer — an '
            'archived block\'s leftovers are not all wanted back');
  });

  testWidgets('a simple program has no Unfiled group', (tester) async {
    await pump(tester, usesBlocks: false);

    expect(find.text('Unfiled'), findsNothing,
        reason: 'a simple program has no blocks to be unfiled from — its '
            'Workouts tab already lists every one of them');
  });

  testWidgets('filing asks which block, then moves that link', (tester) async {
    await pump(tester, usesBlocks: true);

    await reveal(tester);
    await tester.tap(find.byIcon(Icons.drive_file_move_outline));
    await tester.pumpAndSettle();

    // The sheet offers the program's blocks to choose between — by name, which
    // is the only thing the user has to go on.
    final option = find.widgetWithText(ListTile, 'Accumulation');
    expect(option, findsOneWidget);
    await tester.tap(option);
    await tester.pumpAndSettle();

    expect(workouts.assignCalls, hasLength(1));
    final call = workouts.assignCalls.single;
    expect(call.blockId, 'b1');
    expect(
      call.linkIds,
      ['l9'],
      reason: 'the link of the workout that was swiped, not the workout id — '
          'the server keys membership off the join row',
    );
    expect(call.programId, 'p1');
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
