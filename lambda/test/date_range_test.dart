import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lambda/core/utils/date_range.dart';

void main() {
  final today = DateTime(2026, 8, 24);

  test('preset windows roll from today with exclusive end', () {
    final sel = DateRangeSelection.preset(DateRangePreset.m1);
    final w = sel.window(today);
    expect(w.from, DateTime(2026, 7, 26));
    expect(w.to, DateTime(2026, 8, 25));

    final y = DateRangeSelection.preset(DateRangePreset.y1).window(today);
    expect(y.from, DateTime(2025, 8, 25));
    expect(y.to, DateTime(2026, 8, 25));
  });

  test('custom windows use picked days, end exclusive', () {
    final sel = DateRangeSelection.custom(
      DateTimeRange(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 20),
      ),
    );
    final w = sel.window(today);
    expect(w.from, DateTime(2026, 8, 1));
    expect(w.to, DateTime(2026, 8, 21));
  });

  test('single-day custom ranges are legal', () {
    final sel = DateRangeSelection.custom(
      DateTimeRange(
        start: DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 10),
      ),
    );
    final w = sel.window(today);
    expect(w.from, DateTime(2026, 8, 10));
    expect(w.to, DateTime(2026, 8, 11));
  });

  test('monthToDate covers the 1st through today, even on the 1st', () {
    final sel = DateRangeSelection.monthToDate(DateTime(2026, 8, 24));
    final w = sel.window(today);
    expect(w.from, DateTime(2026, 8, 1));
    expect(w.to, DateTime(2026, 8, 25));

    // Month/year boundary: Jan 1 → single-day window.
    final jan = DateRangeSelection.monthToDate(
      DateTime(2026, 1, 1),
    ).window(DateTime(2026, 1, 1));
    expect(jan.from, DateTime(2026, 1, 1));
    expect(jan.to, DateTime(2026, 1, 2));
  });

  test('labels name the preset and the compact window', () {
    expect(
      DateRangeSelection.preset(DateRangePreset.m3).label(today),
      '3M · 27 May – 24 Aug',
    );
    expect(
      DateRangeSelection.monthToDate(today).label(today),
      'This Month · 1 Aug – 24 Aug',
    );
    // A non-MTD custom range stays labelled Custom.
    expect(
      DateRangeSelection.custom(
        DateTimeRange(
          start: DateTime(2026, 7, 10),
          end: DateTime(2026, 8, 10),
        ),
      ).label(today),
      'Custom · 10 Jul – 10 Aug',
    );
  });
}
