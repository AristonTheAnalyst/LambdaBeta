import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/workout_format.dart';
import '../../../../data/models/planned_workout.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/page_header.dart';
import '../viewmodel/program_detail_viewmodel.dart';
import 'plan_workout_screen.dart';

/// 3-step guided program creation: choose progression (with helper text),
/// name + goals, then design the planned workouts. Calendar workouts must
/// have a weekday assigned; sequential ones cycle by order.
///
/// The program is created as soon as progression is chosen (step 1), then the
/// wizard edits it via a real [ProgramDetailViewModel].
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
  final _goalCtrl = TextEditingController();
  final List<String> _goals = [];

  bool get _isCalendar => _progression == 'calendar';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _goalCtrl.dispose();
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
        1 => 'Name & goals',
        _ => 'Design workouts',
      };

  String get _stepSubtitle => switch (_step) {
        0 => 'Choose how the program schedules your training.',
        1 => 'Give it a name and, optionally, a goal.',
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
      // Persist goals (free-text; structured exercise targets use the
      // "exercise 100kg x 1" form and are stored as text for now).
      for (final g in _goals) {
        await _vm.addProgramGoalText(g);
      }
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
        const SizedBox(height: AppSpacing.lg),
        Text('Goals',
            style: AppFonts.ui(
                fontSize: AppTextStyles.md,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
        const SizedBox(height: AppSpacing.xs),
        Text('Free text or exercise targets, e.g. "bench 100kg x 1"',
            style: AppFonts.ui(fontSize: AppTextStyles.xs, color: AppColors.muted)),
        const SizedBox(height: AppSpacing.sm),
        for (final g in _goals) ...[
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(g,
                      style: AppFonts.ui(
                          fontSize: AppTextStyles.sm, color: AppColors.primary)),
                ),
                GestureDetector(
                  onTap: () => setState(() => _goals.remove(g)),
                  child: Icon(Icons.close, size: 16, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: LambdaInput(
                controller: _goalCtrl,
                placeholder: 'Add a goal…',
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GlassButton(
              label: 'Add',
              compact: true,
              onPressed: () {
                final text = _goalCtrl.text.trim();
                if (text.isEmpty) return;
                setState(() {
                  _goals.add(text);
                  _goalCtrl.clear();
                });
              },
            ),
          ],
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
        GlassButton(
          label: '+ Add workout',
          icon: Icons.add,
          onPressed: _addWorkout,
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
        for (var i = 0; i < workouts.length; i++) ...[
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            onTap: () => _openWorkout(workouts[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(toProperCase(workouts[i].name),
                        style: AppFonts.ui(
                            fontSize: AppTextStyles.md,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                  ),
                  _badge(
                      _isCalendar
                          ? (workouts[i].dayOfWeek != null
                              ? _dayOfWeekLabel(workouts[i].dayOfWeek)
                              : 'No day assigned')
                          : 'Session ${i + 1}',
                      _isCalendar && workouts[i].dayOfWeek == null
                          ? AppColors.danger
                          : AppColors.accent),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(Icons.chevron_right, size: 16, color: AppColors.muted),
                ],
              ),
            ),
          ),
        ],
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
