import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/planned_session_program.dart';
import 'package:lambda/data/repositories/planned_session_repository.dart';
import 'package:lambda/features/programs/view/plan_session_screen.dart';
import 'package:lambda/features/programs/view/program_block_editor_screen.dart';
import 'package:lambda/features/programs/viewmodel/program_detail_viewmodel.dart';
import 'package:lambda/shared/widgets/glass_button.dart';

import 'support/fake_program_repos.dart';

/// What the block's rows and its `+` actually do.
///
/// For a blocked program the block editor is the *only* workout surface — there
/// is no Workouts tab — so these two affordances carry the whole of "add and
/// edit this block's workouts". Both are wiring, and wiring is what breaks
/// without looking broken: a row with no `onTap` renders identically and simply
/// goes nowhere, and a link written without a `block_id` looks right on screen
/// while filing the workout somewhere the user cannot see it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bundled typefaces, for the same reason `program_block_editor_test.dart`
  // loads them: Flutter's test font gives every glyph the same square advance,
  // so the block's narrow Weeks/Days pair reports an overflow no device would
  // ever draw — and a red overflow fails the test it is drawn in.
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
  late FakeProgramRunRepository runs;
  late _RecordingWorkouts workouts;
  late ProgramDetailViewModel vm;

  setUp(() {
    programs = FakeProgramRepository(programs: [testProgram(usesBlocks: true)]);
    runs = FakeProgramRunRepository();
    workouts = _RecordingWorkouts();
    vm = ProgramDetailViewModel(
      repo: programs,
      runRepo: runs,
      workoutPlanRepo: workouts,
      exerciseRepo: FakeExercises(),
      lessonRepo: FakeLessons(),
      userId: 'u1',
    );
  });

  tearDown(() => vm.dispose());

  /// The program as the editor finds it: one block, one workout already filed
  /// into it.
  void seed() {
    vm.state.value = ProgramDetailState(
      program: testProgram(usesBlocks: true),
      blocks: [testBlock(blockId: 'b1', name: 'Accumulation')],
      plannedWorkouts: const [
        PlannedSession(sessionId: 'w1', userId: 'u1', name: 'Push'),
      ],
      programLinks: const [
        PlannedSessionProgram(
          plannedSessionProgramId: 'l1',
          programId: 'p1',
          plannedSessionId: 'w1',
          userId: 'u1',
          blockId: 'b1',
        ),
      ],
      nameDraft: 'Base',
    );
  }

  Future<void> pump(WidgetTester tester) async {
    seed();
    // A real phone's height, not the 800×600 the harness defaults to: the
    // block's row list sits well below the fold on that tiny surface, and a
    // tap that never lands proves nothing about the row.
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ProgramBlockEditorScreen(
          viewModel: vm,
          block: testBlock(blockId: 'b1', name: 'Accumulation'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The `+` beside the Workouts heading. Its label is empty by design, so the
  /// icon is the identifier — and the goals section has a `+` of its own.
  Finder addButton() => find.byWidgetPredicate(
        (w) => w is GlassButton && w.icon == Icons.add && w.label.isEmpty,
      );

  testWidgets('a workout row opens that workout in the editor', (tester) async {
    await pump(tester);
    expect(find.text('Push'), findsOneWidget);

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();

    expect(
      find.byType(PlanSessionScreen),
      findsOneWidget,
      reason: 'the block editor is the only way into a blocked program\'s '
          'workout contents — a row that renders but does not open leaves the '
          'whole program uneditable',
    );
    expect(vm.editor.state.value.editingWorkout?.sessionId, 'w1',
        reason: 'the row that was tapped is the workout that opened, not just '
            'any workout');
  });

  testWidgets('"New workout" files the new workout into this block',
      (tester) async {
    await pump(tester);

    await tester.tap(addButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('New workout'));
    await tester.pumpAndSettle();

    expect(workouts.createdLinks, hasLength(1));
    final link = workouts.createdLinks.single;
    expect(
      link.blockId,
      'b1',
      reason: 'the link is created with the block already on it. A blocked '
          'program has no Workouts tab, so a link left at block_id = NULL is a '
          'workout with nowhere to appear — and assigning it afterwards would '
          'be a second write racing the first',
    );
    expect(link.programId, 'p1');
    expect(link.plannedSessionId, workouts.createdSessions.single);
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

/// One recorded `createProgramLink` call — the write D13 is about.
typedef _CreatedLink = ({
  String programId,
  String plannedSessionId,
  int? sequenceOrder,
  String? blockId,
});

/// Answers the editor's create path and records it. Everything else — the
/// normalizing reads, the history read — is left to `noSuchMethod`, because a
/// host test has no PowerSync and the editor already treats those as best-effort.
class _RecordingWorkouts implements PlannedSessionRepository {
  final createdSessions = <String>[];
  final createdLinks = <_CreatedLink>[];

  @override
  Future<PlannedSession> createPlannedSession(
    String userId, {
    String? name,
    String? notes,
  }) async {
    final id = 'w${createdSessions.length + 2}';
    createdSessions.add(id);
    return PlannedSession(sessionId: id, userId: userId, name: name ?? '');
  }

  @override
  Future<PlannedSessionProgram> createProgramLink(
    String userId, {
    required String programId,
    required String plannedSessionId,
    int? sequenceOrder,
    String? blockId,
    int? dayOfWeek,
    int? weekOffset,
  }) async {
    createdLinks.add((
      programId: programId,
      plannedSessionId: plannedSessionId,
      sequenceOrder: sequenceOrder,
      blockId: blockId,
    ));
    return PlannedSessionProgram(
      plannedSessionProgramId: 'l${createdLinks.length}',
      programId: programId,
      plannedSessionId: plannedSessionId,
      userId: userId,
      sequenceOrder: sequenceOrder,
      blockId: blockId,
    );
  }

  @override
  Future<List<PlannedSession>> fetchPlannedSessions(
    String userId, {
    String? programId,
    String? blockId,
  }) async =>
      const [];

  @override
  Future<List<PlannedSessionProgram>> fetchProgramLinks(
    String programId, {
    String? blockId,
  }) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
