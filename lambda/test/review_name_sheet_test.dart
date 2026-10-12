import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/reviews/view/review_name_sheet.dart';
import 'package:lambda/shared/widgets/glass_button.dart';

/// The sheet the + button opens first: what is this pass called?
///
/// Two answers it must be able to give, never confused with each other: a
/// trimmed name (go on to the picker), or null (dismissed — the caller must
/// start nothing). The tests pin both, plus the gate the flow is built on: a
/// review goes on to be filed under its name, so Next does not arm until there
/// is one.
void main() {
  late String? result;

  Future<void> openSheet(WidgetTester tester) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showReviewNameSheet(context);
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

  GlassButton nextButton(WidgetTester tester) =>
      tester.widget<GlassButton>(find.widgetWithText(GlassButton, 'Next'));

  testWidgets('Next stays disabled until the review has a name', (
    tester,
  ) async {
    await openSheet(tester);
    expect(nextButton(tester).disabled, isTrue);

    // Whitespace is not a name: the sheet compares trimmed, so padding cannot
    // arm a Next that would file the pass under an invisible title.
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(nextButton(tester).disabled, isTrue);

    await tester.enterText(find.byType(TextField), 'End of block 1');
    await tester.pump();
    expect(nextButton(tester).disabled, isFalse);
  });

  testWidgets('Next returns the trimmed name', (tester) async {
    await openSheet(tester);
    await tester.enterText(find.byType(TextField), '  End of block 1  ');
    await tester.pump();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(result, 'End of block 1');
  });

  testWidgets('dismissing returns null — the caller must start nothing', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.enterText(find.byType(TextField), 'End of block 1');
    await tester.pump();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
