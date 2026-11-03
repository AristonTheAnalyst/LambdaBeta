import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/session.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/feeling_rating.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/session_log_card.dart';

final List<SessionCardSample> kSessionCardSamples = <SessionCardSample>[
  SessionCardSample(
    date: DateTime(2026, 10, 28),
    plan: 'Leg Day',
    pre: 4,
    post: 4,
    exercises: const [
      ('Back Squat', 4, 2),
      ('Leg Press', 3, 0),
      ('Leg Curl', 3, 0),
      ('Leg Extension', 3, 0),
      ('Calf Raise', 3, 0),
      ('Hip Thrust', 3, 0),
    ],
  ),
  SessionCardSample(
    date: DateTime(2026, 10, 21),
    plan: 'Push A + Accessories',
    pre: 5,
    post: 4,
    exercises: const [
      ('Bench Press', 4, 1),
      ('Cable Row', 3, 0),
    ],
  ),
  SessionCardSample(
    date: DateTime(2026, 10, 17),
    plan: 'Full Body',
    pre: 3,
    post: 4,
    exercises: const [
      ('Bench Press', 3, 1),
      ('Back Squat', 3, 0),
      ('Cable Row', 3, 0),
    ],
  ),
  SessionCardSample(
    date: DateTime(2026, 10, 12),
    plan: 'Lower Power',
    pre: 4,
    post: 3,
    exercises: const [
      ('Deadlift', 5, 2),
      ('Front Squat', 4, 0),
      ('Leg Curl', 3, 0),
    ],
  ),
  SessionCardSample(
    date: DateTime(2026, 10, 6),
    plan: null,
    pre: 2,
    post: 3,
    exercises: const [
      ('Pull-ups', 4, 1),
      ('Dip', 3, 0),
    ],
  ),
  SessionCardSample(
    date: DateTime(2026, 9, 29),
    plan: 'Upper Hypertrophy',
    pre: 4,
    post: 4,
    exercises: const [
      ('Overhead Press', 4, 0),
      ('Cable Row', 4, 0),
      ('Lateral Raise', 3, 0),
      ('Face Pull', 3, 0),
    ],
  ),
  SessionCardSample(
    date: DateTime(2026, 10, 26),
    plan: null,
    pre: 5,
    post: 4,
    exercises: const [
      ('Bench Press', 4, 1),
      ('Cable Row', 3, 0),
    ],
  ),
  // Last year: the rail trades the weekday for the year, so the card reads
  // `14 / OCT / 2025` rather than guessing which October (2026-11-02).
  SessionCardSample(
    date: DateTime(2025, 10, 14),
    plan: 'Upper Power',
    pre: 3,
    post: 4,
    exercises: const [
      ('Overhead Press', 3, 0),
      ('Cable Row', 3, 0),
      ('Lateral Raise', 3, 0),
    ],
  ),
];

/// Session-card designs, side by side (2026-10-31).
///
/// The first card is the one that ships — the real `SessionLogCard`, not a
/// copy. The rest are new shapes for the same fact, drawn from scratch with
/// the app's tokens but none of the old card's layout: a ledger row, a date
/// tile and a ticket. Every card carries the same two sample sessions, so
/// the comparison is layout against layout.
///
/// Static: nothing here is wired in. Say a design's name and it becomes the
/// Sessions list's card.
class SessionCardsScreen extends StatelessWidget {
  const SessionCardsScreen({super.key});


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          const PageHeader(title: 'Session Cards'),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.lg + ScrollShrinkNavBar.contentInset(context),
              ),
              children: [
                Text(
                  'Same two sessions, four shapes. The first is the real '
                  'card that ships; the rest are drawn from scratch. Name '
                  "the one you want and it replaces the Sessions list's "
                  'card.',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    height: 1.4,
                    color: AppColors.inkSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                const _DesignLabel(
                  'CURRENT — SHIPPED',
                  'The 2×2 identity grid, hairline-separated, exercises '
                  'centred below it.',
                  current: true,
                ),
                for (final sample in kSessionCardSamples)
                  SessionLogCard(
                    workout: sample.toSessionWithSets(),
                    onTap: () {},
                    prsByExercise: sample.prsByExercise.isEmpty
                        ? null
                        : sample.prsByExercise,
                  ),
                const SizedBox(height: AppSpacing.xl),

                const _DesignLabel(
                  'A — LEDGER',
                  'No card chrome: a hairline row, the date standing in a '
                  'left column like a ledger entry.',
                ),
                for (final sample in kSessionCardSamples) _LedgerCard(sample: sample),
                const SizedBox(height: AppSpacing.xl),

                const _DesignLabel(
                  'A′ — LEDGER, LISTED',
                  'The same ledger, expanded: PRE and POST take the summary '
                  'line, every exercise is listed at the card\'s own height, '
                  'and each one carries its own PRs instead of a total.',
                ),
                for (final sample in kSessionCardSamples)
                  _LedgerListCard(sample: sample),
                const SizedBox(height: AppSpacing.xl),

                const _DesignLabel(
                  'A″ — LEDGER, CHIPS',
                  'Everything on four lines: the ratings squeezed to one '
                  'line, and each exercise a chip that carries its own PRs, '
                  'so six exercises and two cost the same height.',
                ),
                for (final sample in kSessionCardSamples) _ChipsCard(sample: sample),
                const SizedBox(height: AppSpacing.xl),

                const _DesignLabel(
                  'A‴ — LEDGER, CHIPS, LARGE',
                  'The chips ledger with room to breathe: a bigger day and '
                  'date, a bigger plan name sized to hold the longest name '
                  'the app allows, air around the ratings, and a larger PR '
                  'total.',
                ),
                for (final sample in kSessionCardSamples)
                  LedgerChipsCard(sample: sample),
                const SizedBox(height: AppSpacing.xl),

                const _DesignLabel(
                  'B″ — LEDGER, GRID',
                  'Two columns of exercises keep the height down; trophies '
                  'ride inline with the name instead of a far-right column.',
                ),
                for (final sample in kSessionCardSamples) _GridCard(sample: sample),
                const SizedBox(height: AppSpacing.xl),

                const _DesignLabel(
                  'B — DATE TILE',
                  'One recessed tile for the day; everything else is one '
                  'column of type beside it.',
                ),
                for (final sample in kSessionCardSamples) _DateTileCard(sample: sample),
                const SizedBox(height: AppSpacing.xl),

                const _DesignLabel(
                  'C — TICKET',
                  'A header strip stamped with the date, then the exercises '
                  'as a scrolling list — each row carries its own PRs, not '
                  'its set count.',
                ),
                for (final sample in kSessionCardSamples) _TicketCard(sample: sample),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesignLabel extends StatelessWidget {
  const _DesignLabel(this.name, this.note, {this.current = false});

  final String name;
  final String note;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.inkSecondary,
                  ),
                ),
              ),
              if (current)
                Text(
                  'IN USE',
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            note,
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              height: 1.4,
              color: AppColors.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A — ledger row: date column, hairline, then the facts.
class _LedgerCard extends StatelessWidget {
  const _LedgerCard({required this.sample});

  final SessionCardSample sample;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sample.date.day}',
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xl,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  _month(sample.date),
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: AppColors.accent,
                  ),
                ),
                Text(
                  _weekday(sample.date),
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 56,
            margin: const EdgeInsets.only(right: AppSpacing.md),
            color: AppColors.border,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sample.plan ?? 'Freestyle Session',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.body,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    if (sample.totalPrs > 0) _PrChip(count: sample.totalPrs),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  sample.exerciseLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.inkSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    _MiniStars(label: 'PRE', value: sample.pre),
                    const SizedBox(width: AppSpacing.md),
                    _MiniStars(label: 'POST', value: sample.post),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A′ — the ledger with its whole list: PRE/POST on the summary line,
/// every exercise under it, each with its own PRs, and a divider that runs
/// the card's full height.
class _LedgerListCard extends StatelessWidget {
  const _LedgerListCard({required this.sample});

  final SessionCardSample sample;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 52,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${sample.date.day}',
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.xl,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    _month(sample.date),
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.xs,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: AppColors.accent,
                    ),
                  ),
                  Text(
                    _weekday(sample.date),
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.xs,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              margin: const EdgeInsets.only(right: AppSpacing.md),
              color: AppColors.border,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sample.plan ?? 'Freestyle Session',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.body,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // The shipped card's reading, kept: label above, stars
                  // under it, the two halves sharing the width evenly.
                  Row(
                    children: [
                      Expanded(
                        child: _StackedStars(
                          label: 'PRE',
                          value: sample.pre,
                        ),
                      ),
                      Expanded(
                        child: _StackedStars(
                          label: 'POST',
                          value: sample.post,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final (name, _, prs) in sample.exercises)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.ui(
                                fontSize: AppTextStyles.sm,
                                color: AppColors.inkSecondary,
                              ),
                            ),
                          ),
                          if (prs > 0) _PrChip(count: prs),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A‴ — the chips ledger, sized up: a 30pt day and a 14pt date line, an
/// 18pt plan name that holds a 20-character name beside the PR total, and
/// air above and below the ratings.
class LedgerChipsCard extends StatelessWidget {
  const LedgerChipsCard({
    super.key,
    required this.sample,
    this.topPadding = AppSpacing.lg,
  });

  final SessionCardSample sample;

  /// The card's leading space. A card standing right under a toolbar passes
  /// 0, so the bar's own padding is the only gap.
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    // Within 99 days the rail carries a compact `5D` beneath the weekday,
    // in the weekday's own ink: the day and month keep the written date, so
    // the card says both. A session from another year — and not inside the
    // 99-day window, where the day count already places it — trades the
    // weekday for the year instead, which is the one that cannot be guessed
    // (2026-11-02).
    final days = railDaysReading(sample.date);
    final lastLine = days == null && sample.date.year != DateTime.now().year
        ? '${sample.date.year}'
        : _weekday(sample.date);
    return Container(
      // 16 above and below: the space from content to the rule, and from
      // the rule to the next card's content, are the same step.
      padding: EdgeInsets.only(
        top: topPadding,
        bottom: AppSpacing.lg,
      ),
      // Bottom rule only: the strip above already draws a line, and a card
      // stacked under another one shares that neighbour's bottom rule, so a
      // top rule here would double every separator.
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${sample.date.day}',
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.xxl,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _month(sample.date),
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.sm,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: AppColors.accent,
                    ),
                  ),
                  Text(
                    lastLine,
                    maxLines: 1,
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.sm,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                  // The relative reading sits beneath the weekday, in its
                  // own ink — `WED` over `5D` — so the written date and
                  // the count read as one stacked date block (2026-11-02).
                  if (days != null)
                    Text(
                      days,
                      maxLines: 1,
                      style: AppFonts.mono(
                        fontSize: AppTextStyles.sm,
                        color: AppColors.inkSecondary,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              width: 1,
              margin: const EdgeInsets.only(right: AppSpacing.md),
              color: AppColors.border,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          sample.plan ?? 'Freestyle Session',
                          maxLines: 2,
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.lg,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      if (sample.totalPrs > 0)
                        _PrChip(count: sample.totalPrs, large: true),
                    ],
                  ),
                  // Air around the ratings: the line is the card's second
                  // voice, not a caption folded into the chips.
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      _MiniStars(label: 'PRE', value: sample.pre),
                      const SizedBox(width: AppSpacing.lg),
                      _MiniStars(label: 'POST', value: sample.post),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (name, _, prs) in sample.exercises)
                        _ExerciseChip(name: name, prs: prs),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A″ — chips: ratings on one line, exercises as wrapping chips.
class _ChipsCard extends StatelessWidget {
  const _ChipsCard({required this.sample});

  final SessionCardSample sample;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dateRail(sample),
            Container(
              width: 1,
              margin: const EdgeInsets.only(right: AppSpacing.md),
              color: AppColors.border,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sample.plan ?? 'Freestyle Session',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.body,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      if (sample.totalPrs > 0)
                        _PrChip(count: sample.totalPrs),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _MiniStars(label: 'PRE', value: sample.pre),
                      const SizedBox(width: AppSpacing.md),
                      _MiniStars(label: 'POST', value: sample.post),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (name, _, prs) in sample.exercises)
                        _ExerciseChip(name: name, prs: prs),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// B″ — grid: two columns of exercises, trophies inline with the names.
class _GridCard extends StatelessWidget {
  const _GridCard({required this.sample});

  final SessionCardSample sample;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dateRail(sample),
            Container(
              width: 1,
              margin: const EdgeInsets.only(right: AppSpacing.md),
              color: AppColors.border,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          sample.plan ?? 'Freestyle Session',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.body,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _MiniStars(label: 'PRE', value: sample.pre),
                          const SizedBox(height: 2),
                          _MiniStars(label: 'POST', value: sample.post),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (var row = 0; row * 2 < sample.exercises.length; row++)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ExerciseLine(
                              exercise: sample.exercises[row * 2],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: row * 2 + 1 < sample.exercises.length
                                ? _ExerciseLine(
                                    exercise: sample.exercises[row * 2 + 1],
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ledger's date column, shared by the derived designs.
Widget _dateRail(SessionCardSample sample) {
  return SizedBox(
    width: 52,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${sample.date.day}',
          style: AppFonts.mono(
            fontSize: AppTextStyles.xl,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        Text(
          _month(sample.date),
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: AppColors.accent,
          ),
        ),
        Text(
          _weekday(sample.date),
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            color: AppColors.inkSecondary,
          ),
        ),
      ],
    ),
  );
}

class _ExerciseChip extends StatelessWidget {
  const _ExerciseChip({required this.name, required this.prs});

  final String name;
  final int prs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            // One line per chip: a long name ellipsizes inside its own
            // chip instead of wrapping it to two lines.
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.ui(
              fontSize: AppTextStyles.xs,
              color: AppColors.inkSecondary,
            ),
          ),
          // The PR reads as the top-right chip does: its own dark-orange
          // panel, not outline ink floating on the chip.
          if (prs > 0) ...[
            const SizedBox(width: 6),
            _PrBadge(count: prs),
          ],
        ],
      ),
    );
  }
}

/// One exercise in the two-column grid: the name, its trophy beside it.
class _ExerciseLine extends StatelessWidget {
  const _ExerciseLine({required this.exercise});

  final (String, int, int) exercise;

  @override
  Widget build(BuildContext context) {
    final (name, _, prs) = exercise;
    return Row(
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.inkSecondary,
            ),
          ),
        ),
        if (prs > 0) ...[
          const SizedBox(width: 6),
          _PrBadge(count: prs),
        ],
      ],
    );
  }
}

/// The small PR badge: trophy and count on `accentBg`, the same ground the
/// card's top-right chip stands on, so a PR reads identically wherever it
/// appears.
class _PrBadge extends StatelessWidget {
  const _PrBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.trophy, size: 12, color: AppColors.accent),
          const SizedBox(width: 2),
          Text(
            '$count',
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// B — date tile: a recessed square for the day, one column beside it.
class _DateTileCard extends StatelessWidget {
  const _DateTileCard({required this.sample});

  final SessionCardSample sample;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${sample.date.day}',
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.lg,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    _month(sample.date),
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.xs,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sample.plan ?? 'Freestyle Session',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.body,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      if (sample.totalPrs > 0)
                        _PrChip(count: sample.totalPrs),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sample.exerciseLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.sm,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                  if (sample.exercises.length > 3) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.chevronDown,
                          size: 12,
                          color: AppColors.inkSecondary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'scroll for ${sample.exercises.length - 3} more',
                          style: AppFonts.mono(
                            fontSize: AppTextStyles.xs,
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      _MiniStars(label: 'PRE', value: sample.pre),
                      const SizedBox(width: AppSpacing.md),
                      _MiniStars(label: 'POST', value: sample.post),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// C — ticket: a stamped header, then one row per fact.
class _TicketCard extends StatefulWidget {
  const _TicketCard({required this.sample});

  final SessionCardSample sample;

  /// Tall enough for three rows; more exercises scroll inside the card
  /// rather than being cut off or growing it without bound.
  static const _rowsHeight = 3 * 24.0;

  @override
  State<_TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends State<_TicketCard> {
  /// One controller per card so the scrollbar can stay visible — the card
  /// has to say that it scrolls, or the fourth exercise is invisible.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sample = widget.sample;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.border),
                ),
              ),
              child: Text(
                '${_weekday(sample.date)} ${sample.date.day} '
                '${_month(sample.date)}',
                style: AppFonts.mono(
                  fontSize: AppTextStyles.xs,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: AppColors.accent,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sample.plan ?? 'Freestyle Session',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.body,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      if (sample.totalPrs > 0)
                        _PrChip(count: sample.totalPrs),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: _TicketCard._rowsHeight,
                    ),
                    child: SingleChildScrollView(
                      controller: _scroll,
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // The right column is the exercise's own PRs, not
                          // its set count: what the session WON, and where.
                          for (final (name, _, prs) in sample.exercises)
                            SizedBox(
                              height: 24,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppFonts.ui(
                                        fontSize: AppTextStyles.sm,
                                        color: AppColors.inkSecondary,
                                      ),
                                    ),
                                  ),
                                  if (prs > 0) _PrChip(count: prs),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (sample.exercises.length > 3) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.chevronDown,
                          size: 12,
                          color: AppColors.inkSecondary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'scroll for ${sample.exercises.length - 3} more',
                          style: AppFonts.mono(
                            fontSize: AppTextStyles.xs,
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      _MiniStars(label: 'PRE', value: sample.pre),
                      const SizedBox(width: AppSpacing.md),
                      _MiniStars(label: 'POST', value: sample.post),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rating read the way the shipped card reads it — the word above,
/// the stars under it — for the designs that split the row in two.
class _StackedStars extends StatelessWidget {
  const _StackedStars({required this.label, required this.value});

  final String label;
  final int value;

  static const double _size = 14;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: AppColors.inkSecondary,
          ),
        ),
        const SizedBox(height: 2),
        FeelingRating(value: value, size: _size, spacing: 2, framed: false),
      ],
    );
  }
}

/// `PRE ★★★★☆` at list size.
class _MiniStars extends StatelessWidget {
  const _MiniStars({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: AppColors.inkSecondary,
          ),
        ),
        const SizedBox(width: 4),
        FeelingRating(value: value, size: 11, spacing: 1, framed: false),
      ],
    );
  }
}

class _PrChip extends StatelessWidget {
  const _PrChip({required this.count, this.large = false});

  final int count;

  /// The ledger's own chip: a step up in trophy, number and padding.
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 8 : 6,
        vertical: large ? 4 : 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.trophy,
            size: large ? 14 : 12,
            color: AppColors.accent,
          ),
          SizedBox(width: large ? 4 : 3),
          Text(
            '+$count',
            style: AppFonts.mono(
              fontSize: large ? AppTextStyles.caption : AppTextStyles.xs,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

String _month(DateTime d) =>
    const ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'][d.month - 1];

String _weekday(DateTime d) =>
    const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][d.weekday - 1];

/// How far either side of today a written date also reads as a count of
/// days: 99 days, the most that still fits in two digits. At 100 the count
/// drops and the written date stands alone (2026-11-02).
const recentDateWindow = Duration(days: 99);

/// `9d`, `1d`, `today` — or null when [date] is outside
/// [recentDateWindow]. Both sides count: a session date and a goal's
/// deadline read the same way, and the row's own verb says which side of
/// today it is. Calendar days, so the reading does not drift with the hour
/// it is read at.
String? daysReading(DateTime date, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(date);
  final days = day.difference(today).inDays;
  if (days.abs() > recentDateWindow.inDays) return null;
  if (days == 0) return 'today';
  return '${days.abs()}d';
}

/// The date rail's short reading: `5D` for a session within 99 days, and
/// `TODAY` for one today. Null outside the window. Sessions
/// are always past, so this never invents a future reading for a date the
/// rail cannot hold.
String? railDaysReading(DateTime date, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(date);
  final days = day.difference(today).inDays;
  if (days > 0 || days < -recentDateWindow.inDays) return null;
  return days == 0 ? 'TODAY' : '${-days}D';
}

/// One sample session, in the shape every design carries.
class SessionCardSample {
  const SessionCardSample({
    required this.date,
    required this.plan,
    required this.pre,
    required this.post,
    required this.exercises,
  });

  final DateTime date;
  final String? plan;
  final int pre;
  final int post;
  /// name, sets, PRs gained on that exercise.
  final List<(String, int, int)> exercises;

  int get totalPrs => exercises.fold(0, (sum, e) => sum + e.$3);

  String get exerciseLine => exercises.map((e) => e.$1).join(' · ');

  /// Per-exercise PR counts, keyed the way the shipped card reads them.
  Map<String, int> get prsByExercise => {
    for (final (name, _, prs) in exercises)
      if (prs > 0) name: prs,
  };

  /// The shipped card's model, built from the same facts.
  SessionWithSets toSessionWithSets() {
    final sets = <SessionExerciseSet>[];
    for (final (name, count, _) in exercises) {
      for (var n = 1; n <= count; n++) {
        sets.add(
          SessionExerciseSet(
            sessionExerciseSetId: 'set-${date.day}-$name-$n',
            sessionExerciseId: 'ex-${date.day}-$name',
            sessionId: 'session-${date.day}',
            userId: 'me',
            setNumber: n,
            reps: const [8],
            exerciseId: name,
            weight: 60,
            exerciseName: name,
          ),
        );
      }
    }
    return SessionWithSets(
      session: Session(
        sessionId: 'session-${date.day}',
        userId: 'me',
        createdDatetime: DateTime(date.year, date.month, date.day, 18),
        endDatetime: DateTime(date.year, date.month, date.day, 19),
        plannedSessionName: plan,
        preFeeling: pre,
        feeling: post,
      ),
      sets: sets,
    );
  }
}
