import 'package:flutter/material.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/program_content.dart';
import '../../../data/models/program_review.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../model/program_content_diff.dart';
import 'review_checkpoint_meta.dart';

/// A **completed** checkpoint, read back.
///
/// Deliberately not the same thing as the review itself. A review is a pass
/// over the plan you can still change; this is the record of one that has been
/// taken, and it is fed by the review's own `snapshot` — never by the live
/// program, which would state a fact about the wrong moment. Nothing here
/// writes.
///
/// [onViewWorkouts] drills into the snapshot's workouts at full size (the same
/// shared card and rows the planner draws); [onViewChanges] opens the diff
/// against the same-scope checkpoint before this one.
Future<void> showReviewDetailSheet(
  BuildContext context, {
  required ProgramReview review,

  /// Whether the program is built from blocks — the shape the contents render
  /// in. Never inferred from an empty block list (see [ProgramContent]).
  bool usesBlocks = false,

  /// What this checkpoint changed, against the same-scope snapshot before it.
  /// Null when there is no predecessor, or when either document is unreadable.
  ContentDiff? change,

  VoidCallback? onViewChanges,
  VoidCallback? onViewWorkouts,

  /// Resolves an exercise id to a name. Names are never stored in a document,
  /// so a contents view that could not resolve one would list uuids.
  Map<String, String> exerciseNames = const {},
}) {
  return showLambdaModal<void>(
    context,
    child: SafeArea(
      child: _ReviewDetailSheet(
        review: review,
        usesBlocks: usesBlocks,
        change: change,
        onViewChanges: onViewChanges,
        onViewWorkouts: onViewWorkouts,
        exerciseNames: exerciseNames,
      ),
    ),
  );
}

class _ReviewDetailSheet extends StatelessWidget {
  const _ReviewDetailSheet({
    required this.review,
    required this.usesBlocks,
    required this.change,
    required this.onViewChanges,
    required this.onViewWorkouts,
    required this.exerciseNames,
  });

  final ProgramReview review;
  final bool usesBlocks;
  final ContentDiff? change;
  final VoidCallback? onViewChanges;
  final VoidCallback? onViewWorkouts;
  final Map<String, String> exerciseNames;

  @override
  Widget build(BuildContext context) {
    // The record this pass left: its snapshot, narrowed to the workouts the
    // review actually covers. A set review stored a whole-program document, so
    // rendering it whole would report on workouts the pass never looked at; a
    // legacy row carries no set and passes through whole.
    final content = scopedSnapshot(review);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            review.title?.trim().isNotEmpty == true
                ? review.title!.trim()
                : reviewKindLabel(review.kind),
            style: AppFonts.ui(
              fontSize: AppTextStyles.lg,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ReviewCheckpointMeta(review: review),
          if (review.notes?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              review.notes!.trim(),
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.primary,
              ),
            ),
          ],
          if (change != null) ...[
            const SizedBox(height: AppSpacing.lg),
            const _SectionLabel('WHAT CHANGED'),
            const SizedBox(height: AppSpacing.sm),
            _ChangeLine(change: change!, onViewAll: onViewChanges),
          ],
          const SizedBox(height: AppSpacing.lg),
          const _SectionLabel('WHAT IT WAS'),
          const SizedBox(height: AppSpacing.sm),
          if (content == null)
            const _Note(
              'Nothing was recorded for this checkpoint. A dismissal is an '
              'answer — "not now" — so there is nothing to show.',
            )
          else
            _ContentsPanel(
              content: content,
              usesBlocks: usesBlocks,
              // Already narrowed to the pass's set above; these two are the
              // LEGACY single-scope fields, so a row written before reviews
              // were re-scoped still lays out its block or its workout alone.
              blockId: review.blockId,
              sessionId: review.sessionId,
              exerciseNames: exerciseNames,
              // And the pass's own notes, read back beside the exercises
              // they were about — the part of a review that is not in the
              // plan at all.
              notes: review.exerciseNotes,
            ),
          if (onViewWorkouts != null || onViewChanges != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                if (onViewWorkouts != null)
                  Expanded(
                    child: GlassButton(
                      label: 'View workouts',
                      solid: true,
                      onPressed: onViewWorkouts!,
                    ),
                  ),
                if (onViewWorkouts != null && onViewChanges != null)
                  const SizedBox(width: AppSpacing.sm),
                if (onViewChanges != null)
                  Expanded(
                    child: GlassButton(
                      label: 'Changes',
                      onPressed: onViewChanges!,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "What did this one change?" — the Versions timeline's question, answered by
/// the same-scope snapshot before it.
class _ChangeLine extends StatelessWidget {
  const _ChangeLine({required this.change, this.onViewAll});

  final ContentDiff change;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final diff = change;
    final summary = diff.summary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  summary,
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w700,
                    color: diff.isEmpty
                        ? AppColors.muted
                        : AppColors.accent,
                  ),
                ),
              ),
              if (diff.isNotEmpty && onViewAll != null)
                GlassButton(
                  label: 'All',
                  compact: true,
                  onPressed: onViewAll!,
                ),
            ],
          ),
          // The first few lines, so the summary means something without a tap.
          // A diff is only worth counting if the count is made of nouns.
          if (diff.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final c in diff.changes.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  c.detail == null
                      ? '${_verb(c.kind)} ${c.label}'
                      : '${_verb(c.kind)} ${c.label} — ${c.detail}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.muted,
                  ),
                ),
              ),
            if (diff.changes.length > 3)
              Text(
                '+${diff.changes.length - 3} more',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.xs,
                  color: AppColors.muted,
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _verb(ContentChangeKind kind) => switch (kind) {
    ContentChangeKind.added => 'added',
    ContentChangeKind.removed => 'removed',
    ContentChangeKind.edited => 'changed',
    ContentChangeKind.moved => 'moved',
  };
}

/// What the program was made of, per shape and per scope.
///
/// The directive's answer to "what is being reviewed": a simple program is its
/// workouts in order, a blocked one is its phases — each with the workouts in
/// it and its own goals — followed by the targets that apply to the program as
/// a whole. A review **scoped to a block** lays out that block alone: its own
/// goals plus the program's goals that are in force in it. A review **scoped to
/// a workout** lays out that workout's exercises and what each was asked to
/// lift. The other phases are not what this review is about, and listing them
/// would bury the answer.
///
/// Goals always appear at the scope they were SET at, because that scope is
/// what decides when they are in force.
class _ContentsPanel extends StatelessWidget {
  const _ContentsPanel({
    required this.content,
    required this.usesBlocks,
    required this.blockId,
    required this.sessionId,
    required this.exerciseNames,
    required this.notes,
  });

  final ProgramContent content;
  final bool usesBlocks;

  /// The review's scope: both null = the program's own, a block, or a workout.
  final String? blockId;
  final String? sessionId;

  final Map<String, String> exerciseNames;

  /// The review's per-exercise notes, keyed by `planned_exercise_id`. Not
  /// part of [content] and not derived from it: the plan is what the pass
  /// produced, the notes are what it thought.
  final Map<String, String> notes;

  @override
  Widget build(BuildContext context) {
    // A workout scope is the narrowest and answers first: a review of one
    // workout is not a review of its block. On a simple program the block scope
    // is a stale id rather than a filter, and narrowing by it would blank the
    // panel — so it is checked second.
    final session = sessionId;
    if (session != null) return _workout(session);

    final programGoals = _goalsIn(null);
    if (!usesBlocks) return _simple(programGoals);
    final block = blockId;
    if (block != null) return _block(block, programGoals);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (content.blocks.isEmpty)
          const _Note(
            'No blocks yet — this program is waiting for its first phase.',
          ),
        for (final b in content.blocks) ...[
          _BlockContents(
            block: b,
            goals: _goalsIn(b.blockId),
            sessions: _sessionsIn(b.blockId),
            exerciseNames: exerciseNames,
            notes: notes,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        // The workouts no block holds. A phase that was archived leaves its
        // workouts here, and a review that did not mention them would report
        // a program smaller than it is.
        ..._unfiledSection(),
        if (programGoals.isNotEmpty) ...[
          const _Line('Whole program', mono: false),
          for (final g in programGoals)
            _GoalLine(goal: g, exerciseNames: exerciseNames),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  /// The whole program, which for a simple program is exactly its workouts.
  Widget _simple(List<ContentGoal> programGoals) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (content.sessions.isEmpty) const _Note('No workouts yet.'),
      for (final s in content.sessions)
        _SessionLine(session: s, exerciseNames: exerciseNames, notes: notes),
      // No "Whole program" heading: every goal a simple program holds IS the
      // program's own, so the label would invent a distinction it cannot have.
      for (final g in programGoals)
        _GoalLine(goal: g, exerciseNames: exerciseNames),
    ],
  );

  /// One phase in full: what it is, what is in it, and what is being chased in
  /// it.
  Widget _block(String blockId, List<ContentGoal> programGoals) {
    final block = _blockById(blockId);
    final sessions = _sessionsIn(blockId);
    final goals = _goalsIn(blockId);
    // Two groups are labelled, one is not: a lone group needs no heading,
    // because whatever heading is above it already says whose it is.
    final twoScopes = goals.isNotEmpty && programGoals.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // An archived block leaves the document but not its review: the
        // workouts and goals below are still what is being reviewed, and the
        // heading says what it still can.
        if (block != null)
          _BlockHeading(block: block)
        else
          const _Line('This block', mono: false),
        for (final s in sessions)
          _SessionLine(session: s, exerciseNames: exerciseNames, notes: notes),
        if (twoScopes) const _Line('This block', mono: false),
        for (final g in goals) _GoalLine(goal: g, exerciseNames: exerciseNames),
        if (programGoals.isNotEmpty) ...[
          if (twoScopes)
            const _Line('Whole program · in force here', mono: false),
          for (final g in programGoals)
            _GoalLine(goal: g, exerciseNames: exerciseNames),
        ],
        if (block == null &&
            sessions.isEmpty &&
            goals.isEmpty &&
            programGoals.isEmpty)
          const _Note('Nothing left of this block.'),
      ],
    );
  }

  /// One workout, as the targets it asked for.
  ///
  /// The narrowest scope, and the only one where the sets themselves are the
  /// subject: a review of a workout is "is this the right work at the right
  /// numbers?", so the numbers are what it lays out. Goals are not repeated
  /// here — a workout does not own them, and listing the program's under one
  /// would read as though it did.
  Widget _workout(String sessionId) {
    final session = _sessionById(sessionId);
    if (session == null) {
      return const _Note('This workout is no longer in the program.');
    }
    final block = session.blockId == null
        ? null
        : _blockById(session.blockId!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (block != null) _BlockHeading(block: block),
        Text(
          session.name,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        if (session.exercises.isEmpty) const _Note('No exercises.'),
        for (final e in session.exercises)
          _ExerciseTargets(
            exercise: e,
            exerciseNames: exerciseNames,
            note: notes[e.plannedExerciseId],
          ),
      ],
    );
  }

  List<ContentSession> _sessionsIn(String? blockId) => [
    for (final s in content.sessions)
      if (s.blockId == blockId) s,
  ];

  List<ContentGoal> _goalsIn(String? blockId) => [
    for (final g in content.goals)
      if (g.blockId == blockId) g,
  ];

  ContentBlock? _blockById(String blockId) {
    for (final b in content.blocks) {
      if (b.blockId == blockId) return b;
    }
    return null;
  }

  ContentSession? _sessionById(String sessionId) {
    for (final s in content.sessions) {
      if (s.sessionId == sessionId) return s;
    }
    return null;
  }

  List<Widget> _unfiledSection() {
    final unfiled = _sessionsIn(null);
    if (unfiled.isEmpty) return const [];
    return [
      const _Line('Unfiled', mono: false),
      for (final s in unfiled)
        _SessionLine(session: s, exerciseNames: exerciseNames, notes: notes),
      const SizedBox(height: AppSpacing.sm),
    ];
  }
}

/// One exercise inside a workout-scoped review: its name, what each set asked
/// for, and what the review said about it.
class _ExerciseTargets extends StatelessWidget {
  const _ExerciseTargets({
    required this.exercise,
    required this.exerciseNames,
    this.note,
  });

  final ContentExercise exercise;
  final Map<String, String> exerciseNames;

  /// The review's note for this exercise, when it left one.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final targets = [
      for (final s in exercise.sets) _setLabel(s),
    ]..removeWhere((t) => t.isEmpty);
    final note = this.note?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exerciseNames[exercise.exerciseId] ?? 'Exercise',
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.primary,
            ),
          ),
          if (targets.isNotEmpty)
            Text(
              targets.join('  ·  '),
              style: AppFonts.mono(
                fontSize: AppTextStyles.xs,
                color: AppColors.muted,
              ),
            ),
          // Nameless here: the exercise's name is the line directly above, so
          // repeating it would be the layout saying the same thing twice.
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.sticky_note_2_outlined,
                      size: 10,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      note,
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.xs,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// "60 × 8". An empty target row is still a row the plan holds — an unfilled
  /// slot is not a missing one — so a set with neither number reports the
  /// variation or nothing at all rather than being dropped.
  static String _setLabel(ContentSet set) {
    final weight = set.targetWeight?.trim() ?? '';
    final reps = set.targetReps?.trim() ?? '';
    if (weight.isEmpty && reps.isEmpty) return '';
    if (weight.isEmpty) return reps;
    if (reps.isEmpty) return '$weight kg';
    return '$weight × $reps';
  }
}

/// A phase's name and length, as the panel heads it.
class _BlockHeading extends StatelessWidget {
  const _BlockHeading({required this.block});

  final ContentBlock block;

  @override
  Widget build(BuildContext context) {
    final weeks = block.targetWeeks;
    final sessions = block.targetSessions;
    final length = weeks != null
        ? '$weeks weeks'
        : (sessions != null ? '$sessions sessions' : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          toProperCase(block.name),
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            fontWeight: FontWeight.w700,
            color: AppColors.accent,
          ),
        ),
        if (length != null)
          Text(
            length,
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              color: AppColors.muted,
            ),
          ),
        const SizedBox(height: 2),
      ],
    );
  }
}

/// One phase inside a whole-program review: its name, its workouts, and its
/// own targets.
class _BlockContents extends StatelessWidget {
  const _BlockContents({
    required this.block,
    required this.sessions,
    required this.goals,
    required this.exerciseNames,
    required this.notes,
  });

  final ContentBlock block;
  final List<ContentSession> sessions;
  final List<ContentGoal> goals;
  final Map<String, String> exerciseNames;
  final Map<String, String> notes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BlockHeading(block: block),
        if (sessions.isEmpty && goals.isEmpty)
          const _Note('Nothing in this block yet.'),
        for (final s in sessions)
          _SessionLine(session: s, exerciseNames: exerciseNames, notes: notes),
        for (final g in goals) _GoalLine(goal: g, exerciseNames: exerciseNames),
      ],
    );
  }
}

/// One workout: its name, the exercises it holds, and anything the review
/// said about them.
class _SessionLine extends StatelessWidget {
  const _SessionLine({
    required this.session,
    required this.exerciseNames,
    required this.notes,
  });

  final ContentSession session;
  final Map<String, String> exerciseNames;
  final Map<String, String> notes;

  @override
  Widget build(BuildContext context) {
    final names = [
      for (final e in session.exercises)
        e.exerciseId != null ? (exerciseNames[e.exerciseId] ?? 'Exercise') : 'Exercise',
    ];
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.name,
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.primary,
            ),
          ),
          if (names.isNotEmpty)
            Text(
              '${names.length} exercise${names.length == 1 ? '' : 's'} · '
              '${names.join(', ')}',
              style: AppFonts.ui(
                fontSize: AppTextStyles.xs,
                color: AppColors.muted,
              ),
            ),
          // The pass's notes, each named for the exercise it was about: the
          // line above lists the exercises as one run of words, and a bare
          // note under it would leave the reader guessing whose it is.
          for (final e in session.exercises)
            if ((notes[e.plannedExerciseId] ?? '').trim().isNotEmpty)
              _NoteLine(
                label: e.exerciseId != null
                    ? (exerciseNames[e.exerciseId] ?? 'Exercise')
                    : 'Exercise',
                text: notes[e.plannedExerciseId]!.trim(),
              ),
        ],
      ),
    );
  }
}

/// One review note as the record reads it: whose, and what was said.
class _NoteLine extends StatelessWidget {
  const _NoteLine({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.sticky_note_2_outlined,
            size: 10,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label  ',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.xs,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
                TextSpan(
                  text: text,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// One goal, as the target it is.
class _GoalLine extends StatelessWidget {
  const _GoalLine({required this.goal, required this.exerciseNames});

  final ContentGoal goal;
  final Map<String, String> exerciseNames;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (goal.targetWeight != null) parts.add('${goal.targetWeight} kg');
    if (goal.targetReps != null) {
      parts.add('${goal.targetReps} rep${goal.targetReps == 1 ? '' : 's'}');
    }
    final name = goal.text?.trim().isNotEmpty == true
        ? goal.text!.trim()
        : (goal.exerciseId != null
              ? (exerciseNames[goal.exerciseId] ?? 'Goal')
              : 'Goal');

    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 3),
      child: Text(
        parts.isEmpty ? name : '$name — ${parts.join(' × ')}',
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, {this.mono = true});

  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      text,
      style: mono
          ? AppFonts.mono(fontSize: AppTextStyles.xs, color: AppColors.muted)
          : AppFonts.ui(
              fontSize: AppTextStyles.sm,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8, bottom: 3),
    child: Text(
      text,
      style: AppFonts.ui(fontSize: AppTextStyles.sm, color: AppColors.muted),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppFonts.mono(
      fontSize: AppTextStyles.xs,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      color: AppColors.muted,
    ),
  );
}
