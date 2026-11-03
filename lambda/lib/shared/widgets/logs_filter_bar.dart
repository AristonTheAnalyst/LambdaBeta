import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import 'container_styles.dart';
import 'dropdown_select.dart';

/// The Sessions browse's filter chips — exercise, variation, the workout
/// (planned session) the session followed, and the date-range selector.
/// Shared between the Logs screen and the Session tab's Sessions page (the
/// ALL SESSIONS browse) so the filters look and behave identically.
///
/// Two rows of two: four chips and the clear button cannot hold their labels
/// on one 402pt line at the 14px chip type (2026-10-23).
class LogsFilterBar extends StatelessWidget {
  const LogsFilterBar({
    super.key,
    required this.exercises,
    required this.variations,
    required this.workouts,
    required this.selectedExercise,
    required this.selectedVariation,
    required this.selectedWorkoutId,
    required this.dateLabel,
    required this.dateActive,
    required this.onExerciseChanged,
    required this.onVariationChanged,
    required this.onWorkoutChanged,
    required this.onDateTap,
    required this.onClear,
  });

  final List<String> exercises;
  final List<String> variations;

  /// The planned sessions found in the list, keyed by `planned_session_id`
  /// and labelled with the name their sessions snapshot — insertion order is
  /// the list's own (newest first).
  final Map<String, String> workouts;

  final String? selectedExercise;
  final String? selectedVariation;
  final String? selectedWorkoutId;
  final String dateLabel;
  final bool dateActive;
  final ValueChanged<String?> onExerciseChanged;
  final ValueChanged<String?> onVariationChanged;
  final ValueChanged<String?> onWorkoutChanged;
  final VoidCallback onDateTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final workoutLabel = selectedWorkoutId == null
        ? 'Workout'
        : (workouts[selectedWorkoutId] ?? 'Workout');
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _FilterChip(
                  label: selectedExercise ?? 'Exercise',
                  isActive: selectedExercise != null,
                  onTap: exercises.isEmpty
                      ? null
                      : () => showDropdownPickerSheet<String>(
                          context,
                          options: exercises
                              .map((e) => DropdownOption(label: e, value: e))
                              .toList(),
                          value: selectedExercise,
                          searchable: true,
                          // The picker's copy follows the chip's kind
                          // (2026-10-23): the sheet's default reads
                          // "variation", which is the other chip's job.
                          title: 'Choose exercise',
                          searchHint: 'Search exercises…',
                          emptyLabel: 'No exercises found',
                          onSelect: onExerciseChanged,
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _FilterChip(
                  label: selectedVariation ?? 'Variation',
                  isActive: selectedVariation != null,
                  onTap: variations.isEmpty
                      ? null
                      : () => showDropdownPickerSheet<String>(
                          context,
                          options: variations
                              .map((v) => DropdownOption(label: v, value: v))
                              .toList(),
                          value: selectedVariation,
                          searchable: true,
                          onSelect: onVariationChanged,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _FilterChip(
                  label: workoutLabel,
                  isActive: selectedWorkoutId != null,
                  onTap: workouts.isEmpty
                      ? null
                      : () => showDropdownPickerSheet<String>(
                          context,
                          options: workouts.entries
                              .map(
                                (e) => DropdownOption(
                                  label: e.value,
                                  value: e.key,
                                ),
                              )
                              .toList(),
                          value: selectedWorkoutId,
                          searchable: true,
                          title: 'Choose workout',
                          searchHint: 'Search workouts…',
                          emptyLabel: 'No workouts found',
                          onSelect: onWorkoutChanged,
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _FilterChip(
                  label: dateLabel,
                  isActive: dateActive,
                  onTap: onDateTap,
                ),
              ),
              if (onClear != null) ...[
                const SizedBox(width: AppSpacing.sm),
                GestureDetector(
                  onTap: onClear,
                  child: Icon(LucideIcons.x, size: 18, color: AppColors.muted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Generic filter chip (non-searchable, just opens a sheet).
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        // The glass recipe — active in accent, inactive in primary.
        decoration: glassBox(isActive ? AppColors.accent : AppColors.primary),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: FontWeight.w600,
                  color: isActive ? AppColors.accent : AppColors.inkSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              LucideIcons.chevronDown,
              size: 14,
              color: isActive ? AppColors.accent : AppColors.inkSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
