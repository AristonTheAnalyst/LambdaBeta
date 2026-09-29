import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/program_revision.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/section_divider.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../../../shared/widgets/stats_row.dart';
import 'revision_diff_sheet.dart';

/// One immutable version of a program, read-only.
///
/// Deliberately VM-free: a revision is a document, not a view of live state, so
/// there is nothing to load, mutate or reload. The name maps come from the
/// history screen because names are resolved live from the dims (a revision
/// stores ids only) and re-fetching them per version would query for data the
/// caller already holds.
///
/// Renders through the SAME `SessionExerciseCard` / `SessionSetRow` the planner
/// and the session screen use, with every action callback null — a version
/// viewer that drifted from the planner would defeat the point of keeping the
/// three (now four) surfaces on one implementation.
class ProgramRevisionScreen extends StatelessWidget {
  const ProgramRevisionScreen({
    super.key,
    required this.revision,
    this.previous,
    this.exerciseNames = const {},
    this.variationNames = const {},
  });

  final ProgramRevision revision;

  /// The version immediately before this one. When present the header offers
  /// the diff against it — "what changed?" is the question a history exists to
  /// answer.
  final ProgramRevision? previous;

  final Map<String, String> exerciseNames;
  final Map<String, String> variationNames;

  @override
  Widget build(BuildContext context) {
    final content = revision.content;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          PageHeader(
            title: 'Version ${revision.revisionNumber}',
            left: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Icon(
                Icons.arrow_back_ios_new,
                size: 18,
                color: AppColors.accent,
              ),
            ),
            right: previous == null
                ? null
                : GlassButton(
                    label: 'Changes',
                    compact: true,
                    onPressed: () => showVersionDiffSheet(
                      context,
                      from: previous!,
                      to: revision,
                      exerciseNames: exerciseNames,
                    ),
                  ),
          ),
          Expanded(
            child: content == null
                ? const _UnreadableVersion()
                : _VersionBody(
                    revision: revision,
                    content: content,
                    exerciseNames: exerciseNames,
                    variationNames: variationNames,
                  ),
          ),
        ],
      ),
    );
  }
}

/// A revision this build cannot decode — written by a NEWER app version whose
/// document schema this one doesn't know. Shown as a placeholder rather than
/// thrown: an old build must not crash on the history another device wrote.
class _UnreadableVersion extends StatelessWidget {
  const _UnreadableVersion();

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
                "This version can't be displayed",
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

class _VersionBody extends StatelessWidget {
  const _VersionBody({
    required this.revision,
    required this.content,
    required this.exerciseNames,
    required this.variationNames,
  });

  final ProgramRevision revision;
  final ProgramRevisionContent content;
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
              _VersionMeta(revision: revision),
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
                'This version had no workouts.',
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
              child: _RevisionWorkoutCard(
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

/// The reason / date / fingerprint line that heads a version.
class _VersionMeta extends StatelessWidget {
  const _VersionMeta({required this.revision});

  final ProgramRevision revision;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: AppColors.accentBg,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.accent.withAlpha(77)),
          ),
          child: Text(
            revisionReasonLabel(revision.reason).toUpperCase(),
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              fontWeight: FontWeight.w700,
              color: AppColors.accentText,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            DateFormat('MMM d, yyyy').format(revision.createdDate),
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              color: AppColors.muted,
            ),
          ),
        ),
        // The content fingerprint. Two versions showing the same short hash
        // are byte-identical, which is how a "review where nothing changed"
        // proves itself.
        Text(
          '#${revision.contentHash.isEmpty ? '--------' : revision.contentHash.substring(0, 8)}',
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}

/// One workout inside a version — a read-only mirror of the planner's card,
/// tabbed across that workout's exercises.
class _RevisionWorkoutCard extends StatefulWidget {
  const _RevisionWorkoutCard({
    required this.session,
    required this.exerciseNames,
    required this.variationNames,
  });

  final RevisionSession session;
  final Map<String, String> exerciseNames;
  final Map<String, String> variationNames;

  @override
  State<_RevisionWorkoutCard> createState() => _RevisionWorkoutCardState();
}

class _RevisionWorkoutCardState extends State<_RevisionWorkoutCard> {
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
    // contain every variation the version references — including one that has
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
      // A version is immutable: no reorder, no add, no delete. Null greys the
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
    RevisionExercise exercise,
    RevisionSet set,
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
