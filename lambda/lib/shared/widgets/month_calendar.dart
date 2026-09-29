import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import 'container_styles.dart';

/// The app's calendar: one month, its navigation, and its day grid.
///
/// The grid is deliberately split from its meaning. This widget owns layout,
/// bounds and hit-testing; the caller owns what a day *means* — which is the
/// only way one calendar serves a single-date picker, a two-tap range picker
/// and a date-of-birth picker. [isSelected] and [isInRange] are that seam.
///
/// [firstDate] and [lastDate] are dates, not a "no future days" flag. That
/// distinction is the reason this widget exists at all: the date-of-birth and
/// logs-range sheets both stop at today, while a block's Ends field has to
/// reach years ahead — so a calendar with a hard-wired ceiling could not have
/// served all of them, and two of them grew their own copy of this grid
/// instead.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.onMonthChanged,
    required this.firstDate,
    required this.lastDate,
    this.isSelected,
    this.isInRange,
    this.onDayTap,
  });

  /// First day of the displayed month. The calendar is controlled — the caller
  /// holds the month, so a sheet that re-renders mid-selection never loses it.
  final DateTime month;

  final ValueChanged<DateTime> onMonthChanged;

  /// Earliest and latest selectable days, inclusive. Both gate hit-testing and
  /// clamp month navigation, so a bounded calendar cannot be scrolled to a
  /// month where nothing can be picked. Time-of-day is ignored.
  final DateTime firstDate;
  final DateTime lastDate;

  /// Filled with accent — the single picked day, or a range's leading and
  /// trailing edge. Null when nothing is selected.
  final bool Function(DateTime day)? isSelected;

  /// Interior of a range: accentBg with accent text instead of a solid fill.
  /// Null outside range mode.
  final bool Function(DateTime day)? isInRange;

  final ValueChanged<DateTime>? onDayTap;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  bool get _isBounded => !firstDate.isAfter(lastDate);

  bool _isDisabled(DateTime day) =>
      day.isBefore(_day(firstDate)) || day.isAfter(_day(lastDate));

  bool get _canPrevMonth =>
      _firstOfMonth(month).isAfter(_firstOfMonth(firstDate));

  bool get _canNextMonth =>
      _firstOfMonth(month).isBefore(_firstOfMonth(lastDate));

  @override
  Widget build(BuildContext context) {
    final today = _day(DateTime.now());
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _monthNav(
              Icons.chevron_left,
              _canPrevMonth,
              () => onMonthChanged(
                DateTime(month.year, month.month - 1, 1),
              ),
            ),
            Expanded(
              child: Text(
                DateFormat('MMMM yyyy').format(month),
                textAlign: TextAlign.center,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.md,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
            _monthNav(
              Icons.chevron_right,
              _canNextMonth,
              () => onMonthChanged(
                DateTime(month.year, month.month + 1, 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (final d in const ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'])
              Expanded(
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  style: AppFonts.mono(fontSize: 13, color: AppColors.muted),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (!_isBounded)
          // Degenerate bounds would render an empty grid with no explanation;
          // say so instead of showing a blank month.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              'No selectable dates',
              textAlign: TextAlign.center,
              style: AppFonts.mono(fontSize: 13, color: AppColors.muted),
            ),
          )
        else
          ..._calendarRows(today),
      ],
    );
  }

  Widget _monthNav(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: lambdaBox(
          enabled ? ContainerTone.ghost : ContainerTone.field,
          radius: AppRadius.md,
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? AppColors.primary : AppColors.muted,
        ),
      ),
    );
  }

  List<Widget> _calendarRows(DateTime today) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = DateTime(month.year, month.month, 1).weekday - 1;
    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) _blankCell(),
      for (var d = 1; d <= daysInMonth; d++)
        _dayCell(DateTime(month.year, month.month, d), today),
    ];
    // Pad the last row out to seven. `Expanded` divides whatever is left
    // between however many children a row has, so a three-day final row would
    // render three cells a *third* of the grid wide — the dates landing under
    // the first three weekday headers, with nothing beneath the last four.
    // Every row has to carry seven slots for the columns to hold.
    while (cells.length % 7 != 0) {
      cells.add(_blankCell());
    }
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: cells.sublist(i, i + 7)),
        ),
      );
    }
    return rows;
  }

  /// An empty slot — the leading offset, and the tail of the last row. It must
  /// be an `Expanded` like a real cell, or the columns it stands in for
  /// collapse into the ones beside it.
  Widget _blankCell() => const Expanded(child: SizedBox());

  Widget _dayCell(DateTime d, DateTime today) {
    final disabled = _isDisabled(d);
    final selected = isSelected?.call(d) ?? false;
    final inRange = isInRange?.call(d) ?? false;

    Color bg = Colors.transparent;
    Color fg = AppColors.primary;
    if (selected) {
      bg = AppColors.accent;
      fg = AppColors.bg;
    } else if (inRange) {
      bg = AppColors.accentBg;
      fg = AppColors.accent;
    } else if (disabled) {
      fg = AppColors.muted.withValues(alpha: 0.4);
    }

    return Expanded(
      child: GestureDetector(
        onTap: disabled || onDayTap == null ? null : () => onDayTap!(d),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            // Today is only outlined when nothing else is claiming the cell —
            // a selection or a range already reads as "your date" and the
            // outline would compete with it.
            border: _sameDay(d, today) && !selected && !inRange
                ? Border.all(color: AppColors.accent.withValues(alpha: 0.35))
                : null,
          ),
          child: Text(
            '${d.day}',
            textAlign: TextAlign.center,
            style: AppFonts.mono(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
