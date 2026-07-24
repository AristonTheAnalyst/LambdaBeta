import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import '../../core/utils/workout_format.dart';
import '../../data/models/exercise_detail.dart';
import '../../data/models/workout_set.dart';

class WorkoutSetsList extends StatelessWidget {
  const WorkoutSetsList({
    super.key,
    required this.sets,
    required this.exerciseDetailMap,
    this.setsLoading = false,
    this.viewMode = 'grouped',
    this.onToggleViewMode,
    this.onEditSet,
    this.interactive = false,
    this.onReorderSets,
    this.title,
    this.emptyHint,
  });

  final List<WorkoutSet> sets;
  final Map<String, ExerciseDetail> exerciseDetailMap;
  final bool setsLoading;
  final String viewMode; // 'grouped' | 'chrono'
  final VoidCallback? onToggleViewMode;
  final ValueChanged<WorkoutSet>? onEditSet;
  final bool interactive;
  final void Function(List<WorkoutSet> reordered, List<String> orderedIds)?
      onReorderSets;
  final Widget? title;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            if (title != null)
              Expanded(child: title!)
            else
              Expanded(
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Sets ',
                        style: TextStyle(
                            fontSize: AppTextStyles.xl,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary),
                      ),
                      TextSpan(
                        text:
                            '(${viewMode == 'grouped' ? 'grouped' : 'chronological'})',
                        style: TextStyle(
                            fontSize: AppTextStyles.sm,
                            fontWeight: FontWeight.w400,
                            color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            if (onToggleViewMode != null)
              GestureDetector(
                onTap: onToggleViewMode,
                child: Icon(Icons.swap_vert,
                    size: 20, color: AppColors.accent),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        if (setsLoading)
          Center(
              child: CircularProgressIndicator(color: AppColors.accent))
        else if (sets.isEmpty)
          Text(emptyHint ?? 'No sets yet.',
              style: TextStyle(
                  color: AppColors.muted, fontSize: AppTextStyles.sm))
        else if (viewMode == 'grouped')
          _GroupedSetsList(
            sets: sets,
            exerciseDetailMap: exerciseDetailMap,
            interactive: interactive,
            onEditSet: onEditSet,
            onReorderSets: onReorderSets,
          )
        else
          _ChronoSetsList(
            sets: sets,
            exerciseDetailMap: exerciseDetailMap,
            interactive: interactive,
            onEditSet: onEditSet,
            onReorderSets: onReorderSets,
          ),
      ],
    );
  }
}

// ── Grouped view ───────────────────────────────────────────────────────────────

class _GroupedSetsList extends StatelessWidget {
  const _GroupedSetsList({
    required this.sets,
    required this.exerciseDetailMap,
    required this.interactive,
    this.onEditSet,
    this.onReorderSets,
  });

  final List<WorkoutSet> sets;
  final Map<String, ExerciseDetail> exerciseDetailMap;
  final bool interactive;
  final ValueChanged<WorkoutSet>? onEditSet;
  final void Function(List<WorkoutSet>, List<String>)? onReorderSets;

  Map<String, List<WorkoutSet>> _groupByExercise() {
    final map = <String, List<WorkoutSet>>{};
    for (final s in sets) {
      map.putIfAbsent(s.exerciseId, () => []).add(s);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupByExercise();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.entries.map((entry) {
        final detail = exerciseDetailMap[entry.key];
        final exName = detail != null
            ? toProperCase(detail.name)
            : 'Unknown exercise';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(exName,
                  style: TextStyle(
                      fontSize: AppTextStyles.sm,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent)),
            ),
            ...entry.value.map((s) => SetRow(
                  set: s,
                  detail: detail,
                  interactive: interactive,
                  onEdit: onEditSet,
                )),
            const SizedBox(height: AppSpacing.md),
          ],
        );
      }).toList(),
    );
  }
}

// ── Chrono view ────────────────────────────────────────────────────────────────

class _ChronoSetsList extends StatelessWidget {
  const _ChronoSetsList({
    required this.sets,
    required this.exerciseDetailMap,
    required this.interactive,
    this.onEditSet,
    this.onReorderSets,
  });

  final List<WorkoutSet> sets;
  final Map<String, ExerciseDetail> exerciseDetailMap;
  final bool interactive;
  final ValueChanged<WorkoutSet>? onEditSet;
  final void Function(List<WorkoutSet>, List<String>)? onReorderSets;

  @override
  Widget build(BuildContext context) {
    if (interactive && onReorderSets != null) {
      return ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        onReorderItem: (oldIndex, newIndex) {
          final updated = List<WorkoutSet>.from(sets);
          final item = updated.removeAt(oldIndex);
          updated.insert(newIndex, item);
          onReorderSets!(
              updated, updated.map((s) => s.setId).toList());
        },
        children: sets
            .map((s) => SetRow(
                  key: ValueKey(s.setId),
                  set: s,
                  detail: exerciseDetailMap[s.exerciseId],
                  interactive: interactive,
                  onEdit: onEditSet,
                  showExerciseName: true,
                ))
            .toList(),
      );
    }
    return Column(
      children: sets
          .map((s) => SetRow(
                set: s,
                detail: exerciseDetailMap[s.exerciseId],
                interactive: interactive,
                onEdit: onEditSet,
                showExerciseName: true,
              ))
          .toList(),
    );
  }
}

// ── Single set row ─────────────────────────────────────────────────────────────

class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.set,
    required this.detail,
    this.interactive = false,
    this.onEdit,
    this.showExerciseName = false,
  });

  final WorkoutSet set;
  final ExerciseDetail? detail;
  final bool interactive;
  final ValueChanged<WorkoutSet>? onEdit;
  final bool showExerciseName;

  String _volumeLabel() {
    final isReps = set.duration.isEmpty;
    final values = isReps ? set.reps : set.duration;
    final valStr = values.isEmpty ? '—' : values.join(', ');
    final weightStr = set.weight != null ? '${set.weight} kg' : null;
    final unit = isReps ? 'reps' : 's';
    if (weightStr != null) return '$weightStr × $valStr $unit';
    return '$valStr $unit';
  }

  String? _variationLabel() {
    if (set.variationId == null || detail == null) return null;
    final v = detail!.assignedVariations
        .where((v) => v.variationId == set.variationId)
        .firstOrNull;
    return v != null ? toProperCase(v.name) : null;
  }

  /// Variation and notes condensed onto one muted line, e.g. "Incline · so close".
  String? _metaLabel() {
    final varLabel = _variationLabel();
    final notes = set.notes?.isNotEmpty == true ? set.notes : null;
    if (varLabel == null) return notes;
    if (notes == null) return varLabel;
    return '$varLabel · $notes';
  }

  @override
  Widget build(BuildContext context) {
    final metaLabel = _metaLabel();
    final content = Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showExerciseName && detail != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      toProperCase(detail!.name),
                      style: TextStyle(
                          fontSize: AppTextStyles.sm,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                Text(
                  _volumeLabel(),
                  style: TextStyle(
                      fontSize: AppTextStyles.md,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary),
                ),
                if (metaLabel != null)
                  Text(
                    metaLabel,
                    style: TextStyle(
                        fontSize: AppTextStyles.xs,
                        color: AppColors.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (interactive) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.drag_handle,
                size: 18, color: AppColors.muted),
          ],
        ],
      ),
    );

    if (interactive && onEdit != null) {
      return GestureDetector(
        onLongPress: () => onEdit!(set),
        child: content,
      );
    }
    return content;
  }
}
