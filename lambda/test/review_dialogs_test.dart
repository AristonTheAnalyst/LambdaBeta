import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/reviews/view/review_dialogs.dart';

/// The questions asked before a row leaves the Reviews list: cancelling an
/// open pass, and deleting a completed record.
///
/// Each takes a row the user made — a walk already started, or the record it
/// left — so the dialog has to name what goes with it, and its dismissal must
/// not read as its answer. These tests pin both dialogs, plus the null-is-no
/// contract every dialog here keeps.
void main() {
  late bool? answer;

  Future<void> openDialog(
    WidgetTester tester, {
    String label = 'Legs · Push',
    bool completed = false,
  }) async {
    answer = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  answer = completed
                      ? await confirmDeleteCompletedReview(
                          context,
                          label: label,
                        )
                      : await confirmCancelReview(context, label: label);
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
      reason:
          'the row being taken is the one under the finger, and "this '
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

    expect(
      answer,
      isFalse,
      reason:
          'a dismissed dialog answers null — read as "go ahead" it '
          'would delete the pass the user had just backed away from',
    );
  });

  testWidgets('deleting a record names it and the record going with it', (
    tester,
  ) async {
    await openDialog(tester, label: 'Block 1 review', completed: true);

    expect(find.text('Delete this review?'), findsOneWidget);
    expect(
      find.textContaining(
        '"Block 1 review" is deleted, with the record it kept',
      ),
      findsOneWidget,
      reason:
          'a record is the finished thing the pass existed to make — the '
          'body says plainly that it goes with the row',
    );
    expect(find.textContaining("This can't be undone."), findsOneWidget);
  });

  testWidgets('the delete confirm carries the verb and returns true', (
    tester,
  ) async {
    await openDialog(tester, completed: true);

    await tester.tap(find.widgetWithText(TextButton, 'Delete review'));
    await tester.pumpAndSettle();

    expect(answer, isTrue);
  });

  testWidgets('keeping the record returns false', (tester) async {
    await openDialog(tester, completed: true);

    // "Keep it", not "Cancel": the other question's verb belongs to the other
    // question, and sharing it would blur which row is being answered.
    await tester.tap(find.widgetWithText(TextButton, 'Keep it'));
    await tester.pumpAndSettle();

    expect(answer, isFalse);
  });

  testWidgets('dismissing the delete dialog is a no, not a yes', (
    tester,
  ) async {
    await openDialog(tester, completed: true);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(
      answer,
      isFalse,
      reason:
          'a dismissed dialog answers null — read as "go ahead" it '
          'would take the record the user had just backed away from',
    );
  });
}
