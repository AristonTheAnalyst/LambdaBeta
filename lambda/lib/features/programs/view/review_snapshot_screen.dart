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
class ReviewSnapshotScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final content = review.snapshot;
    final before = previous?.snapshot;
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
                      title: 'What changed',
                      subtitle:
                          '${DateFormat('MMM d').format(previous!.effectiveDate)}'
                          '  ·  '
                          '${DateFormat('MMM d, yyyy').format(review.effectiveDate)}',
                      before: before,
                      after: content,
                      exerciseNames: exerciseNames,
                    ),
                  ),
          ),
          Expanded(
            child: content == null
                ? const _UnreadableCheckpoint()
                : _SnapshotBody(
                    review: review,
                    content: content,
                    exerciseNames: exerciseNames,
                    variationNames: variationNames,
                  ),
          ),
        ],
      ),
    );
  }

  /// The user's own name for the checkpoint when they gave one; the kind is
  /// the fallback, because a close or a change says more than "Review".
  String get _title {
    final title = review.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    return reviewKindLabel(review.kind);
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

class _SnapshotBody extends StatelessWidget {
  const _SnapshotBody({
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
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReviewCheckpointMeta(review: review),
              const SizedBox(height: AppSpacing.md),
              StatsRow(
                tiles: [
                  StatsTile(
                    label: 'WORKOUTS',
                    value: '${content.sessionCount}',
                  ),
                  StatsTile(
                    label: 'EXERCISES',
                    value: '${content.exerciseCount}',
                  ),
                  StatsTile(label: 'SETS', value: '${content.setCount}'),
                ],
              ),
            ],
          ),
        ),
        if (content.sessions.isEmpty)
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
          for (final session in content.sessions) ...[
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
                session: session,
                exerciseNames: exerciseNames,
                variationNames: variationNames,
              ),
            ),
          ],
      ],
    );
  }
}

/// One workout inside a checkpoint — a read-only mirror of the planner's card,
/// tabbed across that workout's exercises.
class _SnapshotWorkoutCard extends StatefulWidget {
  const _SnapshotWorkoutCard({
    required this.session,
    required this.exerciseNames,
    required this.variationNames,
  });

  final ContentSession session;
  final Map<String, String> exerciseNames;
  final Map<String, String> variationNames;

  @override
  State<_SnapshotWorkoutCard> createState() => _SnapshotWorkoutCardState();
}

class _SnapshotWorkoutCardState extends State<_SnapshotWorkoutCard> {
  int _activeIndex = 0;

  @override
  Widget build(BuildContext context) {
    final exercises = widget.session.exercises;
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

    final index = _activeIndex.clamp(0, exercises.length - 1);
    final active = exercises[index];

    // The row reads its variation label out of these options, so they must
    // contain every variation the workout references — including one that has
    // since been archived, which is exactly why the map is built from the
    // archived-inclusive dim read.
    final variationOptions = <DropdownOption<String?>>[
      const DropdownOption<String?>(label: 'No Variation', value: null),
      for (final entry in widget.variationNames.entries)
        DropdownOption<String?>(label: entry.value, value: entry.key),
    ];

    return SessionExerciseCard(
      exerciseNames: [
        for (final e in exercises) _exerciseLabel(e.exerciseId),
      ],
      activeIndex: index,
      onSelect: (i) => setState(() => _activeIndex = i),
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
    );
  }

  /// A raw id never reaches the UI: an unresolved exercise means the row is
  /// gone entirely (not merely archived, which the map already covers).
  String _exerciseLabel(String? exerciseId) =>
      widget.exerciseNames[exerciseId] ?? 'Exercise';

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
      initialVariationName: widget.variationNames[set.variationId],
      initialNotes: set.targetNotes,
      hasNotes: set.targetNotes?.isNotEmpty ?? false,
      readOnly: true,
      // Required plumbing, all inert — `readOnly` keeps every one of these
      // from firing, and the planner passes the same shapes with real bodies.
      onCommit: (isDraft, values) async {},
      onVariationChanged: (_) {},
      onNotesSave: (_) {},
      onDelete: () async {},
      onDuplicate: () {},
      variationOptions: variationOptions,
      allVariations: [
        for (final entry in widget.variationNames.entries)
          (id: entry.key, name: entry.value),
      ],
      findSimilarVariations: (_) => const [],
      submitNewVariation: (name, {required exerciseId, useExistingId}) async =>
          null,
    );
  }
}
