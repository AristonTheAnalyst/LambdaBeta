import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/shared/widgets/feeling_rating.dart';
import 'package:lambda/shared/widgets/lambda_input.dart';
import 'package:lambda/shared/widgets/lambda_readout.dart';

/// The read/edit rule — C · Hollow, shipped 2026-10-28.
///
/// A control's mode is its FILL: filled = it takes input, hollow = it only
/// reads. The edge never moves, and neither does anything else — so the read
/// side must be the very field it stands in for, at the same height for the
/// same words. These tests pin both halves:
///
/// - the box pair (`LambdaInput` / `LambdaReadout`) agrees on height at 1,
///   3 and 8 lines of notes, and the readout's fill is transparent while its
///   edge is the field's own `border` hairline;
/// - the stars' pill keeps one rim and moves only its tint (glass while it
///   takes a tap, hollow while it only reads), and the inline summary stars
///   take no pill at all.
void main() {
  String lines(int n) => List.generate(n, (i) => 'Note line $i').join('\n');

  Future<void> pumpPair(WidgetTester tester, int lineCount) async {
    final controller = TextEditingController(text: lines(lineCount));
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LambdaInput(
                    controller: controller,
                    minLines: 2,
                    maxLines: 6,
                    onChanged: (_) {},
                  ),
                  LambdaReadout(value: lines(lineCount)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final n in [1, 3, 8]) {
    testWidgets('read and edit agree on height at $n line(s)', (tester) async {
      await pumpPair(tester, n);
      final field = tester.getSize(find.byType(LambdaInput)).height;
      final readout = tester.getSize(find.byType(LambdaReadout)).height;
      expect(
        readout,
        field,
        reason:
            'the read box is the field hollowed — the toggle must not move '
            'the text when it flips',
      );
    });
  }

  testWidgets('the readout is hollow: transparent fill, the field edge', (
    tester,
  ) async {
    await pumpPair(tester, 1);
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(LambdaReadout),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, Colors.transparent);
    expect(decoration.border, Border.all(color: AppColors.border));
    expect(decoration.borderRadius, BorderRadius.circular(8));
  });

  Future<BoxDecoration> pumpRating(
    WidgetTester tester, {
    required bool interactive,
    bool framed = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FeelingRating(
              value: 3,
              onChanged: interactive ? (_) {} : null,
              framed: framed,
            ),
          ),
        ),
      ),
    );
    final pill = find.descendant(
      of: find.byType(FeelingRating),
      matching: find.byType(Container),
    );
    return (tester.widget<Container>(pill).decoration! as BoxDecoration);
  }

  testWidgets('an interactive pill is filled with the glass tint', (
    tester,
  ) async {
    final decoration = await pumpRating(tester, interactive: true);
    expect(decoration.color, AppColors.primary.withAlpha(26));
    expect(decoration.border, Border.all(color: AppColors.primary.withAlpha(77)));
  });

  testWidgets('a read-only pill keeps the rim and loses the tint', (
    tester,
  ) async {
    final decoration = await pumpRating(tester, interactive: false);
    expect(decoration.color, Colors.transparent);
    expect(decoration.border, Border.all(color: AppColors.primary.withAlpha(77)));
  });

  testWidgets('the inline glance wears no pill', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: FeelingRating(value: 3, size: 14, framed: false),
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(FeelingRating),
        matching: find.byType(Container),
      ),
      findsNothing,
    );
  });
}
