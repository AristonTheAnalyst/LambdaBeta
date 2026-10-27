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

  Future<void> pumpPair(
    WidgetTester tester,
    int lineCount, {
    String? hint,
  }) async {
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
                    placeholder: hint,
                    onChanged: (_) {},
                  ),
                  LambdaReadout(
                    value: lines(lineCount),
                    fieldHint: hint,
                  ),
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

  // The ratings sheet's own case: the field's hint is the wizard's prompt
  // (three lines), the note is one. A field reserves the hint's height even
  // with a value in it (`InputDecorator.maintainHintSize`), so the hollow
  // box must reserve it too or the pencil's toggle resizes the section.
  const wizardHint = 'Sleep and eat well?\nHydrated?\nGoals today?';
  for (final n in [1, 2, 4]) {
    testWidgets('a $n-line note under a three-line hint stays level', (
      tester,
    ) async {
      await pumpPair(tester, n, hint: wizardHint);
      expect(
        tester.getSize(find.byType(LambdaReadout)).height,
        tester.getSize(find.byType(LambdaInput)).height,
        reason: 'the field reserves its hint; the hollow box must too',
      );
    });
  }

  // The field seats its input at the decoration's 16 plus the outline
  // border's 4pt gap — the hollow box puts the words in the same place.
  testWidgets('the words sit where the field puts them', (tester) async {
    await pumpPair(tester, 1);
    final fieldBox = tester.getRect(find.byType(LambdaInput));
    final fieldText = tester.getRect(find.byType(EditableText));
    final readBox = tester.getRect(find.byType(LambdaReadout));
    final readText = tester.getRect(
      find.descendant(
        of: find.byType(LambdaReadout),
        matching: find.text(lines(1)),
      ),
    );
    expect(readText.left - readBox.left, fieldText.left - fieldBox.left);
    expect(readText.top - readBox.top, fieldText.top - fieldBox.top);
  });

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
