import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/features/dev/pr_history_fixture.dart';
import 'package:lambda/features/dev/view/pr_history_sheet.dart';
import 'package:lambda/shared/widgets/menu_popover.dart';

/// Opens the sheet over a bare host — no stage, so every finder below names
/// the sheet's own widgets unambiguously.
Future<void> _openSheet(
  WidgetTester tester, {
  String exerciseId = 'demo-bench',
  String exerciseName = 'Bench Press',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      // A fresh tree per call: without its own key a second pump updates the
      // same MaterialApp in place and its Navigator keeps the first sheet's
      // route up, so the next tap lands on the old sheet's barrier.
      key: UniqueKey(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showPrHistorySheet(
                context,
                exerciseName: exerciseName,
                prs: demoPrsFor(exerciseId),
              ),
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

/// A phone-sized viewport: a long feed must scroll inside its ceiling rather
/// than overflow the sheet, and the filter menus must land on screen.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the sheet names the exercise and its all-time count', (
    tester,
  ) async {
    await _openSheet(tester);
    expect(find.text('PR History'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('12 PRs'), findsOneWidget);
    expect(find.text('ALL-TIME · NEWEST FIRST'), findsOneWidget);
  });

  testWidgets('the feed runs newest first', (tester) async {
    await _openSheet(tester);
    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('pr-history-list')),
    );
    expect(list.childrenDelegate.estimatedChildCount, 12);
    // Today's rep PR leads the heavy triple that landed before it in the
    // same session — the later set is the newest PR.
    final newest = tester.getTopLeft(
      find.byKey(const ValueKey('history-entry-bench-9')),
    );
    final next = tester.getTopLeft(
      find.byKey(const ValueKey('history-entry-bench-8')),
    );
    expect(newest.dy, lessThan(next.dy));
  });

  testWidgets('a PR names the record it beat, unstruck', (tester) async {
    await _openSheet(tester);
    final entry = find.byKey(const ValueKey('history-entry-bench-9'));

    // 100 × 12 beat the best 10 reps at exactly 100kg — named beside it, with
    // no strike-through: the WAS label already carries the meaning.
    final victim = find.descendant(
      of: entry,
      matching: find.text('100kg × 10'),
    );
    expect(victim, findsOneWidget);
    expect(
      tester.widget<Text>(victim).style?.decoration,
      isNot(TextDecoration.lineThrough),
    );

    // The PR itself is not struck through either.
    final killer = find.descendant(
      of: entry,
      matching: find.text('100kg × 12'),
    );
    expect(killer, findsOneWidget);
    expect(
      tester.widget<Text>(killer).style?.decoration,
      isNot(TextDecoration.lineThrough),
    );
    expect(
      find.descendant(of: entry, matching: find.text('WAS')),
      findsOneWidget,
    );
  });

  testWidgets('WAS sits to the right of the PR, on its line', (tester) async {
    _phone(tester);
    await _openSheet(tester);
    // 11 Aug: 65kg × 8 beat 60kg × 8 — one victim, so the line fits in one
    // piece at the test font's width. It sits below the fold of the lazy
    // list, so scroll it up first.
    final entry = find.byKey(const ValueKey('history-entry-bench-2'));
    await tester.scrollUntilVisible(
      entry,
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('pr-history-list')),
        matching: find.byType(Scrollable),
      ),
    );
    final was = find.descendant(of: entry, matching: find.text('WAS'));
    final killer = find.descendant(of: entry, matching: find.text('65kg × 8'));

    expect(was, findsOneWidget);
    // The old anatomy put the label under the PR, at the line's left; the
    // kill now reads across the row, the quarry to the PR's right.
    expect(tester.getCenter(was).dx, greaterThan(tester.getCenter(killer).dx));
    expect(tester.getCenter(was).dy, closeTo(tester.getCenter(killer).dy, 2));
  });

  testWidgets('the outcome hugs the row\'s right edge, variation or not', (
    tester,
  ) async {
    _phone(tester);
    await _openSheet(tester);

    // A five-rep feed holds one plain row beside the paused ones, so the
    // variated outcomes have a plain edge to answer to — and all four fit in
    // the sheet at once.
    await tester.tap(find.byKey(const ValueKey('history-reps-filter')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('5 reps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 reps'));
    await tester.pumpAndSettle();

    double rightOf(String entry, String text) => tester
        .getTopRight(
          find.descendant(
            of: find.byKey(ValueKey(entry)),
            matching: find.text(text),
          ),
        )
        .dx;

    // The plain row's victim names the edge every outcome shares. A variated
    // WAS and a variated FIRST PR land on it too — the badge labels the PR,
    // it does not take width from the outcome.
    final edge = rightOf('history-entry-bench-7', '100kg × 5');
    expect(rightOf('history-entry-bench-p2', '60kg × 5'), closeTo(edge, 0.5));
    expect(rightOf('history-entry-bench-p1', 'FIRST PR'), closeTo(edge, 0.5));
  });

  testWidgets('a handled weight names its own prior best, not the weight '
      'side', (tester) async {
    _phone(tester);
    await _openSheet(tester);

    // 18 Aug's 70 × 8 beat both the best 8-rep weight (65) and the best reps
    // at exactly 70 (5) — a dual kill. The weight was not new, so the line
    // names the same-weight comparison alone (2026-10-21).
    final entry = find.byKey(const ValueKey('history-entry-bench-4'));
    await tester.scrollUntilVisible(
      entry,
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('pr-history-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      find.descendant(of: entry, matching: find.text('70kg × 5')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: entry, matching: find.text('65kg × 8')),
      findsNothing,
    );
  });

  testWidgets('the variation rides the killer line, not the date', (
    tester,
  ) async {
    _phone(tester);
    await _openSheet(tester);
    final entry = find.byKey(const ValueKey('history-entry-bench-p3'));
    final variation = find.descendant(of: entry, matching: find.text('Paused'));
    final killer = find.descendant(of: entry, matching: find.text('80kg × 3'));
    final date = find.descendant(of: entry, matching: find.text('16 Sep 2026'));

    // The tag shares the killer's line — the frontier it beat is the same
    // variation's — and sits below the date, which stands alone.
    expect(variation, findsOneWidget);
    expect(
      tester.getCenter(variation).dy,
      closeTo(tester.getCenter(killer).dy, 2),
    );
    expect(tester.getCenter(date).dy, lessThan(tester.getCenter(variation).dy));
  });

  testWidgets('the date line says when the previous PR landed', (tester) async {
    _phone(tester);
    await _openSheet(tester);

    // Two PRs landed today: the newest names the previous as same-day.
    final newest = find.byKey(const ValueKey('history-entry-bench-9'));
    final date = find.descendant(
      of: newest,
      matching: find.text('20 Oct 2026'),
    );
    final sameDay = find.descendant(
      of: newest,
      matching: find.text('Same day'),
    );
    expect(sameDay, findsOneWidget);
    expect(
      tester.getCenter(sameDay).dx,
      greaterThan(tester.getCenter(date).dx),
    );
    expect(tester.getCenter(sameDay).dy, closeTo(tester.getCenter(date).dy, 2));

    // The heavy triple's previous PR was achieved 34 days before it (16 Sep
    // → 20 Oct).
    final prior = find.byKey(const ValueKey('history-entry-bench-8'));
    expect(
      find.descendant(of: prior, matching: find.text('34 days prior')),
      findsOneWidget,
    );
  });

  testWidgets('the oldest entry is a FIRST PR, with no wait above it', (
    tester,
  ) async {
    // A phone-sized viewport: the twelve-entry feed must scroll inside its
    // ceiling rather than overflow the sheet.
    _phone(tester);
    await _openSheet(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('history-entry-bench-1')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('pr-history-list')),
        matching: find.byType(Scrollable),
      ),
    );
    final entry = find.byKey(const ValueKey('history-entry-bench-1'));
    expect(entry, findsOneWidget);
    expect(find.text('FIRST PR'), findsWidgets);
    // Nothing came before it, so the date keeps the line to itself.
    expect(
      find.descendant(
        of: entry,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text && (widget.data?.contains('prior') ?? false),
        ),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the weight filter narrows the feed to that weight', (
    tester,
  ) async {
    _phone(tester);
    await _openSheet(tester);

    await tester.tap(find.byKey(const ValueKey('history-weight-filter')));
    await tester.pumpAndSettle();
    // The menu's rows scroll inside its 280pt ceiling; 100kg sits low in the
    // ascending list.
    await tester.ensureVisible(find.text('100 kg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('100 kg'));
    await tester.pumpAndSettle();

    // The two 100kg PRs: today's rep PR and the 8 Sep ten.
    expect(find.byKey(const ValueKey('history-entry-bench-9')), findsOneWidget);
    expect(find.byKey(const ValueKey('history-entry-bench-6')), findsOneWidget);
    expect(find.byKey(const ValueKey('history-entry-bench-8')), findsNothing);
    expect(find.text('2 of 12 PRs'), findsOneWidget);
    // A gap is a fact about the PR, not about the rows on screen: the 8 Sep
    // ten still says 6 days prior — the paused 2 Sep PR in between, not the
    // 42 days a filtered neighbour would suggest.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('history-entry-bench-6')),
        matching: find.text('6 days prior'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('weight and reps AND, down to an empty feed', (tester) async {
    _phone(tester);
    await _openSheet(tester);

    await tester.tap(find.byKey(const ValueKey('history-weight-filter')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('100 kg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('100 kg'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('history-reps-filter')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('10 reps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 reps'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('history-entry-bench-6')), findsOneWidget);
    expect(find.byKey(const ValueKey('history-entry-bench-9')), findsNothing);
    expect(find.text('1 of 12 PRs'), findsOneWidget);

    // 100kg never landed at 5 reps — the two filters meet nothing.
    await tester.tap(find.byKey(const ValueKey('history-reps-filter')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('5 reps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 reps'));
    await tester.pumpAndSettle();
    expect(find.text('No PRs match'), findsOneWidget);
    expect(find.byKey(const ValueKey('pr-history-list')), findsNothing);

    // "Any weight" restores the whole feed.
    await tester.tap(find.byKey(const ValueKey('history-weight-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any weight'));
    await tester.pumpAndSettle();
    // Five-rep PRs across both bench lines: 105×5, 70×5 (paused), 60×5
    // (paused, the line's first) and 70×5.
    expect(find.text('4 of 12 PRs'), findsOneWidget);
  });

  testWidgets('the variation filter narrows the feed to that line', (
    tester,
  ) async {
    _phone(tester);
    await _openSheet(tester);

    await tester.tap(find.byKey(const ValueKey('history-variation-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceRow, 'Paused'));
    await tester.pumpAndSettle();

    // The paused line alone — its first set (a FIRST PR of its own), then
    // 70 × 5 and 80 × 3 — never one of the regular bench PRs.
    expect(find.text('3 of 12 PRs'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('history-entry-bench-p1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('history-entry-bench-p2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('history-entry-bench-p3')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('history-entry-bench-9')), findsNothing);

    // "No variation" is the unvaried line, not another way of saying "any".
    await tester.tap(find.byKey(const ValueKey('history-variation-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceRow, 'No variation'));
    await tester.pumpAndSettle();
    expect(find.text('9 of 12 PRs'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-entry-bench-9')), findsOneWidget);
    expect(find.byKey(const ValueKey('history-entry-bench-p3')), findsNothing);
  });

  testWidgets('the sheet keeps one height, whatever the feed holds', (
    tester,
  ) async {
    _phone(tester);
    double sheetHeight() =>
        tester.getSize(find.byKey(const ValueKey('pr-history-sheet'))).height;

    await _openSheet(tester);
    final full = sheetHeight();

    // Three PRs instead of twelve: the room is the same room, so the header
    // and filters never move between feeds.
    await _openSheet(tester, exerciseId: 'demo-fly', exerciseName: 'Cable Fly');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pr-history-sheet')),
        matching: find.text('3 PRs'),
      ),
      findsOneWidget,
    );
    final thin = sheetHeight();

    expect(thin, closeTo(full, 0.5));
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(full, closeTo(screenHeight * 0.7, 1));
  });

  testWidgets('a filter menu is fully on screen', (tester) async {
    _phone(tester);
    await _openSheet(tester);
    final trigger = find.byKey(const ValueKey('history-weight-filter'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    // The menu's first and long last row both stand on screen — the panel
    // opens on whichever side can hold it (the direction itself is
    // MenuPopover's own test).
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getRect(find.text('Any weight')).bottom,
      lessThan(screenHeight),
    );
    expect(tester.getRect(find.text('110 kg')).bottom, lessThan(screenHeight));
    expect(tester.takeException(), isNull);
  });
}
