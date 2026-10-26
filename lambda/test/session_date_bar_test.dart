import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:lambda/features/session/model/session_local_state.dart';
import 'package:lambda/shared/widgets/session_chevron_button.dart';
import 'package:lambda/shared/widgets/session_date_bar.dart';

/// The floor's date bar walks the session stack (2026-10-22): one chevron
/// each side of `TODAY -` / `PREVIOUSLY -`, drawn from the session stage's
/// one chevron recipe. The bar only asks for the two taps — the stage decides
/// what a step means — so a null callback is the whole of "there is nothing
/// older" here. Tapping the phrase itself cycles how the date reads
/// (2026-10-23): the written date, `N days ago`, `N weeks N days ago`.
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    bool isToday = false,
    DateTime? date,
    SessionDateMode mode = SessionDateMode.exercise,
    VoidCallback? onToggleMode,
    VoidCallback? onOlder,
    VoidCallback? onNewer,
  }) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            // The page's own gutter, so the bar sits where the floor puts it.
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SessionDateBar(
              isToday: isToday,
              date: date ?? DateTime(2026, 10, 22),
              mode: mode,
              onToggleMode: onToggleMode,
              onOlder: onOlder,
              onNewer: onNewer,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the phrase sits between two chevrons on the stage recipe', (
    tester,
  ) async {
    await pumpBar(tester);

    expect(find.text('PREVIOUSLY -'), findsOneWidget);
    expect(
      find.text(DateFormat('d MMM yyyy').format(DateTime(2026, 10, 22))),
      findsOneWidget,
    );

    for (final key in const [
      'session-date-bar-older',
      'session-date-bar-newer',
    ]) {
      final box = find.byKey(ValueKey(key));
      expect(box, findsOneWidget);
      expect(
        tester.getSize(box),
        const Size(
          SessionChevronButton.kSessionChevronSize,
          SessionChevronButton.kSessionChevronSize,
        ),
      );
      final icon = tester.widget<Icon>(
        find.descendant(of: box, matching: find.byType(Icon)),
      );
      expect(
        icon.icon,
        key.endsWith('older') ? Icons.chevron_left : Icons.chevron_right,
      );
      expect(icon.size, SessionChevronButton.kSessionChevronIconSize);
    }
  });

  testWidgets('live arrows fire; a null callback greys the arrow and it '
      'does not move', (tester) async {
    var older = 0;
    await pumpBar(tester, onOlder: () => older++);

    // The live side: glass, full ink, tap does its job.
    final olderBar = tester.widget<SessionChevronButton>(
      find.byKey(const ValueKey('session-date-bar-older')),
    );
    expect(olderBar.enabled, isTrue);
    await tester.tap(find.byKey(const ValueKey('session-date-bar-older')));
    expect(older, 1);

    // The spent side: still drawn, still claiming its tap, doing nothing.
    final newerBar = tester.widget<SessionChevronButton>(
      find.byKey(const ValueKey('session-date-bar-newer')),
    );
    expect(newerBar.enabled, isFalse);
    await tester.tap(find.byKey(const ValueKey('session-date-bar-newer')));
    // Nothing to observe but the absence of an exception and of a rebuild
    // change — the spent arrow is inert by construction.
    expect(find.byKey(const ValueKey('session-date-bar')), findsOneWidget);
  });

  testWidgets('both arrows live while there is a session each way', (
    tester,
  ) async {
    var older = 0;
    var newer = 0;
    await pumpBar(tester, onOlder: () => older++, onNewer: () => newer++);

    await tester.tap(find.byKey(const ValueKey('session-date-bar-older')));
    await tester.tap(find.byKey(const ValueKey('session-date-bar-newer')));
    expect(older, 1);
    expect(newer, 1);
  });

  testWidgets('the live session says TODAY in the accent', (tester) async {
    await pumpBar(tester, isToday: true);
    expect(find.text('TODAY -'), findsOneWidget);
    expect(find.text('PREVIOUSLY -'), findsNothing);
  });

  testWidgets('tapping the phrase reads the date as days ago, then weeks and '
      'days ago, then the date again', (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final tenDaysAgo = today.subtract(const Duration(days: 10));
    await pumpBar(tester, date: tenDaysAgo);

    Future<void> tapPhrase() async {
      await tester.tap(find.byKey(const ValueKey('session-date-bar-date')));
      await tester.pumpAndSettle();
    }

    expect(
      find.text(DateFormat('d MMM yyyy').format(tenDaysAgo)),
      findsOneWidget,
    );
    expect(find.text('10 days ago'), findsNothing);

    await tapPhrase();
    expect(
      find.text('PREVIOUSLY -'),
      findsNothing,
      reason: 'a relative reading is its own whole phrase',
    );
    expect(find.text('10 days ago'), findsOneWidget);

    await tapPhrase();
    expect(find.text('1 week 3 days ago'), findsOneWidget);
    expect(find.text('PREVIOUSLY -'), findsNothing);

    // The third tap wraps back to the dated phrase.
    await tapPhrase();
    expect(find.text('PREVIOUSLY -'), findsOneWidget);
    expect(
      find.text(DateFormat('d MMM yyyy').format(tenDaysAgo)),
      findsOneWidget,
    );
  });

  testWidgets('a session younger than a week has only the dated phrase and '
      'the days — no weeks reading to show', (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final threeDaysAgo = today.subtract(const Duration(days: 3));
    await pumpBar(tester, date: threeDaysAgo);

    Future<void> tapPhrase() async {
      await tester.tap(find.byKey(const ValueKey('session-date-bar-date')));
      await tester.pumpAndSettle();
    }

    await tapPhrase();
    expect(find.text('3 days ago'), findsOneWidget);
    expect(find.text('PREVIOUSLY -'), findsNothing);

    // The next tap returns to the date rather than repeating the days in a
    // weeks format that has no weeks in it.
    await tapPhrase();
    expect(find.text('PREVIOUSLY -'), findsOneWidget);
    expect(
      find.text(DateFormat('d MMM yyyy').format(threeDaysAgo)),
      findsOneWidget,
    );

    await tapPhrase();
    expect(find.text('3 days ago'), findsOneWidget);
  });

  testWidgets('whole weeks drop the day part', (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    await pumpBar(tester, date: today.subtract(const Duration(days: 14)));

    // Date → days → weeks.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('session-date-bar-date')));
      await tester.pumpAndSettle();
    }
    expect(find.text('2 weeks ago'), findsOneWidget);
  });

  testWidgets('the old reading cuts away and the new one scales in', (
    tester,
  ) async {
    await pumpBar(tester);
    final phrase = find.byKey(const ValueKey('session-date-bar-phrase'));
    // `Transform.scale` is the x/y diagonal only; the z axis stays 1, so the
    // reading to assert is the x scale, not `getMaxScaleOnAxis`.
    double xScale() => tester.widget<Transform>(phrase).transform.storage[0];
    expect(xScale(), moreOrLessEquals(1));

    await tester.tap(find.byKey(const ValueKey('session-date-bar-date')));
    await tester.pump();
    final mid = xScale();
    expect(mid, lessThan(1), reason: 'the new reading scales up from small');
    expect(mid, greaterThanOrEqualTo(0.85));

    await tester.pumpAndSettle();
    expect(xScale(), moreOrLessEquals(1));
  });

  testWidgets('a live session\'s phrase is not a control — the tap does '
      'nothing', (tester) async {
    await pumpBar(tester, isToday: true);
    final phrase = find.byKey(const ValueKey('session-date-bar-phrase'));
    double xScale() => tester.widget<Transform>(phrase).transform.storage[0];

    await tester.tap(find.byKey(const ValueKey('session-date-bar-date')));
    await tester.pump();
    expect(
      xScale(),
      moreOrLessEquals(1),
      reason: 'no cycle runs, so no scale-in starts either',
    );
    await tester.pumpAndSettle();
    expect(find.text('TODAY -'), findsOneWidget);
    expect(find.text('22 Oct 2026'), findsOneWidget);
  });

  testWidgets('the mode radios are the stage\'s fact — absent without a '
      'toggle', (tester) async {
    await pumpBar(tester);
    expect(find.byKey(const ValueKey('session-date-bar-mode')), findsNothing);
    expect(find.text('SESSION'), findsNothing);
    expect(find.text('SESSION BY EXERCISE'), findsNothing);
  });

  testWidgets('both modes stay visible, SESSION BY EXERCISE is checked by '
      'default, and only the unchecked radio switches', (tester) async {
    var toggles = 0;
    await pumpBar(tester, onToggleMode: () => toggles++);

    final pair = find.byKey(const ValueKey('session-date-bar-mode'));
    expect(pair, findsOneWidget);
    expect(find.text('SESSION'), findsOneWidget);
    expect(find.text('SESSION BY EXERCISE'), findsOneWidget);

    Finder option(String mode) =>
        find.byKey(ValueKey('session-date-bar-mode-$mode'));
    Icon ringOf(String mode) => tester.widget<Icon>(
      find.descendant(of: option(mode), matching: find.byType(Icon)),
    );
    expect(ringOf('exercise').icon, Icons.radio_button_checked);
    expect(ringOf('session').icon, Icons.radio_button_unchecked);

    // The pair rides inside the selector's own box, under the date: one
    // control, read top to bottom (2026-10-23).
    final bar = find.byKey(const ValueKey('session-date-bar'));
    expect(
      find.descendant(of: bar, matching: pair),
      findsOneWidget,
      reason: 'the radios are part of the date selector, not a second bar',
    );
    final barRect = tester.getRect(bar);
    final pairRect = tester.getRect(pair);
    final olderRect = tester.getRect(
      find.byKey(const ValueKey('session-date-bar-older')),
    );
    expect(
      pairRect.top,
      greaterThanOrEqualTo(olderRect.bottom),
      reason: 'the mode sits under the date, not above it',
    );
    expect(
      pairRect.bottom,
      lessThanOrEqualTo(barRect.bottom),
      reason: 'the box wraps both rows',
    );
    expect(pairRect.center.dx, moreOrLessEquals(barRect.center.dx, epsilon: 1));
    expect(
      pairRect.width,
      lessThan(barRect.width),
      reason: 'the pair hugs its words — it is not a second bar',
    );

    // Each radio claims a 40pt target, though its text is the date's size.
    for (final mode in const ['exercise', 'session']) {
      expect(
        tester.getSize(option(mode)).height,
        SessionChevronButton.kSessionChevronSize,
      );
    }

    // The live side is not a switch; the other is.
    await tester.tap(option('exercise'));
    expect(toggles, 0);
    await tester.tap(option('session'));
    expect(toggles, 1);

    // The parent owns the mode: repump with SESSION and the ring moves.
    await pumpBar(
      tester,
      mode: SessionDateMode.session,
      onToggleMode: () => toggles++,
    );
    expect(ringOf('exercise').icon, Icons.radio_button_unchecked);
    expect(ringOf('session').icon, Icons.radio_button_checked);

    await tester.tap(option('session'));
    expect(toggles, 1, reason: 'the checked radio is not a switch either');
  });

  testWidgets('the arrows name what they walk in each mode', (tester) async {
    await pumpBar(tester, onOlder: () {}, onNewer: () {});
    expect(find.bySemanticsLabel('Previous performance'), findsOneWidget);
    expect(find.bySemanticsLabel('Next performance'), findsOneWidget);

    await pumpBar(
      tester,
      mode: SessionDateMode.session,
      onOlder: () {},
      onNewer: () {},
    );
    expect(find.bySemanticsLabel('Previous session'), findsOneWidget);
    expect(find.bySemanticsLabel('Next session'), findsOneWidget);
  });

  testWidgets('a plan draws the bar spent: a lone PLAN, no date, no radios', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SessionDateBar.plan(),
          ),
        ),
      ),
    );

    // The planner stands on the session bar's furniture with every session
    // meaning spent (2026-10-26): a template is planned FOR sessions, so it
    // has no date to name a stack it is not in.
    expect(find.text('PLAN'), findsOneWidget);
    expect(find.text('TODAY -'), findsNothing);
    expect(find.text('PREVIOUSLY -'), findsNothing);
    expect(find.byKey(const ValueKey('session-date-bar-state')), findsNothing);
    expect(
      find.byKey(const ValueKey('session-date-bar-date')),
      findsNothing,
      reason: 'there is no date, so the bar draws no date readout at all',
    );

    for (final key in const [
      'session-date-bar-older',
      'session-date-bar-newer',
    ]) {
      expect(
        tester.widget<SessionChevronButton>(find.byKey(ValueKey(key))).enabled,
        isFalse,
        reason: 'a plan walks no stack — both ends are the same absence',
      );
    }

    expect(
      find.byKey(const ValueKey('session-date-bar-mode')),
      findsNothing,
      reason: 'with nothing to walk there are no stacks to name',
    );

    // The phrase is the bar's one control elsewhere; on a plan it is a
    // readout — tapping cycles nothing and throws nothing.
    await tester.tap(find.text('PLAN'));
    await tester.pumpAndSettle();
    expect(find.text('PLAN'), findsOneWidget);
    expect(
      tester
          .widget<SessionChevronButton>(
            find.byKey(const ValueKey('session-date-bar-older')),
          )
          .enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
