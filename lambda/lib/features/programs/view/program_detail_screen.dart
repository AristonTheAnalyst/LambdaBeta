import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/workout_format.dart';
import '../../../../data/models/planned_workout.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/press_squash.dart';
import '../../../../shared/widgets/segmented_control.dart';
import '../viewmodel/program_detail_viewmodel.dart';
import 'plan_workout_screen.dart';

const _progressionModeOptions = [
  SegmentOption(label: 'Sequential', value: 'sequential'),
  SegmentOption(label: 'Calendar', value: 'calendar'),
];

String _dayOfWeekLabel(int? d) => switch (d) {
      1 => 'Mon',
      2 => 'Tue',
      3 => 'Wed',
      4 => 'Thu',
      5 => 'Fri',
      6 => 'Sat',
      7 => 'Sun',
      _ => '',
    };

class ProgramDetailScreen extends StatefulWidget {
  const ProgramDetailScreen({super.key, required this.programId});
  final String programId;

  @override
  State<ProgramDetailScreen> createState() => _ProgramDetailScreenState();
}

class _ProgramDetailScreenState extends State<ProgramDetailScreen> {
  late final ProgramDetailViewModel _vm;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _lengthWeeksController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _vm = ProgramDetailViewModel();
    _vm.load(widget.programId).then((_) {
      if (!mounted) return;
      final s = _vm.state.value;
      _nameController.text = s.nameDraft;
      _descriptionController.text = s.descriptionDraft;
      _lengthWeeksController.text = s.lengthWeeksDraft;
    });
  }

  @override
  void dispose() {
    _vm.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _lengthWeeksController.dispose();
    super.dispose();
  }

  void _openCreateWorkout() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlanWorkoutScreen(viewModel: _vm),
      ),
    );
  }

  void _openEditWorkout(PlannedWorkout w) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlanWorkoutScreen(viewModel: _vm, workout: w),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ValueListenableBuilder<ProgramDetailState>(
        valueListenable: _vm.state,
        builder: (context, state, _) {
          return Column(
            children: [
              PageHeader(
                title: state.program != null
                    ? toProperCase(state.program!.name)
                    : 'Program',
                left: GestureDetector(
                  onTap: () => context.pop(),
                  child: Icon(Icons.arrow_back_ios_new,
                      size: 18, color: AppColors.accent),
                ),
                right: GlassButton(
                  label: 'Save',
                  compact: true,
                  loading: state.isSaving,
                  disabled: state.isSaving,
                  onPressed: _vm.saveProgramDetails,
                ),
              ),
              if (state.error != null)
                Container(
                  width: double.infinity,
                  color: AppColors.dangerBg,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  child: Text(state.error!,
                      style: AppFonts.ui(
                          color: AppColors.danger, fontSize: AppTextStyles.sm)),
                ),
              if (state.isLoading)
                Expanded(
                    child:
                        Center(child: CircularProgressIndicator(color: AppColors.accent)))
              else
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LambdaInput(
                          controller: _nameController,
                          label: 'Program name',
                          placeholder: 'e.g. Strength Block 1',
                          textCapitalization: TextCapitalization.words,
                          onChanged: _vm.setNameDraft,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        LambdaInput(
                          controller: _descriptionController,
                          label: 'Goal / description (optional)',
                          placeholder: 'What is this program trying to achieve?',
                          onChanged: _vm.setDescriptionDraft,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        LambdaInput(
                          controller: _lengthWeeksController,
                          label: 'Length in weeks (optional)',
                          placeholder: 'e.g. 6',
                          keyboardType: TextInputType.number,
                          onChanged: _vm.setLengthWeeksDraft,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text('Progression',
                            style: AppFonts.ui(
                                fontSize: AppTextStyles.sm,
                                fontWeight: FontWeight.w500,
                                color: AppColors.primary)),
                        const SizedBox(height: AppSpacing.xs),
                        SegmentedControl<String>(
                          options: _progressionModeOptions,
                          value: state.progressionModeDraft,
                          onChange: _vm.setProgressionModeDraft,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: [
                            Expanded(
                              child: state.isCurrent
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentBg,
                                        borderRadius: BorderRadius.circular(AppRadius.md),
                                        border: Border.all(color: AppColors.accent),
                                      ),
                                      child: Center(
                                        child: Text('Current Program',
                                            style: AppFonts.ui(
                                                fontSize: AppTextStyles.sm,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.accent)),
                                      ),
                                    )
                                  : GlassButton(
                                      label: 'Set as Current Program',
                                      icon: Icons.play_circle_outline,
                                      loading: state.settingCurrent,
                                      disabled: state.settingCurrent,
                                      onPressed: _vm.setAsCurrent,
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Divider(color: AppColors.border),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: Text('Planned Workouts',
                                  style: AppFonts.ui(
                                      fontSize: AppTextStyles.md,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary)),
                            ),
                            GlassButton(
                              label: '',
                              icon: Icons.add,
                              compact: true,
                              onPressed: _openCreateWorkout,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (state.plannedWorkouts.isEmpty)
                          Text('No planned workouts yet.',
                              style: AppFonts.ui(
                                  color: AppColors.muted, fontSize: AppTextStyles.sm))
                        else
                          ReorderableListView(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            onReorderItem: (oldIndex, newIndex) {
                              final updated =
                                  List<PlannedWorkout>.from(state.plannedWorkouts);
                              final item = updated.removeAt(oldIndex);
                              updated.insert(newIndex, item);
                              _vm.reorderWorkouts(updated,
                                  updated.map((w) => w.plannedWorkoutId).toList());
                            },
                            children: state.plannedWorkouts
                                .map((w) => _PlannedWorkoutRow(
                                      key: ValueKey(w.plannedWorkoutId),
                                      workout: w,
                                      showDayOfWeek: state.isCalendarMode,
                                      onTap: () => _openEditWorkout(w),
                                    ))
                                .toList(),
                          ),
                        const SizedBox(height: AppSpacing.xxl),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Rows ─────────────────────────────────────────────────────────────────────

class _PlannedWorkoutRow extends StatelessWidget {
  const _PlannedWorkoutRow({
    super.key,
    required this.workout,
    required this.showDayOfWeek,
    required this.onTap,
  });

  final PlannedWorkout workout;
  final bool showDayOfWeek;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: PressSquash(
          onTap: onTap,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(toProperCase(workout.name),
                        style: AppFonts.ui(
                            fontSize: AppTextStyles.md,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                    if (workout.notes?.isNotEmpty == true)
                      Text(workout.notes!,
                          style: AppFonts.ui(
                              fontSize: AppTextStyles.xs, color: AppColors.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (showDayOfWeek && workout.dayOfWeek != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(_dayOfWeekLabel(workout.dayOfWeek),
                      style:
                          AppFonts.ui(fontSize: AppTextStyles.xs, color: AppColors.muted)),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Icon(Icons.drag_handle, size: 18, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
