import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/session_format.dart';
import '../../../../data/models/exercise_detail.dart';
import '../../../../data/models/planned_session.dart';
import '../../../../data/models/goal.dart';
import '../../../../data/models/program_run.dart';
import '../../../../data/repositories/planned_session_repository.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/segmented_control.dart';
import '../../../../shared/utils/pop_dialog.dart';
import '../../../../shared/mixins/unsaved_changes_guard.dart';
import '../../../../shared/widgets/swipe_actions.dart';
import '../viewmodel/program_detail_viewmodel.dart';
import 'plan_session_screen.dart';

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

class _ProgramDetailScreenState extends State<ProgramDetailScreen>
    with UnsavedChangesGuard<ProgramDetailScreen> {
  late final ProgramDetailViewModel _vm;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  // ── UnsavedChangesGuard overrides ─────────────────────────────────────────

  @override
  bool get hasUnsavedChanges => _vm.state.value.hasUnsavedProgramFields;

  @override
  Future<void> onSave() async => await _vm.saveProgramDetails();

  @override
  void onDiscard() {
    final s = _vm.state.value;
    _nameController.text = s.program?.name ?? '';
    _descriptionController.text = s.program?.description ?? '';
    _vm.setNameDraft(s.program?.name ?? '');
    _vm.setDescriptionDraft(s.program?.description ?? '');
  }

  Future<void> _confirmBeginProgram() async {
    final controller = TextEditingController();
    var mode = 'order';
    var useEndDate = false;
    DateTime? endDate;
    bool isFrequency() => mode == 'frequency';

    final result = await showDialog<({int? count, DateTime? endDate, String mode})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Begin Program',
            style: AppFonts.ui(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This resets progress on any currently active program.',
                style: AppFonts.ui(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedControl<String>(
                subtle: true,
                options: const [
                  SegmentOption(label: 'Order', value: 'order'),
                  SegmentOption(label: 'Frequency', value: 'frequency'),
                ],
                value: mode,
                onChange: (v) => setState(() => mode = v),
              ),
              const SizedBox(height: AppSpacing.md),
              if (isFrequency()) ...[
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
              if (!isFrequency() || !useEndDate)
                LambdaInput(
                  controller: controller,
                  label: isFrequency() ? 'Number of weeks' : 'Number of sessions',
                  placeholder: isFrequency() ? 'e.g. 6' : 'e.g. 12',
                  keyboardType: TextInputType.number,
                  required: true,
                )
              else ...[
                Text(
                  'End date',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      endDate != null
                          ? '${endDate!.day}/${endDate!.month}/${endDate!.year}'
                          : 'Pick a date…',
                      style: AppFonts.ui(
                        color: endDate != null
                            ? AppColors.primary
                            : AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => popDialog(ctx),
              child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted)),
            ),
            TextButton(
              onPressed: () {
                final count = int.tryParse(controller.text.trim());
                if (isFrequency() && useEndDate) {
                  if (endDate == null) return;
                  // Release focus before popping — otherwise the dialog's
                  // FocusScope inherited element deactivates while the
                  // TextField still depends on it, throwing "depends is
                  // empty is not true" (framework debugDeactivated assert).
                  popDialog(ctx, (count: null, endDate: endDate, mode: mode));
                } else {
                  if (count == null || count <= 0) return;
                  popDialog(ctx, (count: count, endDate: null, mode: mode));
                }
              },
              child: Text(
                'Begin',
                style: AppFonts.ui(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    await _vm.setAsCurrent(
      progressionMode: result.mode,
      targetSessions: result.mode == 'order' ? result.count : null,
      targetWeeks: (result.mode == 'frequency' && !useEndDate)
          ? result.count
          : null,
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

  /// The day assigned to a planned session via its program link row.
  int? _dayFor(PlannedSession w) {
    for (final l in _vm.state.value.programLinks) {
      if (l.plannedSessionId == w.sessionId) return l.dayOfWeek;
    }
    return null;
  }

  Future<void> _confirmEndRun(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'End program?',
          style: AppFonts.ui(
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        content: Text(
          'Your progress will be saved. You can start this program again later.',
          style: AppFonts.ui(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('End', style: AppFonts.ui(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _vm.endCurrentRun();
    }
  }

  /// Edits the active run's config while the program is running — progression
  /// mode and/or duration.
  Future<void> _editRunConfig(ProgramRun run) async {
    var mode = run.progressionMode ?? 'order';
    bool isFrequency() => mode == 'frequency';
    final controller = TextEditingController(
      text: (run.targetSessions ?? run.targetWeeks ?? '').toString(),
    );
    var useEndDate =
        isFrequency() && run.endDate != null && run.targetWeeks == null;
    var endDate = run.endDate;

    final result = await showDialog<({int? count, DateTime? endDate, String mode})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Edit run config',
            style: AppFonts.ui(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedControl<String>(
                subtle: true,
                options: const [
                  SegmentOption(label: 'Order', value: 'order'),
                  SegmentOption(label: 'Frequency', value: 'frequency'),
                ],
                value: mode,
                onChange: (v) => setState(() => mode = v),
              ),
              const SizedBox(height: AppSpacing.md),
              if (isFrequency()) ...[
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
              if (!isFrequency() || !useEndDate)
                LambdaInput(
                  controller: controller,
                  label: isFrequency() ? 'Number of weeks' : 'Number of sessions',
                  placeholder: isFrequency() ? 'e.g. 6' : 'e.g. 12',
                  keyboardType: TextInputType.number,
                )
              else ...[
                Text(
                  'End date',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate:
                          endDate ??
                          DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(DateTime.now().year + 5),
                    );
                    if (picked != null) setState(() => endDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      endDate != null
                          ? '${endDate!.day}/${endDate!.month}/${endDate!.year}'
                          : 'Pick a date…',
                      style: AppFonts.ui(
                        color: endDate != null
                            ? AppColors.primary
                            : AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => popDialog(ctx),
              child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted)),
            ),
            TextButton(
              onPressed: () {
                final count = int.tryParse(controller.text.trim());
                if (isFrequency() && useEndDate) {
                  if (endDate == null) return;
                  popDialog(ctx, (count: null, endDate: endDate, mode: mode));
                } else {
                  if (count == null || count <= 0) return;
                  popDialog(ctx, (count: count, endDate: null, mode: mode));
                }
              },
              child: Text(
                'Save',
                style: AppFonts.ui(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    await _vm.updateRunConfig(
      progressionMode: result.mode,
      targetSessions: result.mode == 'order' ? result.count : null,
      clearSessions: result.mode != 'order',
      targetWeeks: (result.mode == 'frequency' && !useEndDate)
          ? result.count
          : null,
      clearWeeks: (result.mode != 'frequency' || useEndDate),
      endDate: result.endDate,
      clearEndDate: (result.mode != 'frequency' || !useEndDate),
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
    Navigator.of(context, rootNavigator: true)
        .push<bool>(
          MaterialPageRoute(builder: (_) => PlanSessionScreen(viewModel: _vm)),
        )
        .then((_) {
          if (mounted) _refreshAfterEdit();
        });
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
              child: Text(
                'Add workout',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.lg,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.add, color: AppColors.accent),
              title: Text(
                'New workout',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.md,
                  color: AppColors.primary,
                ),
              ),
              onTap: () => Navigator.of(ctx).pop('new'),
            ),
            ListTile(
              leading: Icon(
                Icons.library_add_outlined,
                color: AppColors.accent,
              ),
              title: Text(
                'From Workouts',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.md,
                  color: AppColors.primary,
                ),
              ),
              onTap: () => Navigator.of(ctx).pop('from'),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'new') {
      _openCreateWorkout(); // fire-and-forget — .then() handles refresh
    } else if (choice == 'from') {
      await _addExistingWorkout();
      if (mounted) _refreshAfterEdit();
    }
  }

  /// Confirms and removes a planned workout from this program.
  Future<void> _confirmDeleteWorkout(PlannedSession w) async {
    final isCurrent = _vm.state.value.isCurrent;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          isCurrent ? 'Remove from active program?' : 'Remove Session',
          style: AppFonts.ui(
            fontWeight: FontWeight.w800,
            color: AppColors.danger,
          ),
        ),
        content: Text(
          isCurrent
              ? '"${toProperCase(w.name)}" is part of your active program. '
                    'Removing it changes the workout cycle — the next session '
                    'will skip to the following workout. '
                    'Past logged sets stay intact.'
              : 'Remove "${toProperCase(w.name)}" from this program?',
          style: AppFonts.ui(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Remove',
              style: AppFonts.ui(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _vm.removePlannedSession(w);
    }
  }

  /// Lets the user pick a standalone workout to copy into this program.
  Future<void> _addExistingWorkout() async {
    final repo = PlannedSessionRepository();
    final workouts = await repo.fetchPlannedSessions(
      Supabase.instance.client.auth.currentUser!.id,
    );
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
              child: Text(
                'Add workout to program',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.lg,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            for (final w in workouts)
              ListTile(
                title: Text(
                  toProperCase(w.name),
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.md,
                    color: AppColors.primary,
                  ),
                ),
                onTap: () => Navigator.of(ctx).pop(w.sessionId),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await _vm.copyWorkoutIntoProgram(chosen);
  }

  Future<void> _openEditWorkout(PlannedSession w) async {
    // Informational confirm when editing a workout in a running program:
    // changes apply to future sessions only; already-logged sets are snapshots
    // and won't change.
    if (_vm.state.value.isCurrent) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Edit while running?',
            style: AppFonts.ui(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          content: Text(
            'This program is active. Changes to the workout apply to future '
            'sessions; past logged sets and PRs won\'t change.',
            style: AppFonts.ui(color: AppColors.muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Edit',
                style: AppFonts.ui(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    Navigator.of(context, rootNavigator: true)
        .push<bool>(
          MaterialPageRoute(
            builder: (_) => PlanSessionScreen(viewModel: _vm, workout: w),
          ),
        )
        .then((_) {
          if (mounted) _refreshAfterEdit();
        });
  }

  /// Refreshes after returning from the workout editor by deferring a full
  /// ViewModel reload past the current frame so the pop transition settles.
  void _refreshAfterEdit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _vm.load(widget.programId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return buildGuardedScaffold(
      scaffold: Scaffold(
        backgroundColor: AppColors.bg,
        body: ValueListenableBuilder<ProgramDetailState>(
          valueListenable: _vm.state,
          builder: (context, state, _) {
            return Column(
              children: [
                PageHeader(
                  title: 'Program',
                  left: GestureDetector(
                    onTap: () async {
                      final nav = Navigator.of(context);
                      if (await confirmBack() && mounted) {
                        nav.pop();
                      }
                    },
                    child: Icon(
                      Icons.arrow_back_ios_new,
                      size: 18,
                      color: AppColors.accent,
                    ),
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
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      state.error!,
                      style: AppFonts.ui(
                        color: AppColors.danger,
                        fontSize: AppTextStyles.sm,
                      ),
                    ),
                  ),
                if (state.saveSuccess)
                  Container(
                    width: double.infinity,
                    color: AppColors.successBg,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      'Program saved.',
                      style: AppFonts.ui(
                        color: AppColors.success,
                        fontSize: AppTextStyles.sm,
                      ),
                    ),
                  ),
                if (state.isLoading)
                  Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                  )
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
                            label: 'Description',
                            placeholder: 'What is this program about?',
                            onChanged: _vm.setDescriptionDraft,
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
                                fontSize: 10,
                                color: AppColors.muted,
                              ),
                            ),
                            if (state.currentProgress != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                state.currentProgress!.remainingLabel,
                                style: AppFonts.mono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accent,
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.xs),
                            GlassButton(
                              label: 'Edit duration',
                              icon: Icons.tune,
                              compact: true,
                              onPressed: () => _editRunConfig(state.activeRun!),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            GlassButton(
                              label: 'End Program',
                              icon: Icons.stop_circle_outlined,
                              compact: true,
                              onPressed: () => _confirmEndRun(context),
                            ),
                          ],
                          if (state.isCurrent && state.activeRun != null) ...[
                            const SizedBox(height: AppSpacing.lg),
                            _buildGoalsSection(state),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          Divider(color: AppColors.border),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Planned Workouts',
                                  style: AppFonts.ui(
                                    fontSize: AppTextStyles.md,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
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
                            Text(
                              'No planned workouts yet.',
                              style: AppFonts.ui(
                                color: AppColors.muted,
                                fontSize: AppTextStyles.sm,
                              ),
                            )
                          else
                            ReorderableListView(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: false,
                              onReorderItem: (oldIndex, newIndex) {
                                final updated = List<PlannedSession>.from(
                                  state.plannedWorkouts,
                                );
                                final item = updated.removeAt(oldIndex);
                                updated.insert(newIndex, item);
                                _vm.reorderWorkouts(
                                  updated,
                                  updated.map((w) => w.sessionId).toList(),
                                );
                              },
                              children: [
                                for (
                                  var i = 0;
                                  i < state.plannedWorkouts.length;
                                  i++
                                )
                                  _PlannedSessionRow(
                                    key: ValueKey(
                                      state.plannedWorkouts[i].sessionId,
                                    ),
                                    workout: state.plannedWorkouts[i],
                                    dayOfWeek: _dayFor(
                                      state.plannedWorkouts[i],
                                    ),
                                    index: i,
                                    onTap: () => _openEditWorkout(
                                      state.plannedWorkouts[i],
                                    ),
                                    onDuplicate: () =>
                                        _vm.duplicatePlannedSession(
                                          state.plannedWorkouts[i],
                                        ),
                                    onDelete: () => _confirmDeleteWorkout(
                                      state.plannedWorkouts[i],
                                    ),
                                  ),
                              ],
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
      ),
    );
  }

  Widget _buildGoalsSection(ProgramDetailState state) {
    final goals = state.programGoals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Goals',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.md,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (goals.isEmpty)
          Text(
            "No goals set — add a PR target you'd like to hit during this run.",
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.muted,
            ),
          ),
        for (final g in goals) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(child: _goalLabel(g, state)),
                GestureDetector(
                  onTap: () => _vm.deleteGoal(g.goalId),
                  child: Icon(Icons.close, size: 16, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        const SizedBox(height: AppSpacing.sm),
        _GoalPicker(
          detailMap: state.exerciseDetailMap,
          onAdd: (exerciseId, exerciseName, weight, reps) {
            _vm.addGoal(
              exerciseId: exerciseId,
              exerciseName: exerciseName,
              targetWeight: weight,
              targetReps: reps,
            );
          },
        ),
      ],
    );
  }

  Widget _goalLabel(Goal goal, ProgramDetailState state) {
    final exerciseName = toProperCase(
      state.exerciseDetailMap[goal.exerciseId]?.name ?? goal.text ?? '',
    );
    final weightStr = goal.targetWeight != null
        ? '${_fmtNum(goal.targetWeight!)} kg'
        : '';
    final repsStr = goal.targetReps != null
        ? '${goal.targetReps} rep${goal.targetReps == 1 ? '' : 's'}'
        : '';
    final targetStr = [
      weightStr,
      repsStr,
    ].where((s) => s.isNotEmpty).join(' × ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          targetStr.isNotEmpty ? '$exerciseName — $targetStr' : exerciseName,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  static String _fmtNum(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

// ── Goal Picker ─────────────────────────────────────────────────────────────

/// An inline picker for adding exercise-target goals. Expands from a compact
/// toggle into exercise search + weight/reps, then collapses again after add.
class _GoalPicker extends StatefulWidget {
  const _GoalPicker({required this.detailMap, required this.onAdd});

  final Map<String, ExerciseDetail> detailMap;
  final void Function(
    String exerciseId,
    String exerciseName,
    num? weight,
    int? reps,
  )
  onAdd;

  @override
  State<_GoalPicker> createState() => _GoalPickerState();
}

class _GoalPickerState extends State<_GoalPicker> {
  bool _expanded = false;
  String _query = '';
  String? _selectedExerciseId;
  final _weightCtrl = TextEditingController();
  final _repsCtrl = TextEditingController();

  @override
  void dispose() {
    _weightCtrl.dispose();
    _repsCtrl.dispose();
    super.dispose();
  }

  List<MapEntry<String, String>> get _filtered {
    final detailMap = widget.detailMap;
    if (detailMap.isEmpty) return [];
    final results = detailMap.entries
        .where((e) {
          final name = e.value.name;
          return _query.isEmpty ||
              toProperCase(name).toLowerCase().contains(_query.toLowerCase());
        })
        .map((e) => MapEntry(e.key, toProperCase(e.value.name)))
        .toList();
    results.sort(
      (a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()),
    );
    return results;
  }

  void _add() {
    final weight = double.tryParse(_weightCtrl.text.trim());
    final reps = int.tryParse(_repsCtrl.text.trim());
    if (_selectedExerciseId == null) return;
    final detail = widget.detailMap[_selectedExerciseId!];
    final name = detail?.name ?? '';
    widget.onAdd(_selectedExerciseId!, toProperCase(name), weight, reps);
    setState(() {
      _expanded = false;
      _query = '';
      _selectedExerciseId = null;
      _weightCtrl.clear();
      _repsCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return GestureDetector(
        onTap: () => setState(() => _expanded = true),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                'Add a PR target…',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          autofocus: true,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            color: AppColors.primary,
          ),
          decoration: InputDecoration(
            hintText: 'Search exercises…',
            hintStyle: AppFonts.ui(color: AppColors.muted),
            prefixIcon: Icon(Icons.search, size: 16, color: AppColors.muted),
            suffixIcon: GestureDetector(
              onTap: () => setState(() {
                _expanded = false;
                _selectedExerciseId = null;
              }),
              child: Icon(Icons.close, size: 16, color: AppColors.muted),
            ),
            filled: true,
            fillColor: AppColors.surfaceHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide(color: AppColors.border),
            ),
          ),
          onChanged: (v) => setState(() {
            _query = v;
            _selectedExerciseId = null;
          }),
        ),
        if (_selectedExerciseId == null) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: ListView(
              shrinkWrap: true,
              children: _filtered
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedExerciseId = e.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            e.value,
                            style: AppFonts.ui(
                              fontSize: AppTextStyles.sm,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        if (_selectedExerciseId != null) ...[
          const SizedBox(height: 8),
          Text(
            toProperCase(widget.detailMap[_selectedExerciseId!]?.name ?? ''),
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weightCtrl,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                  style: AppFonts.mono(fontSize: 14, color: AppColors.primary),
                  decoration: InputDecoration(
                    hintText: 'kg',
                    hintStyle: AppFonts.mono(color: AppColors.muted),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surfaceHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '×',
                  style: AppFonts.ui(fontSize: 14, color: AppColors.muted),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _repsCtrl,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppFonts.mono(fontSize: 14, color: AppColors.primary),
                  decoration: InputDecoration(
                    hintText: 'reps',
                    hintStyle: AppFonts.mono(color: AppColors.muted),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surfaceHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GlassButton(label: 'Add', compact: true, onPressed: _add),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

// ── Rows ─────────────────────────────────────────────────────────────────────

class _PlannedSessionRow extends StatelessWidget {
  const _PlannedSessionRow({
    super.key,
    required this.workout,
    required this.onTap,
    required this.onDuplicate,
    required this.onDelete,
    this.dayOfWeek,
    this.index,
  });

  final PlannedSession workout;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  /// The session's assigned day (from its program link row) — null = none.
  final int? dayOfWeek;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SwipeActions(
        actions: [
          SwipeAction(
            icon: Icons.copy_rounded,
            label: 'Duplicate',
            color: AppColors.accent,
            onTap: onDuplicate,
          ),
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
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      toProperCase(workout.name),
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.md,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    if (workout.notes?.isNotEmpty == true)
                      Text(
                        workout.notes!,
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.xs,
                          color: AppColors.muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'Session ${(index ?? 0) + 1}',
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.accent,
                  ),
                ),
              ),
              if (dayOfWeek != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _dayOfWeekLabel(dayOfWeek),
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.xs,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
              ReorderableDragStartListener(
                index: index ?? 0,
                child: Icon(
                  Icons.drag_handle,
                  size: 18,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return row;
  }
}
