import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_fonts.dart';
import 'package:lambda/data/models/planned_session.dart';
import 'package:lambda/data/models/program_review.dart';
import 'package:lambda/features/reviews/view/reviews_screen.dart';
import 'package:lambda/features/reviews/viewmodel/reviews_viewmodel.dart';
import 'package:lambda/shared/widgets/swipe_actions.dart';

import 'support/fake_program_repos.dart';
import 'support/readable_text.dart';

/// The reviews library's destructive verbs: an open pass can be cancelled, and
/// a completed record deleted — each with its own question.
///
/// The open row is a walk already started and the completed one is the record
/// it left, so either swipe is a question rather than a delete — the screen's
/// whole job here is the order: reveal, ask, and only then write.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bundled typefaces: Flutter's test font gives every glyph the same
  // square advance, so cards measure far wider than a device draws them.
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

  late FakeProgramHistoryRepository history;
  late FakePlannedSessions planned;
  late FakeProgramRepository programs;
  late FakeExercises exercises;
  late ReviewsViewModel vm;

  ProgramReview review({
    required String id,
    DateTime? completedDate,
    String? title,
  }) => ProgramReview(
    reviewId: id,
    userId: 'u1',
    sessionIdsJson: jsonEncode(['s1']),
    title: title,
    kind: kReviewKindReview,
    completedDate: completedDate,
    outcome: completedDate == null ? null : kOutcomeReviewed,
    createdDate: DateTime(2026, 1, 1),
  );

  setUp(() {
    history = FakeProgramHistoryRepository();
    planned = FakePlannedSessions();
    programs = FakeProgramRepository();
    exercises = FakeExercises();
    vm = ReviewsViewModel(
      userId: 'u1',
      historyRepository: history,
      plannedRepository: planned,
      programRepository: programs,
      exerciseRepository: exercises,
    );
  });

  tearDown(() => vm.dispose());

  Future<void> pumpReviews(WidgetTester tester) async {
    planned.reviewableRows = [
      (
        session: const PlannedSession(
          sessionId: 's1',
          userId: 'u1',
          name: 'push day',
        ),
        lastLogged: null,
        finished: 0,
        lastReview: null,
      ),
    ];
    // The injected view model is not loaded by the screen — a host test owns
    // the state it hands in.
    await vm.load();
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ReviewsScreen(viewModel: vm)));
    await tester.pumpAndSettle();
  }

  testWidgets('search reads the workouts a pass covers, not only its title', (
    tester,
  ) async {
    history.reviews = [
      review(id: 'r1', title: 'Mid block'),
      review(
        id: 'r2',
        title: 'Block 1 review',
        completedDate: DateTime(2026, 2, 5),
      ),
    ];
    await pumpReviews(tester);

    // Neither title says "push" — the covered workout's name does.
    await tester.enterText(find.byType(TextField), 'push');
    await tester.pumpAndSettle();
    expect(find.text('Mid block'), findsOneWidget);
    expect(find.text('Block 1 review'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nothing');
    await tester.pumpAndSettle();
    expect(find.text('No reviews match "nothing".'), findsOneWidget);
    expect(find.text('Mid block'), findsNothing);
  });

  testWidgets('the date filter narrows the records, never an open pass', (
    tester,
  ) async {
    final now = DateTime.now();
    history.reviews = [
      review(id: 'r1', title: 'Mid block'),
      review(
        id: 'r2',
        title: 'Recent pass',
        completedDate: now.subtract(const Duration(days: 2)),
      ),
      review(
        id: 'r3',
        title: 'Old pass',
        completedDate: now.subtract(const Duration(days: 400)),
      ),
    ];
    await pumpReviews(tester);

    await tester.tap(find.byIcon(Icons.date_range_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1M'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Recent pass'), findsOneWidget);
    expect(find.text('Old pass'), findsNothing);
    expect(
      find.text('Mid block'),
      findsOneWidget,
      reason:
          'an open pass is current work, not history — a date window '
          'narrows the records only',
    );
  });

  testWidgets('swiping an open card asks first, and keeping deletes nothing', (
    tester,
  ) async {
    history.reviews = [review(id: 'r1', title: 'Mid block')];
    await pumpReviews(tester);

    await tester.drag(find.text('Mid block'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Cancel this review?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Keep reviewing'));
    await tester.pumpAndSettle();

    expect(
      history.deletedReviews,
      isEmpty,
      reason:
          'the swipe only reveals the verb — the dialog is what '
          'decides, and a kept review is never written away',
    );
    expect(find.text('Mid block'), findsOneWidget);
  });

  testWidgets('a confirmed cancel deletes the row and the card leaves', (
    tester,
  ) async {
    history.reviews = [review(id: 'r1', title: 'Mid block')];
    await pumpReviews(tester);

    await tester.drag(find.text('Mid block'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel review'));
    await tester.pumpAndSettle();

    expect(history.deletedReviews, ['r1']);
    // The reload that follows the write is what takes the card off: the list
    // shows what the row now is, not what the screen remembered.
    expect(find.text('Mid block'), findsNothing);
    expect(find.text('IN PROGRESS'), findsNothing);
  });

  testWidgets('both halves own a drawer', (tester) async {
    history.reviews = [
      review(id: 'r1', title: 'Mid block'),
      review(
        id: 'r2',
        title: 'Block 1 review',
        completedDate: DateTime(2026, 2, 5),
      ),
    ];
    await pumpReviews(tester);

    // One drawer per row. A shut drawer's action sits in the tree at zero
    // opacity, so "which card owns a drawer" is the ancestor question, not
    // whether the label is anywhere on screen.
    expect(find.byType(SwipeActions), findsNWidgets(2));
    expect(
      find.ancestor(
        of: find.text('Block 1 review'),
        matching: find.byType(SwipeActions),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Mid block'),
        matching: find.byType(SwipeActions),
      ),
      findsOneWidget,
    );
  });

  testWidgets('swiping a completed card asks first, and keeping deletes '
      'nothing', (tester) async {
    history.reviews = [
      review(
        id: 'r2',
        title: 'Block 1 review',
        completedDate: DateTime(2026, 2, 5),
      ),
    ];
    await pumpReviews(tester);

    await tester.drag(find.text('Block 1 review'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Delete this review?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Keep it'));
    await tester.pumpAndSettle();

    expect(
      history.deletedCompletedReviews,
      isEmpty,
      reason:
          'the swipe only reveals the verb — the dialog is what '
          'decides, and a kept record is never written away',
    );
    expect(find.text('Block 1 review'), findsOneWidget);
  });

  testWidgets('a confirmed delete removes the record and the card leaves', (
    tester,
  ) async {
    history.reviews = [
      review(
        id: 'r2',
        title: 'Block 1 review',
        completedDate: DateTime(2026, 2, 5),
      ),
    ];
    await pumpReviews(tester);

    await tester.drag(find.text('Block 1 review'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete review'));
    await tester.pumpAndSettle();

    expect(history.deletedCompletedReviews, ['r2']);
    // The reload that follows the write is what takes the card off: the list
    // shows what the row now is, not what the screen remembered.
    expect(find.text('Block 1 review'), findsNothing);
    expect(find.text('COMPLETED'), findsNothing);
  });

  testWidgets('the reviews list draws readable ink and type', (tester) async {
    await pumpReviews(tester);
    expectReadableText(tester, find.byType(MaterialApp));
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
