import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/program_content.dart';
import '../../../data/models/program_review.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/section_divider.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../../../shared/widgets/stats_row.dart';
import 'content_diff_sheet.dart';
import '../model/program_content_diff.dart';
import 'review_checkpoint_meta.dart';

/// One checkpoint's frozen snapshot of a program, read-only.
///
/// Deliberately VM-free: a snapshot is a document, not a view of live state,
/// so there is nothing to load, mutate or reload. The name maps come from the
/// history screen because names are resolved live from the dims (a snapshot
/// stores ids only) and re-fetching them per checkpoint would query for data
/// the caller already holds.
///
/// Renders through the SAME `SessionExerciseCard` / `SessionSetRow` the planner
/// and the session screen use, with every action callback null — a snapshot
/// viewer that drifted from the planner would defeat the point of keeping the
/// three (now four) surfaces on one implementation.
///
/// The one state it holds is which exercise each card is showing — view state,
/// not document state — because the Changes sheet's exercise cards open the
/// exercise on this screen (see [_SnapshotBodyState.revealExercise]).
class ReviewSnapshotScreen extends StatefulWidget {
  const ReviewSnapshotScreen({
    super.key,
    required this.review,
    this.previous,
    this.exerciseNames = const {},
    this.variationNames = const {},
  });

  final ProgramReview review;

  /// The same-scope checkpoint before this one, when there is one. When its
  /// snapshot is readable the header offers the diff against it — "what
  /// changed?" is the question a history exists to answer.
  final ProgramReview? previous;

  final Map<String, String> exerciseNames;
  final Map<String, String> variationNames;

  @override
  State<ReviewSnapshotScreen> createState() => _ReviewSnapshotScreenState();
}

class _ReviewSnapshotScreenState extends State<ReviewSnapshotScreen> {
  /// The body under the changes sheet — what its cards open their exercise on.
  final _bodyKey = GlobalKey<_SnapshotBodyState>();

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    // Both sides narrowed to the workouts the checkpoint covers: a review
    // stores a whole-program snapshot, and a set review read back whole would
    // report on workouts the pass never looked at. Legacy rows pass through.
    final content = scopedSnapshot(review);
    final before = widget.previous == null
        ? null
        : scopedSnapshot(widget.previous!);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: _title,
            left: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Icon(
                Icons.arrow_back_ios_new,
                size: 18,
                color: AppColors.accent,
              ),
            ),
            right: before == null || content == null
                ? null
                : GlassButton(
                    label: 'Changes',
                    compact: true,
                    onPressed: () => showContentDiffSheet(
                      context,
                      title: kReviewChangesTitle,
                      subtitle:
                          '${DateFormat('MMM d').format(widget.previous!.effectiveDate)}'
                          '  ·  '
                          '${DateFormat('MMM d, yyyy').format(review.effectiveDate)}',
                      before: before,
                      after: content,
                      exerciseNames: widget.exerciseNames,
                      variationNames: widget.variationNames,
                      // The body below holds the exercises, so a card can open
                      // the one it names: the snapshot switches to it.
                      onExerciseTap: (id) =>
                          _bodyKey.currentState?.revealExercise(id),
                    ),
                  ),
          ),
          Expanded(
            child: content == null
                ? const _UnreadableCheckpoint()
                : _SnapshotBody(
                    key: _bodyKey,
                    review: review,
                    content: content,
                    exerciseNames: widget.exerciseNames,
                    variationNames: widget.variationNames,
                  ),
          ),
        ],
      ),
    );
  }

  /// The user's own name for the checkpoint when they gave one; the kind is
  /// the fallback, because a close or a change says more than "Review".
  String get _title {
    final title = widget.review.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    return reviewKindLabel(widget.review.kind);
  }
}

/// A snapshot this build cannot decode — written by a NEWER app version whose
/// document schema this one doesn't know. Shown as a placeholder rather than
/// thrown: an old build must not crash on the history another device wrote.
class _UnreadableCheckpoint extends StatelessWidget {
  const _UnreadableCheckpoint();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.help_outline, color: AppColors.muted, size: 32),
          const SizedBox(height: AppSpacing.md),
          Text(
            "This checkpoint can't be displayed",
            style: AppFonts.ui(
              fontSize: AppTextStyles.md,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'It was saved by a newer version of the app.',
            textAlign: TextAlign.center,
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SnapshotBody extends StatefulWidget {
  const _SnapshotBody({
    super.key,
    required this.review,
    required this.content,
    required this.exerciseNames,
    required this.variationNames,
  });

  final ProgramReview review;
  final ProgramContent content;
  final Map<String, String> exerciseNames;
  final Map<String, String> variationNames;

  @override
  State<_SnapshotBody> createState() => _SnapshotBodyState();
}

class _SnapshotBodyState extends State<_SnapshotBody> {
  /// Which exercise each workout card shows, by workout id. A workout the
  /// reveal has not visited reads as its first exercise.
  final Map<String, int> _activeIndex = {};

  /// One key per workout card, so a reveal can scroll the card it switched.
  final Map<String, GlobalKey> _cardKeys = {};

  /// Answers a tap on one of the changes sheet's exercise cards: the workout
  /// holding [plannedExerciseId] switches to that exercise, and its card
  /// comes into view.
  ///
  /// The id always resolves — the sheet lists this same document — and the
  /// scroll is deferred a frame because the card may be off-screen at the
  /// moment of the tap.
  void revealExercise(String plannedExerciseId) {
    for (final session in widget.content.sessions) {
      final index = session.exercises.indexWhere(
        (e) => e.plannedExerciseId == plannedExerciseId,
      );
      if (index < 0) continue;
      setState(() => _activeIndex[session.sessionId] = index);
      // The tab switch is done; bring its card to the top, because the point
      // of the tap is seeing the exercise it landed on.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final card = _cardKeys[session.sessionId]?.currentContext;
        if (card == null) return;
        Scrollable.ensureVisible(
          card,
          alignment: 0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    // A scroll view rather than a lazy list: every card is built up front so
    // a reveal can always scroll to the one it switched — an unmounted card
    // has no context to bring into view, and a tap that lands invisibly
    // reads as no tap at all.
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ReviewCheckpointMeta(review: widget.review),
                const SizedBox(height: AppSpacing.md),
                StatsRow(
                  tiles: [
                    StatsTile(
                      label: 'WORKOUTS',
                      value: '${widget.content.sessionCount}',
                    ),
                    StatsTile(
                      label: 'EXERCISES',
                      value: '${widget.content.exerciseCount}',
                    ),
                    StatsTile(
                      label: 'SETS',
                      value: '${widget.content.setCount}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.content.sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Text(
                  'This checkpoint had no workouts.',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.muted,
                  ),
                ),
              ),
            )
          else
            for (final session in widget.content.sessions) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: SectionDivider(session.name),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _SnapshotWorkoutCard(
                  key: _cardKeys.putIfAbsent(
                    session.sessionId,
                    () => GlobalKey(),
                  ),
                  session: session,
                  activeIndex: _activeIndex[session.sessionId] ?? 0,
                  onSelect: (i) =>
                      setState(() => _activeIndex[session.sessionId] = i),
                  exerciseNames: widget.exerciseNames,
                  variationNames: widget.variationNames,
                  // The review's own notes, keyed by planned exercise id — the
                  // pass's record, shown beside the exercise it was about.
                  exerciseNotes: widget.review.exerciseNotes,
                ),
              ),
            ],
        ],
      ),
    );
  }
}

/// One workout inside a checkpoint — a read-only mirror of the planner's card,
/// tabbed across that workout's exercises.
///
/// The tab is the body's, not the card's: the changes sheet reveals an
/// exercise by moving it, and two owners of one answer is one too many.
class _SnapshotWorkoutCard extends StatelessWidget {
  const _SnapshotWorkoutCard({
    super.key,
    required this.session,
    required this.activeIndex,
    required this.onSelect,
    required this.exerciseNames,
    required this.variationNames,
    required this.exerciseNotes,
  });

  final ContentSession session;

  /// Which exercise the card shows, owned by [_SnapshotBodyState].
  final int activeIndex;

  final ValueChanged<int> onSelect;

  final Map<String, String> exerciseNames;
  final Map<String, String> variationNames;
  final Map<String, String> exerciseNotes;

  @override
  Widget build(BuildContext context) {
    final exercises = session.exercises;
    if (exercises.isEmpty) {
      return AppCard(
        child: Text(
          'No exercises',
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            color: AppColors.muted,
          ),
        ),
      );
    }

    final index = activeIndex.clamp(0, exercises.length - 1);
    final active = exercises[index];

    // The row reads its variation label out of these options, so they must
    // contain every variation the workout references — including one that has
    // since been archived, which is exactly why the map is built from the
    // archived-inclusive dim read.
    final variationOptions = <DropdownOption<String?>>[
      const DropdownOption<String?>(label: 'No Variation', value: null),
      for (final entry in variationNames.entries)
        DropdownOption<String?>(label: entry.value, value: entry.key),
    ];

    return SessionExerciseCard(
      exerciseNames: [
        for (final e in exercises) _exerciseLabel(e.exerciseId),
      ],
      activeIndex: index,
      onSelect: onSelect,
      // A snapshot is immutable: no reorder, no add, no delete. Null greys the
      // arrows and greys the Add row, so the card reads as the planner's with
      // its editing affordances switched off.
      onMove: null,
      onAdd: null,
      lessonsCount: 0,
      onLessonsTap: null,
      prCount: 0,
      onPrTap: null,
      rows: [
        for (var i = 0; i < active.sets.length; i++)
          _setRow(active, active.sets[i], i, variationOptions),
      ],
      onAddSet: null,
      history: null,
      // What the review said about the exercise on screen, read-only: no
      // change callback, so the box is display and nothing else. An exercise
      // with no note has no box — on a record, an empty one would only take
      // up the space a note did not earn.
      reviewNote: exerciseNotes[active.plannedExerciseId],
    );
  }

  /// A raw id never reaches the UI: an unresolved exercise means the row is
  /// gone entirely (not merely archived, which the map already covers).
  String _exerciseLabel(String? exerciseId) =>
      exerciseNames[exerciseId] ?? 'Exercise';

  Widget _setRow(
    ContentExercise exercise,
    ContentSet set,
    int index,
    List<DropdownOption<String?>> variationOptions,
  ) {
    return SessionSetRow(
      key: ValueKey(set.plannedSetId),
      mode: SetRowMode.planned,
      exerciseId: exercise.exerciseId ?? '',
      displayIndex: index + 1,
      isDraft: false,
      initialWeightText: set.targetWeight ?? '',
      initialRepsText: set.targetReps ?? '',
      initialVariationId: set.variationId,
      initialVariationName: variationNames[set.variationId],
      initialNotes: set.targetNotes,
      hasNotes: set.targetNotes?.isNotEmpty ?? false,
      readOnly: true,
      // Required plumbing, all inert — `readOnly` keeps every one of these
      // from firing, and the planner passes the same shapes with real bodies.
      onCommit: (isDraft, values, {bool immediate = false}) async {},
      onVariationChanged: (_) {},
      onNotesSave: (_) {},
      onDelete: () async {},
      onDuplicate: (_) {},
      variationOptions: variationOptions,
      allVariations: [
        for (final entry in variationNames.entries)
          (id: entry.key, name: entry.value),
      ],
      findSimilarVariations: (_) => const [],
      submitNewVariation: (name, {required exerciseId, useExistingId}) async =>
          null,
    );
  }
}
