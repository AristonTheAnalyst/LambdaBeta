import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_fonts.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import 'container_styles.dart';
import 'dropdown_select.dart';

/// The Training Logs filter chips — exercise, variation, and the date-range
/// selector. Shared between the Logs screen and the Session tab's Session
/// Prep page (ALL SESSIONS browse) so the filters look and behave
/// identically.
class LogsFilterBar extends StatelessWidget {
  const LogsFilterBar({
    super.key,
    required this.exercises,
    required this.variations,
    required this.selectedExercise,
    required this.selectedVariation,
    required this.dateLabel,
    required this.dateActive,
    required this.onExerciseChanged,
    required this.onVariationChanged,
    required this.onDateTap,
    required this.onClear,
  });

  final List<String> exercises;
  final List<String> variations;
  final String? selectedExercise;
  final String? selectedVariation;
  final String dateLabel;
  final bool dateActive;
  final ValueChanged<String?> onExerciseChanged;
  final ValueChanged<String?> onVariationChanged;
  final VoidCallback onDateTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
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
              child: Icon(Icons.close, size: 18, color: AppColors.muted),
            ),
          ],
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
                  color: isActive ? AppColors.accent : AppColors.muted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down, size: 14,
                color: isActive ? AppColors.accent : AppColors.muted),
          ],
        ),
      ),
    );
  }
}
