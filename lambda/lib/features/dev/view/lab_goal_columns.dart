import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import 'session_cards_screen.dart';

/// One goal in the lab's preview shape: what it is, the one date it states
/// (met on, or due by — null = no date), and the day it was created.
class GoalLabRow {
  const GoalLabRow(
    this.name,
    this.date, {
    required this.met,
    required this.created,
  });

  final String name;
  final DateTime? date;
  final bool met;
  final DateTime created;
}

/// The goals' two-column ledger — OPEN | COMPLETE — shared by the Friend
/// Screen's Goals tab and the Exercise screen so the two can never drift
/// (2026-11-03).
class GoalLabColumns extends StatelessWidget {
  const GoalLabColumns({
    super.key,
    required this.complete,
    required this.open,
    this.onTap,
  });

  final List<GoalLabRow> complete;
  final List<GoalLabRow> open;

  /// A row's door — the entity screen behind the goal. Null leaves the rows
  /// inert.
  final void Function(GoalLabRow goal)? onTap;

  @override
  Widget build(BuildContext context) {
    Widget column(
      String label,
      int count,
      List<GoalLabRow> rows, {
      required bool met,
    }) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                '$label · $count',
                style: AppFonts.mono(
                  fontSize: AppTextStyles.xs,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.inkSecondary,
                ),
              ),
            ),
            for (final goal in rows)
              _GoalRow(goal: goal, met: met, onTap: onTap),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        column('OPEN', open.length, open, met: false),
        Container(
          width: 1,
          margin: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
          ),
          color: AppColors.border,
        ),
        column('COMPLETE', complete.length, complete, met: true),
      ],
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal, required this.met, this.onTap});

  final GoalLabRow goal;
  final bool met;
  final void Function(GoalLabRow goal)? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            goal.name,
            style: AppFonts.ui(
              fontSize: AppTextStyles.body,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          _GoalMetaLine(
            icon: LucideIcons.crosshair,
            text: goalWhen(goal),
            color: met ? AppColors.success : AppColors.inkSecondary,
          ),
          const SizedBox(height: 2),
          _GoalMetaLine(
            icon: LucideIcons.notebookPen,
            text: goalCreated(goal),
            color: AppColors.inkSecondary,
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      onTap: () => onTap!(goal),
      behavior: HitTestBehavior.opaque,
      child: row,
    );
  }
}

/// One icon-led line under a goal's name: the glyph says which date it is —
/// the goal's own bullseye, or the notebook that wrote it down (2026-11-02).
class _GoalMetaLine extends StatelessWidget {
  const _GoalMetaLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: AppTextStyles.xs, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.mono(fontSize: AppTextStyles.xs, color: color),
          ),
        ),
      ],
    );
  }
}

/// A written date in the goals' voice: `24 oct`, with the year when it is
/// not this one — `14 oct 2025`, `1 feb 2027` — so last year and next year
/// are never guessed. [withYear] is false where the days reading already
/// places the date (2026-11-02).
String goalDate(DateTime date, {bool withYear = false}) {
  final written = '${date.day} ${_months[date.month - 1]}';
  if (!withYear || date.year == DateTime.now().year) return written;
  return '$written ${date.year}';
}

/// The goal's state date: the day it was met, or the deadline it chases —
/// the glyph in front says which. Within 99 days it also reads as a count
/// of days — `24 oct · 9d`, `15 nov · 13d` — and a goal with no date says
/// so (2026-11-02).
String goalWhen(GoalLabRow goal) {
  final date = goal.date;
  if (date == null) return 'no date';
  final days = daysReading(date);
  final written = goalDate(date, withYear: days == null);
  return days == null ? written : '$written · $days';
}

/// The day the goal was set, in the same written voice (2026-11-02).
String goalCreated(GoalLabRow goal) =>
    goalDate(goal.created, withYear: true);

const _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];
