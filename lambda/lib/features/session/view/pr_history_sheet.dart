import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/menu_popover.dart';
import '../../../shared/widgets/pr_event_row.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/user_name_text.dart';
import '../model/pr_engine.dart';
import 'sheet_section_label.dart';

/// The PR History sheet (2026-10-22) — the PR Lab's feed, production's door.
///
/// Every PR an exercise ever logged, newest first, each one sitting beside
/// the frontier value(s) it beat. The feed reads in chronological shelves,
/// newest first (2026-10-23): everything achieved after the session on the
/// desk (`AFTER`, drawn only when it holds something), then the
/// session itself — `THIS SESSION` while it is the live one, its date
/// (`18 OCT 2026`) when it is a past record — then everything from before it
/// (`PREVIOUSLY`). A past record opened from Logs needs the third shelf: PRs
/// landed after the session read could not have preceded it, so folding them
/// into "previously" would misdate the record it is being read against.
/// Passing the session's own set ids, start and live-ness rather than
/// reading a viewmodel keeps the sheet a rendering of whichever feed it is
/// handed — today's live session, a record stepped onto by the date bar, or
/// a past session opened from Logs.
///
/// A review checkpoint ([sinceLastReviewAt], 2026-10-26) splits the
/// after-group once more: PRs landed since the last pass closed
/// (`SINCE LAST REVIEW`) sit above those landed after the session but no
/// later than it (`AFTER`). With no session on the desk — the planner, which
/// has no record to place in time — the same checkpoint divides the whole
/// shelf outside the session instead: what landed since the pass leads, what
/// came at or before it is `PREVIOUSLY`. Without one the shelves read exactly
/// as before.
Future<void> showPrHistorySheet(
  BuildContext context, {
  required String exerciseName,
  required List<PrEvent> prs,
  required Set<String> sessionSetIds,

  /// The session on the desk's start. Null falls back to the lab's two
  /// groups (everything outside the session is `PREVIOUSLY`), which is what
  /// a caller that cannot place the session in time should say rather than
  /// invent a boundary.
  DateTime? sessionStartedAt,

  /// Whether the session on the desk is the live one. True names the middle
  /// shelf `THIS SESSION`; false dates it (`18 OCT 2026`), because a record
  /// being read is not "this session" to the person reading it.
  bool sessionIsLive = false,

  /// Where the last review of this ground ended (2026-10-26) — resolved by
  /// the caller (the record's own review history, the pass in hand, or the
  /// planner's review editor). A PR landed after it leads the feed as
  /// `SINCE LAST REVIEW`; one landed after the session but no later than it
  /// stays `AFTER`. Without a session start (the planner) it splits the whole
  /// outside-the-session shelf against `PREVIOUSLY`. Null keeps the shelves
  /// exactly as they were.
  DateTime? sinceLastReviewAt,
}) {
  return showLambdaModal<void>(
    context,
    child: _PrHistorySheet(
      exerciseName: exerciseName,
      prs: prs,
      sessionSetIds: sessionSetIds,
      sessionStartedAt: sessionStartedAt,
      sessionIsLive: sessionIsLive,
      sinceLastReviewAt: sinceLastReviewAt,
    ),
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
  const _PrHistorySheet({
    required this.exerciseName,
    required this.prs,
    required this.sessionSetIds,
    this.sessionStartedAt,
    this.sessionIsLive = false,
    this.sinceLastReviewAt,
  });

  final String exerciseName;
  final List<PrEvent> prs;

  /// The set ids the session on the desk landed PRs on — the feed's middle
  /// group. Every other event is history, before or after it.
  final Set<String> sessionSetIds;

  /// When the session on the desk started; null keeps the lab's two groups.
  final DateTime? sessionStartedAt;

  /// Live session → `THIS SESSION`; a record → its date.
  final bool sessionIsLive;

  /// Where the last review of this ground ended — the split inside the
  /// after-group (2026-10-26). Null keeps the three shelves.
  final DateTime? sinceLastReviewAt;

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
    // The feed reads in up to three groups, all narrowed by the filters
    // alike, and newest first overall (2026-10-23): what has been achieved
    // since the session, the session itself, then what came before it. The
    // start time is what places an event on the right side of the session —
    // a date alone cannot (two sessions can share a day). Without it, the
    // lab's two-group reading stands.
    final startedAt = widget.sessionStartedAt;
    // A live session's middle shelf is "this session"; a record's is the
    // date it was logged, because to the reader it is not theirs to edit.
    final sessionLabel = widget.sessionIsLive || startedAt == null
        ? 'This session'
        : DateFormat('d MMM yyyy').format(startedAt);
    final sessionPrs = [
      for (final event in filtered)
        if (widget.sessionSetIds.contains(event.sessionExerciseSetId)) event,
    ];
    final afterPrs = [
      for (final event in filtered)
        if (!widget.sessionSetIds.contains(event.sessionExerciseSetId) &&
            startedAt != null &&
            event.achievedDate.isAfter(startedAt))
          event,
    ];
    // A checkpoint behind the record splits the after-group again
    // (2026-10-26): the newest PRs — those landed since the last review —
    // lead the feed, and the ones landed after the session but no later
    // than that review keep the `AFTER` shelf. Strict split, newest-first,
    // so a later PR can never be filed under the older heading. With no
    // session on the desk (the planner) there is no after-group to split:
    // the checkpoint divides the whole outside-the-session shelf instead —
    // what landed since the pass leads, what came at or before it is
    // `PREVIOUSLY`.
    final checkpoint = widget.sinceLastReviewAt;
    bool afterCheckpoint(PrEvent event) =>
        checkpoint != null && event.achievedDate.isAfter(checkpoint);
    final sinceReviewPrs = [
      for (final event in filtered)
        if (!widget.sessionSetIds.contains(event.sessionExerciseSetId) &&
            (startedAt == null || event.achievedDate.isAfter(startedAt)) &&
            afterCheckpoint(event))
          event,
    ];
    final afterRemainderPrs = [
      for (final event in afterPrs)
        if (!afterCheckpoint(event)) event,
    ];
    final previousPrs = [
      for (final event in filtered)
        if (!widget.sessionSetIds.contains(event.sessionExerciseSetId) &&
            (startedAt == null
                ? !afterCheckpoint(event)
                : !event.achievedDate.isAfter(startedAt)))
          event,
    ];
    final feedGroups = <(String, List<PrEvent>)>[
      ('Since last review', sinceReviewPrs),
      ('After', afterRemainderPrs),
      (sessionLabel, sessionPrs),
      ('Previously', previousPrs),
    ];
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The Lessons sheet's own header recipe — the
                        // exercise uppercased as an eyebrow over the title —
                        // so both doors open onto the same furniture.
                        UserNameText(
                          widget.exerciseName.toUpperCase(),
                          tooltip: true,
                          style: AppFonts.mono(
                            fontSize: AppTextStyles.caption,
                            fontWeight: FontWeight.w500,
                            color: AppColors.inkSecondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          'PR History',
                          style: AppFonts.ui(
                            fontSize: AppTextStyles.lg,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    countLabel,
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.caption,
                      fontWeight: FontWeight.w500,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  HeaderIconButton(
                    key: const ValueKey('pr-history-close'),
                    icon: Icons.close,
                    semanticsLabel: 'Close',
                    color: AppColors.muted,
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _filterField(
                      key: const ValueKey('pr-history-weight-filter'),
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
                      key: const ValueKey('pr-history-reps-filter'),
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
                key: const ValueKey('pr-history-variation-filter'),
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
                            fontSize: AppTextStyles.sm,
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      )
                    : ListView(
                        key: const ValueKey('pr-history-list'),
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (var g = 0; g < feedGroups.length; g++)
                            ..._feedGroup(
                              feedGroups[g].$1,
                              feedGroups[g].$2,
                              gaps: gaps,
                              lastOfFeed: !feedGroups
                                  .skip(g + 1)
                                  .any((group) => group.$2.isNotEmpty),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One group of the feed: its name, then its entries newest first. A group
  /// with nothing in it draws nothing at all — a filter that keeps one side
  /// shows one heading, never an empty shelf under the other.
  ///
  /// [lastOfFeed] belongs to the last group that actually draws, so only the
  /// very last entry loses its bottom padding.
  List<Widget> _feedGroup(
    String label,
    List<PrEvent> events, {
    required Map<PrEvent, int> gaps,
    required bool lastOfFeed,
  }) {
    if (events.isEmpty) return const [];
    return [
      SheetSectionLabel(label),
      const SizedBox(height: AppSpacing.md),
      for (var i = 0; i < events.length; i++)
        _PrHistoryEntry(
          event: events[i],
          isLast: lastOfFeed && i == events.length - 1,
          daysSincePrevious: gaps[events[i]],
        ),
    ];
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
                // The field-label recipe the app's own inputs use — a
                // readable label over its value, not a caption under it.
                Text(
                  label,
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: AppColors.primary,
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
    required this.event,
    required this.isLast,
    required this.daysSincePrevious,
  });

  final PrEvent event;
  final bool isLast;

  /// Calendar days since the PR before this one on the feed; null for the
  /// oldest entry, which had nothing to wait on.
  final int? daysSincePrevious;

  /// The frontier value this event beat — narrowed to one reading. Empty
  /// means the set was first on both dimensions.
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
      key: ValueKey('pr-history-entry-${event.sessionExerciseSetId}'),
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
                // A date is mixed-case mono — tracking belongs to uppercase
                // labels only (typography §5).
                style: AppFonts.mono(
                  fontSize: AppTextStyles.xs,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkSecondary,
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
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.xs,
                      color: AppColors.inkSecondary,
                    ),
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
                  fontSize: AppTextStyles.body,
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
                      // A badge is still text: the sheet draws nothing below
                      // the 12 floor, capsule or not (2026-10-21).
                      style: AppFonts.mono(
                        fontSize: AppTextStyles.xs,
                        fontWeight: FontWeight.w700,
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
                            fontSize: AppTextStyles.xs,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: AppColors.accent,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // The label stays quiet; the values it
                            // introduces are the comparison's payoff, so
                            // they carry the content ink (2026-10-21).
                            Text(
                              'WAS',
                              style: AppFonts.mono(
                                fontSize: AppTextStyles.xs,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.6,
                                color: AppColors.inkSecondary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                victims.join(' · '),
                                textAlign: TextAlign.end,
                                style: AppFonts.mono(
                                  fontSize: AppTextStyles.sm,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.primary,
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
