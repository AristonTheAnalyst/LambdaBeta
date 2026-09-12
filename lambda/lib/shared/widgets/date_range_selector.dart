import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import '../../core/utils/date_range.dart';
import 'container_styles.dart';
import 'glass_button.dart';
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

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta, 1);
    if (next.isAfter(DateTime(_today.year, _today.month, 1))) return;
    setState(() => _month = next);
  }

  bool get _canNextMonth =>
      _month.isBefore(DateTime(_today.year, _today.month, 1));

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
                fontSize: 9,
                letterSpacing: 1.2,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // ── Calendar ──
            Row(
              children: [
                _monthNav(Icons.chevron_left, _month.isAfter(
                  DateTime(_today.year - 1, 1, 1),
                ), () => _shiftMonth(-1)),
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(_month),
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
                  () => _shiftMonth(1),
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
                      style: AppFonts.mono(
                        fontSize: 9,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ..._calendarRows(),
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
                  fontSize: 11,
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

  Widget _monthNav(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: lambdaBox(
          enabled ? ContainerTone.ghost : ContainerTone.field,
          radius: AppRadius.md,
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.primary : AppColors.muted,
        ),
      ),
    );
  }

  List<Widget> _calendarRows() {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = DateTime(_month.year, _month.month, 1).weekday - 1;
    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) const Expanded(child: SizedBox()),
      for (var d = 1; d <= daysInMonth; d++)
        _dayCell(DateTime(_month.year, _month.month, d)),
    ];
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: cells.sublist(
              i,
              (i + 7).clamp(0, cells.length),
            ),
          ),
        ),
      );
    }
    return rows;
  }

  Widget _dayCell(DateTime d) {
    final future = d.isAfter(_today);
    final range = _selection.customRange;
    final rStart = range?.start;
    final rEnd = range?.end;
    final inRange =
        rStart != null &&
        rEnd != null &&
        !d.isBefore(rStart) &&
        !d.isAfter(rEnd);
    final isEdge = inRange && (_sameDay(d, rStart) || _sameDay(d, rEnd));

    Color bg = Colors.transparent;
    Color fg = AppColors.primary;
    if (isEdge) {
      bg = AppColors.accent;
      fg = AppColors.bg;
    } else if (inRange) {
      bg = AppColors.accentBg;
      fg = AppColors.accent;
    } else if (future) {
      fg = AppColors.muted.withValues(alpha: 0.4);
    }

    return Expanded(
      child: GestureDetector(
        onTap: future ? null : () => _onDayTap(d),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: _sameDay(d, _today) && !inRange
                ? Border.all(
                    color: AppColors.accent.withValues(alpha: 0.35),
                  )
                : null,
          ),
          child: Text(
            '${d.day}',
            textAlign: TextAlign.center,
            style: AppFonts.mono(
              fontSize: 11,
              fontWeight: isEdge ? FontWeight.w700 : FontWeight.w500,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
