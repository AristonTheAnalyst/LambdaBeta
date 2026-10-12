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

/// The reviews library's destructive verb: an open pass can be cancelled, and
/// only an open one.
///
/// The row is a walk already started, so the swipe is a question rather than a
/// delete — the screen's whole job here is the order: reveal, ask, and only
/// then write. The completed half has no drawer at all: a record is not
/// something a list takes back.
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

  testWidgets('swiping an open card asks first, and keeping deletes nothing',
      (tester) async {
    history.reviews = [review(id: 'r1', title: 'Mid block')];
    await pumpReviews(tester);

    await tester.drag(find.text('Mid block'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Cancel this review?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Keep reviewing'));
    await tester.pumpAndSettle();

    expect(history.deletedReviews, isEmpty,
        reason: 'the swipe only reveals the verb — the dialog is what '
            'decides, and a kept review is never written away');
    expect(find.text('Mid block'), findsOneWidget);
  });

  testWidgets('a confirmed cancel deletes the row and the card leaves',
      (tester) async {
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

  testWidgets('a completed card has no drawer — a record is not taken back',
      (tester) async {
    history.reviews = [
      review(id: 'r1', title: 'Mid block'),
      review(
        id: 'r2',
        title: 'Block 1 review',
        completedDate: DateTime(2026, 2, 5),
      ),
    ];
    await pumpReviews(tester);

    // One drawer, on the open row alone. A shut drawer's action sits in the
    // tree at zero opacity, so "which card owns a drawer" is the ancestor
    // question, not whether the label is anywhere on screen.
    expect(find.byType(SwipeActions), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Block 1 review'),
        matching: find.byType(SwipeActions),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.text('Mid block'),
        matching: find.byType(SwipeActions),
      ),
      findsOneWidget,
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
