import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import 'container_styles.dart';
import 'glass_button.dart';
import 'month_calendar.dart';
import 'section_divider.dart';
import 'slide_up_modal.dart';

/// Opens a single-date picker in the app's own calendar language — the same
/// month nav, weekday header and day cells as the logs date filter and the
/// date-of-birth picker, collapsed to one day. Returns the picked date, or null
/// when cancelled. Nothing commits until Apply — the sheet is pure.
///
/// [firstDate] and [lastDate] are required because the callers genuinely
/// differ: a date of birth stops at today, a scheduled review may not, and a
/// block's end date reaches years ahead. Making them explicit is what keeps
/// this one widget from having to guess.
Future<DateTime?> showDatePickerSheet(
  BuildContext context, {
  required DateTime? initial,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'DATE',
}) {
  return showLambdaModal<DateTime>(
    context,
    fitContent: true,
    child: _DatePickerSheet(
      initial: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
    ),
  );
}

class _DatePickerSheet extends StatefulWidget {
  const _DatePickerSheet({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  final DateTime? initial;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  late DateTime? _picked;
  late DateTime _month;

  /// The bounds, widened to hold [initial] when it falls outside them. An
  /// existing value must stay visible and re-pickable — clamping it would
  /// silently move a date the user never touched, and hiding it would strand
  /// them with a blank grid.
  late final DateTime _firstDate = _widen(widget.firstDate, widget.initial, earlier: true);
  late final DateTime _lastDate = _widen(widget.lastDate, widget.initial, earlier: false);

  static DateTime _widen(DateTime bound, DateTime? value, {required bool earlier}) {
    if (value == null) return bound;
    if (earlier && value.isBefore(bound)) return value;
    if (!earlier && value.isAfter(bound)) return value;
    return bound;
  }

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
    _month = _monthFor(_picked ?? DateTime.now());
  }

  /// First day of the month holding [d], pulled into the selectable range so a
  /// calendar whose whole range is in the future (or the past) still opens on a
  /// month it can offer.
  DateTime _monthFor(DateTime d) {
    var day = DateTime(d.year, d.month, d.day);
    if (day.isBefore(_firstDate)) day = _firstDate;
    if (day.isAfter(_lastDate)) day = _lastDate;
    return DateTime(day.year, day.month, 1);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionDivider(widget.title),
            const SizedBox(height: AppSpacing.lg),
            MonthCalendar(
              month: _month,
              onMonthChanged: (m) => setState(() => _month = m),
              firstDate: _firstDate,
              lastDate: _lastDate,
              isSelected: (d) => _picked != null && _sameDay(d, _picked!),
              onDayTap: (d) => setState(() => _picked = d),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
              child: Text(
                _picked == null
                    ? 'Select date'
                    : DateFormat('d MMMM yyyy').format(_picked!),
                textAlign: TextAlign.center,
                style: AppFonts.mono(
                  fontSize: 13,
                  color: _picked == null ? AppColors.muted : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Cancel',
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: GlassButton(
                    label: 'Apply',
                    solid: true,
                    onPressed: () => Navigator.of(
                      context,
                      rootNavigator: true,
                    ).pop(_picked),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
