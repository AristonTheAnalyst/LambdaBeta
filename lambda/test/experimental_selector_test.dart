import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/dev/view/experimental_screen.dart';

void main() {
  testWidgets('C pager: tapping opens the exercise menu', (tester) async {
    // A taller surface so C's card is built (it sits below the fold in the
    // default 800x600 test viewport).
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ExperimentalScreen()));
    await tester.pump();

    // Tap the pager — the menu should open with the reorder rows and the
    // New Exercise entry at the bottom.
    await tester.tap(find.byKey(const ValueKey('c-pager')));
    await tester.pump();

    expect(find.text('New Exercise'), findsOneWidget);
    expect(find.text('Pull Up'), findsWidgets);
  });

  testWidgets('A dropdown: pop-up menu selects, and there is no delete control',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ExperimentalScreen()));
    await tester.pump();

    // Open the pop-up menu — the selected (Benchpress) stays in the field;
    // the sheet lists the others.
    await tester.tap(find.byKey(const ValueKey('exercise-selector-field')));
    await tester.pumpAndSettle();
    expect(find.text('Squat'), findsOneWidget);

    // Tap a row — the sheet closes and the field shows the pick.
    await tester.tap(find.text('Deadlift'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('exercise-selector-field')),
        matching: find.text('Deadlift'),
      ),
      findsOneWidget,
    );

    // The hold-to-delete X is gone (2026-09-29): removal moved into the
    // add-exercise modal, where a ticked row is tapped to un-tick it. The
    // selector field no longer carries a control at all, so the cheapest
    // regression test for the whole removal is that the key is not there.
    expect(
      find.byKey(const ValueKey('exercise-selector-delete')),
      findsNothing,
    );
  });
}
