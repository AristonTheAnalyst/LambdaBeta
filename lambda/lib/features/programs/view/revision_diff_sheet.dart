import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/program_revision.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../model/program_revision_diff.dart';

/// What changed between two versions of a program.
///
/// Pure data in, like `showPrModal`: it decodes the two documents, diffs them
/// and renders. Nothing is fetched and nothing is written — a version
/// comparison is a read of two immutable records.
///
/// [title] and [subtitle] are supplied by the caller because there are two
/// questions this answers — "what changed in version 4?" and "what would this
/// proposed change do?" — and they are the same comparison with a different
/// header.
void showRevisionDiffSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required ProgramRevisionContent? before,
  required ProgramRevisionContent? after,
  Map<String, String> exerciseNames = const {},
}) {
  showLambdaModal(
    context,
    child: SafeArea(
      child: _RevisionDiffSheet(
        title: title,
        subtitle: subtitle,
        before: before,
        after: after,
        exerciseNames: exerciseNames,
      ),
    ),
  );
}

/// "Version 3 → Version 4", the timeline's question.
void showVersionDiffSheet(
  BuildContext context, {
  required ProgramRevision from,
  required ProgramRevision to,
  Map<String, String> exerciseNames = const {},
}) =>
    showRevisionDiffSheet(
      context,
      title: 'Version ${from.revisionNumber} → ${to.revisionNumber}',
      subtitle: '${DateFormat('MMM d').format(from.createdDate)}'
          '  ·  '
          '${DateFormat('MMM d, yyyy').format(to.createdDate)}',
      before: from.content,
      after: to.content,
      exerciseNames: exerciseNames,
    );

class _RevisionDiffSheet extends StatelessWidget {
  const _RevisionDiffSheet({
    required this.title,
    required this.subtitle,
    required this.before,
    required this.after,
    required this.exerciseNames,
  });

  final String title;
  final String subtitle;
  final ProgramRevisionContent? before;
  final ProgramRevisionContent? after;
  final Map<String, String> exerciseNames;

  @override
  Widget build(BuildContext context) {
    final readable = before != null && after != null;
    final diff = readable
        ? diffRevisions(before, after, exerciseNames: exerciseNames)
        : const RevisionDiff.empty();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppFonts.ui(
              fontSize: AppTextStyles.lg,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text(
                subtitle,
                style: AppFonts.mono(
                  fontSize: AppTextStyles.xs,
                  color: AppColors.muted,
                ),
              ),
              const Spacer(),
              _SummaryChip(summary: diff.summary, isEmpty: diff.isEmpty),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!readable)
            _Note(
              "One of these versions can't be displayed — it was saved by a "
              'newer version of the app.',
            )
          else if (diff.isEmpty)
            const _Note(
              'The contents are identical. This checkpoint recorded no '
              'changes — that is worth knowing on its own.',
            )
          else
            ConstrainedBox(
              // The sheet sizes to its content, so a long diff needs its own
              // ceiling or it would run past the top of the screen.
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: _rows(diff),
              ),
            ),
        ],
      ),
    );
  }

  /// One row per change, with a workout heading whenever the change's workout
  /// differs from the previous row's — the diff emits a workout's changes
  /// together, so a running comparison is enough to group them.
  List<Widget> _rows(RevisionDiff diff) {
    final rows = <Widget>[];
    String? lastSessionId;
    for (final change in diff.changes) {
      if (change.sessionId != lastSessionId) {
        lastSessionId = change.sessionId;
        if (change.sessionName != null) {
          rows.add(
            Padding(
              padding: EdgeInsets.only(
                top: rows.isEmpty ? 0 : AppSpacing.md,
                bottom: AppSpacing.xs,
              ),
              child: Text(
                change.sessionName!.toUpperCase(),
                style: AppFonts.mono(
                  fontSize: AppTextStyles.xs,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppColors.accent,
                ),
              ),
            ),
          );
        }
      }
      rows.add(_ChangeRow(change: change));
    }
    return rows;
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change});

  final RevisionChange change;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (change.kind) {
      RevisionChangeKind.added => (Icons.add_circle_outline, AppColors.success),
      RevisionChangeKind.removed => (
          Icons.remove_circle_outline,
          AppColors.danger,
        ),
      RevisionChangeKind.edited => (Icons.edit_outlined, AppColors.accent),
      RevisionChangeKind.moved => (Icons.swap_vert, AppColors.muted),
    };

    // A set's own label is "Set 2", so it needs its exercise named; an
    // exercise's label IS the exercise, and repeating it would be noise.
    final exerciseContext = change.entity == RevisionEntity.set
        ? change.exerciseName
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: lambdaBox(ContainerTone.surface),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exerciseContext == null
                      ? change.label
                      : '${change.label} · $exerciseContext',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                if (change.detail != null)
                  Text(
                    change.detail!,
                    style: AppFonts.mono(
                      fontSize: AppTextStyles.xs,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.summary, required this.isEmpty});

  final String summary;
  final bool isEmpty;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        decoration: isEmpty
            ? lambdaBox(ContainerTone.ghost)
            : lambdaBox(ContainerTone.accent),
        child: Text(
          summary,
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w700,
            color: isEmpty ? AppColors.muted : AppColors.accentText,
          ),
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          color: AppColors.muted,
        ),
      );
}
