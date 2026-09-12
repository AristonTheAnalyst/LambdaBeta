import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Date-filter presets — rolling windows from today, plus ALL (no filter).
enum DateRangePreset { all, m1, m3, m6, y1, custom }

const _presetDays = {
  DateRangePreset.m1: 30,
  DateRangePreset.m3: 90,
  DateRangePreset.m6: 180,
  DateRangePreset.y1: 365,
};

/// One date-range selection: a rolling preset, or an explicit custom range.
/// All date math for the filter lives here (and in [DateRangeSelection]) so
/// the page and the selector sheet can never disagree.
class DateRangeSelection {
  const DateRangeSelection.preset(this.preset) : customRange = null;

  const DateRangeSelection.custom(DateTimeRange range)
    : preset = DateRangePreset.custom,
      customRange = range;

  final DateRangePreset preset;

  /// Non-null iff [preset] is [DateRangePreset.custom].
  final DateTimeRange? customRange;

  /// Month-to-date: the 1st of the current month → today. A DEFAULT,
  /// recomputed per page open — never a persisted range that could freeze
  /// on last month's dates.
  factory DateRangeSelection.monthToDate(DateTime today) {
    return DateRangeSelection.custom(
      DateTimeRange(
        start: DateTime(today.year, today.month, 1),
        end: DateTime(today.year, today.month, today.day),
      ),
    );
  }

  /// The `[from, to)` window this selection covers — presets roll from
  /// today; custom uses the picked days with an exclusive end; ALL covers
  /// everything (no filtering).
  ({DateTime from, DateTime to}) window(DateTime today) {
    final range = customRange;
    if (preset == DateRangePreset.custom && range != null) {
      final start = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      final end = DateTime(range.end.year, range.end.month, range.end.day);
      return (from: start, to: end.add(const Duration(days: 1)));
    }
    if (preset == DateRangePreset.all) {
      return (from: DateTime(1900, 1, 1), to: DateTime(today.year + 1, 1, 1));
    }
    final days = _presetDays[preset] ?? 30;
    final todayStart = DateTime(today.year, today.month, today.day);
    return (
      from: todayStart.subtract(Duration(days: days - 1)),
      to: todayStart.add(const Duration(days: 1)),
    );
  }

  /// Whether this is the month-to-date default range (1st of [today]'s
  /// month → today) — shown as "This Month" instead of "Custom".
  bool isMonthToDate(DateTime today) {
    final range = customRange;
    if (preset != DateRangePreset.custom || range == null) return false;
    return range.start.year == today.year &&
        range.start.month == today.month &&
        range.start.day == 1 &&
        range.end.year == today.year &&
        range.end.month == today.month &&
        range.end.day == today.day;
  }

  /// The compact pill text: "1M · 24 Jul – 24 Aug"; ALL is just "All".
  String label(DateTime today) {
    if (preset == DateRangePreset.all) return 'All';
    final w = window(today);
    final fmt = DateFormat('d MMM');
    final end = w.to.subtract(const Duration(days: 1));
    final name = switch (preset) {
      DateRangePreset.all => 'All', // unreachable — early-returned above
      DateRangePreset.m1 => '1M',
      DateRangePreset.m3 => '3M',
      DateRangePreset.m6 => '6M',
      DateRangePreset.y1 => '1Y',
      DateRangePreset.custom =>
        isMonthToDate(today) ? 'This Month' : 'Custom',
    };
    return '$name · ${fmt.format(w.from)} – ${fmt.format(end)}';
  }

  @override
  bool operator ==(Object other) =>
      other is DateRangeSelection &&
      other.preset == preset &&
      other.customRange?.start == customRange?.start &&
      other.customRange?.end == customRange?.end;

  @override
  int get hashCode => Object.hash(preset, customRange?.start, customRange?.end);
}
