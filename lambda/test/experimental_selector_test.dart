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

  testWidgets('A dropdown: pop-up menu selects, and delete confirms', (
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

    // Hold the X for 1 second → the warning dialog appears.
    final x = find.byKey(const ValueKey('exercise-selector-delete'));
    final hold = await tester.startGesture(tester.getCenter(x));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(
      find.text('Are you sure you want to delete this exercise?'),
      findsOneWidget,
    );
    await hold.up();
    await tester.pumpAndSettle();

    // Confirm the delete.
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Deadlift is gone; the field now shows the exercise that took its
    // index.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('exercise-selector-field')),
        matching: find.text('Overhead Press'),
      ),
      findsOneWidget,
    );
  });
}
