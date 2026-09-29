import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/styles/app_colors.dart';
import '../../../../core/styles/app_radius.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../../core/styles/app_fonts.dart';
import '../../../../core/styles/app_spacing.dart';
import '../../../../core/styles/app_text_styles.dart';
import '../../../../core/utils/block_length.dart';
import '../../../../core/utils/session_format.dart';
import '../../../../data/models/planned_session.dart';
import '../../../../data/models/program_block.dart';
import '../../../../data/models/program_history.dart';
import '../../../../data/models/program_run.dart';
import '../../../../data/repositories/planned_session_repository.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/exercise_target_picker.dart';
import '../../../../shared/widgets/glass_button.dart';
import '../../../../shared/widgets/lambda_input.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/mixins/unsaved_changes_guard.dart';
import '../../../../shared/widgets/segmented_control.dart';
import '../../../../shared/widgets/swipe_actions.dart';
import '../viewmodel/program_detail_viewmodel.dart';
import 'goal_row.dart';
import 'plan_session_screen.dart';
import 'program_block_editor_screen.dart';
import 'program_workout_row.dart';
import 'run_config_sheet.dart';

/// The two scopes the goal picker can write, as segment values.
const _kScopeBlock = 'block';
const _kScopeProgram = 'program';

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

  /// Where a newly added goal is scoped, when a block is running. Block by
  /// default: a target set mid-block is usually about the block you are in, and
  /// the program level is one tap away. Meaningless with no block running,
  /// which is exactly when the control is hidden.
  String _goalScope = _kScopeBlock;

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

  /// Opens the run config and, on confirm, makes the program current.
  ///
  /// [blockId] preselects a block — the block-start prompt comes through here,
  /// because "begin Accumulation" and "begin this program" are the same act
  /// with a different default.
  Future<void> _confirmBeginProgram({String? blockId}) async {
    final state = _vm.state.value;
    final result = await showRunConfigSheet(
      context,
      programName: state.program?.name ?? 'this program',
      blocks: state.blocks,
      initialBlockId: blockId,
      // Only when there is something to replace. The block-start prompt
      // arrives with nothing running by definition, and warning a user about
      // a program they do not have is how a warning stops being read.
      warning: state.anotherProgramIsCurrent
          ? 'This ends your current run on another program. '
              'Sessions you logged stay intact.'
          : null,
    );
    if (result == null || !mounted) return;
    await _vm.setAsCurrent(
      progressionMode: result.progressionMode,
      targetSessions: result.targetSessions,
      targetWeeks: result.targetWeeks,
      endDate: result.endDate,
      blockId: result.blockId,
    );
  }

  /// The run's length, as a line of text.
  ///
  /// [block] is consulted first because a block run has no length of its own —
  /// the block owns it. Without that, a phase with a perfectly good eight weeks
  /// on it would read "duration not set", which is the exact confusion the
  /// block owning its length exists to remove. Falling through both nulls with
  /// no block is different, and says so: there was never a length to set.
  String _runConfigLabel(ProgramRun run, ProgramBlock? block) {
    // A block's length is one phrase and it is spelled in one place — with a
    // remainder in play, "8 weeks" and "8 weeks 3 days" are different plans, so
    // the number cannot be re-derived screen by screen.
    final phrase = blockLengthPhrase(
      targetWeeks: block?.targetWeeks ?? run.targetWeeks,
      targetDays: block?.targetDays,
      targetSessions: block?.targetSessions ?? run.targetSessions,
    );
    if (phrase != null) return phrase;
    final end = run.endDate;
    if (end != null) return 'ends ${DateFormat('d MMM yyyy').format(end)}';
    return block == null ? 'duration not set' : 'open-ended';
  }

  /// The day assigned to a planned session via its program link row.
  int? _dayFor(PlannedSession w) {
    for (final l in _vm.state.value.programLinks) {
      if (l.plannedSessionId == w.sessionId) return l.dayOfWeek;
    }
    return null;
  }

  /// What a due item's banner does when it is tapped.
  ///
  /// The three kinds are three different verbs, which is why the banner carries
  /// the action rather than a fixed destination. A review opens the history,
  /// where the review, its achievements panel and its proposal all live. The
  /// two run prompts act here instead: both are yes/no questions about the
  /// program the user is already looking at, and making them walk to another
  /// screen to answer is how a question gets postponed forever — which is
  /// precisely what the old silent auto-end was papering over.
  Future<void> _actOnDue(DueItem due) async {
    switch (due.kind) {
      case kDueReview:
        context.push('/exercises/programs/${widget.programId}/history');
      case kDueRunFinished:
        await _confirmEndRun(context);
      case kDueBlockStart:
        await _confirmBeginProgram(blockId: due.blockId);
      case _:
        // An unrecognised kind reaches here only if a newer client's item
        // synced down to an older one. Showing the history is the safe wrong
        // answer: it is a read, on the program the user is already looking at.
        context.push('/exercises/programs/${widget.programId}/history');
    }
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
  ///
  /// The clear flags are derived from what came back rather than tracked here:
  /// switching mode or duration unit has to null the field that no longer
  /// applies, and the sheet's answer already says which one is in force.
  Future<void> _editRunConfig(ProgramRun run) async {
    final result = await showRunConfigSheet(
      context,
      programName: _vm.state.value.program?.name ?? 'this program',
      run: run,
    );
    if (result == null || !mounted) return;
    final isFrequency = result.progressionMode == 'frequency';
    await _vm.updateRunConfig(
      progressionMode: result.progressionMode,
      targetSessions: result.targetSessions,
      // Clear whichever duration unit is not the one now in force: sessions
      // belong to order, weeks and an end date to frequency.
      clearSessions: isFrequency,
      targetWeeks: result.targetWeeks,
      clearWeeks: !isFrequency || result.endDate != null,
      endDate: result.endDate,
      clearEndDate: !isFrequency || result.endDate == null,
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
          MaterialPageRoute(
            builder: (_) => PlanSessionScreen(viewModel: _vm.editor),
          ),
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
            builder: (_) =>
                PlanSessionScreen(viewModel: _vm.editor, workout: w),
          ),
        )
        .then((_) {
          if (mounted) _refreshAfterEdit();
        });
  }

  // ── Blocks ───────────────────────────────────────────────────────────────

  /// The workout list, split into its blocks.
  ///
  /// A program with no blocks renders as the flat list it has always been —
  /// one group, no headers, no extra chrome.
  List<Widget> _buildWorkoutSections(ProgramDetailState state) {
    if (state.blocks.isEmpty) {
      if (state.plannedWorkouts.isEmpty) return const [_NoWorkouts()];
      return [
        _workoutList(state, state.plannedWorkouts, null),
        const SizedBox(height: AppSpacing.md),
        GlassButton(
          label: 'Add block',
          icon: Icons.view_agenda_outlined,
          compact: true,
          onPressed: _openCreateBlock,
        ),
      ];
    }

    return [
      for (final group in _vm.blockGroups) ...[
        if (group.block != null)
          _BlockHeader(
            block: group.block!,
            workoutCount: group.workouts.length,
            onTap: () => _openBlockEditor(group.block!),
            onAddWorkouts: () => _addWorkoutsToBlock(group.block!),
          )
        else
          _UnassignedHeader(count: group.workouts.length),
        const SizedBox(height: AppSpacing.xs),
        if (group.workouts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.sm,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              group.block == null
                  ? 'Every workout is in a block.'
                  : 'No workouts in this block yet.',
              style: AppFonts.ui(
                color: AppColors.muted,
                fontSize: AppTextStyles.sm,
              ),
            ),
          )
        else
          _workoutList(state, group.workouts, group.block?.blockId),
        const SizedBox(height: AppSpacing.md),
      ],
      GlassButton(
        label: 'Add block',
        icon: Icons.add,
        compact: true,
        onPressed: _openCreateBlock,
      ),
    ];
  }

  /// One reorderable list. [blockId] null = the flat, whole-program list.
  ///
  /// The badge is the workout's position in the PROGRAM, not in its group —
  /// "Session 3" keeps meaning the third workout of the program no matter how
  /// the blocks are arranged.
  Widget _workoutList(
    ProgramDetailState state,
    List<PlannedSession> workouts,
    String? blockId,
  ) {
    final position = {
      for (var i = 0; i < state.plannedWorkouts.length; i++)
        state.plannedWorkouts[i].sessionId: i,
    };
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) {
        final updated = List<PlannedSession>.from(workouts);
        final item = updated.removeAt(oldIndex);
        updated.insert(newIndex, item);
        final ids = updated.map((w) => w.sessionId).toList();
        if (blockId == null && state.blocks.isEmpty) {
          _vm.reorderWorkouts(updated, ids);
        } else {
          _vm.reorderBlockWorkouts(blockId, ids);
        }
      },
      children: [
        for (var i = 0; i < workouts.length; i++)
          ProgramWorkoutRow(
            key: ValueKey(workouts[i].sessionId),
            workout: workouts[i],
            dayOfWeek: _dayFor(workouts[i]),
            badge: 'Session ${(position[workouts[i].sessionId] ?? i) + 1}',
            dragIndex: i,
            onTap: () => _openEditWorkout(workouts[i]),
            swipeActions: [
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
                onTap: () => _confirmDeleteWorkout(workouts[i]),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _openCreateBlock() async {
    await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProgramBlockEditorScreen(viewModel: _vm),
      ),
    );
    if (mounted) _refreshAfterEdit();
  }

  Future<void> _openBlockEditor(ProgramBlock block) async {
    await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProgramBlockEditorScreen(viewModel: _vm, block: block),
      ),
    );
    if (mounted) _refreshAfterEdit();
  }

  /// Offers the program's unassigned workouts, and assigns the chosen one to
  /// [block]. Adding an existing workout is a MOVE — it is the same workout,
  /// being filed. Wanting a second copy is what Duplicate is for.
  Future<void> _addWorkoutsToBlock(ProgramBlock block) async {
    final unassigned = _vm.blockGroups
        .where((g) => g.isUnassigned)
        .expand((g) => g.workouts)
        .toList();
    if (unassigned.isEmpty) {
      _showSnack('No unassigned workouts. Create one, or remove one from a block.');
      return;
    }
    final picked = await showModalBottomSheet<PlannedSession>(
      context: context,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Add to ${block.name}',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.lg,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            for (final w in unassigned)
              ListTile(
                title: Text(
                  toProperCase(w.name),
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.md,
                    color: AppColors.primary,
                  ),
                ),
                onTap: () => Navigator.of(ctx).pop(w),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _vm.assignWorkoutToBlock(picked.sessionId, block.blockId);
    if (mounted) _refreshAfterEdit();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppFonts.ui(fontSize: AppTextStyles.sm),
        ),
      ),
    );
  }

  /// Refreshes after returning from the workout editor by deferring a full
  /// ViewModel reload past the current frame so the pop transition settles.
  void _refreshAfterEdit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _vm.load(widget.programId);
    });
  }  @override
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
                  right: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icon-only: the header centres its title in a box that
                      // stops 88px from each edge, so a second worded button
                      // would crowd it. The tooltip carries the label instead.
                      Tooltip(
                        message: 'Version history',
                        child: GestureDetector(
                          onTap: () => context.push(
                            '/exercises/programs/${widget.programId}/history',
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(11),
                            decoration: glassBox(AppColors.accent),
                            child: Icon(
                              Icons.history,
                              size: 18,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      GlassButton(
                        label: 'Save',
                        compact: true,
                        loading: state.isSaving,
                        disabled: state.isSaving,
                        onPressed: _vm.saveProgramDetails,
                      ),
                    ],
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
                if (state.due != null)
                  _DueBanner(
                    due: state.due!,
                    onAct: () => _actOnDue(state.due!),
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
                            // Which block is running, when one is — the
                            // duration line below it reads the same either way,
                            // because a block run's numbers are block-relative.
                            if (state.currentProgress?.blockLabel != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.xs,
                                ),
                                child: Text(
                                  state.currentProgress!.blockLabel!,
                                  style: AppFonts.ui(
                                    fontSize: AppTextStyles.sm,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            Text(
                              _runConfigLabel(
                                state.activeRun!,
                                state.currentProgress?.block,
                              ),
                              style: AppFonts.mono(
                                fontSize: 14,
                                color: AppColors.muted,
                              ),
                            ),
                            if (state.currentProgress != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                state.currentProgress!.remainingLabel,
                                style: AppFonts.mono(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accent,
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.xs),
                            GlassButton(
                              // A block run has no duration of its own to
                              // edit here — only how it progresses.
                              label: state.currentProgress?.isBlockRun == true
                                  ? 'Progression'
                                  : 'Edit duration',
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
                          const SizedBox(height: AppSpacing.lg),
                          _buildGoalsSection(state),
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
                          ..._buildWorkoutSections(state),
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

  /// The program's goals, at both levels, with whatever the running window
  /// says about the ones in force.
  ///
  /// Rendered whether or not a run is active: a goal is part of what the
  /// program is, and setting targets is the natural thing to do before starting
  /// it. The scope picker below the list only appears when there is a block to
  /// scope to — offering "This block" with no block running would be a choice
  /// the user cannot make.
  Widget _buildGoalsSection(ProgramDetailState state) {
    final goals = state.programGoals;
    final run = state.activeRun;
    final blockId = run?.blockId;

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
            run == null
                ? "No goals set — add a PR target you'd like to hit."
                : "No goals set — add a PR target you'd like to hit during "
                    'this run.',
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.muted,
            ),
          ),
        for (final g in goals) ...[
          GoalRow(
            label: goalLabelFor(g, state.exerciseDetailMap),
            // The scope chip, so a block goal reads as that block's even when
            // it is listed alongside the program's own.
            scopeLabel: _blockName(state, g.blockId),
            // Absent for a goal not in force right now — which is the point of
            // the keyed map: no entry, no verdict, rather than a false "missed".
            outcome: state.goalOutcomes[g.goalId],
            onDelete: () => _vm.deleteGoal(g.goalId),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (blockId != null) ...[
          SegmentedControl<String>(
            options: const [
              SegmentOption(label: 'This block', value: _kScopeBlock),
              SegmentOption(label: 'Whole program', value: _kScopeProgram),
            ],
            value: _goalScope,
            onChange: (v) => setState(() => _goalScope = v),
            subtle: true,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        ExerciseTargetPicker(
          detailMap: state.exerciseDetailMap,
          variations: state.allVariations,
          onAdd: (target) {
            final scopeBlock =
                blockId != null && _goalScope == _kScopeBlock ? blockId : null;
            _vm.addGoal(
              exerciseId: target.exerciseId,
              exerciseName: target.exerciseName,
              variationId: target.variationId,
              targetWeight: target.weight,
              targetReps: target.reps,
              blockId: scopeBlock,
            );
          },
        ),
      ],
    );
  }

  /// The name of the block a goal is scoped to, or null when it is the
  /// program's own (or the block has since been archived — the chip then falls
  /// back to naming nothing rather than showing an id).
  String? _blockName(ProgramDetailState state, String? blockId) {
    if (blockId == null) return null;
    for (final b in state.blocks) {
      if (b.blockId == blockId) return b.name;
    }
    return null;
  }
}

// ── Rows ─────────────────────────────────────────────────────────────────────

/// Something this program is waiting on, at the top of the screen it is about.
///
/// Modelled on the error bar below it — the same full-bleed strip, in the
/// accent rather than the danger tone, because a due item is an invitation and
/// an error is a problem. Both the wording ([DueItem.prompt]) and the trailing
/// verb come off the item, because the three kinds do three different things
/// and a strip that always said "review" would be lying about two of them.
class _DueBanner extends StatelessWidget {
  const _DueBanner({required this.due, required this.onAct});

  final DueItem due;
  final VoidCallback onAct;

  /// What tapping does, in one word. Reads as the strip's own button — the
  /// whole thing is tappable, this is just the part that says so.
  String get _verb => switch (due.kind) {
        kDueReview => 'Review',
        kDueRunFinished => 'End',
        kDueBlockStart => 'Begin',
        _ => 'Open',
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAct,
      child: Container(
        width: double.infinity,
        color: AppColors.accentBg,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              due.isBlockStart ? Icons.play_circle_outline : Icons.flag_outlined,
              size: 16,
              color: AppColors.accent,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                due.prompt,
                style: AppFonts.ui(
                  color: AppColors.accent,
                  fontSize: AppTextStyles.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              _verb,
              style: AppFonts.ui(
                color: AppColors.accentText,
                fontSize: AppTextStyles.sm,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}

/// The header of one block in the program's ordered workout view: its name,
/// what it holds, and its targets — tappable into the editor.
class _BlockHeader extends StatelessWidget {
  const _BlockHeader({
    required this.block,
    required this.workoutCount,
    required this.onTap,
    required this.onAddWorkouts,
  });

  final ProgramBlock block;
  final int workoutCount;
  final VoidCallback onTap;
  final VoidCallback onAddWorkouts;

  String get _meta {
    // The length comes from the shared phrase rather than being re-spelled
    // here — this card was the third place that used to write "N weeks" for
    // itself, and a third spelling is a third thing to keep in step.
    final length = blockLengthPhrase(
      targetWeeks: block.targetWeeks,
      targetDays: block.targetDays,
      targetSessions: block.targetSessions,
    );
    final parts = <String>[
      workoutCount == 1 ? '1 workout' : '$workoutCount workouts',
      ?length,
    ];
    if (block.startDate != null || block.endDate != null) {
      final from = block.startDate == null
          ? null
          : DateFormat('d MMM').format(block.startDate!);
      final to = block.endDate == null
          ? null
          : DateFormat('d MMM').format(block.endDate!);
      parts.add(
        from == null
            ? 'to $to'
            : to == null
            ? 'from $from'
            : '$from – $to',
      );
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.view_agenda_outlined, size: 18, color: AppColors.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    toProperCase(block.name),
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.md,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    _meta,
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.xs,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.add, size: 18, color: AppColors.accent),
              onPressed: onAddWorkouts,
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// The label above the workouts that belong to no block. Only appears once a
/// program has blocks — a blockless program's list needs no explainer.
class _UnassignedHeader extends StatelessWidget {
  const _UnassignedHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        top: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            'Unassigned',
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$count',
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoWorkouts extends StatelessWidget {
  const _NoWorkouts();

  @override
  Widget build(BuildContext context) => Text(
    'No planned workouts yet.',
    style: AppFonts.ui(color: AppColors.muted, fontSize: AppTextStyles.sm),
  );
}
