import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/dev/view/pr_history_demo_screen.dart';

/// Scopes a finder to the history sheet — the stage behind it still holds
/// the pill and the selector field, which carry the same words.
Finder _inSheet(Finder matching) => find.descendant(
  of: find.byKey(const ValueKey('pr-history-sheet')),
  matching: matching,
);

Future<void> _pumpStage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: PrHistoryDemoScreen()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the stage is a live session picture on fake data', (
    tester,
  ) async {
    await _pumpStage(tester);
    expect(find.text('Freestyle Session'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    // The pill quotes what this session added — a gain, not the all-time
    // total the sheet opens on...
    expect(find.text('+2 PRs'), findsOneWidget);
    // ...as does the bar.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('demo-prs-tile')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    expect(find.text('PRS:'), findsOneWidget);
    expect(find.text('NOTES:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the PRs pill opens the all-time feed', (tester) async {
    await _pumpStage(tester);
    await tester.tap(find.text('+2 PRs'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pr-history-sheet')), findsOneWidget);
    expect(_inSheet(find.text('Bench Press')), findsOneWidget);
    // The sheet itself is all-time, so its count is still the total.
    expect(_inSheet(find.text('12 PRs')), findsOneWidget);
  });

  testWidgets('switching exercise re-reads the pill and the feed', (
    tester,
  ) async {
    await _pumpStage(tester);
    // The selector's next arrow — switching is all this test needs, and it
    // keeps the popover (whose greyed Add row is wider than the test font)
    // out of the frame.
    await tester.tap(find.byKey(const ValueKey('exercise-selector-next')));
    await tester.pumpAndSettle();
    expect(find.text('Incline Bench Press'), findsOneWidget);
    expect(find.text('+2 PRs'), findsOneWidget);

    await tester.tap(find.text('+2 PRs'));
    await tester.pumpAndSettle();
    expect(_inSheet(find.text('Incline Bench Press')), findsOneWidget);
    expect(_inSheet(find.text('5 PRs')), findsOneWidget);
  });

  testWidgets('a lone PR reads as "+1 PR"', (tester) async {
    await _pumpStage(tester);
    final next = find.byKey(const ValueKey('exercise-selector-next'));
    await tester.tap(next);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Cable Fly'), findsOneWidget);
    expect(find.text('+1 PR'), findsOneWidget);
  });

  testWidgets('the PRS tile opens the feed for the active exercise', (
    tester,
  ) async {
    await _pumpStage(tester);
    await tester.tap(find.byKey(const ValueKey('demo-prs-tile')));
    await tester.pumpAndSettle();
    expect(_inSheet(find.text('Bench Press')), findsOneWidget);
    expect(_inSheet(find.text('12 PRs')), findsOneWidget);
  });
}
