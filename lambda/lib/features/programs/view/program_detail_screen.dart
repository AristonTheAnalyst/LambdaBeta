import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/workout_format.dart';
import '../../../../data/models/planned_set.dart';
import '../../../../data/models/planned_workout.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/dropdown_select.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/press_squash.dart';
import '../../../../shared/widgets/segmented_control.dart';
import '../../../../shared/widgets/set_form_sheet.dart';
import '../../../../shared/widgets/slide_up_modal.dart';
import '../viewmodel/program_detail_viewmodel.dart';

const _progressionModeOptions = [
  SegmentOption(label: 'Sequential', value: 'sequential'),
  SegmentOption(label: 'Calendar', value: 'calendar'),
];

const _dayOfWeekOptions = [
  SegmentOption<int?>(label: 'Mon', value: 1),
  SegmentOption<int?>(label: 'Tue', value: 2),
  SegmentOption<int?>(label: 'Wed', value: 3),
  SegmentOption<int?>(label: 'Thu', value: 4),
  SegmentOption<int?>(label: 'Fri', value: 5),
  SegmentOption<int?>(label: 'Sat', value: 6),
  SegmentOption<int?>(label: 'Sun', value: 7),
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
  final _workoutNameController = TextEditingController();
  final _workoutNotesController = TextEditingController();
  final _setWeightController = TextEditingController();
  final _setRepsController = TextEditingController();
  final _setNotesController = TextEditingController();

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
    _workoutNameController.dispose();
    _workoutNotesController.dispose();
    _setWeightController.dispose();
    _setRepsController.dispose();
    _setNotesController.dispose();
    super.dispose();
  }

  // ── Planned workout editor sheet ─────────────────────────────────────────

  void _openCreateWorkout() {
    _workoutNameController.clear();
    _workoutNotesController.clear();
    _vm.openCreateWorkout();
    _showWorkoutEditorSheet();
  }

  void _openEditWorkout(PlannedWorkout w) {
    _workoutNameController.text = w.name;
    _workoutNotesController.text = w.notes ?? '';
    _vm.openEditWorkout(w);
    _showWorkoutEditorSheet();
  }

  void _showWorkoutEditorSheet() {
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: ValueListenableBuilder<ProgramDetailState>(
        valueListenable: _vm.state,
        builder: (context, state, _) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            state.editingWorkout == null
                                ? 'New Planned Workout'
                                : 'Edit Planned Workout',
                            style: AppFonts.ui(
                                fontSize: AppTextStyles.lg,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary)),
                      ),
                      if (state.editingWorkout != null)
                        GlassButton(
                          label: '',
                          icon: Icons.delete_outline,
                          color: AppColors.danger,
                          compact: true,
                          onPressed: () => _confirmDeleteWorkout(
                              state.editingWorkout!.plannedWorkoutId),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LambdaInput(
                    controller: _workoutNameController,
                    label: 'Workout name',
                    placeholder: 'e.g. Push Day',
                    textCapitalization: TextCapitalization.words,
                    onChanged: _vm.setWorkoutNameDraft,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LambdaInput(
                    controller: _workoutNotesController,
                    label: 'Focus / notes (optional)',
                    placeholder: 'What to focus on…',
                    onChanged: _vm.setWorkoutNotesDraft,
                  ),
                  if (state.isCalendarMode) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text('Day of week',
                        style: AppFonts.ui(
                            fontSize: AppTextStyles.sm,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary)),
                    const SizedBox(height: AppSpacing.xs),
                    SegmentedControl<int?>(
                      options: _dayOfWeekOptions,
                      value: state.workoutDayOfWeekDraft,
                      onChange: _vm.setWorkoutDayOfWeekDraft,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  GlassButton(
                    label: state.editingWorkout == null ? 'Create Workout' : 'Save',
                    loading: state.workoutSaving,
                    disabled: state.workoutSaving,
                    onPressed: _vm.submitWorkoutEditor,
                  ),
                  if (state.editingWorkout != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Divider(color: AppColors.border),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Planned Sets',
                              style: AppFonts.ui(
                                  fontSize: AppTextStyles.md,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary)),
                        ),
                        GlassButton(
                          label: '',
                          icon: Icons.add,
                          compact: true,
                          onPressed: _openCreateSet,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (state.workoutSetsLoading)
                      Center(
                          child: CircularProgressIndicator(color: AppColors.accent))
                    else if (state.workoutPlannedSets.isEmpty)
                      Text('No planned sets yet.',
                          style: AppFonts.ui(
                              color: AppColors.muted, fontSize: AppTextStyles.sm))
                    else
                      ReorderableListView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        onReorderItem: (oldIndex, newIndex) {
                          final updated =
                              List<PlannedSet>.from(state.workoutPlannedSets);
                          final item = updated.removeAt(oldIndex);
                          updated.insert(newIndex, item);
                          _vm.reorderPlannedSets(updated,
                              updated.map((s) => s.plannedSetId).toList());
                        },
                        children: state.workoutPlannedSets
                            .map((ps) => _PlannedSetRow(
                                  key: ValueKey(ps.plannedSetId),
                                  set: ps,
                                  onTap: () {
                                    _openEditSet(ps);
                                  },
                                ))
                            .toList(),
                      ),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) => _vm.closeWorkoutEditor());
  }

  void _confirmDeleteWorkout(String plannedWorkoutId) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete Planned Workout',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.danger)),
        content: Text('Remove this workout and its planned sets?',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context, rootNavigator: true).pop();
                _vm.archiveWorkout(plannedWorkoutId);
              },
              child: Text('Delete',
                  style: AppFonts.ui(
                      color: AppColors.danger, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  // ── Planned set form sheet (nested inside the workout editor sheet) ─────

  void _openCreateSet() {
    _setWeightController.clear();
    _setRepsController.clear();
    _setNotesController.clear();
    _vm.openCreateSet();
    _showSetFormSheet();
  }

  void _openEditSet(PlannedSet ps) {
    _vm.openEditSet(ps);
    final s = _vm.state.value;
    _setWeightController.text = s.setWeightDraft;
    _setRepsController.text = s.setRepsDraft;
    _setNotesController.text = s.setNotesDraft;
    _showSetFormSheet();
  }

  void _showSetFormSheet() {
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: ValueListenableBuilder<ProgramDetailState>(
        valueListenable: _vm.state,
        builder: (context, state, _) {
          final detail = state.setExDetail;
          return SetFormSheet(
            title: state.editingSet == null ? 'Plan Set' : 'Edit Planned Set',
            exerciseOptions: state.exerciseDetailMap.values
                .map((d) =>
                    DropdownOption(label: toProperCase(d.name), value: d.exerciseId))
                .toList(),
            selectedExerciseId: state.setExId,
            onExerciseChanged: _vm.setSetExId,
            variationOptions: [
              const DropdownOption<String?>(label: 'None', value: null),
              ...(detail?.assignedVariations ?? []).map((v) =>
                  DropdownOption(label: toProperCase(v.name), value: v.variationId)),
            ],
            selectedVariationId: state.setVarId,
            onVariationChanged: _vm.setSetVarId,
            volumeType: state.setVolumeType,
            onVolumeTypeChanged: _vm.setSetVolumeType,
            weightCtrl: _setWeightController,
            repsCtrl: _setRepsController,
            notesCtrl: _setNotesController,
            onWeightChanged: _vm.setSetWeightDraft,
            onRepsChanged: _vm.setSetRepsDraft,
            onNotesChanged: _vm.setSetNotesDraft,
            weightLabel: 'Target Weight (optional)',
            repsLabel: 'Target Reps',
            durationLabel: 'Target Duration (seconds)',
            notesLabel: 'Target notes (optional)',
            submitLabel: state.editingSet == null ? 'Add to Plan' : 'Save',
            submitLoading: state.setSaving,
            onSubmit: _vm.submitSetForm,
            onDelete: state.editingSet != null
                ? () => _confirmDeleteSet(state.editingSet!.plannedSetId)
                : null,
          );
        },
      ),
    ).then((_) => _vm.closeSetForm());
  }

  void _confirmDeleteSet(String plannedSetId) {
    Navigator.of(context, rootNavigator: true).pop();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete Planned Set',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.primary)),
        content:
            Text('Remove this planned set?', style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _vm.deletePlannedSet(plannedSetId);
              },
              child: Text('Delete',
                  style: AppFonts.ui(
                      color: AppColors.danger, fontWeight: FontWeight.w600))),
        ],
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

class _PlannedSetRow extends StatelessWidget {
  const _PlannedSetRow({super.key, required this.set, required this.onTap});

  final PlannedSet set;
  final VoidCallback onTap;

  String _volumeLabel() {
    final isReps = set.targetDuration.isEmpty;
    final values = isReps ? set.targetReps : set.targetDuration;
    final valStr = values.isEmpty ? '—' : values.join(', ');
    final weightStr = set.targetWeight != null ? '${set.targetWeight} kg' : null;
    final unit = isReps ? 'reps' : 's';
    if (weightStr != null) return '$weightStr × $valStr $unit';
    return '$valStr $unit';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (set.exerciseName != null)
                    Text(toProperCase(set.exerciseName!),
                        style: AppFonts.ui(
                            fontSize: AppTextStyles.sm,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                  Text(_volumeLabel(),
                      style: AppFonts.mono(
                          fontSize: AppTextStyles.md,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                  if (set.variationName != null)
                    Text(toProperCase(set.variationName!),
                        style:
                            AppFonts.ui(fontSize: AppTextStyles.xs, color: AppColors.muted)),
                ],
              ),
            ),
            Icon(Icons.drag_handle, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
