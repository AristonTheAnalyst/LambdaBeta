import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/workout_format.dart';
import '../../../../data/models/planned_workout.dart';
import '../../../../data/repositories/workout_plan_repository.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/swipe_actions.dart';
import '../viewmodel/program_detail_viewmodel.dart';
import 'plan_workout_screen.dart';

/// 3-step guided program creation: choose progression, name the program,
/// then design the planned workouts. Calendar workouts must have a weekday
/// assigned; sequential ones cycle by order.
///
/// The program is created as soon as progression is chosen (step 1), then the
/// wizard edits it via a real [ProgramDetailViewModel]. Goals are set later
/// from the program detail screen once a run is active.
class ProgramWizardScreen extends StatefulWidget {
  const ProgramWizardScreen({super.key});

  @override
  State<ProgramWizardScreen> createState() => _ProgramWizardScreenState();
}

class _ProgramWizardScreenState extends State<ProgramWizardScreen> {
  int _step = 0;
  String? _progression;
  String? _programId;
  ProgramDetailViewModel? _detailVm;
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  bool get _isCalendar => _progression == 'calendar';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _detailVm?.dispose();
    super.dispose();
  }

  ProgramDetailViewModel get _vm {
    final vm = _detailVm;
    if (vm == null) {
      throw StateError('detail VM not ready before step 2');
    }
    return vm;
  }

  bool get _canContinue => switch (_step) {
        0 => _progression != null,
        1 => _nameCtrl.text.trim().isNotEmpty,
        _ => true,
      };

  String get _stepTitle => switch (_step) {
        0 => 'How will it progress?',
        1 => 'Name your program',
        _ => 'Design workouts',
      };

  String get _stepSubtitle => switch (_step) {
        0 => 'Choose how the program schedules your training.',
        1 => 'Give it a name and, optionally, a description.',
        _ => 'Add the workouts in the order they repeat.',
      };

  Future<void> _next() async {
    if (_step == 0) {
      // Create the program now so steps 2-3 operate on a real program.
      final vm = ProgramDetailViewModel();
      final id = await vm.createNewProgram(_progression!);
      if (id == null) return;
      await vm.load(id);
      if (!mounted) return;
      setState(() {
        _detailVm = vm;
        _programId = id;
        _nameCtrl.text = vm.state.value.nameDraft;
        _step = 1;
      });
      return;
    }
    if (_step == 1) {
      _vm.setNameDraft(_nameCtrl.text);
      _vm.setDescriptionDraft(_descriptionCtrl.text);
      await _vm.saveProgramDetails();
      if (!mounted) return;
      setState(() => _step = 2);
      return;
    }
    if (_step == 2) {
      if (!mounted || _programId == null) return;
      // Close the wizard (a plain MaterialPageRoute overlay), then navigate to
      // the program detail via the go_router.
      final router = GoRouter.of(context);
      Navigator.of(context, rootNavigator: true).pop();
      router.push('/exercises/programs/$_programId');
      return;
    }
  }

  Future<void> _addWorkout() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => PlanWorkoutScreen(viewModel: _vm)),
    );
    if (mounted) setState(() {});
  }

  /// Copies an existing standalone workout into the program as a planned
  /// workout (including its exercises and sets).
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
              InkWell(
                onTap: () => Navigator.of(ctx).pop(w.workoutId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                  child: Text(toProperCase(w.name),
                      style: AppFonts.ui(
                          fontSize: AppTextStyles.md,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await _vm.copyWorkoutIntoProgram(chosen);
    if (mounted) setState(() {});
  }

  Future<void> _openWorkout(PlannedWorkout w) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
          builder: (_) => PlanWorkoutScreen(viewModel: _vm, workout: w)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(
              title: 'New Program',
              left: GestureDetector(
                onTap: () => context.pop(),
                child: Icon(Icons.arrow_back_ios_new,
                    size: 18, color: AppColors.accent),
              ),
            ),
            _stepIndicator(),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_stepTitle,
                      style: AppFonts.ui(
                          fontSize: AppTextStyles.xl,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                  const SizedBox(height: 2),
                  Text(_stepSubtitle,
                      style: AppFonts.ui(
                          fontSize: AppTextStyles.sm, color: AppColors.muted)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
                child: switch (_step) {
                  0 => _progressionStep(),
                  1 => _nameStep(),
                  _ => _workoutsStep(),
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: GlassButton(
                        label: 'Back',
                        color: AppColors.muted,
                        onPressed: () => setState(() => _step--),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: GlassButton(
                      label: _step == 2 ? 'Finish' : 'Continue',
                      solid: true,
                      disabled: !_canContinue,
                      onPressed: _canContinue ? _next : () {},
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  color: i <= _step ? AppColors.accent : AppColors.border,
                ),
              ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i <= _step ? AppColors.accent : AppColors.border,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _progressionStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _choiceCard(
          icon: Icons.loop,
          title: 'Sessions-based',
          subtitle:
              'You log workout 1, then 2, then 3… in order, no matter the day '
              'or how much rest you take. The next workout is always the next '
              'one in line.',
          selected: _progression == 'sequential',
          onTap: () => setState(() => _progression = 'sequential'),
        ),
        const SizedBox(height: AppSpacing.md),
        _choiceCard(
          icon: Icons.calendar_month_outlined,
          title: 'Calendar-based',
          subtitle:
              'Workouts are pinned to specific weekdays (e.g. Mon / Wed / Fri). '
              'If you miss a day, you simply do the next scheduled workout on '
              'its day.',
          selected: _progression == 'calendar',
          onTap: () => setState(() => _progression = 'calendar'),
        ),
      ],
    );
  }

  Widget _choiceCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentBg : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: selected ? 1.5 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 22, color: selected ? AppColors.accent : AppColors.muted),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppFonts.ui(
                          fontSize: AppTextStyles.md,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: AppFonts.ui(
                          fontSize: AppTextStyles.sm, color: AppColors.muted)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 18, color: AppColors.accent),
          ],
        ),
      ),
    );
  }

  Widget _nameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LambdaInput(
          controller: _nameCtrl,
          label: 'Program name',
          placeholder: 'e.g. Strength Block 1',
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          required: true,
        ),
        const SizedBox(height: AppSpacing.md),
        LambdaInput(
          controller: _descriptionCtrl,
          label: 'Description',
          placeholder: 'Optional program description',
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _workoutsStep() {
    final workouts = _vm.state.value.plannedWorkouts;
    final missingDays =
        _isCalendar && workouts.any((w) => w.dayOfWeek == null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: GlassButton(
                label: 'New',
                icon: Icons.add,
                onPressed: _addWorkout,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: GlassButton(
                label: 'From Workouts',
                icon: Icons.library_add_outlined,
                onPressed: _addExistingWorkout,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (workouts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(
              child: Text('No workouts yet — add at least one.',
                  style: AppFonts.ui(
                      fontSize: AppTextStyles.sm, color: AppColors.muted)),
            ),
          ),
        if (workouts.isNotEmpty)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) {
              final updated = List<PlannedWorkout>.from(workouts);
              final item = updated.removeAt(oldIndex);
              updated.insert(newIndex, item);
              _vm.reorderWorkouts(
                  updated, updated.map((w) => w.plannedWorkoutId).toList());
            },
            children: [
              for (var i = 0; i < workouts.length; i++)
                Padding(
                  key: ValueKey(workouts[i].plannedWorkoutId),
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: SwipeActions(
                    actions: [
                      SwipeAction(
                        icon: Icons.copy_rounded,
                        label: 'Duplicate',
                        color: AppColors.accent,
                        onTap: () => _vm.duplicatePlannedWorkout(workouts[i]),
                      ),
                      SwipeAction(
                        icon: Icons.delete_outline,
                        label: 'Delete',
                        color: AppColors.danger,
                        onTap: () {
                          _vm.removePlannedWorkout(workouts[i]);
                          setState(() {});
                        },
                      ),
                    ],
                    child: AppCard(
                      onTap: () => _openWorkout(workouts[i]),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(toProperCase(workouts[i].name),
                                    style: AppFonts.ui(
                                        fontSize: AppTextStyles.md,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary)),
                                if (workouts[i].notes?.isNotEmpty == true)
                                  Text(workouts[i].notes!,
                                      style: AppFonts.ui(
                                          fontSize: AppTextStyles.xs,
                                          color: AppColors.muted),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          _badge(
                              _isCalendar
                                  ? (workouts[i].dayOfWeek != null
                                      ? _dayOfWeekLabel(workouts[i].dayOfWeek)
                                      : 'No day assigned')
                                  : 'Workout ${workouts[i].sequenceOrder}',
                              _isCalendar && workouts[i].dayOfWeek == null
                                  ? AppColors.danger
                                  : AppColors.accent),
                          const SizedBox(width: AppSpacing.sm),
                          ReorderableDragStartListener(
                            index: i,
                            child: Icon(Icons.drag_handle,
                                size: 18, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        if (missingDays) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Calendar workouts need a day of the week — open each workout '
              'and assign one.',
              style: AppFonts.ui(
                  fontSize: AppTextStyles.xs, color: AppColors.danger)),
        ],
      ],
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: AppFonts.mono(fontSize: 9, color: color)),
    );
  }

  static String _dayOfWeekLabel(int? d) => switch (d) {
        1 => 'Mon',
        2 => 'Tue',
        3 => 'Wed',
        4 => 'Thu',
        5 => 'Fri',
        6 => 'Sat',
        7 => 'Sun',
        _ => '—',
      };
}
