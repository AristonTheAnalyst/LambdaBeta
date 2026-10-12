import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/widgets/dropdown_select.dart';
import 'package:lambda/shared/widgets/session_exercise_card.dart';
import 'package:lambda/shared/widgets/session_set_row.dart';

/// Holding a set number to move the row.
///
/// The gesture has to survive the row it is attached to: a set row carries
/// [SwipeActions]' horizontal drag, so the handle is a LONG press — a swipe
/// that starts moving before the hold completes must still reveal
/// Duplicate/Delete, and only a hold may lift the row. The move itself is
/// reported by the card, and only by a card that was given somewhere to
/// report it: a read-only surface draws the same rows with nothing draggable.
void main() {
  /// One reorderable row. Planned mode keeps the row free of live-session
  /// machinery (PR accents, ghost targets) that the gesture has nothing to do
  /// with.
  SessionSetRow row(String id, int index, {int? dragIndex}) => SessionSetRow(
    key: ValueKey(id),
    mode: SetRowMode.planned,
    exerciseId: 'ex-bench',
    displayIndex: index + 1,
    isDraft: false,
    dragIndex: dragIndex,
    initialWeightText: '60',
    initialRepsText: '5',
    initialVariationId: null,
    hasNotes: false,
    onCommit: (_, _) async {},
    onVariationChanged: (_) {},
    onNotesSave: (_) {},
    onDelete: () async {},
    onDuplicate: () {},
    variationOptions: const [
      DropdownOption<String?>(label: 'No Variation', value: null),
    ],
    allVariations: const [],
    findSimilarVariations: (_) => const [],
    submitNewVariation: (name, {required exerciseId, useExistingId}) async =>
        null,
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    required List<Widget> rows,
    void Function(int, int)? onReorderSets,
  }) => tester.pumpWidget(
    MaterialApp(
      // Half-scale text. The test font's glyphs are far wider than the real
      // one's, which wraps the 64pt action labels onto three lines — an
      // overflow Flutter only reports when the drawer paints, i.e. only while
      // a swipe is under test. Scaling the text keeps the labels on one line
      // and the rows exactly as tall as they ship.
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.5)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SessionExerciseCard(
                exerciseNames: const ['Bench Press'],
                activeIndex: 0,
                onSelect: (_) {},
                rows: rows,
                onReorderSets: onReorderSets,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// How far the drawer over a row's actions has opened — 0 while the row is
  /// at rest.
  double drawerOpacity(WidgetTester tester) => tester
      .widget<Opacity>(
        find
            .ancestor(of: find.text('Delete'), matching: find.byType(Opacity))
            .first,
      )
      .opacity;

  /// Holds [from] past the long-press delay, then walks it [dy] pixels down in
  /// small steps and lets go.
  ///
  /// The hold comes first, and nothing may move during it: the handle's
  /// recognizer is the delayed one, so movement before the hold completes is a
  /// swipe and stays one. The walk is stepped because the sliver re-reads its
  /// own layout on every update — one long jump lands the row somewhere else
  /// than a finger would.
  Future<void> holdAndDrag(WidgetTester tester, Offset from, double dy) async {
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 600));
    for (var walked = 0.0; walked < dy - 0.01; walked += dy / 8) {
      await gesture.moveBy(Offset(0, dy / 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// The distance between two stacked rows — what a drag is measured against.
  double rowPitch(WidgetTester tester) =>
      tester.getTopLeft(find.byType(SessionSetRow).at(1)).dy -
      tester.getTopLeft(find.byType(SessionSetRow).at(0)).dy;

  testWidgets('holding a set number and dragging it down moves that row', (
    tester,
  ) async {
    final moves = <(int, int)>[];
    await pumpCard(
      tester,
      rows: [for (var i = 0; i < 3; i++) row('s$i', i, dragIndex: i)],
      onReorderSets: (oldIndex, newIndex) => moves.add((oldIndex, newIndex)),
    );

    // Down by exactly one row: far enough to trade places with the row below,
    // short of being carried past it.
    await holdAndDrag(
      tester,
      tester.getCenter(find.text('1')),
      rowPitch(tester),
    );

    expect(
      moves,
      [(0, 1)],
      reason: 'the number is the handle; one row down is one move, reported '
          'with the index the lifted row has left behind',
    );
    expect(
      drawerOpacity(tester),
      0,
      reason: 'a hold is not a swipe — the row may be lifted without the '
          'actions drawer waking up behind it',
    );
  });

  testWidgets('a swipe on the number still reveals the row actions', (
    tester,
  ) async {
    final moves = <(int, int)>[];
    await pumpCard(
      tester,
      rows: [for (var i = 0; i < 3; i++) row('s$i', i, dragIndex: i)],
      onReorderSets: (oldIndex, newIndex) => moves.add((oldIndex, newIndex)),
    );

    // Left, and over before the hold would have had anything to say about it.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('1')),
    );
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      moves,
      isEmpty,
      reason: 'the number is a handle only for a hold — a swipe is the row\'s '
          'own gesture and must not move anything',
    );
    expect(
      drawerOpacity(tester),
      greaterThan(0),
      reason: 'Duplicate/Delete are still reached by swiping the row, number '
          'cell included',
    );
  });

  testWidgets('a row that is not given a drag index cannot be lifted', (
    tester,
  ) async {
    final moves = <(int, int)>[];
    await pumpCard(
      tester,
      // The drafts: real rows to the grid, but with nothing to key a move to.
      rows: [
        row('s0', 0),
        row('s1', 1),
        row('s2', 2),
      ],
      onReorderSets: (oldIndex, newIndex) => moves.add((oldIndex, newIndex)),
    );

    await holdAndDrag(
      tester,
      tester.getCenter(find.text('1')),
      rowPitch(tester),
    );

    expect(moves, isEmpty);
  });

  testWidgets('with nowhere to report a move the rows are drawn as a plain '
      'column', (tester) async {
    await pumpCard(
      tester,
      rows: [for (var i = 0; i < 3; i++) row('s$i', i, dragIndex: i)],
    );

    expect(
      find.byType(ReorderableListView),
      findsNothing,
      reason: 'the read-only surfaces — the viewer at rest, the history '
          'picker — draw these same rows and must not gain a drag layer',
    );
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('the set number rolls over instead of swapping', (tester) async {
    await pumpCard(
      tester,
      rows: [row('s0', 0, dragIndex: 0)],
      onReorderSets: (_, _) {},
    );

    // A drop renumbers every row between the lifted row's old and new slot at
    // once; without the switch, and without the travel under the fade, those
    // numbers would flick from one to the next.
    expect(
      find.ancestor(
        of: find.text('1'),
        matching: find.byType(AnimatedSwitcher),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('1'),
        matching: find.byType(SlideTransition),
      ),
      findsWidgets,
    );
  });
}
