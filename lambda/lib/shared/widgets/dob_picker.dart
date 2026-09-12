import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import 'container_styles.dart';
import 'glass_button.dart';
import 'section_divider.dart';
import 'slide_up_modal.dart';

/// Opens the date-of-birth picker sheet — the same calendar language as the
/// logs date filter (month nav, weekday header, day cells), collapsed to a
/// single day. Returns the picked date, or null when cancelled. Nothing
/// commits until Apply — the sheet is pure.
Future<DateTime?> showDateOfBirthPicker(
  BuildContext context, {
  required DateTime? initial,
}) {
  return showLambdaModal<DateTime>(
    context,
    fitContent: true,
    child: _DobSheet(initial: initial),
  );
}

class _DobSheet extends StatefulWidget {
  const _DobSheet({required this.initial});

  final DateTime? initial;

  @override
  State<_DobSheet> createState() => _DobSheetState();
}

class _DobSheetState extends State<_DobSheet> {
  static final DateTime _firstMonth = DateTime(1900, 1, 1);

  late DateTime? _picked = widget.initial;

  /// First day of the displayed calendar month.
  late DateTime _month;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    final base = widget.initial ?? _today;
    _month = DateTime(base.year, base.month, 1);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta, 1);
    if (next.isBefore(_firstMonth)) return;
    if (next.isAfter(DateTime(_today.year, _today.month, 1))) return;
    setState(() => _month = next);
  }

  bool get _canPrevMonth => _month.isAfter(_firstMonth);

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
            const SectionDivider('DATE OF BIRTH'),
            const SizedBox(height: AppSpacing.lg),
            // ── Calendar ──
            Row(
              children: [
                _monthNav(Icons.chevron_left, _canPrevMonth, () => _shiftMonth(-1)),
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
                _monthNav(Icons.chevron_right, _canNextMonth, () => _shiftMonth(1)),
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
                        fontSize: 13,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: lambdaBox(
                ContainerTone.ghost,
                radius: AppRadius.md,
              ),
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
            children: cells.sublist(i, (i + 7).clamp(0, cells.length)),
          ),
        ),
      );
    }
    return rows;
  }

  Widget _dayCell(DateTime d) {
    final future = d.isAfter(_today);
    final selected = _picked != null && _sameDay(d, _picked!);

    Color bg = Colors.transparent;
    Color fg = AppColors.primary;
    if (selected) {
      bg = AppColors.accent;
      fg = AppColors.bg;
    } else if (future) {
      fg = AppColors.muted.withValues(alpha: 0.4);
    }

    return Expanded(
      child: GestureDetector(
        onTap: future ? null : () => setState(() => _picked = d),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: _sameDay(d, _today) && !selected
                ? Border.all(
                    color: AppColors.accent.withValues(alpha: 0.35),
                  )
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
}
