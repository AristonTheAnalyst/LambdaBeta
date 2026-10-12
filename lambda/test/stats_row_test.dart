import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/shared/widgets/stats_row.dart';

/// How a stats tile reads.
///
/// A tile is a label and its number, and the two can sit two ways: stacked
/// (the default — the logs viewer's four tiles, where there is no width to
/// spare) or on one line (the planner's two — `inline`). The one-line mode is
/// how the live session's bar reads its own counts, and it is one reading: the
/// label steps up to the number's size and the two share a baseline.
void main() {
  Future<void> pumpRow(WidgetTester tester, {required bool inline}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatsRow(
              inline: inline,
              tiles: const [StatsTile(label: 'SETS', value: '25')],
            ),
          ),
        ),
      );

  testWidgets('stacked by default: the number reads under its label', (
    tester,
  ) async {
    await pumpRow(tester, inline: false);

    final label = tester.getCenter(find.text('SETS'));
    final value = tester.getCenter(find.text('25'));
    expect(
      value.dy,
      greaterThan(label.dy),
      reason: 'the default keeps the two-line tile every four-tile bar wears',
    );
    expect(value.dx, label.dx, reason: 'and centres them on each other');
  });

  testWidgets('inline: the number reads beside its label', (tester) async {
    await pumpRow(tester, inline: true);

    final label = tester.getCenter(find.text('SETS'));
    final value = tester.getCenter(find.text('25'));
    expect(
      value.dx,
      greaterThan(label.dx),
      reason: 'the label comes first and its number follows it across',
    );
    expect(
      (value.dy - label.dy).abs(),
      lessThan(3),
      reason: 'one line, baselined — the two type sizes sit on a shared '
          'baseline, not stacked a row apart',
    );
    expect(
      tester.widget<Text>(find.text('SETS')).style!.fontSize,
      tester.widget<Text>(find.text('25')).style!.fontSize,
      reason: 'one reading, one size: the label steps up to its number, since '
          'a count reads better a touch large than a label does',
    );
  });
}
