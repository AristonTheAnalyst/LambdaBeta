import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/data/models/program.dart';
import 'package:lambda/data/models/program_block.dart';
import 'package:lambda/data/repositories/lesson_repository.dart';
import 'package:lambda/data/repositories/program_repository.dart';
import 'package:lambda/features/programs/view/program_block_editor_screen.dart';
import 'package:lambda/features/programs/viewmodel/program_detail_viewmodel.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';

/// The block editor's two length fields, and the one date they project.
///
/// The arithmetic itself is covered in `block_length_test.dart` and through the
/// real database in `integration_test/program_block_repo_test.dart`. What is
/// only testable here is the *wiring*: that the pair the user types reaches the
/// repository as a normalized length, and that `Ends` re-renders as it is
/// typed. A host widget test also fails loudly on a layout overflow, which is
/// the other thing the narrow `Weeks`/`Days` pair risks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bundled typefaces, and the reason this file checks layout at all.
  // Flutter's test font gives every glyph the same square advance, so a word
  // measures its character count × the font size — "Weeks" would come out ~70pt
  // wide in a 67.6pt box and report an overflow no device would ever draw.
  // Manrope is what [AppFonts.uiFamily] resolves to off iOS; the device draws
  // `.SF Pro`, which is a proportional face of its own and close enough in
  // width that a red overflow here means one there.
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

  /// The projection the screen must be showing, spelled the way it spells it.
  String day(DateTime d) => DateFormat('d MMM yyyy').format(d);

  /// The `TextField` inside the labelled input — `find.byType(TextField)` would
  /// find the name and notes fields too.
  Finder field(String label) => find.descendant(
        of: find.widgetWithText(LambdaInput, label),
        matching: find.byType(TextField),
      );

  Future<void> pumpEditor(
    WidgetTester tester, {
    required ProgramBlock block,
    required _FakePrograms repo,
  }) async {
    final vm = ProgramDetailViewModel(repo: repo, lessonRepo: _FakeLessons());
    vm.state.value = ProgramDetailState(
      program: Program(
        programId: 'p1',
        userId: 'u1',
        name: 'Base',
        createdDate: DateTime(2026, 1, 1),
        updatedDate: DateTime(2026, 1, 1),
      ),
      blocks: [block],
    );

    // The iPhone 17's logical size — the width the two narrow boxes have to fit
    // inside, and the width at which an overflow would actually happen.
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ProgramBlockEditorScreen(
          viewModel: vm,
          block: block.blockId.isEmpty ? null : block,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProgramBlock block({
    int? weeks,
    int? days,
    int? sessions,
    DateTime? start,
  }) =>
      ProgramBlock(
        blockId: 'b1',
        userId: 'u1',
        programId: 'p1',
        name: 'Accumulation',
        blockOrder: 1,
        targetWeeks: weeks,
        targetDays: days,
        targetSessions: sessions,
        startDate: start,
      );

  testWidgets('a weeks block opens with its days beside its weeks',
      (tester) async {
    await pumpEditor(
      tester,
      block: block(weeks: 8, days: 3, start: DateTime(2026, 10, 1)),
      repo: _FakePrograms(),
    );

    expect(tester.widget<TextField>(field('Weeks')).controller!.text, '8');
    expect(tester.widget<TextField>(field('Days')).controller!.text, '3');

    // Ends is Starts plus both halves — 59 days, not the 56 the weeks alone
    // would say. This is the whole point of the field pair.
    expect(find.text(day(DateTime(2026, 11, 29))), findsOneWidget);
  });

  testWidgets('a zero remainder is an empty Days field, not a zero',
      (tester) async {
    await pumpEditor(
      tester,
      block: block(weeks: 8, start: DateTime(2026, 10, 1)),
      repo: _FakePrograms(),
    );

    expect(tester.widget<TextField>(field('Weeks')).controller!.text, '8');
    expect(tester.widget<TextField>(field('Days')).controller!.text, '',
        reason: 'null means "no remainder" and prints as absence — a 0 would '
            'read as a value the user never entered');
    expect(find.text(day(DateTime(2026, 11, 26))), findsOneWidget);
  });

  testWidgets('typing a remainder moves Ends as it is typed', (tester) async {
    await pumpEditor(
      tester,
      block: block(weeks: 8, start: DateTime(2026, 10, 1)),
      repo: _FakePrograms(),
    );

    expect(find.text(day(DateTime(2026, 11, 26))), findsOneWidget);

    await tester.enterText(field('Days'), '3');
    await tester.pump();

    expect(find.text(day(DateTime(2026, 11, 29))), findsOneWidget,
        reason: 'the fill is live, not a surprise on save');
    expect(find.text(day(DateTime(2026, 11, 26))), findsNothing);
  });

  testWidgets('picking an end back-fills the length exactly', (tester) async {
    await pumpEditor(
      tester,
      block: block(weeks: 8, start: DateTime(2026, 10, 1)),
      repo: _FakePrograms(),
    );

    // The date field itself, not its label — only the box is tappable.
    await tester.tap(find.text(day(DateTime(2026, 11, 26))));
    await tester.pumpAndSettle();

    // 29 November is 59 days out: eight weeks and three days, exactly. The
    // weeks-only length could only have offered 26 November, and picking the
    // 29th would have been rounded back to it.
    await tester.tap(find.text('29'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(field('Weeks')).controller!.text, '8');
    expect(tester.widget<TextField>(field('Days')).controller!.text, '3');
    expect(find.text(day(DateTime(2026, 11, 29))), findsOneWidget,
        reason: 'and the field shows the day that was picked — the two fields '
            'are one value, so a pick that came back rounded would be visible '
            'here as a different date than the one tapped');
  });

  testWidgets('a sub-week length is a length', (tester) async {
    final repo = _FakePrograms();
    await pumpEditor(
      tester,
      block: block(weeks: 3, start: DateTime(2026, 10, 1)),
      repo: repo,
    );

    await tester.enterText(field('Weeks'), '0');
    await tester.enterText(field('Days'), '3');
    await tester.pump();

    expect(find.text(day(DateTime(2026, 10, 4))), findsOneWidget,
        reason: 'three days from the start — weeks may be 0 now, so the '
            'projection cannot assume a whole week');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.written['targetWeeks'], 0);
    expect(repo.written['targetDays'], 3,
        reason: 'the remainder is stored beside weeks: 0, not null — the pair '
            'is the length, and `null weeks` would mean the block has none');
  });

  testWidgets('a remainder over a week is normalized on save', (tester) async {
    final repo = _FakePrograms();
    await pumpEditor(
      tester,
      block: block(weeks: 7, start: DateTime(2026, 10, 1)),
      repo: repo,
    );

    // 6 weeks 9 days is 51 days — the same length as 7 weeks 2 days, which is
    // how the column holds it. The user types the sum in their head and the
    // save normalizes it rather than refusing it. Until then the two are one
    // number, so `Ends` projects the total while the fields still read 6 / 9.
    await tester.enterText(field('Weeks'), '6');
    await tester.enterText(field('Days'), '9');
    await tester.pump();

    expect(find.text(day(DateTime(2026, 11, 21))), findsOneWidget,
        reason: '51 days from the start, which is what 6 weeks 9 days *is* — '
            'the projection reads the total, not the weeks field');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.written['targetWeeks'], 7);
    expect(repo.written['targetDays'], 2,
        reason: 'stored as whole weeks plus a remainder in 0..6, which is the '
            'only shape the column documents and the server accepts');
  });

  testWidgets('sessions mode hides the pair and says how long it is',
      (tester) async {
    final repo = _FakePrograms();
    await pumpEditor(
      tester,
      block: block(sessions: 24, start: DateTime(2026, 10, 1)),
      repo: repo,
    );

    // The mode is read off the block, so a sessions block opens in sessions
    // mode with neither calendar field on screen.
    expect(find.widgetWithText(LambdaInput, 'Sessions'), findsOneWidget);
    expect(find.widgetWithText(LambdaInput, 'Weeks'), findsNothing);
    expect(find.widgetWithText(LambdaInput, 'Days'), findsNothing);
    expect(find.text('Ends'), findsNothing,
        reason: 'a sessions block has no calendar end at all, so the field is '
            'absent rather than empty');
  });

  testWidgets('switching to sessions clears both halves of the weeks length',
      (tester) async {
    final repo = _FakePrograms();
    await pumpEditor(
      tester,
      block: block(weeks: 8, days: 3, start: DateTime(2026, 10, 1)),
      repo: repo,
    );

    await tester.tap(find.text('Sessions'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Sessions'), '24');
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.written['targetSessions'], 24);
    expect(repo.written['clearWeeks'], isTrue);
    expect(repo.written['clearTargetDays'], isTrue,
        reason: 'days are part of the weeks length — a unit switch that cleared '
            'the weeks and left the remainder would leave a row the server '
            'rejects and nothing downstream could read');
  });
}

/// Registers a bundled typeface with the test's font collection under the
/// family name the app asks for.
Future<void> _loadFont(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final asset in assets) {
    loader.addFont(rootBundle.load(asset));
  }
  await loader.load();
}

/// Records what the editor tried to write. `noSuchMethod` covers the rest of
/// the repository: a host test has no PowerSync, so any call that reached the
/// database would be a mistake worth failing on.
class _FakePrograms implements ProgramRepository {
  final written = <String, Object?>{};

  @override
  Future<bool> updateBlock(
    String blockId, {
    String? name,
    String? notes,
    bool clearNotes = false,
    int? targetWeeks,
    int? targetDays,
    bool clearTargetDays = false,
    bool clearWeeks = false,
    int? targetSessions,
    bool clearSessions = false,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? endDate,
    bool clearEndDate = false,
  }) async {
    written.addAll({
      'targetWeeks': targetWeeks,
      'targetDays': targetDays,
      'clearTargetDays': clearTargetDays,
      'clearWeeks': clearWeeks,
      'targetSessions': targetSessions,
      'endDate': endDate,
    });
    return true;
  }

  @override
  Future<List<ProgramBlock>> fetchBlocks(String programId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Only here because `LessonRepository`'s constructor evaluates the global
/// `ps.db` — the one repository that cannot be default-constructed off-device.
class _FakeLessons implements LessonRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
