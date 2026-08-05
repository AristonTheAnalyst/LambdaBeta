import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/workout_format.dart';
import '../../../../data/models/planned_workout.dart';
import '../../../../data/models/program_run.dart';
import '../../../../data/repositories/workout_plan_repository.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/segmented_control.dart';
import '../../../../shared/widgets/swipe_actions.dart';
import '../viewmodel/program_detail_viewmodel.dart';
import 'plan_workout_screen.dart';

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

  Future<void> _confirmBeginProgram() async {
    final state = _vm.state.value;
    final isCalendar = state.program?.progressionMode == 'calendar';
    final controller = TextEditingController();
    var useEndDate = false;
    DateTime? endDate;

    final result = await showDialog<({int? count, DateTime? endDate})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Begin Program',
              style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.primary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  'This resets progress on any currently active program.',
                  style: AppFonts.ui(color: AppColors.muted)),
              const SizedBox(height: AppSpacing.md),
              if (isCalendar) ...[
                SegmentedControl<bool>(
                  subtle: true,
                  options: const [
                    SegmentOption(label: 'Weeks', value: false),
                    SegmentOption(label: 'End date', value: true),
                  ],
                  value: useEndDate,
                  onChange: (v) => setState(() => useEndDate = v),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (!isCalendar || !useEndDate)
                LambdaInput(
                  controller: controller,
                  label: isCalendar ? 'Number of weeks' : 'Number of sessions',
                  placeholder: isCalendar ? 'e.g. 6' : 'e.g. 12',
                  keyboardType: TextInputType.number,
                  required: true,
                )
              else ...[
                Text('End date',
                    style: AppFonts.ui(fontSize: AppTextStyles.sm,
                        fontWeight: FontWeight.w600, color: AppColors.primary)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(DateTime.now().year + 5),
                    );
                    if (picked != null) setState(() => endDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(endDate != null
                        ? '${endDate!.day}/${endDate!.month}/${endDate!.year}'
                        : 'Pick a date…',
                        style: AppFonts.ui(color: endDate != null ? AppColors.primary : AppColors.muted)),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
            TextButton(
                onPressed: () {
                  final count = int.tryParse(controller.text.trim());
                  if (isCalendar && useEndDate) {
                    if (endDate == null) return;
                    Navigator.of(ctx).pop((count: null, endDate: endDate));
                  } else {
                    if (count == null || count <= 0) return;
                    Navigator.of(ctx).pop((count: count, endDate: null));
                  }
                },
                child: Text('Begin',
                    style: AppFonts.ui(color: AppColors.accent, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    await _vm.setAsCurrent(
      targetSessions: isCalendar ? null : result.count,
      targetWeeks: (isCalendar && !useEndDate) ? result.count : null,
      endDate: result.endDate,
    );
  }

  String _runConfigLabel(ProgramRun run) {
    if (run.targetSessions != null) return '${run.targetSessions} sessions';
    final w = run.targetWeeks;
    if (w != null) return '$w weeks';
    final end = run.endDate;
    if (end != null) return 'ends ${end.day}/${end.month}/${end.year}';
    return 'duration not set';
  }

  /// Edits the active run's duration config while the program is running.
  Future<void> _editRunConfig(ProgramRun run) async {
    final isCalendar = _vm.state.value.program?.progressionMode == 'calendar';
    final controller = TextEditingController(
        text: (run.targetSessions ?? run.targetWeeks ?? '').toString());
    var useEndDate = isCalendar && run.endDate != null && run.targetWeeks == null;
    var endDate = run.endDate;

    final result = await showDialog<({int? count, DateTime? endDate})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Edit duration',
              style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.primary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isCalendar) ...[
                SegmentedControl<bool>(
                  subtle: true,
                  options: const [
                    SegmentOption(label: 'Weeks', value: false),
                    SegmentOption(label: 'End date', value: true),
                  ],
                  value: useEndDate,
                  onChange: (v) => setState(() => useEndDate = v),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (!isCalendar || !useEndDate)
                LambdaInput(
                  controller: controller,
                  label: isCalendar ? 'Number of weeks' : 'Number of sessions',
                  placeholder: isCalendar ? 'e.g. 6' : 'e.g. 12',
                  keyboardType: TextInputType.number,
                )
              else ...[
                Text('End date',
                    style: AppFonts.ui(fontSize: AppTextStyles.sm,
                        fontWeight: FontWeight.w600, color: AppColors.primary)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: endDate ?? DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(DateTime.now().year + 5),
                    );
                    if (picked != null) setState(() => endDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(endDate != null
                        ? '${endDate!.day}/${endDate!.month}/${endDate!.year}'
                        : 'Pick a date…',
                        style: AppFonts.ui(color: endDate != null ? AppColors.primary : AppColors.muted)),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
            TextButton(
                onPressed: () {
                  final count = int.tryParse(controller.text.trim());
                  if (isCalendar && useEndDate) {
                    if (endDate == null) return;
                    Navigator.of(ctx).pop((count: null, endDate: endDate));
                  } else {
                    if (count == null || count <= 0) return;
                    Navigator.of(ctx).pop((count: count, endDate: null));
                  }
                },
                child: Text('Save',
                    style: AppFonts.ui(color: AppColors.accent, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    await _vm.updateRunConfig(
      targetSessions: isCalendar ? null : result.count,
      clearSessions: !isCalendar,
      targetWeeks: (isCalendar && !useEndDate) ? result.count : null,
      clearWeeks: (isCalendar && useEndDate),
      endDate: result.endDate,
      clearEndDate: (isCalendar && !useEndDate),
    );
  }

  @override
  void initState() {
    super.initState();
    _vm = ProgramDetailViewModel();
    _vm.load(widget.programId).then((_) {
      if (!mounted) return;
      final s = _vm.state.value;
      _nameController.text = s.nameDraft;
      _descriptionController.text = s.descriptionDraft;
    });
  }

  @override
  void dispose() {
    _vm.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _openCreateWorkout() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => PlanWorkoutScreen(viewModel: _vm),
      ),
    );
  }

  /// "+" on Planned Workouts: offer creating a new workout or copying an
  /// existing standalone workout into this program.
  Future<void> _openAddWorkoutMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text('Add workout',
                  style: AppFonts.ui(
                      fontSize: AppTextStyles.lg,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ),
            ListTile(
              leading: Icon(Icons.add, color: AppColors.accent),
              title: Text('New workout',
                  style: AppFonts.ui(
                      fontSize: AppTextStyles.md, color: AppColors.primary)),
              onTap: () => Navigator.of(ctx).pop('new'),
            ),
            ListTile(
              leading: Icon(Icons.library_add_outlined, color: AppColors.accent),
              title: Text('From Workouts',
                  style: AppFonts.ui(
                      fontSize: AppTextStyles.md, color: AppColors.primary)),
              onTap: () => Navigator.of(ctx).pop('from'),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'new') {
      _openCreateWorkout();
    } else if (choice == 'from') {
      await _addExistingWorkout();
    }
  }

  /// Confirms and removes a planned workout from this program.
  Future<void> _confirmDeleteWorkout(PlannedWorkout w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Remove Workout',
            style: AppFonts.ui(fontWeight: FontWeight.w800, color: AppColors.danger)),
        content: Text('Remove "${toProperCase(w.name)}" from this program?',
            style: AppFonts.ui(color: AppColors.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Remove',
                  style: AppFonts.ui(
                      color: AppColors.danger, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _vm.removePlannedWorkout(w);
    }
  }

  /// Lets the user pick a standalone workout to copy into this program.
  Future<void> _addExistingWorkout() async {
    final repo = WorkoutPlanRepository();
    final workouts = await repo.fetchWorkouts(
        Supabase.instance.client.auth.currentUser!.id);
    if (workouts.isEmpty || !mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text('Add workout to program',
                  style: AppFonts.ui(
                      fontSize: AppTextStyles.lg,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary)),
            ),
            for (final w in workouts)
              ListTile(
                title: Text(toProperCase(w.name),
                    style: AppFonts.ui(
                        fontSize: AppTextStyles.md, color: AppColors.primary)),
                onTap: () => Navigator.of(ctx).pop(w.workoutId),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await _vm.copyWorkoutIntoProgram(chosen);
  }

  Future<void> _openEditWorkout(PlannedWorkout w) async {
    // Informational confirm when editing a workout in a running program:
    // changes apply to future sessions only; already-logged sets are snapshots
    // and won't change.
    if (_vm.state.value.isCurrent) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Edit while running?',
              style: AppFonts.ui(
                  fontWeight: FontWeight.w800, color: AppColors.primary)),
          content: Text(
              'This program is active. Changes to the workout apply to future '
              'sessions; past logged sets and PRs won\'t change.',
              style: AppFonts.ui(color: AppColors.muted)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child:
                    Text('Cancel', style: AppFonts.ui(color: AppColors.muted))),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('Edit',
                    style: AppFonts.ui(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    Navigator.of(context, rootNavigator: true).push(
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
                title: 'Program',
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
                          required: true,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        LambdaInput(
                          controller: _descriptionController,
                          label: 'Goal / description',
                          placeholder: 'What is this program trying to achieve?',
                          onChanged: _vm.setDescriptionDraft,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text('Progression',
                            style: AppFonts.ui(
                                fontSize: AppTextStyles.sm,
                                fontWeight: FontWeight.w500,
                                color: AppColors.primary)),
                        const SizedBox(height: AppSpacing.xs),
                        // Locked once created — progression determines how the
                        // run schedules workouts and can't change afterwards.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 14, color: AppColors.muted),
                              const SizedBox(width: 8),
                              Text(
                                state.progressionModeDraft == 'calendar'
                                    ? 'Calendar'
                                    : 'Sequential',
                                style: AppFonts.ui(
                                    fontSize: AppTextStyles.sm,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (!state.isCurrent)
                          Row(
                            children: [
                              Expanded(
                                child: GlassButton(
                                  label: 'Begin Program',
                                  icon: Icons.play_circle_outline,
                                  loading: state.settingCurrent,
                                  disabled: state.settingCurrent,
                                  onPressed: _confirmBeginProgram,
                                ),
                              ),
                            ],
                          ),
                        if (state.isCurrent && state.activeRun != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _runConfigLabel(state.activeRun!),
                            style: AppFonts.mono(
                                fontSize: 10, color: AppColors.muted),
                          ),
                          if (state.currentProgress != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              state.currentProgress!.remainingLabel,
                              style: AppFonts.mono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accent),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xs),
                          GlassButton(
                            label: 'Edit duration',
                            icon: Icons.tune,
                            compact: true,
                            onPressed: () => _editRunConfig(state.activeRun!),
                          ),
                        ],
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
                              onPressed: _openAddWorkoutMenu,
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
                                      onDelete: () => _confirmDeleteWorkout(w),
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
    required this.onDelete,
  });

  final PlannedWorkout workout;
  final bool showDayOfWeek;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SwipeActions(
        actions: [
          SwipeAction(
            icon: Icons.delete_outline,
            label: 'Delete',
            color: AppColors.danger,
            onTap: onDelete,
          ),
        ],
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
              if (showDayOfWeek) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: workout.dayOfWeek != null
                        ? AppColors.surfaceHigh
                        : AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(workout.dayOfWeek != null
                      ? _dayOfWeekLabel(workout.dayOfWeek)
                      : 'No day',
                      style: AppFonts.ui(
                          fontSize: AppTextStyles.xs,
                          color: workout.dayOfWeek != null
                              ? AppColors.muted
                              : AppColors.danger)),
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
