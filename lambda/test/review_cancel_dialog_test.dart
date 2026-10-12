import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/reviews/view/review_cancel_dialog.dart';

/// The question asked before an open pass is deleted.
///
/// The cancel is the one destructive thing this list offers, and the row it
/// takes is a walk the user has already started — so the dialog has to name
/// what goes with it, and its dismissal must not read as its answer. These
/// tests pin both, plus the null-is-no contract every dialog here keeps.
void main() {
  late bool? answer;

  Future<void> openDialog(
    WidgetTester tester, {
    String label = 'Legs · Push',
  }) async {
    answer = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  answer = await confirmCancelReview(context, label: label);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('names the pass and what is deleted with it', (tester) async {
    await openDialog(tester, label: 'Legs · Push');

    expect(find.text('Cancel this review?'), findsOneWidget);
    expect(
      find.textContaining('"Legs · Push" is deleted'),
      findsOneWidget,
      reason: 'the row being taken is the one under the finger, and "this '
          'review" alone would leave the user checking which one',
    );
    expect(find.textContaining("This can't be undone."), findsOneWidget);
  });

  testWidgets('the confirm carries the verb and returns true', (tester) async {
    await openDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel review'));
    await tester.pumpAndSettle();

    expect(answer, isTrue);
  });

  testWidgets('keeping the review returns false', (tester) async {
    await openDialog(tester);

    // The dismiss verb is deliberately not "Cancel": the confirm's own verb IS
    // cancel, and a dismissal reading the same as the destructive answer is
    // one made by reflex.
    await tester.tap(find.widgetWithText(TextButton, 'Keep reviewing'));
    await tester.pumpAndSettle();

    expect(answer, isFalse);
  });

  testWidgets('dismissing the dialog is a no, not a yes', (tester) async {
    await openDialog(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(answer, isFalse,
        reason: 'a dismissed dialog answers null — read as "go ahead" it '
            'would delete the pass the user had just backed away from');
  });
}
