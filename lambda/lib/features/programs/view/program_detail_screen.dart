import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/block_length.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/models/program_block.dart';
import '../../../data/models/program_history.dart';
import '../../../data/models/program_progress.dart';
import '../../../data/models/program_run.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/option_picker_sheet.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/mixins/unsaved_changes_guard.dart';
import '../../../shared/widgets/slide_tab_bar.dart';
import '../../../shared/widgets/slide_tab_view.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../../shared/widgets/swipe_actions.dart';
import '../viewmodel/program_detail_viewmodel.dart';
import 'goal_row.dart';
import 'run_confirm_dialog.dart';
import 'plan_session_screen.dart';
import 'program_block_editor_screen.dart';
import 'program_history_panel.dart';
import 'program_workout_row.dart';
import 'review_container.dart';
import 'run_config_sheet.dart';

/// The whole-program scope in the goal picker's value space.
///
/// A sentinel rather than `null` because the option sheet returns `null` for
/// "dismissed", and the program's own level has to be sayable — a goal scoped
/// to nothing is a real answer, and one the user picks on purpose.
const _kScopeProgram = 'program';

/// One face of a program.
///
/// Which faces a program has is its shape, decided when it was created: a
/// simple program is a list of workouts, a blocked program is a sequence of
/// phases you work through, and both are reviewed. Goals sit beside whichever
/// of the two the program is made of, because a goal is about the running of
/// it either way.
enum _ProgramTab { workouts, blocks, goals, reviews }

/// The tabs a program shows, in order — the one list the bar, the page
/// controller and the bodies all come from, so they cannot drift apart.
///
/// [blocked] comes from `dim_program.uses_blocks`, never from an empty block
/// list: a blocked program that has no blocks yet is a real state, and it
/// lands on Blocks so that the first thing it asks for is a block.
List<_ProgramTab> _tabsFor({required bool blocked}) => [
      blocked ? _ProgramTab.blocks : _ProgramTab.workouts,
      _ProgramTab.goals,
      _ProgramTab.reviews,
    ];

String _tabLabel(_ProgramTab tab) => switch (tab) {
      _ProgramTab.workouts => 'Workouts',
      _ProgramTab.blocks => 'Blocks',
      _ProgramTab.goals => 'Goals',
      _ProgramTab.reviews => 'Reviews',
    };

class ProgramDetailScreen extends StatefulWidget {
  const ProgramDetailScreen({super.key, required this.programId, this.viewModel});

  final String programId;

  /// The view model to render, when a caller already has one.
  ///
  /// Null = the screen loads its own. The seam exists for host tests: the
  /// repositories this screen reads through reach PowerSync, which a widget
  /// test has no way to stand up, so the only place to inject a fake is above
  /// them. A real caller never passes one — this screen owns its program.
  final ProgramDetailViewModel? viewModel;

  @override
  State<ProgramDetailScreen> createState() => _ProgramDetailScreenState();
}

class _ProgramDetailScreenState extends State<ProgramDetailScreen>
    with UnsavedChangesGuard<ProgramDetailScreen> {
  late final ProgramDetailViewModel _vm;

  /// Whether [_vm] is this screen's to dispose. An injected view model belongs
  /// to whoever passed it — and a host test that supplies one goes on asserting
  /// against it after the widget is gone, so disposing it here would end the
  /// state under the assertions rather than tidy anything up.
  var _ownsVm = true;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  /// The header IS the name field — losing focus is what commits a rename.
  final _nameFocus = FocusNode();

  /// The rename currently in flight, if any. The blur and the back button
  /// both commit, and one rename must not become two writes.
  Future<void>? _nameSave;

  /// Where a newly added goal is scoped: a block id, or null for the program
  /// itself.
  ///
  /// One value rather than a mode plus a block, because the two are a single
  /// decision — "scoped to a block" with no block named is a state that should
  /// not be expressible. Only a blocked program offers the choice at all: a
  /// simple program has no blocks for a goal to belong to, so everything it
  /// holds is the program's own.
  String? _goalScope;

  /// The tab on screen.
  int _tab = 0;
  final _tabController = SlideTabController();

  /// Bumped when an edit lands, so the Reviews tab's panel — a separate reader
  /// with its own view model — reloads instead of showing a history that the
  /// edit just made stale.
  int _historyEpoch = 0;

  /// The block a review was asked for, if any. A due *block* review opens the
  /// panel already scoped to its own block, because that is the question the
  /// banner was asking; the panel is keyed by this, so a later unfiltered
  /// visit is a fresh panel rather than one still holding a stale filter.
  String? _reviewScope;

  bool get _usesBlocks => _vm.state.value.program?.usesBlocks ?? false;

  void _onTabChanged(int i) {
    setState(() => _tab = i);
    _tabController.jumpTo(i);
  }

  /// Shows the reviews — where a due review, its achievements and its proposal
  /// all live.
  void _showReviews({String? blockId}) {
    setState(() => _reviewScope = blockId);
    // Derived from the same list the tabs are built from — the Reviews tab is
    // wherever that list puts it.
    _onTabChanged(
      _tabsFor(blocked: _usesBlocks).indexOf(_ProgramTab.reviews),
    );
  }

  // ── UnsavedChangesGuard overrides ─────────────────────────────────────────

  @override
  bool get hasUnsavedChanges =>
      _vm.state.value.hasUnsavedProgramFields ||
      // Typing reaches the draft on every keystroke, so the two disagree only
      // when something else moved the draft under the field — a reload, say.
      // What the header shows is what the user means to keep.
      (_nameController.text.trim().isNotEmpty &&
          _nameController.text.trim() != _vm.state.value.nameDraft.trim());

  @override
  Future<void> onSave() async => await _saveAll();

  /// The save both the header button and the guard's dialog go through.
  ///
  /// The header holds the name, so its text is written to the draft first: a
  /// save that never saw the field blur must still save what is on screen.
  Future<void> _saveAll() async {
    final typed = _nameController.text.trim();
    if (typed.isNotEmpty) _vm.setNameDraft(typed);
    await _vm.saveProgramDetails();
  }

  @override
  void onDiscard() {
    final s = _vm.state.value;
    _nameController.text = s.program?.name ?? '';
    _descriptionController.text = s.program?.description ?? '';
    _vm.setNameDraft(s.program?.name ?? '');
    _vm.setDescriptionDraft(s.program?.description ?? '');
  }

  /// A nav-bar tab tap: run the unsaved-changes guard, then jump to the tab.
  ///
  /// This screen is reached two ways and they unwind differently. Day to day
  /// it is a pushed route, which `go` replaces on its way to the tab. During a
  /// review it is rendered by the review route — a route `go` knows nothing
  /// about — so that one has to be popped first, or the review would stay up
  /// over the tab the user just asked for.
  Future<void> _onNavTap(String route) async {
    final router = GoRouter.of(context);
    if (!await confirmBack()) return;
    if (!mounted) return;
    if (ModalRoute.of(context)?.settings.name == kReviewRouteName) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    router.go(route);
  }

  /// Keeps the header's text equal to the draft whenever something other than
  /// typing changed it — a reload, a discard, the name a save settled on.
  /// While the field holds focus the user's own text wins.
  void _syncNameField() {
    if (_nameFocus.hasFocus) return;
    final draft = _vm.state.value.nameDraft;
    if (draft.isNotEmpty && _nameController.text != draft) {
      _nameController.text = draft;
    }
  }

  /// Saves the header's name, the way the workout editor saves its own: the
  /// field commits when it loses focus.
  ///
  /// An emptied field falls back to the saved name rather than leaving the
  /// program nameless — a program always has one, which is what the required
  /// marker on the old form field meant, and a blank header would be a name
  /// with no way back.
  Future<void> _commitName() {
    final inFlight = _nameSave;
    if (inFlight != null) return inFlight;

    final stored = _vm.state.value.program?.name ?? '';
    final typed = _nameController.text.trim();
    if (typed.isEmpty) {
      _nameController.text = stored;
      _vm.setNameDraft(stored);
      return Future.value();
    }
    if (typed == stored) return Future.value();

    _vm.setNameDraft(typed);
    final save = _vm.saveProgramDetails();
    _nameSave = save;
    return save.whenComplete(() => _nameSave = null);
  }

  /// Opens the run config and, on confirm, makes the program current.
  ///
  /// The block is not a parameter and not a question: a begin follows the
  /// program's next unended block, which is what [ProgramDetailState
  /// .blockSequence] answers — the same answer the block rows and the due
  /// prompts render from, so the sheet cannot name one block while the write
  /// starts another.
  Future<void> _confirmBeginProgram() async {
    final state = _vm.state.value;
    // Asked BEFORE the config and every time, not only when there is something
    // to replace: beginning changes which program you are running, and that is
    // the decision — "how long" is a detail of an act already chosen. Asking
    // only when another run was current meant the block-start prompt (which
    // arrives with nothing running by definition) skipped the question
    // entirely, so the one path a user could not predict from the screen was
    // the one with no gate on it.
    final otherRunPaused = await _vm.anotherProgramIsPaused();
    if (!mounted) return;
    final ok = await confirmStartRun(
      context,
      entry: RunEntry.begin,
      programName: state.program?.name ?? 'this program',
      displacesCurrentRun: state.anotherProgramIsCurrent,
      displacedName: state.currentProgramName,
      otherRunPaused: otherRunPaused,
    );
    if (!ok || !mounted) return;
    final result = await showRunConfigSheet(
      context,
      programName: state.program?.name ?? 'this program',
      block: state.blockSequence.nextBlock,
      usesBlocks: state.program?.usesBlocks ?? false,
      defaultTargetSessions: state.program?.defaultTargetSessions,
    );
    if (result == null || !mounted) return;
    await _vm.setAsCurrent(
      targetSessions: result.targetSessions,
      blockId: result.blockId,
    );
  }

  /// Resumes this program's paused run, asking first.
  ///
  /// Resume has no sheet of its own, so the question stands alone — and it is
  /// the same gate Begin passes through, because it is the same act: a switch
  /// that pauses what it leaves, so the sentence about the run being displaced
  /// is shared word for word (only the opening line differs — picking a run
  /// back up is not starting one). Asked every time for the same reason it is
  /// asked before the config: it decides which program you are on, and one gate
  /// that is always there is one the user can trust rather than guess at.
  Future<void> _confirmResume() async {
    final state = _vm.state.value;
    final otherRunPaused = await _vm.anotherProgramIsPaused();
    if (!mounted) return;
    final ok = await confirmStartRun(
      context,
      entry: RunEntry.resume,
      programName: state.program?.name ?? 'this program',
      displacesCurrentRun: state.anotherProgramIsCurrent,
      displacedName: state.currentProgramName,
      otherRunPaused: otherRunPaused,
    );
    if (!ok || !mounted) return;
    await _vm.resumeRun();
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

  /// What a due item's banner does when it is tapped.
  ///
  /// The three kinds are three different verbs, which is why the banner carries
  /// the action rather than a fixed destination. A review switches to the
  /// Reviews tab, where the review, its achievements panel and its proposal all
  /// live. The two run prompts act here instead: both are yes/no questions
  /// about the program the user is already looking at, and making them walk to
  /// another screen to answer is how a question gets postponed forever — which
  /// is precisely what the old silent auto-end was papering over.
  Future<void> _actOnDue(DueItem due) async {
    switch (due.kind) {
      case kDueReview:
        // A block's review opens scoped to that block: the panel is the whole
        // program's timeline, and arriving at it unfiltered for a question
        // about one phase is how the reason it was opened gets lost.
        _showReviews(blockId: due.review?.blockId);
      case kDueRunFinished:
        await _confirmEndRun(context);
      case kDueBlockStart:
        // No block handed over: the sheet asks the sequence the same way every
        // other begin does, and the due item is only raised for the block the
        // sequence is on, so the two answers are the same block.
        await _confirmBeginProgram();
      case _:
        // An unrecognised kind reaches here only if a newer client's item
        // synced down to an older one. Showing the reviews is the safe wrong
        // answer: it is a read, on the program the user is already looking at.
        _showReviews();
    }
  }

  /// Ends a run, from either state.
  ///
  /// [paused] changes which run is addressed and what the dialog promises, and
  /// nothing else: ending is the same act either way — a formal end that records
  /// what the attempt got to. It is deliberately reachable from the paused state,
  /// because "I am not finishing this, but I am done with it" is a real answer,
  /// and without it the only way out of a pause would be to resume and end.
  Future<void> _confirmEndRun(BuildContext context, {bool paused = false}) async {
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
          paused
              ? 'This run is paused, not finished. Ending it records what it '
                  'got to, and you can begin the program again afterwards.'
              : 'Your progress will be saved. You can start this program again later.',
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
    if (ok != true) return;
    await (paused ? _vm.endPausedRun() : _vm.endCurrentRun());
  }

  /// Starts this attempt over: the old run is ended with its record and a fresh
  /// one begins.
  ///
  /// One confirmation, not two — the config sheet *is* the confirmation, with
  /// the warning line saying what restarting does. Two dialogs back to back for
  /// one decision is how a user stops reading either of them.
  ///
  /// The sheet opens prefilled with the old numbers ([run] is passed), so a
  /// restart that is meant to change the length can, and one that is not does
  /// not have to retype anything. What the sheet returns is a starting point,
  /// not a carry-over: the new run is new in every other respect.
  Future<void> _confirmRestart(ProgramRun run) async {
    final forBlock = run.blockId != null;
    final result = await showRunConfigSheet(
      context,
      programName: _vm.state.value.program?.name ?? 'this program',
      run: run,
      title: forBlock ? 'Restart this block' : 'Restart program',
      actionLabel: 'Restart',
      warning: 'This ends the current run and records what it got to, then '
          'starts a new one from the first workout. Your logged sessions stay '
          'in your history.',
    );
    if (result == null || !mounted) return;
    await _vm.restartRun(targetSessions: result.targetSessions);
  }

  /// Edits the active run's duration while the program is running.
  ///
  /// The run is always order-based now, so a calendar duration left on it by an
  /// older build is cleared here — the sheet can no longer express weeks or an
  /// end date, and leaving one in place would keep measuring the run against
  /// something the user cannot see.
  Future<void> _editRunConfig(ProgramRun run) async {
    final result = await showRunConfigSheet(
      context,
      programName: _vm.state.value.program?.name ?? 'this program',
      run: run,
    );
    if (result == null || !mounted) return;
    await _vm.updateRunConfig(
      progressionMode: 'order',
      targetSessions: result.targetSessions,
      targetWeeks: null,
      endDate: null,
      clearWeeks: true,
      clearEndDate: true,
    );
  }

  @override
  void initState() {
    super.initState();
    final injected = widget.viewModel;
    _ownsVm = injected == null;
    _vm = injected ?? ProgramDetailViewModel();
    _vm.state.addListener(_syncNameField);
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) _commitName();
    });
    if (injected != null) {
      // A caller that supplied the view model supplied its state too — loading
      // over it would replace what they set up. The controllers still have to
      // open on that state, or the header would show an empty name until the
      // next sync.
      _nameController.text = injected.state.value.nameDraft;
      _descriptionController.text = injected.state.value.descriptionDraft;
      return;
    }
    _vm.load(widget.programId).then((_) {
      if (!mounted) return;
      final s = _vm.state.value;
      _nameController.text = s.nameDraft;
      _descriptionController.text = s.descriptionDraft;
    });
  }

  @override
  void dispose() {
    _vm.state.removeListener(_syncNameField);
    _nameFocus.dispose();
    _tabController.dispose();
    if (_ownsVm) _vm.dispose();
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

  /// "+" on Program Workouts: offer creating a new workout or copying an
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
                'From library',
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
    final workouts = await _vm.standaloneWorkouts();
    if (!mounted) return;
    if (workouts.isEmpty) {
      _showSnack('No workouts in your library to copy from.');
      return;
    }
    final chosen = await showOptionPickerSheet(
      context,
      title: 'Add workout to program',
      options: [
        for (final w in workouts) (id: w.sessionId, label: toProperCase(w.name)),
      ],
    );
    if (chosen == null || !mounted) return;
    await _vm.copyWorkoutIntoProgram(chosen);
  }

  Future<void> _openEditWorkout(PlannedSession w) async {
    // Informational confirm when editing a workout in a running program:
    // changes apply to future sessions only; already-logged sets are snapshots
    // and won't change. Shared with the block editor, which is the other way
    // into this editor and has to say exactly the same thing.
    if (_vm.state.value.isCurrent &&
        !await confirmEditWhileRunning(context)) {
      return;
    }
    if (!mounted) return;
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

  /// The Workouts tab's list: every workout of the program, in the program's
  /// order.
  ///
  /// Blocks are a phase structure laid over these workouts, not a way of filing
  /// them out of this list — they are created, named and filled in the Blocks
  /// tab and the block editor, and those are the only places that show them.
  /// Grouping this list by block put the same headers on two tabs and made one
  /// drag gesture mean two things: "reorder the program" under one header and
  /// "reorder inside this block" under another.
  List<Widget> _buildWorkoutSections(ProgramDetailState state) {
    if (state.plannedWorkouts.isEmpty) return const [_NoWorkouts()];
    return [_workoutList(state.plannedWorkouts)];
  }

  /// The program's workouts, reorderable. "Session 3" is the third workout of
  /// the program — which is now simply this list's order, with no second
  /// ordering to reconcile it against.
  Widget _workoutList(List<PlannedSession> workouts) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) {
        final updated = List<PlannedSession>.from(workouts);
        final item = updated.removeAt(oldIndex);
        updated.insert(newIndex, item);
        _vm.reorderWorkouts(updated, [for (final w in updated) w.sessionId]);
      },
      children: [
        for (var i = 0; i < workouts.length; i++)
          ProgramWorkoutRow(
            key: ValueKey(workouts[i].sessionId),
            workout: workouts[i],
            badge: 'Session ${i + 1}',
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

  // ── Blocks ───────────────────────────────────────────────────────────────

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
      _showSnack(
        'Nothing to move in — make a workout inside the block instead.',
      );
      return;
    }
    final picked = await showOptionPickerSheet(
      context,
      title: 'Add to ${toProperCase(block.name)}',
      options: [
        for (final w in unassigned)
          (id: w.sessionId, label: toProperCase(w.name)),
      ],
    );
    if (picked == null || !mounted) return;
    await _vm.assignWorkoutToBlock(picked, block.blockId);
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
      if (!mounted) return;
      _vm.load(widget.programId);
      // The history panel reads the program through its own view model, so a
      // reload here does not reach it. An edit is exactly what makes the
      // versions it is showing stale, so it is rebuilt too.
      setState(() => _historyEpoch++);
    });
  }

  @override
  Widget build(BuildContext context) {
    return buildGuardedScaffold(
      scaffold: Scaffold(
        backgroundColor: AppColors.bg,
        // The nav bar belongs here only when this screen is drawn outside the
        // tab shell. Day to day it is not: the shell owns the bar for this
        // whole branch, and it keeps drawing it on every page pushed within
        // the branch — so a bar here would stack a second one on top (the
        // shell's `_showBottomNav` is gated in the router). It is the review
        // that renders this screen bare — its route sits on the root
        // navigator, over the shell — and with the review running, that is
        // exactly `ReviewScope.maybeOf` being non-null.
        //
        // Tab taps then run the unsaved-changes guard in `_onNavTap` and pop
        // the review route before leaving; a review stacks its own bar above
        // this one.
        bottomNavigationBar: reviewBottomSlot(
          context,
          settle: confirmBack,
          child: ReviewScope.maybeOf(context) == null
              ? null
              : BottomNavBar(
                  currentRoute: '/exercises',
                  onTap: _onNavTap,
                ),
        ),
        body: ValueListenableBuilder<ProgramDetailState>(
          valueListenable: _vm.state,
          builder: (context, state, _) {
            // The shape as the schema stores it. Read once here and handed to
            // the list — every surface below (the tabs, the run block, the
            // goals picker) branches on it, and none of them may infer it from
            // something else.
            final tabs = _tabsFor(
              blocked: state.program?.usesBlocks ?? false,
            );
            return Column(
              children: [
                PageHeader(
                  // Rendered by [titleWidget]; the plain title is the name
                  // this screen falls back on before the fetch lands.
                  title: 'Program',
                  // The program's name lives here rather than in a field
                  // below, exactly as the workout editor's does: tap it to
                  // rename, and losing focus saves it.
                  titleWidget: TextField(
                    controller: _nameController,
                    focusNode: _nameFocus,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.words,
                    style: AppFonts.ui(
                      fontSize: AppTextStyles.lg,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Program name',
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    onChanged: _vm.setNameDraft,
                    onSubmitted: (_) => _nameFocus.unfocus(),
                  ),
                  left: GestureDetector(
                    onTap: () async {
                      // Blur first — the name commits on focus loss, and the
                      // back guard must see the rename as saved before it
                      // decides whether there is anything to ask about.
                      FocusManager.instance.primaryFocus?.unfocus();
                      final nav = Navigator.of(context);
                      await _commitName();
                      if (!mounted) return;
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
                  // No history icon any more: versions and reviews are the
                  // Reviews tab, which is also what frees the title up on a
                  // long program name.
                  //
                  // Save appears only once there is something to save — the
                  // same rule the planner's header follows. An always-present
                  // Save reads as a claim that something changed.
                  right: hasUnsavedChanges
                      ? GlassButton(
                          label: 'Save',
                          compact: true,
                          loading: state.isSaving,
                          disabled: state.isSaving,
                          onPressed: _saveAll,
                        )
                      : null,
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
                // Not an error: the run action succeeded. But a run that ended
                // without its record is a real loss, and nothing else would
                // ever say so.
                if (state.historyWarning != null)
                  Container(
                    width: double.infinity,
                    color: AppColors.dangerBg,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      state.historyWarning!,
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
                else ...[
                  SlideTabBar(
                    tabs: [for (final t in tabs) _tabLabel(t)],
                    activeIndex: _tab,
                    onTap: _onTabChanged,
                  ),
                  SlideTabView(
                    controller: _tabController,
                    onPageChanged: (i) => setState(() => _tab = i),
                    tabs: [for (final t in tabs) _bodyFor(t, state)],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// The body behind a tab. The workouts/blocks split is the shape rule
  /// itself: a simple program's only workout surface is its list, and a
  /// blocked program's is its blocks.
  Widget _bodyFor(_ProgramTab tab, ProgramDetailState state) => switch (tab) {
        _ProgramTab.workouts => _workoutsTab(state),
        _ProgramTab.blocks => _blocksTab(state),
        _ProgramTab.goals => _goalsTab(state),
        // Keyed by epoch so an edit elsewhere on the screen rebuilds it into
        // a fresh load, and by scope so a due block review opens filtered.
        _ProgramTab.reviews => ProgramHistoryPanel(
            key: ValueKey('history-$_historyEpoch-$_reviewScope'),
            programId: widget.programId,
            initialBlockId: _reviewScope,
          ),
      };

  /// What the program is — the preamble both workout surfaces open with.
  ///
  /// It follows the substance: the top of Workouts for a simple program, the
  /// top of Blocks for a blocked one, since a blocked program's workouts only
  /// exist inside those blocks.
  Widget _descriptionField() => LambdaInput(
    controller: _descriptionController,
    label: 'Description',
    placeholder: 'What is this program about?',
    onChanged: _vm.setDescriptionDraft,
  );

  /// The workouts themselves, and what the run is doing — the tab a simple
  /// program opens on.
  ///
  /// The description and Begin Program live here rather than in a tab of their
  /// own because they are the preamble to the list: what this program is, and
  /// whether you are doing it.
  Widget _workoutsTab(ProgramDetailState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _descriptionField(),
          const SizedBox(height: AppSpacing.lg),
          _runBlock(state),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Program Workouts',
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
    );
  }

  /// What the run is doing: running, paused, or not started.
  ///
  /// Three renderings of one state machine, deliberately built side by side. A
  /// current run and a paused one show the same facts — which block, how long,
  /// how far — and differ only in the verbs offered, so splitting them across
  /// two builders is how they drift apart.
  Widget _runBlock(ProgramDetailState state) {
    final run = state.activeRun;
    if (state.isCurrent && run != null) return _currentRunBlock(state, run);
    final paused = state.pausedRun;
    if (paused != null) return _pausedRunBlock(state, paused);
    // A blocked program is run through its blocks, so there is no "the
    // program" to begin: the Begin lives on the block the sequence is on,
    // where it names the phase it starts. Not inferred from an empty list
    // alone — a simple program has no blocks either, and it begins whole.
    if (state.program?.usesBlocks ?? false) {
      // Nothing to begin from here, and nothing to say about it either — the
      // blocks below carry both the action and the reason.
      if (state.blocks.isNotEmpty) return const SizedBox.shrink();
      // No blocks at all: saying so is the whole difference between this and a
      // button that does nothing.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassButton(
            label: 'Begin Program',
            icon: Icons.play_circle_outline,
            disabled: true,
            onPressed: _confirmBeginProgram,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Add a block to run this program.',
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.muted,
            ),
          ),
        ],
      );
    }
    return Row(
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
    );
  }

  /// The run you are doing: how far it is, and the two things you can do to it
  /// while it runs — change its length, or end it.
  Widget _currentRunBlock(ProgramDetailState state, ProgramRun run) {
    final progress = state.currentProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Which block is running, when one is — the duration line below it
        // reads the same either way, because a block run's numbers are
        // block-relative.
        if (progress?.blockLabel != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              progress!.blockLabel!,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        Text(
          _runConfigLabel(run, progress?.block),
          style: AppFonts.mono(fontSize: 14, color: AppColors.muted),
        ),
        if (progress != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            progress.remainingLabel,
            style: AppFonts.mono(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        // A block run has nothing to edit here: the block owns its length
        // (shown on the line above) and the schedule that used to be the
        // other half of this button is retired. Changing the phase is done
        // on the block itself.
        if (run.blockId == null)
          GlassButton(
            label: 'Edit duration',
            icon: Icons.tune,
            compact: true,
            onPressed: () => _editRunConfig(run),
          ),
        const SizedBox(height: AppSpacing.xs),
        GlassButton(
          label: 'End Program',
          icon: Icons.stop_circle_outlined,
          compact: true,
          onPressed: () => _confirmEndRun(context),
        ),
      ],
    );
  }

  /// The run you stepped away from: the same facts as a current run, and the
  /// one difference that matters — the verb.
  ///
  /// Resume is primary, because picking it back up is what this state is for.
  /// Restart and End are secondary and sit together: both end the run, and the
  /// difference between them is whether a new attempt begins afterwards. That
  /// distinction is spelled out in each one's confirmation rather than left to
  /// the labels.
  Widget _pausedRunBlock(ProgramDetailState state, ProgramRun run) {
    final progress = state.pausedProgress;
    final forBlock = run.blockId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const StatusChip(label: 'Paused', muted: true),
            if (progress?.blockLabel != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  progress!.blockLabel!,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _runConfigLabel(run, progress?.block),
          style: AppFonts.mono(fontSize: 14, color: AppColors.muted),
        ),
        if (_loggedLabel(progress) != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _loggedLabel(progress)!,
            style: AppFonts.mono(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        GlassButton(
          label: 'Resume',
          icon: Icons.play_circle_outline,
          solid: true,
          loading: state.settingCurrent,
          disabled: state.settingCurrent,
          onPressed: _confirmResume,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: GlassButton(
                label: forBlock ? 'Restart this block' : 'Restart program',
                icon: Icons.restart_alt,
                compact: true,
                disabled: state.settingCurrent,
                onPressed: () => _confirmRestart(run),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: GlassButton(
                label: 'End Program',
                icon: Icons.stop_circle_outlined,
                compact: true,
                disabled: state.settingCurrent,
                onPressed: () => _confirmEndRun(context, paused: true),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// How far the paused run got — the line a current run uses for what is left.
  ///
  /// Null when there is nothing to say (no progress could be read). The count is
  /// the run's own, not the cycle's: a paused run's story is "what I did", and
  /// the cycle number would restart it at the top of a block it never finished.
  String? _loggedLabel(ProgramProgress? progress) {
    if (progress == null) return null;
    final done = progress.totalWorkoutsCompleted;
    final total = progress.totalWorkoutsInCycle;
    if (done == 0) return 'no sessions logged';
    if (total <= 0) {
      return '$done session${done == 1 ? '' : 's'} logged';
    }
    return '$done of $total sessions';
  }

  /// The blocks themselves — the program's phases, as things to manage — and
  /// the whole workout surface of a blocked program.
  ///
  /// There is no Workouts tab to sit beside this one: a blocked program's
  /// workouts are made, edited, ordered and removed inside its blocks, so this
  /// tab carries what that tab carries for a simple program — the description,
  /// the run block, and the list — with blocks where the flat list would be.
  /// Anything belonging to no block is listed under Unfiled rather than being
  /// invisible, which is where archiving a block puts its workouts.
  Widget _blocksTab(ProgramDetailState state) {
    // From the groups rather than `state.blocks`: the groups are in block
    // order and already carry each block's workouts, so this tab and the block
    // editor can never disagree about what is in what.
    final groups = _vm.blockGroups;
    final blocks = groups.where((g) => g.block != null).toList();
    final unfiled = groups
        .where((g) => g.isUnassigned)
        .expand((g) => g.workouts)
        .toList();

    // Where the program is in its sequence. Blocks run in order, so exactly
    // one of them can be begun — the next one — and the one waiting on an
    // unended predecessor is told why instead of being offered nothing.
    final sequence = state.blockSequence;
    final openBlock = sequence.hasOpenRun ? sequence.pending : null;
    final openIndex = openBlock == null
        ? -1
        : blocks.indexWhere((g) => g.block!.blockId == openBlock.blockId);
    // Only the block right after the open one: pointing at a phase three
    // phases away would be repeating the same sentence down the list.
    final waitingId = openIndex >= 0 && openIndex + 1 < blocks.length
        ? blocks[openIndex + 1].block!.blockId
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _descriptionField(),
          const SizedBox(height: AppSpacing.lg),
          _runBlock(state),
          const SizedBox(height: AppSpacing.lg),
          if (blocks.isEmpty)
            Text(
              'No blocks yet. A block is a phase of the program with its own '
              'length, dates and workouts — Accumulation, Intensification, '
              'and so on.',
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.muted,
              ),
            )
          else
            for (final group in blocks)
              _BlockHeader(
                block: group.block!,
                workoutCount: group.workouts.length,
                onTap: () => _openBlockEditor(group.block!),
                onAddWorkouts: () => _addWorkoutsToBlock(group.block!),
                onBegin: sequence.canBegin(group.block!.blockId)
                    ? _confirmBeginProgram
                    : null,
                blockedReason: group.block!.blockId == waitingId
                    ? 'End ${toProperCase(openBlock!.name)} first.'
                    : null,
              ),
          const SizedBox(height: AppSpacing.md),
          GlassButton(
            label: 'Add block',
            icon: Icons.add,
            compact: true,
            onPressed: _openCreateBlock,
          ),
          if (unfiled.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _UnfiledGroup(
              workouts: unfiled,
              onTap: _openEditWorkout,
              onFile: _fileWorkoutIntoBlock,
              onDelete: _confirmDeleteWorkout,
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  /// Files an unfiled workout into one of the program's blocks — the way a
  /// workout that lost its phase (or arrived with none) finds one again.
  Future<void> _fileWorkoutIntoBlock(PlannedSession w) async {
    final blocks = _vm.state.value.blocks;
    if (blocks.isEmpty) return;
    final picked = await showOptionPickerSheet(
      context,
      title: 'File into…',
      options: [
        for (final b in blocks)
          (id: b.blockId, label: toProperCase(b.name)),
      ],
    );
    if (picked == null || !mounted) return;
    await _vm.assignWorkoutToBlock(w.sessionId, picked);
  }

  /// The program's goals, at both levels, with whatever the running window
  /// says about the ones in force.
  ///
  /// Rendered whether or not a run is active: a goal is part of what the
  /// program is, and setting targets is the natural thing to do before starting
  /// it — including a phase's targets, which is why the scope choice is offered
  /// whenever the program has blocks rather than only while one is running.
  /// A simple program has no blocks, so it is never offered one: every goal it
  /// holds is the program's own.
  Widget _goalsTab(ProgramDetailState state) {
    final goals = state.programGoals;
    final blocks = state.blocks;
    final run = state.activeRun;
    // Read through the current blocks rather than used raw: a block archived
    // while this screen was open would otherwise still be scoped to, and the
    // goal would be filed against a phase that no longer exists.
    final scope =
        blocks.any((b) => b.blockId == _goalScope) ? _goalScope : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              // Absent for a goal not in force right now — which is the point
              // of the keyed map: no entry, no verdict, rather than a false
              // "missed".
              outcome: state.goalOutcomes[g.goalId],
              onDelete: () => _vm.deleteGoal(g.goalId),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (blocks.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: GlassButton(
                label: 'Add to: ${_scopeLabel(blocks, scope)}',
                compact: true,
                onPressed: () => _pickGoalScope(blocks),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          ExerciseTargetPicker(
            detailMap: state.exerciseDetailMap,
            variations: state.allVariations,
            onAdd: (target) {
              _vm.addGoal(
                exerciseId: target.exerciseId,
                exerciseName: target.exerciseName,
                variationId: target.variationId,
                targetWeight: target.weight,
                targetReps: target.reps,
                blockId: scope,
              );
            },
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  /// Chooses which block — or the program itself — the next goal belongs to.
  ///
  /// A picker rather than a segmented control because the list is the program's
  /// blocks and a program can have any number of them: two fixed segments
  /// could only ever say "this block" about whichever one happened to be
  /// running, which is exactly the gate that kept a phase's goals from being
  /// set before the phase started.
  Future<void> _pickGoalScope(List<ProgramBlock> blocks) async {
    final picked = await showOptionPickerSheet(
      context,
      title: 'Add goal to…',
      options: [
        (id: _kScopeProgram, label: 'Whole program'),
        for (final b in blocks)
          (id: b.blockId, label: toProperCase(b.name)),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _goalScope = picked == _kScopeProgram ? null : picked);
  }

  /// What a scope is called on the button that picks it.
  String _scopeLabel(List<ProgramBlock> blocks, String? scope) {
    for (final b in blocks) {
      if (b.blockId == scope) return toProperCase(b.name);
    }
    return 'Whole program';
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
    this.onBegin,
    this.blockedReason,
  });

  final ProgramBlock block;
  final int workoutCount;
  final VoidCallback onTap;
  final VoidCallback onAddWorkouts;

  /// Begins a run of this block. Null on every block that is not the
  /// sequence's next one — blocks run in order, so a begin here would be an
  /// act the sequencing rule refuses, and an inert button is worse than none.
  final VoidCallback? onBegin;

  /// Why this block cannot be begun yet, when it is the one waiting on an
  /// unended predecessor. Shown instead of a greyed-out Begin: the reason is
  /// the useful half, and a dead button carries none of it.
  final String? blockedReason;

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
                  if (blockedReason != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      blockedReason!,
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.xs,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onBegin != null)
              GlassButton(
                label: 'Begin',
                icon: Icons.play_circle_outline,
                compact: true,
                onPressed: onBegin!,
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

/// The workouts that belong to no block.
///
/// Not an error state — it is where archiving a block puts its workouts, and
/// where an unfiled one waits — but a blocked program's workouts are made
/// inside a block, so a row here is something that has lost its phase or never
/// got one. Each row can be filed into a block, or removed from the program,
/// which is what keeps a blocked program's leftovers from being stranded with
/// no Workouts tab to show them.
class _UnfiledGroup extends StatelessWidget {
  const _UnfiledGroup({
    required this.workouts,
    required this.onTap,
    required this.onFile,
    required this.onDelete,
  });

  final List<PlannedSession> workouts;
  final ValueChanged<PlannedSession> onTap;
  final ValueChanged<PlannedSession> onFile;
  final ValueChanged<PlannedSession> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Unfiled',
          style: AppFonts.ui(
            fontSize: AppTextStyles.md,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          workouts.length == 1
              ? '1 workout is in no block. File it into one, or remove it '
                    'from the program.'
              : '${workouts.length} workouts are in no block. File them into '
                    'one, or remove them from the program.',
          style: AppFonts.ui(
            fontSize: AppTextStyles.xs,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final w in workouts)
          ProgramWorkoutRow(
            key: ValueKey('unfiled-${w.sessionId}'),
            workout: w,
            onTap: () => onTap(w),
            swipeActions: [
              SwipeAction(
                icon: Icons.drive_file_move_outline,
                label: 'File into…',
                color: AppColors.accent,
                onTap: () => onFile(w),
              ),
              SwipeAction(
                icon: Icons.delete_outline,
                label: 'Delete',
                color: AppColors.danger,
                onTap: () => onDelete(w),
              ),
            ],
          ),
      ],
    );
  }
}

class _NoWorkouts extends StatelessWidget {
  const _NoWorkouts();

  @override
  Widget build(BuildContext context) => Text(
    'No program workouts yet.',
    style: AppFonts.ui(color: AppColors.muted, fontSize: AppTextStyles.sm),
  );
}
