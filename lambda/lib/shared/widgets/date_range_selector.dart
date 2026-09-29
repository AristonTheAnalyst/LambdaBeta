import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import '../../core/utils/date_range.dart';
import 'container_styles.dart';
import 'glass_button.dart';
import 'month_calendar.dart';
import 'section_divider.dart';
import 'slide_up_modal.dart';

/// Opens the date-range selector sheet. Returns the new selection, or null
/// when cancelled. Nothing commits until Apply — the sheet is pure.
Future<DateRangeSelection?> showDateRangeSelector(
  BuildContext context, {
  required DateRangeSelection initial,
}) {
  return showLambdaModal<DateRangeSelection>(
    context,
    fitContent: true,
    child: _DateRangeSheet(initial: initial),
  );
}

class _DateRangeSheet extends StatefulWidget {
  const _DateRangeSheet({required this.initial});

  final DateRangeSelection initial;

  @override
  State<_DateRangeSheet> createState() => _DateRangeSheetState();
}

class _DateRangeSheetState extends State<_DateRangeSheet> {
  late DateRangeSelection _selection = widget.initial;

  /// First day of the displayed calendar month.
  late DateTime _month;

  /// Pending custom-range start while the user is mid-pick.
  DateTime? _rangeStart;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// The range filter looks back a year and never past today — running history
  /// has no future to show. These are the only bounds the calendar gets; the
  /// grid itself has no opinion about what is selectable.
  DateTime get _firstDate => DateTime(_today.year - 1, 1, 1);

  @override
  void initState() {
    super.initState();
    final range = widget.initial.customRange;
    _month = DateTime(
      (range?.start ?? DateTime.now()).year,
      (range?.start ?? DateTime.now()).month,
      1,
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _selectPreset(DateRangePreset p) {
    setState(() {
      _selection = DateRangeSelection.preset(p);
      _rangeStart = null;
    });
  }

  void _onDayTap(DateTime d) {
    final start = _rangeStart;
    if (start == null || d.isBefore(start)) {
      // First tap (or a restart): begin a fresh single-day range.
      setState(() {
        _rangeStart = d;
        _selection = DateRangeSelection.custom(
          DateTimeRange(start: d, end: d),
        );
      });
    } else {
      setState(() {
        _rangeStart = null;
        _selection = DateRangeSelection.custom(
          DateTimeRange(start: start, end: d),
        );
      });
    }
  }

  /// Days between the pending range's ends, inclusive. A single-day pick has
  /// start == end, so it reads as both an edge and a range — drawn solid accent,
  /// which is what "the day you chose" should look like.
  bool _inRange(DateTime d) {
    final range = _selection.customRange;
    if (range == null) return false;
    return !d.isBefore(range.start) && !d.isAfter(range.end);
  }

  bool _isEdge(DateTime d) {
    final range = _selection.customRange;
    if (range == null || !_inRange(d)) return false;
    return _sameDay(d, range.start) || _sameDay(d, range.end);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionDivider('DATE RANGE'),
            const SizedBox(height: AppSpacing.lg),
            // ── Presets ──
            Row(
              children: [
                for (final p in const [
                  DateRangePreset.all,
                  DateRangePreset.m1,
                  DateRangePreset.m3,
                  DateRangePreset.m6,
                  DateRangePreset.y1,
                ]) ...[
                  Expanded(child: _presetChip(p)),
                  if (p != DateRangePreset.y1)
                    const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'OR CUSTOM',
              textAlign: TextAlign.center,
              style: AppFonts.mono(
                fontSize: 13,
                letterSpacing: 1.2,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // ── Calendar ──
            MonthCalendar(
              month: _month,
              onMonthChanged: (m) => setState(() => _month = m),
              firstDate: _firstDate,
              lastDate: _today,
              isSelected: _isEdge,
              isInRange: _inRange,
              onDayTap: _onDayTap,
            ),
            const SizedBox(height: AppSpacing.md),
            // ── Live label ──
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: lambdaBox(
                ContainerTone.ghost,
                radius: AppRadius.md,
              ),
              child: Text(
                _selection.label(_today),
                textAlign: TextAlign.center,
                style: AppFonts.mono(
                  fontSize: 13,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // ── Actions ──
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
                    ).pop(_selection),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetChip(DateRangePreset p) {
    final active = _selection.preset == p && _selection.customRange == null;
    final label = switch (p) {
      DateRangePreset.all => 'All',
      DateRangePreset.m1 => '1M',
      DateRangePreset.m3 => '3M',
      DateRangePreset.m6 => '6M',
      DateRangePreset.y1 => '1Y',
      DateRangePreset.custom => 'Custom',
    };
    return GestureDetector(
      onTap: () => _selectPreset(p),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: lambdaBox(
          active ? ContainerTone.accent : ContainerTone.ghost,
          radius: AppRadius.md,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            fontWeight: FontWeight.w600,
            color: active ? AppColors.accent : AppColors.muted,
          ),
        ),
      ),
    );
  }

}
