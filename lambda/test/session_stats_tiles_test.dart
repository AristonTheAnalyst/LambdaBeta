import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/features/session/view/session_stats_bar.dart';

/// The session bar's three doors (2026-10-22, reworked 2026-10-27): the
/// trophy, the goals bullseye and the note. The trophy and the note carry no
/// number — their colour says whether the feed behind them has anything —
/// while the bullseye keeps the exercise's open-goal count.
///
/// A door is the app's neutral glass until it has something to say, then the
/// accent: PRs gained (the whole shelf on the planner), open goals standing,
/// notes carried. The count never decides doorness — the sheets hold the
/// exercise's whole story, so a `0` still opens. A null handler — no exercise
/// on the card — is the quiet surface fallback.
///
/// Drawn at the live session's 402pt width, where the three doors share the
/// row with the undo/redo boxes and the star.

Future<void> _pumpTiles(
  WidgetTester tester, {
  int prCount = 0,
  int lessonCount = 0,
  int goalCount = 0,
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
              goalCount: goalCount,
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

/// The glass a control wears — the same `withAlpha(77)` border `glassBox`
/// draws.
Color _edge(WidgetTester tester, String key) {
  final decoration =
      tester.widget<Container>(find.byKey(ValueKey(key))).decoration!
          as BoxDecoration;
  return (decoration.border! as Border).top.color;
}

Color? _ink(WidgetTester tester, String key) =>
    tester.widget<Icon>(_inTile(key, find.byType(Icon))).color;

void main() {
  testWidgets('the doors draw their glyphs, and only the bullseye carries a '
      'number', (tester) async {
    await _pumpTiles(
      tester,
      prCount: 12,
      lessonCount: 3,
      goalCount: 2,
      onPrTap: () {},
      onLessonTap: () {},
      onGoalTap: () {},
    );

    expect(
      _inTile('session-prs-tile', find.byIcon(Icons.emoji_events)),
      findsOneWidget,
    );
    expect(
      _inTile('session-goals-button', find.byIcon(Icons.track_changes)),
      findsOneWidget,
    );
    expect(
      _inTile(
        'session-lessons-tile',
        find.byIcon(Icons.sticky_note_2_outlined),
      ),
      findsOneWidget,
    );

    // The open-goal count is the row's only number (2026-10-27).
    expect(_inTile('session-goals-button', find.text('2')), findsOneWidget);
    expect(find.text('+12'), findsNothing);
    expect(find.text('+3'), findsNothing);
    expect(find.text('12'), findsNothing);
    expect(find.text('3'), findsNothing);

    // One row of 48pt controls, and the line must not overflow.
    expect(
      tester.getSize(find.byKey(const ValueKey('session-prs-tile'))).height,
      48,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a door is neutral until it has something behind it', (
    tester,
  ) async {
    await _pumpTiles(
      tester,
      onPrTap: () {},
      onLessonTap: () {},
      onGoalTap: () {},
    );

    // Nothing gained, nothing open, nothing written: white glass.
    expect(_edge(tester, 'session-prs-tile'), AppColors.primary.withAlpha(77));
    expect(
      _edge(tester, 'session-goals-button'),
      AppColors.primary.withAlpha(77),
    );
    expect(
      _edge(tester, 'session-lessons-tile'),
      AppColors.primary.withAlpha(77),
    );
    expect(_ink(tester, 'session-prs-tile'), AppColors.primary);
    expect(_ink(tester, 'session-lessons-tile'), AppColors.primary);

    await _pumpTiles(
      tester,
      prCount: 2,
      lessonCount: 1,
      goalCount: 3,
      onPrTap: () {},
      onLessonTap: () {},
      onGoalTap: () {},
    );

    // Each turns accent on its own count — the trio the bar's floor reads
    // (2026-10-27).
    expect(_edge(tester, 'session-prs-tile'), AppColors.accent.withAlpha(77));
    expect(
      _edge(tester, 'session-goals-button'),
      AppColors.accent.withAlpha(77),
    );
    expect(
      _edge(tester, 'session-lessons-tile'),
      AppColors.accent.withAlpha(77),
    );
    expect(_ink(tester, 'session-goals-button'), AppColors.accent);
    expect(_ink(tester, 'session-lessons-tile'), AppColors.accent);
  });

  testWidgets('one lit door does not light its neighbours', (tester) async {
    await _pumpTiles(
      tester,
      prCount: 3,
      onPrTap: () {},
      onLessonTap: () {},
      onGoalTap: () {},
    );

    expect(_edge(tester, 'session-prs-tile'), AppColors.accent.withAlpha(77));
    expect(
      _edge(tester, 'session-goals-button'),
      AppColors.primary.withAlpha(77),
    );
    expect(
      _edge(tester, 'session-lessons-tile'),
      AppColors.primary.withAlpha(77),
    );
  });

  testWidgets('every door opens at any count', (tester) async {
    var prTaps = 0;
    var lessonTaps = 0;
    var goalTaps = 0;
    await _pumpTiles(
      tester,
      onPrTap: () => prTaps++,
      onLessonTap: () => lessonTaps++,
      onGoalTap: () => goalTaps++,
    );

    await tester.tap(find.byKey(const ValueKey('session-prs-tile')));
    await tester.pump();
    expect(prTaps, 1);

    // "0" is the absence reading, but the doors still open the exercise's
    // whole story — the PR Lab's own rule (2026-10-23).
    expect(_inTile('session-goals-button', find.text('0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('session-goals-button')));
    await tester.pump();
    expect(goalTaps, 1);

    await tester.tap(find.byKey(const ValueKey('session-lessons-tile')));
    await tester.pump();
    expect(lessonTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a null handler — no exercise on the card — draws the quiet '
      'tile', (tester) async {
    await _pumpTiles(tester);

    // The no-exercise fallback is the only solid state left: surface fill,
    // no tap.
    final quiet =
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('session-prs-tile')),
                )
                .decoration!
            as BoxDecoration;
    expect(quiet.color, AppColors.surfaceHigh);
    await tester.tap(find.byKey(const ValueKey('session-prs-tile')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the bullseye is drawn only where there is a goal door', (
    tester,
  ) async {
    await _pumpTiles(tester, onPrTap: () {}, onLessonTap: () {});
    expect(find.byKey(const ValueKey('session-goals-button')), findsNothing);

    // A friend's or athlete's record passes no goal door: the write behind
    // it would file under their id (2026-10-26).
    await _pumpTiles(
      tester,
      goalCount: 4,
      onPrTap: () {},
      onLessonTap: () {},
      onGoalTap: () {},
    );
    expect(find.byKey(const ValueKey('session-goals-button')), findsOneWidget);
    expect(_inTile('session-goals-button', find.text('4')), findsOneWidget);
  });

  testWidgets('a plan reads its shelves plainly — still doors, never a gain', (
    tester,
  ) async {
    var prTaps = 0;
    await _pumpTiles(
      tester,
      prCount: 12,
      lessonCount: 3,
      goalCount: 2,
      gain: false,
      onPrTap: () => prTaps++,
      onLessonTap: () {},
      onGoalTap: () {},
    );

    // A plan gained nothing, so no reading may claim a session gain.
    expect(find.text('+12'), findsNothing);
    expect(find.text('+3'), findsNothing);
    expect(_inTile('session-goals-button', find.text('2')), findsOneWidget);

    // Doorness does not change with the reading: the doors still open.
    await tester.tap(find.byKey(const ValueKey('session-prs-tile')));
    await tester.pump();
    expect(prTaps, 1);
    expect(tester.takeException(), isNull);
  });
}
