import 'package:flutter/material.dart';
import '../../core/styles/app_colors.dart';
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
    this.onDelete,
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
  final VoidCallback? onNewExercise;
  final VoidCallback? onNewVariation;
  // Shows a delete icon next to the title when set (edit mode only).
  final VoidCallback? onDelete;

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
              label: 'Weight (optional)',
              placeholder: 'kg',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: onWeightChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            LambdaInput(
              controller: repsCtrl,
              label: isDuration ? 'Duration (seconds)' : 'Reps',
              placeholder: isDuration ? 'e.g. 60,45' : 'e.g. 10,8,6',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: false),
              onChanged: onRepsChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            LambdaInput(
              controller: notesCtrl,
              label: 'Set notes (optional)',
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
