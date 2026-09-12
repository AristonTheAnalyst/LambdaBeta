import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/session_format.dart';
import '../../../../data/models/planned_session.dart';
import '../../../../data/repositories/planned_session_repository.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/container_styles.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/swipe_actions.dart';
import '../viewmodel/program_detail_viewmodel.dart';
import 'plan_session_screen.dart';

/// 2-step guided program creation: name the program, then design the planned
/// workouts. Progression mode is NOT chosen here — it's a run property,
/// picked when the program is started (frequency vs order). Day assignment
/// happens in the workout editor (day-of-week lives on the program link).
///
/// The program is created when the name step continues, then the wizard edits
/// it via a real [ProgramDetailViewModel]. Goals are set later from the
/// program detail screen once a run is active.
class ProgramWizardScreen extends StatefulWidget {
  const ProgramWizardScreen({super.key});

  @override
  State<ProgramWizardScreen> createState() => _ProgramWizardScreenState();
}

class _ProgramWizardScreenState extends State<ProgramWizardScreen> {
  int _step = 0;
  String? _programId;
  ProgramDetailViewModel? _detailVm;
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

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
    0 => _nameCtrl.text.trim().isNotEmpty,
    _ => true,
  };

  String get _stepTitle => switch (_step) {
    0 => 'Name your program',
    _ => 'Design workouts',
  };

  String get _stepSubtitle => switch (_step) {
    0 => 'Give it a name and, optionally, a description.',
    _ => 'Add the workouts in the order they repeat.',
  };

  Future<void> _next() async {
    if (_step == 0) {
      // Create the program now so the workouts step operates on a real
      // program. Progression mode is chosen at run start, not here.
      final vm = ProgramDetailViewModel();
      final id = await vm.createNewProgram();
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
    // Workouts step: save the name/description, close the wizard, and open
    // the program detail via the go_router.
    _vm.setNameDraft(_nameCtrl.text);
    _vm.setDescriptionDraft(_descriptionCtrl.text);
    await _vm.saveProgramDetails();
    if (!mounted || _programId == null) return;
    final router = GoRouter.of(context);
    Navigator.of(context, rootNavigator: true).pop();
    router.push('/exercises/programs/$_programId');
  }

  Future<void> _addWorkout() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => PlanSessionScreen(viewModel: _vm)),
    );
    await _reloadWorkouts();
  }

  /// Reloads the workouts list after the editor pops — the editor's async
  /// list refetch may still be in flight, and the wizard has no listener to
  /// pick it up.
  Future<void> _reloadWorkouts() async {
    if (_programId != null) {
      await _vm.load(_programId!);
    }
    if (mounted) setState(() {});
  }

  /// Copies an existing standalone workout into the program as a planned
  /// workout (including its exercises and sets).
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
              InkWell(
                onTap: () => Navigator.of(ctx).pop(w.sessionId),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  // Pressable rows — the glass recipe.
                  decoration: glassBox(AppColors.primary),
                  child: Text(
                    toProperCase(w.name),
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.md,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
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

  Future<void> _openWorkout(PlannedSession w) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => PlanSessionScreen(viewModel: _vm, workout: w),
      ),
    );
    await _reloadWorkouts();
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
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 18,
                  color: AppColors.accent,
                ),
              ),
            ),
            _stepIndicator(),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _stepTitle,
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.xl,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _stepSubtitle,
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.sm,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: switch (_step) {
                  0 => _nameStep(),
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
                      label: _step == 1 ? 'Finish' : 'Continue',
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
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          for (var i = 0; i < 2; i++) ...[
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
              child: Text(
                'No workouts yet — add at least one.',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  color: AppColors.muted,
                ),
              ),
            ),
          ),
        if (workouts.isNotEmpty)
          // .builder instead of the children-based list: the children form
          // hits Flutter's duplicate _ReorderableListViewChildGlobalKey bug
          // when the list rebuilds mid-frame.
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) {
              final updated = List<PlannedSession>.from(workouts);
              final item = updated.removeAt(oldIndex);
              updated.insert(newIndex, item);
              _vm.reorderWorkouts(
                updated,
                updated.map((w) => w.sessionId).toList(),
              );
            },
            itemCount: workouts.length,
            itemBuilder: (context, i) => Padding(
              key: ValueKey(workouts[i].sessionId),
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: SwipeActions(
                actions: [
                  SwipeAction(
                    icon: Icons.copy_rounded,
                    label: 'Duplicate',
                    color: AppColors.accent,
                    onTap: () => _vm.duplicatePlannedSession(workouts[i]),
                  ),
                  SwipeAction(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    color: AppColors.danger,
                    onTap: () {
                      _vm.removePlannedSession(workouts[i]);
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
                            Text(
                              toProperCase(workouts[i].name),
                              style: AppFonts.ui(
                                fontSize: AppTextStyles.md,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                            if (workouts[i].notes?.isNotEmpty == true)
                              Text(
                                workouts[i].notes!,
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
                      _badge(
                        'Session ${i + 1}',
                        AppColors.accent,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      ReorderableDragStartListener(
                        index: i,
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
            ),
          ),
      ],
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: AppFonts.mono(fontSize: 13, color: color)),
    );
  }
}
