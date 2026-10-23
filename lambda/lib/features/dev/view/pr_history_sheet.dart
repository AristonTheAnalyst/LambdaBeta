import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../session/model/pr_engine.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/menu_popover.dart';
import '../../../shared/widgets/pr_event_row.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/user_name_text.dart';

/// The PR History sheet — every PR an exercise ever logged, newest first,
/// each one sitting beside the frontier value(s) it beat (2026-10-21).
///
/// Dev-only for now: opened from the PR History demo's exercise card. The
/// real session's PRs pill is still the greyed placeholder, so nothing in the
/// app reaches this sheet yet.
Future<void> showPrHistorySheet(
  BuildContext context, {
  required String exerciseName,
  required List<PrEvent> prs,
}) {
  return showLambdaModal<void>(
    context,
    child: _PrHistorySheet(exerciseName: exerciseName, prs: prs),
  );
}

/// UTC midnight of a date's calendar day — DST can make two adjacent days
/// 23 or 25 hours apart, which would otherwise round a 1-day gap to 0.
DateTime _calendarDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

/// How long before this PR the previous one landed, said the way a person
/// would say it.
String _sinceLabel(int days) => switch (days) {
  0 => 'Same day',
  1 => '1 day prior',
  _ => '$days days prior',
};

/// The variation filter's answer for the unvaried line. A variation id is
/// never empty, so the empty string sits safely beside a real id and null —
/// which is "any variation".
const String _noVariationId = '';

/// The variation badge's ceiling: the 20-character name cap at this mono size
/// (20 × 6.6 + 12 of padding ≈ 144). Bounded rather than `Flexible` — a flex
/// child is handed its share of the row *before* the outcome's `Expanded` is
/// measured, and the share it leaves unused lands to the outcome's right,
/// which held a variated FIRST PR and WAS off the row's edge (2026-10-21).
const double _variationBadgeMaxWidth = 150;

class _PrHistorySheet extends StatefulWidget {
  const _PrHistorySheet({required this.exerciseName, required this.prs});

  final String exerciseName;
  final List<PrEvent> prs;

  @override
  State<_PrHistorySheet> createState() => _PrHistorySheetState();
}

class _PrHistorySheetState extends State<_PrHistorySheet> {
  /// The feed is narrowed to exactly this weight, this rep count and this
  /// variation; null is "any" throughout. The three AND together.
  num? _weight;
  num? _reps;

  /// A variation id, [_noVariationId] for the unvaried line, or null for any.
  String? _variationId;

  /// What a variation id is called in the filter — its proper-cased name, the
  /// id itself when the feed never carried one, or "No variation".
  String _variationLabel(String id, Map<String, String> names) {
    if (id == _noVariationId) return 'No variation';
    final name = names[id];
    return (name == null || name.isEmpty) ? id : toProperCase(name);
  }

  @override
  Widget build(BuildContext context) {
    final prs = widget.prs;
    // The engine walks history oldest first, so the reverse is newest first
    // (same-day sets included: the later set leads).
    final newestFirst = prs.reversed.toList(growable: false);
    // Each PR's gap to the one before it, read off the FULL chronological
    // feed — a gap is a fact about the PR, so a filter must never rewrite
    // how long the lifter had waited for it.
    final gaps = <PrEvent, int>{};
    DateTime? previousDay;
    for (final event in prs) {
      final day = _calendarDay(event.achievedDate);
      if (previousDay != null) {
        gaps[event] = day.difference(previousDay).inDays;
      }
      previousDay = day;
    }
    // The filter offers only values the feed actually holds, so an option
    // can never yield an empty feed on its own.
    final weights = {for (final event in prs) event.weight}.toList()..sort();
    final reps = {for (final event in prs) event.reps}.toList()..sort();
    // The names the feed carries for each variation id, for the menu's labels.
    final variationNames = <String, String>{
      for (final event in prs)
        if (event.variationId != null &&
            (event.variationName?.isNotEmpty ?? false))
          event.variationId!: event.variationName!,
    };
    // The unvaried line leads, then the named lines alphabetically.
    final variations =
        {for (final event in prs) event.variationId ?? _noVariationId}.toList()
          ..sort((a, b) {
            if (a == _noVariationId) return -1;
            if (b == _noVariationId) return 1;
            return _variationLabel(
              a,
              variationNames,
            ).compareTo(_variationLabel(b, variationNames));
          });
    final filtered = [
      for (final event in newestFirst)
        if ((_weight == null || event.weight == _weight) &&
            (_reps == null || event.reps == _reps) &&
            (_variationId == null ||
                (event.variationId ?? _noVariationId) == _variationId))
          event,
    ];
    final count = prs.length;
    final countLabel = filtered.length == count
        ? (count == 1 ? '1 PR' : '$count PRs')
        : '${filtered.length} of $count PRs';
    return SafeArea(
      key: const ValueKey('pr-history-sheet'),
      top: false,
      child: SizedBox(
        // A settled place, not a fit-content one: the sheet stands at its
        // ceiling whether the feed holds twelve PRs or none, so opening a
        // thin feed never redraws a smaller room around the same header and
        // filters. The list scrolls inside the space that is left over —
        // twelve entries would otherwise run off the screen.
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'PR History',
                      style: AppFonts.ui(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  HeaderIconButton(
                    icon: Icons.close,
                    semanticsLabel: 'Close',
                    color: AppColors.muted,
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: UserNameText(
                      widget.exerciseName,
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.md,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  Text(
                    countLabel,
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.xs,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'ALL-TIME · NEWEST FIRST',
                style: AppFonts.mono(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _filterField(
                      key: const ValueKey('history-weight-filter'),
                      label: 'WEIGHT',
                      anyLabel: 'Any weight',
                      value: _weight,
                      options: weights,
                      optionLabel: (option) => '${formatPrNumber(option)} kg',
                      align: MenuPopoverAlign.start,
                      onChanged: (value) => setState(() => _weight = value),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _filterField(
                      key: const ValueKey('history-reps-filter'),
                      label: 'REPS',
                      anyLabel: 'Any reps',
                      value: _reps,
                      options: reps,
                      optionLabel: (option) =>
                          '${formatPrNumber(option)} '
                          '${option == 1 ? 'rep' : 'reps'}',
                      align: MenuPopoverAlign.end,
                      onChanged: (value) => setState(() => _reps = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Full width: a variation's name is the longest of the three
              // answers, and a third of the row would crush it.
              _filterField(
                key: const ValueKey('history-variation-filter'),
                label: 'VARIATION',
                anyLabel: 'Any variation',
                value: _variationId,
                options: variations,
                optionLabel: (option) =>
                    _variationLabel(option, variationNames),
                align: MenuPopoverAlign.start,
                onChanged: (value) => setState(() => _variationId = value),
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ),
                        child: Text(
                          'No PRs match',
                          style: AppFonts.mono(
                            fontSize: AppTextStyles.xs,
                            color: AppColors.muted,
                          ),
                        ),
                      )
                    : ListView.builder(
                        key: const ValueKey('pr-history-list'),
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => _PrHistoryEntry(
                          key: ValueKey(
                            'history-entry-'
                            '${filtered[index].sessionExerciseSetId}',
                          ),
                          event: filtered[index],
                          isLast: index == filtered.length - 1,
                          daysSincePrevious: gaps[filtered[index]],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One narrowing control: the goals sheet's date-row recipe (glass, a
  /// compact line, a chevron) hung off the shared [MenuPopover]. Accent while
  /// it is doing something, the way the library's funnel does. Generic over
  /// the answer's type — a weight and a rep count are numbers, a variation is
  /// an id — with null as "any" in both.
  Widget _filterField<T>({
    required Key key,
    required String label,
    required String anyLabel,
    required T? value,
    required List<T> options,
    required String Function(T option) optionLabel,
    required MenuPopoverAlign align,
    required ValueChanged<T?> onChanged,
  }) {
    final active = value != null;
    final color = active ? AppColors.accent : AppColors.primary;
    return MenuPopover(
      tone: ContainerTone.ghost,
      align: align,
      semanticsLabel: label,
      trigger: (context, open) => GestureDetector(
        onTap: open,
        child: Container(
          key: key,
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: AppSpacing.sm,
          ),
          decoration: glassBox(color),
          // Scale-to-fit: a wide value in a narrow half-row narrows rather
          // than overflows (the goal card's squeeze, 2026-10-20).
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppFonts.mono(
                    fontSize: 10,
                    letterSpacing: 0.8,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  value == null ? 'Any' : optionLabel(value),
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.expand_more, size: 14, color: color),
              ],
            ),
          ),
        ),
      ),
      contentBuilder: (context, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChoiceRow(
            label: anyLabel,
            active: value == null,
            onTap: () {
              onChanged(null);
              dismiss();
            },
          ),
          for (final option in options)
            ChoiceRow(
              label: optionLabel(option),
              active: value == option,
              onTap: () {
                onChanged(option);
                dismiss();
              },
            ),
        ],
      ),
    );
  }
}

/// One entry: the date and when the previous PR landed, then the PR that
/// landed (accent) with the value it beat at its right — or FIRST PR when it
/// had nothing to beat. The variation rides the killer line — the frontier it
/// beat is the same variation's, never another line's.
class _PrHistoryEntry extends StatelessWidget {
  const _PrHistoryEntry({
    super.key,
    required this.event,
    required this.isLast,
    required this.daysSincePrevious,
  });

  final PrEvent event;
  final bool isLast;

  /// Calendar days since the PR before this one on the feed; null for the
  /// oldest entry, which had nothing to wait on.
  final int? daysSincePrevious;

  /// The frontier value this event beat — [prBeforeFacts] without its "was"
  /// prefix, narrowed to one reading. Empty means the set was first on both
  /// dimensions.
  ///
  /// When the exact weight had been handled before ([PrEvent.beforeReps]
  /// non-null), the same-weight comparison is the one that means something —
  /// "70kg × 8 beat 70kg × 5" — so the best-weight-at-this-rep-count is not
  /// drawn beside it; 18 Aug's 70 × 8 names 70 × 5 alone, not also 65 × 8
  /// (2026-10-21). A weight never handled before keeps the weight reading,
  /// since there is no same-weight prior to name.
  List<String> get _victims => [
    if (event.beforeReps != null)
      '${formatPrNumber(event.weight)}kg × '
          '${formatPrNumber(event.beforeReps!)}'
    else if (event.beforeWeight != null)
      '${formatPrNumber(event.beforeWeight!)}kg × '
          '${formatPrNumber(event.reps)}',
  ];

  @override
  Widget build(BuildContext context) {
    final victims = _victims;
    final variation = event.variationName;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The date and the wait before it, one line: the feed's
          // rhythm is read across the top of each entry.
          Row(
            children: [
              Text(
                DateFormat('d MMM yyyy').format(event.achievedDate),
                style: AppFonts.mono(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: AppColors.muted,
                ),
              ),
              if (daysSincePrevious != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _sinceLabel(daysSincePrevious!),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.mono(fontSize: 10, color: AppColors.muted),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // The PR and its quarry share a line: the kill reads
          // left-to-right, the way it happened.
          Row(
            children: [
              Icon(Icons.emoji_events, size: 15, color: AppColors.accent),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${formatPrNumber(event.weight)}kg × '
                '${formatPrNumber(event.reps)}',
                style: AppFonts.mono(
                  fontSize: AppTextStyles.sm,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
              if (variation != null && variation.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _variationBadgeMaxWidth,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: glassBox(AppColors.accent, radius: 999),
                    child: UserNameText(
                      toProperCase(variation),
                      style: AppFonts.mono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: victims.isEmpty
                      ? Text(
                          'FIRST PR',
                          textAlign: TextAlign.end,
                          style: AppFonts.mono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: AppColors.accent,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'WAS',
                              style: AppFonts.mono(
                                fontSize: 10,
                                letterSpacing: 0.6,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                victims.join(' · '),
                                textAlign: TextAlign.end,
                                style: AppFonts.mono(
                                  fontSize: 13,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
