import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/dev/view/visual_pairings_screen.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';

import 'support/readable_text.dart';

/// The read/edit study page (2026-10-28): every option draws its section, and
/// each card's READ | EDIT switch flips its own sample — the whole point is
/// feeling the transition, so a switch that does not move the sample is the
/// one bug this page can have.

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: VisualPairingsScreen()));
  await tester.pumpAndSettle();
}

Finder _card(String id) => find.byKey(ValueKey('pairing-$id'));

Finder _inCard(String id, Finder matching) =>
    find.descendant(of: _card(id), matching: matching);

void main() {
  testWidgets('every option draws, and nothing starts editable', (
    tester,
  ) async {
    await _pump(tester);

    for (final id in ['today', 'a', 'c']) {
      expect(_card(id), findsOneWidget, reason: 'option $id draws');
    }
    // The affordance and group-tint cards were dropped (2026-10-28): the
    // study now asks about the border and the fill, nothing else.
    expect(_card('b'), findsNothing);
    expect(_card('d'), findsNothing);
    // READ is the starting state everywhere: no field is up, so the study
    // opens on the state the signal must make obvious.
    expect(find.byType(LambdaInput), findsNothing);
    // C's read box is the field itself, held inert — reading never takes a
    // keystroke, and the same widget in EDIT is what keeps the words from
    // moving when the mode flips.
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields, hasLength(1));
    expect(fields.single.readOnly, isTrue, reason: 'READ never accepts typing');
    expectReadableText(tester, find.byType(VisualPairingsScreen));
  });

  testWidgets('each switch flips its own card, and only its own', (
    tester,
  ) async {
    await _pump(tester);

    await tester.ensureVisible(_inCard('a', find.text('EDIT')));
    await tester.tap(_inCard('a', find.text('EDIT')));
    await tester.pumpAndSettle();

    // A turns editable: the field arrives and the bare reading text goes.
    expect(_inCard('a', find.byType(LambdaInput)), findsOneWidget);
    // No other card moved.
    expect(find.byType(LambdaInput), findsOneWidget);

    // Back to reading: the field leaves again.
    await tester.tap(_inCard('a', find.text('READ')));
    await tester.pumpAndSettle();
    expect(find.byType(LambdaInput), findsNothing);

    // C is one TextField in both modes — the toggle only makes it editable,
    // so the words cannot shift with the mode (2026-10-28).
    final cField = _inCard('c', find.byType(TextField));
    expect(tester.widget<TextField>(cField).readOnly, isTrue);
    await tester.ensureVisible(_inCard('c', find.text('EDIT')));
    await tester.tap(_inCard('c', find.text('EDIT')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(cField).readOnly, isFalse);
    expect(
      tester.widget<TextField>(cField).decoration!.fillColor,
      isNot(Colors.transparent),
      reason: 'editing fills the box the border already outlined',
    );
  });
}
