import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/styles/app_colors.dart';
import 'package:lambda/shared/widgets/month_calendar.dart';

/// [MonthCalendar] owns layout, bounds and hit-testing; the caller owns what a
/// day means. These tests pin the half that moved — the bounds — because that
/// is the whole reason the widget was extracted: two sheets hard-disabled
/// future days, and three screens needed them. A calendar that cannot be told
/// to allow a future date would silently re-create the bug this replaced.
void main() {
  // A month far from any plausible "today" so the today-outline never
  // interferes with a fill assertion, and so the bounds tests are about the
  // bounds rather than about when the suite happens to run.
  final june2030 = DateTime(2030, 6, 1);

  Widget host({
    DateTime? month,
    DateTime? firstDate,
    DateTime? lastDate,
    bool Function(DateTime)? isSelected,
    bool Function(DateTime)? isInRange,
    ValueChanged<DateTime>? onDayTap,
    ValueChanged<DateTime>? onMonthChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: MonthCalendar(
          month: month ?? june2030,
          onMonthChanged: onMonthChanged ?? (_) {},
          firstDate: firstDate ?? DateTime(2029, 1, 1),
          lastDate: lastDate ?? DateTime(2031, 12, 31),
          isSelected: isSelected,
          isInRange: isInRange,
          onDayTap: onDayTap,
        ),
      ),
    );
  }

  BoxDecoration decorationOf(WidgetTester tester, String day) {
    final container = tester.widget<Container>(
      find.ancestor(of: find.text(day), matching: find.byType(Container)).first,
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('renders the month title and one cell per day', (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('June 2030'), findsOneWidget);
    // 30 days in June, no leading blanks needed on a fixed-date assertion —
    // what matters is that every day of the month is present exactly once.
    for (var d = 1; d <= 30; d++) {
      expect(find.text('$d'), findsOneWidget);
    }
    expect(find.text('31'), findsNothing);
  });

  /// Every day must sit in its weekday's column, final row included — a
  /// geometry assertion, because "the right dates are on screen" is not the
  /// same claim and was true while the last row was rendering under the wrong
  /// headers.
  void expectEachDayUnderItsWeekday(WidgetTester tester, DateTime month) {
    const headers = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    final centres = [
      for (final h in headers) tester.getCenter(find.text(h)).dx,
    ];
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    for (var d = 1; d <= daysInMonth; d++) {
      final column = DateTime(month.year, month.month, d).weekday - 1;
      expect(
        tester.getCenter(find.text('$d')).dx,
        moreOrLessEquals(centres[column], epsilon: 0.5),
        reason: '$d/${month.month} belongs in the ${headers[column]} column',
      );
    }
  }

  testWidgets('every day sits under its weekday, short last row included',
      (tester) async {
    // Three shapes of final row: July 2030 leaves three days after a Monday
    // start, September 2030 exactly one after a Sunday start, and June 2030
    // lands on a full seven so there is no short row at all. Only the first
    // two can fail — which is why the render test above never caught this.
    for (final month in [
      DateTime(2030, 7, 1),
      DateTime(2030, 9, 1),
      DateTime(2030, 6, 1),
    ]) {
      await tester.pumpWidget(host(month: month));
      expectEachDayUnderItsWeekday(tester, month);
    }
  });

  testWidgets('a day inside the bounds is tappable', (tester) async {
    DateTime? tapped;
    await tester.pumpWidget(host(onDayTap: (d) => tapped = d));
    await tester.tap(find.text('15'));
    expect(tapped, DateTime(2030, 6, 15));
  });

  testWidgets('a day past lastDate is inert', (tester) async {
    DateTime? tapped;
    await tester.pumpWidget(host(
      lastDate: DateTime(2030, 6, 14),
      onDayTap: (d) => tapped = d,
    ));
    await tester.tap(find.text('15'));
    expect(tapped, isNull);
    await tester.tap(find.text('14'));
    expect(tapped, DateTime(2030, 6, 14));
  });

  testWidgets('a day before firstDate is inert', (tester) async {
    DateTime? tapped;
    await tester.pumpWidget(host(
      firstDate: DateTime(2030, 6, 15),
      onDayTap: (d) => tapped = d,
    ));
    await tester.tap(find.text('14'));
    expect(tapped, isNull);
    await tester.tap(find.text('15'));
    expect(tapped, DateTime(2030, 6, 15));
  });

  testWidgets('navigation stops at the bounded months', (tester) async {
    final shifts = <DateTime>[];
    await tester.pumpWidget(host(onMonthChanged: shifts.add));

    // June 2030 is inside a 2029..2031 window, so both arrows work.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.tap(find.byIcon(Icons.chevron_left));
    expect(shifts, [DateTime(2030, 7, 1), DateTime(2030, 5, 1)]);

    // Sitting on the last allowed month, forward does nothing.
    shifts.clear();
    await tester.pumpWidget(host(
      month: DateTime(2031, 12, 1),
      onMonthChanged: shifts.add,
    ));
    await tester.tap(find.byIcon(Icons.chevron_right));
    expect(shifts, isEmpty);

    // And on the first allowed month, back does nothing.
    shifts.clear();
    await tester.pumpWidget(host(
      month: DateTime(2029, 1, 1),
      onMonthChanged: shifts.add,
    ));
    await tester.tap(find.byIcon(Icons.chevron_left));
    expect(shifts, isEmpty);
  });

  testWidgets('a selected day takes the accent fill', (tester) async {
    await tester.pumpWidget(host(
      isSelected: (d) => d.day == 15,
    ));
    expect(decorationOf(tester, '15').color, AppColors.accent);
    expect(decorationOf(tester, '16').color, Colors.transparent);
  });

  testWidgets('a range interior reads differently from its edges', (tester) async {
    await tester.pumpWidget(host(
      isSelected: (d) => d.day == 3 || d.day == 7,
      isInRange: (d) => d.day >= 3 && d.day <= 7,
    ));
    expect(decorationOf(tester, '3').color, AppColors.accent);
    expect(decorationOf(tester, '5').color, AppColors.accentBg);
    expect(decorationOf(tester, '7').color, AppColors.accent);
    expect(decorationOf(tester, '8').color, Colors.transparent);
  });

  testWidgets('degenerate bounds say so instead of rendering a blank month',
      (tester) async {
    await tester.pumpWidget(host(
      firstDate: DateTime(2031, 1, 1),
      lastDate: DateTime(2030, 1, 1),
    ));
    expect(find.text('No selectable dates'), findsOneWidget);
  });
}
