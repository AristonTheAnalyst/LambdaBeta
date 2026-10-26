import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/features/session/view/session_stats_bar.dart';

/// The session bar's two doors (2026-10-22): a trophy and a book, each with
/// the session's count — "+2" for a gain, "0" when the session added none
/// (never "+0"). The count never decides doorness (2026-10-23): the sheets
/// behind the tiles hold the exercise's whole story, so a `0` still opens
/// them. A null handler — no exercise on the card — is the quiet fallback.
/// Drawn at the live session's 402pt width, where two tiles share the row
/// with the undo/redo boxes and the pencil. The planner asks for the same
/// tiles with `gain: false` (2026-10-26): no session to have gained anything
/// in, so the counts are the whole shelves behind them.

Future<void> _pumpTiles(
  WidgetTester tester, {
  required int prCount,
  required int lessonCount,
  bool gain = true,
  VoidCallback? onPrTap,
  VoidCallback? onLessonTap,
  VoidCallback? onGoalTap,
}) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 402,
            child: SessionStatsTiles(
              prCount: prCount,
              lessonCount: lessonCount,
              gain: gain,
              onPrTap: onPrTap,
              onLessonTap: onLessonTap,
              onGoalTap: onGoalTap,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inTile(String key, Finder matching) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: matching);

void main() {
  testWidgets('each tile draws its glyph and its session gain at 402', (
    tester,
  ) async {
    await _pumpTiles(tester, prCount: 12, lessonCount: 3);

    expect(_inTile('session-prs-tile', find.text('+12')), findsOneWidget);
    expect(_inTile('session-lessons-tile', find.text('+3')), findsOneWidget);
    expect(
      _inTile('session-prs-tile', find.byIcon(Icons.emoji_events)),
      findsOneWidget,
    );
    expect(
      _inTile(
        'session-lessons-tile',
        find.byIcon(Icons.sticky_note_2_outlined),
      ),
      findsOneWidget,
    );

    // One row of 48pt controls (the floor's squares), and a two-digit count
    // must not overflow.
    expect(
      tester.getSize(find.byKey(const ValueKey('session-prs-tile'))).height,
      48,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('both tiles are doors at any count', (tester) async {
    var prTaps = 0;
    var lessonTaps = 0;
    await _pumpTiles(
      tester,
      prCount: 2,
      lessonCount: 0,
      onPrTap: () => prTaps++,
      onLessonTap: () => lessonTaps++,
    );

    await tester.tap(find.byKey(const ValueKey('session-prs-tile')));
    await tester.pump();
    expect(prTaps, 1);

    // "0" is the absence reading, but the book still opens the exercise's
    // whole lesson history — the PR Lab's own rule (2026-10-23).
    expect(_inTile('session-lessons-tile', find.text('0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('session-lessons-tile')));
    await tester.pump();
    expect(lessonTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a null handler — no exercise on the card — draws the quiet '
      'tile', (tester) async {
    await _pumpTiles(tester, prCount: 0, lessonCount: 0);

    // The no-exercise fallback is the only quiet state left: surface fill,
    // no tap.
    final quiet = tester.widget<Container>(
      find.byKey(const ValueKey('session-prs-tile')),
    );
    expect((quiet.decoration! as BoxDecoration).color, AppColors.surfaceHigh);
    await tester.tap(find.byKey(const ValueKey('session-prs-tile')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a session with no gains reads 0 and 0, never +0', (
    tester,
  ) async {
    await _pumpTiles(tester, prCount: 0, lessonCount: 0);
    expect(_inTile('session-prs-tile', find.text('0')), findsOneWidget);
    expect(_inTile('session-lessons-tile', find.text('0')), findsOneWidget);
    expect(find.text('+0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a plan reads its shelves plain — never a gain, still doors', (
    tester,
  ) async {
    var prTaps = 0;
    await _pumpTiles(
      tester,
      prCount: 12,
      lessonCount: 3,
      gain: false,
      onPrTap: () => prTaps++,
      onLessonTap: () {},
    );

    // A plan gained nothing: the number is the exercise's whole shelf, so it
    // stands plain — "+12" would claim these are this plan's additions.
    expect(_inTile('session-prs-tile', find.text('12')), findsOneWidget);
    expect(_inTile('session-lessons-tile', find.text('3')), findsOneWidget);
    expect(find.text('+12'), findsNothing);
    expect(find.text('+3'), findsNothing);

    // The doorness rule does not change with the reading: both still open.
    await tester.tap(find.byKey(const ValueKey('session-prs-tile')));
    await tester.pump();
    expect(prTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the goals bullseye rides the row only when there is a door', (
    tester,
  ) async {
    var goalTaps = 0;
    await _pumpTiles(
      tester,
      prCount: 1,
      lessonCount: 1,
      onPrTap: () {},
      onLessonTap: () {},
      onGoalTap: () => goalTaps++,
    );

    // The bullseye stands between the PRs tile and the note's, in the
    // success glass a met goal wears (2026-10-26).
    final bullseye = find.byKey(const ValueKey('session-goals-button'));
    expect(bullseye, findsOneWidget);
    expect(
      tester.getCenter(bullseye).dx,
      greaterThan(
        tester.getCenter(find.byKey(const ValueKey('session-prs-tile'))).dx,
      ),
    );
    expect(
      tester.getCenter(bullseye).dx,
      lessThan(
        tester.getCenter(find.byKey(const ValueKey('session-lessons-tile'))).dx,
      ),
    );
    await tester.tap(bullseye);
    await tester.pump();
    expect(goalTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the planner — no goal data — draws no bullseye', (tester) async {
    await _pumpTiles(
      tester,
      prCount: 12,
      lessonCount: 3,
      gain: false,
      onPrTap: () {},
      onLessonTap: () {},
    );
    expect(find.byKey(const ValueKey('session-goals-button')), findsNothing);
  });
}
