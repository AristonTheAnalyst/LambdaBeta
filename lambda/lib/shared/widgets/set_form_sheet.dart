import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
import '../../core/styles/app_radius.dart';
import '../../core/styles/app_spacing.dart';
import '../../core/styles/app_text_styles.dart';
import 'dropdown_select.dart';
import 'glass_button.dart';
import 'lambda_input.dart';
import 'segmented_control.dart';

const _volumeTypeOptions = [
  SegmentOption(label: 'Reps', value: 'reps'),
  SegmentOption(label: 'Duration', value: 'duration'),
];

/// The Log Set / Edit Set form — shared by the Session screen (logging sets
/// during an active workout) and Workout Detail (editing sets on a past
/// workout). Takes plain values and callbacks rather than a viewmodel, so
/// both screens' viewmodels can drive the same widget.
class SetFormSheet extends StatelessWidget {
  const SetFormSheet({
    super.key,
    required this.title,
    required this.exerciseOptions,
    required this.selectedExerciseId,
    required this.onExerciseChanged,
    required this.variationOptions,
    required this.selectedVariationId,
    required this.onVariationChanged,
    required this.volumeType,
    required this.onVolumeTypeChanged,
    required this.weightCtrl,
    required this.repsCtrl,
    required this.notesCtrl,
    required this.onWeightChanged,
    required this.onRepsChanged,
    required this.onNotesChanged,
    required this.submitLabel,
    required this.submitLoading,
    required this.onSubmit,
    this.onNewExercise,
    this.onNewVariation,
    this.exerciseCreating = false,
    this.variationCreating = false,
    this.onDelete,
    this.weightLabel = 'Weight (optional)',
    this.repsLabel = 'Reps',
    this.durationLabel = 'Duration (seconds)',
    this.notesLabel = 'Set notes (optional)',
  });

  final String title;
  final List<DropdownOption<String>> exerciseOptions;
  final String? selectedExerciseId;
  final ValueChanged<String?> onExerciseChanged;
  final List<DropdownOption<String?>> variationOptions;
  final String? selectedVariationId;
  final ValueChanged<String?> onVariationChanged;
  // 'reps' | 'duration' — chosen per set, not tied to the exercise.
  final String volumeType;
  final ValueChanged<String> onVolumeTypeChanged;
  final TextEditingController weightCtrl;
  final TextEditingController repsCtrl;
  final TextEditingController notesCtrl;
  final ValueChanged<String> onWeightChanged;
  final ValueChanged<String> onRepsChanged;
  final ValueChanged<String> onNotesChanged;
  final String submitLabel;
  final bool submitLoading;
  final Future<bool> Function() onSubmit;
  // Called with whatever the user had already typed in the picker's search
  // box, so "New Exercise"/"New Variation" can create-and-select in one step
  // instead of asking for the name a second time.
  final ValueChanged<String>? onNewExercise;
  final ValueChanged<String>? onNewVariation;
  // True while a quick-create (see onNewExercise/onNewVariation above) is in
  // flight, so the field can show it's busy instead of looking frozen.
  final bool exerciseCreating;
  final bool variationCreating;
  // Shows a delete icon next to the title when set (edit mode only).
  final VoidCallback? onDelete;
  // Overridable so this same form can serve "Plan Set" (program planning)
  // as well as "Log Set"/"Edit Set" (live logging) with different copy.
  final String weightLabel;
  final String repsLabel;
  final String durationLabel;
  final String notesLabel;

  @override
  Widget build(BuildContext context) {
    final isDuration = volumeType == 'duration';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: AppTextStyles.lg,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ),
                SizedBox(
                  width: 148,
                  child: SegmentedControl<String>(
                    options: _volumeTypeOptions,
                    value: volumeType,
                    onChange: onVolumeTypeChanged,
                  ),
                ),
                if (onDelete != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  GlassButton(
                    label: '',
                    icon: Icons.delete_outline,
                    color: AppColors.danger,
                    compact: true,
                    onPressed: onDelete!,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Exercise',
                          style: TextStyle(
                              fontSize: AppTextStyles.sm,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primary)),
                      const SizedBox(height: AppSpacing.xs),
                      if (exerciseCreating)
                        const _CreatingField()
                      else
                        DropdownSelect<String>(
                          options: exerciseOptions,
                          value: selectedExerciseId,
                          onChange: onExerciseChanged,
                          placeholder: 'Select exercise…',
                          searchable: true,
                          onCreateNew: onNewExercise,
                          createNewLabel: 'New Exercise',
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Variation',
                          style: TextStyle(
                              fontSize: AppTextStyles.sm,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primary)),
                      const SizedBox(height: AppSpacing.xs),
                      if (variationCreating)
                        const _CreatingField()
                      else
                        DropdownSelect<String?>(
                          options: variationOptions,
                          value: selectedVariationId,
                          onChange: onVariationChanged,
                          placeholder: 'None',
                          searchable: true,
                          onCreateNew: onNewVariation,
                          createNewLabel: 'New Variation',
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            LambdaInput(
              controller: weightCtrl,
              label: weightLabel,
              placeholder: 'kg',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: onWeightChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            LambdaInput(
              controller: repsCtrl,
              label: isDuration ? durationLabel : repsLabel,
              placeholder: isDuration ? 'e.g. 60,45' : 'e.g. 10,8,6',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: false),
              onChanged: onRepsChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            LambdaInput(
              controller: notesCtrl,
              label: notesLabel,
              placeholder: 'Notes…',
              onChanged: onNotesChanged,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Cancel',
                    color: AppColors.danger,
                    compact: true,
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: GlassButton(
                    label: submitLabel,
                    compact: true,
                    loading: submitLoading,
                    disabled: submitLoading,
                    onPressed: () async {
                      final ok = await onSubmit();
                      if (ok && context.mounted) {
                        Navigator.of(context, rootNavigator: true).pop();
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

/// Stands in for a [DropdownSelect] while a quick-create is in flight —
/// matches its container styling exactly so the field doesn't jump.
class _CreatingField extends StatelessWidget {
  const _CreatingField();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: AppColors.accent),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text('Creating…',
                style: TextStyle(
                    fontSize: AppTextStyles.md, color: AppColors.muted),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
