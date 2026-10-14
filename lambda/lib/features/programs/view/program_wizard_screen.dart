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

/// The wizard's steps, in order. A blocked program's wizard ends after Name:
/// its workouts are made inside its blocks, from the Blocks tab the wizard
/// lands on, so there is nothing for a workouts step to do.
///
/// One derived list drives everything that used to be a hand-kept agreement
/// between an `int`, a two-dot indicator and a body switch — the indicator
/// counts it, the last step's button says Finish, and a third step no longer
/// silently falls through a `_ =>` arm in three places.
enum _WizardStep { shape, name, workouts }

/// Guided program creation: choose the shape, name the program, and — for a
/// simple program — design the planned workouts. Nothing about scheduling is
/// chosen here: how long a run lasts is a run property, set when a run starts.
///
/// The shape is asked **first**, because it decides what the rest of the
/// wizard even is: a simple program goes straight to adding and ordering
/// workouts, while a blocked program is built from blocks and its workouts are
/// made inside them. The choice is one-way, so it is stated as such, and once
/// the program exists the step renders it read-only rather than offering a
/// change that real blocks may already have contradicted.
///
/// The program is created when the name step continues — carrying the name the
/// user just typed, so the next step never shows a placeholder — and the wizard
/// then edits it via a real [ProgramDetailViewModel]. Goals are set later, from
/// the program detail screen.
class ProgramWizardScreen extends StatefulWidget {
  const ProgramWizardScreen({super.key});

  @override
  State<ProgramWizardScreen> createState() => _ProgramWizardScreenState();
}

class _ProgramWizardScreenState extends State<ProgramWizardScreen> {
  int _stepIndex = 0;
  String? _programId;
  ProgramDetailViewModel? _detailVm;
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  /// The shape chosen on step one, and the shape the program is created with.
  /// Null until the user picks one — the decision is the step's whole content,
  /// so nothing is preselected for them.
  bool? _usesBlocks;

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

  /// The steps this run of the wizard has. Before a shape is picked the full
  /// list shows, so the indicator does not move under the user's finger; once
  /// a blocked program is chosen the workouts step is gone for good.
  List<_WizardStep> get _steps => [
        _WizardStep.shape,
        _WizardStep.name,
        if (_usesBlocks != true) _WizardStep.workouts,
      ];

  _WizardStep get _step => _steps[_stepIndex];

  bool get _isBlocked => _usesBlocks == true;

  /// True once the program exists. The shape has been written to the database
  /// by then, and no surface can half-switch — so the choice is shown, not
  /// offered.
  bool get _shapeLocked => _detailVm != null;

  bool get _canContinue => switch (_step) {
    _WizardStep.shape => _usesBlocks != null,
    _WizardStep.name => _nameCtrl.text.trim().isNotEmpty,
    _WizardStep.workouts => true,
  };

  String get _stepTitle => switch (_step) {
    _WizardStep.shape => 'What kind of program?',
    _WizardStep.name => 'Name your program',
    _WizardStep.workouts => 'Design workouts',
  };

  String get _stepSubtitle => switch (_step) {
    _WizardStep.shape =>
      'A list of workouts, or phases you work through. This is set when the '
          'program is made.',
    _WizardStep.name => _isBlocked
        ? 'Name it — then give it its first block.'
        : 'Give it a name and, optionally, a description.',
    _WizardStep.workouts => 'Add the workouts in the order they repeat.',
  };

  Future<void> _next() async {
    switch (_step) {
      case _WizardStep.shape:
        setState(() => _stepIndex++);
      case _WizardStep.name:
        await _continueFromName();
      case _WizardStep.workouts:
        await _finish();
    }
  }

  /// Leaves the name step: creates the program on the first pass, renames it on
  /// any pass after a Back, and moves on — or, for a blocked program, finishes,
  /// because Name is its last step.
  Future<void> _continueFromName() async {
    final name = _nameCtrl.text.trim();
    final description = _descriptionCtrl.text.trim();
    // Back-then-Continue must not create a second program. The first pass
    // already made this one, so a second pass only renames it — and a second
    // create would fail outright, since the name it would reuse is taken.
    final existing = _detailVm;
    if (existing != null) {
      existing.setNameDraft(name);
      existing.setDescriptionDraft(description);
      await existing.saveProgramDetails();
      if (!mounted) return;
      _isBlocked ? _openProgram() : setState(() => _stepIndex++);
      return;
    }
    // Create the program now, name and all, so the next step operates on a
    // real program that is already called what the user called it.
    // Progression mode is chosen at run start, not here.
    final vm = ProgramDetailViewModel();
    final id = await vm.createNewProgram(
      name: name,
      description: description,
      usesBlocks: _isBlocked,
    );
    if (!mounted) return;
    if (id == null) {
      // The VM keeps its error in state, but nothing is listening to it yet
      // — without this the Continue button would just do nothing. A name
      // that is already taken lands here.
      final message = vm.state.value.error ?? 'Could not create the program.';
      vm.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await vm.load(id);
    if (!mounted) return;
    setState(() {
      _detailVm = vm;
      _programId = id;
    });
    _isBlocked ? _openProgram() : setState(() => _stepIndex++);
  }

  /// Last step of a simple program's wizard: save the name/description, close
  /// the wizard, and open the program detail via the go_router.
  Future<void> _finish() async {
    _vm.setNameDraft(_nameCtrl.text);
    _vm.setDescriptionDraft(_descriptionCtrl.text);
    await _vm.saveProgramDetails();
    if (!mounted || _programId == null) return;
    _openProgram();
  }

  /// Closes the wizard and opens the program it made.
  ///
  /// The landing tab is shape-dependent and the route takes no tab parameter,
  /// so a blocked program opens on its Blocks tab — which is where "make at
  /// least one block first" happens.
  void _openProgram() {
    final router = GoRouter.of(context);
    Navigator.of(context, rootNavigator: true).pop();
    router.push('/exercises/programs/$_programId');
  }

  Future<void> _addWorkout() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => PlanSessionScreen(viewModel: _vm.editor),
      ),
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
        builder: (_) =>
            PlanSessionScreen(viewModel: _vm.editor, workout: w),
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
                  _WizardStep.shape => _shapeStep(),
                  _WizardStep.name => _nameStep(),
                  _WizardStep.workouts => _workoutsStep(),
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  if (_stepIndex > 0)
                    Expanded(
                      child: GlassButton(
                        label: 'Back',
                        color: AppColors.muted,
                        onPressed: () => setState(() => _stepIndex--),
                      ),
                    ),
                  if (_stepIndex > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: GlassButton(
                      label: _stepIndex == _steps.length - 1
                          ? 'Finish'
                          : 'Continue',
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
          for (var i = 0; i < _steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  color: i <= _stepIndex ? AppColors.accent : AppColors.border,
                ),
              ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i <= _stepIndex ? AppColors.accent : AppColors.border,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The shape choice: two cards, nothing preselected, and the one-way rule
  /// said out loud. Once the program exists it is a summary, not a control.
  Widget _shapeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _shapeOption(
          title: 'Simple',
          blurb: 'A list of workouts, worked through in order.',
          selected: _usesBlocks == false,
          onTap:
              _shapeLocked ? null : () => setState(() => _usesBlocks = false),
        ),
        const SizedBox(height: AppSpacing.md),
        _shapeOption(
          title: 'Blocks',
          blurb: 'Phases worked through one at a time — each with its own '
              'workouts and goals.',
          selected: _usesBlocks == true,
          onTap: _shapeLocked ? null : () => setState(() => _usesBlocks = true),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          _shapeLocked
              ? 'This program is made, and its shape is set for good.'
              : 'The shape is decided once, when the program is made — it '
                  'cannot be changed after.',
          style: AppFonts.ui(
            fontSize: AppTextStyles.xs,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }

  Widget _shapeOption({
    required String title,
    required String blurb,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return LambdaContainer(
      tone: selected ? ContainerTone.accent : ContainerTone.surface,
      padding: const EdgeInsets.all(AppSpacing.lg),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 20,
            color: selected ? AppColors.accentText : AppColors.muted,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.md,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  blurb,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
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
                    
                    color: AppColors.accent,
                    onTap: () => _vm.duplicatePlannedSession(workouts[i]),
                  ),
                  SwipeAction(
                    icon: Icons.delete_outline,
                    
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
