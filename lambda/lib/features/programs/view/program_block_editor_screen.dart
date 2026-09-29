import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/block_length.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/models/program_block.dart';
import '../../../shared/mixins/unsaved_changes_guard.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/date_picker_sheet.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/segmented_control.dart';
import '../../../shared/widgets/swipe_actions.dart';
import '../viewmodel/program_detail_viewmodel.dart';
import 'goal_row.dart';
import 'program_workout_row.dart';

/// A phase of a program: its name, its targets, its dates, and the workouts
/// assigned to it in order.
///
/// Shares the [ProgramDetailViewModel] instance that pushed it — the same
/// arrangement `PlanSessionScreen` uses — so the block's contents and the
/// program's workout list are one piece of state, never two that can disagree.
class ProgramBlockEditorScreen extends StatefulWidget {
  const ProgramBlockEditorScreen({
    super.key,
    required this.viewModel,
    this.block,
  });

  final ProgramDetailViewModel viewModel;

  /// Null = a new block.
  final ProgramBlock? block;

  @override
  State<ProgramBlockEditorScreen> createState() =>
      _ProgramBlockEditorScreenState();
}

class _ProgramBlockEditorScreenState extends State<ProgramBlockEditorScreen>
    with UnsavedChangesGuard<ProgramBlockEditorScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _notesCtrl;

  /// The length in each unit. Only the unit [_mode] selects is ever visible, and
  /// only that one is read on save — the others are a memory of what the user
  /// typed before switching, so flipping the toggle to look and flipping back
  /// does not wipe a length they had already entered.
  ///
  /// `Weeks` is two fields rather than one because a block's calendar length is
  /// weeks *plus* a remainder of days — "eight weeks and three days" is a real
  /// phase and had no way to be said. The pair is one number ([_totalDays]) and
  /// is only ever read as that number.
  ///
  /// Keeping all of them is safe because the *block* still has exactly one
  /// length: `ProgramRepository.updateBlock` nulls the unit it was not sent, so
  /// a stale hidden number can never reach the database.
  late final TextEditingController _weeksCtrl;
  late final TextEditingController _daysCtrl;
  late final TextEditingController _sessionsCtrl;

  late BlockLengthMode _mode;

  /// The anchor. Everything else about the block's dates is derived from it.
  DateTime? _startDate;

  bool _saving = false;

  ProgramDetailViewModel get _vm => widget.viewModel;
  bool get _isNew => widget.block == null;

  @override
  void initState() {
    super.initState();
    final b = widget.block;
    _nameCtrl = TextEditingController(text: b?.name ?? '');
    _notesCtrl = TextEditingController(text: b?.notes ?? '');
    _mode = blockLengthModeOf(
      targetWeeks: b?.targetWeeks,
      targetSessions: b?.targetSessions,
    );
    _weeksCtrl = TextEditingController(text: _fmt(b?.targetWeeks));
    _daysCtrl = TextEditingController(text: _fmt(b?.targetDays));
    _sessionsCtrl = TextEditingController(text: _fmt(b?.targetSessions));
    _startDate = b?.startDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    _weeksCtrl.dispose();
    _daysCtrl.dispose();
    _sessionsCtrl.dispose();
    super.dispose();
  }

  @override
  bool get hasUnsavedChanges {
    final b = widget.block;
    if (b == null) return _nameCtrl.text.trim().isNotEmpty;
    // The end date is deliberately absent: in weeks mode it is a projection of
    // (Starts, the length) and both of those are compared below, and in
    // sessions mode it is null by constraint. Comparing it directly would flag
    // a legacy block as dirty the moment it was opened, before the user
    // touched it.
    return _nameCtrl.text.trim() != b.name ||
        _notesCtrl.text.trim() != (b.notes ?? '') ||
        _mode !=
            blockLengthModeOf(
              targetWeeks: b.targetWeeks,
              targetSessions: b.targetSessions,
            ) ||
        _lengthChanged(b) ||
        !sameCalendarDay(_startDate, b.startDate);
  }

  /// Whether the length fields disagree with what [b] stores — as days for a
  /// weeks block, or as a plain count for a sessions one. Only reached once the
  /// modes are known to match.
  ///
  /// The weeks pair is compared as a *total*, not field by field, so `6 / 9` is
  /// not dirty against a stored `7 / 2`: those are the same 51 days, and
  /// normalizing a spelling is not a change to the plan.
  bool _lengthChanged(ProgramBlock b) => _mode == BlockLengthMode.sessions
      ? _sessions != b.targetSessions
      : _totalDays != _storedTotalDays(b);

  @override
  Future<void> onSave() async => await _save();

  @override
  void onDiscard() {
    final b = widget.block;
    setState(() {
      _nameCtrl.text = b?.name ?? '';
      _notesCtrl.text = b?.notes ?? '';
      _weeksCtrl.text = _fmt(b?.targetWeeks);
      _daysCtrl.text = _fmt(b?.targetDays);
      _sessionsCtrl.text = _fmt(b?.targetSessions);
      _mode = blockLengthModeOf(
        targetWeeks: b?.targetWeeks,
        targetSessions: b?.targetSessions,
      );
      _startDate = b?.startDate;
    });
  }

  static int? _parse(String s) => int.tryParse(s.trim());

  /// A count as field text. A stored zero reads as an empty field for the same
  /// reason a zero remainder is stored as null: neither is a value the user
  /// entered, and printing `0` would make absence look like a number.
  static String _fmt(int? n) => n == null || n == 0 ? '' : '$n';

  /// The length a weeks block declares, in days — the one number the `Weeks`
  /// and `Days` fields are between them.
  ///
  /// Read as a total rather than as a pair so that the projection and the dirty
  /// check stay honest mid-edit: `6 weeks 9 days` is 51 days on its way to being
  /// re-spelled `7 weeks 2 days`, and both spellings have to project the same
  /// `Ends`. Null when the fields declare nothing, or a total of zero days —
  /// which is not a length, and would project an end *on* the start.
  int? get _totalDays {
    final total = (_parse(_weeksCtrl.text) ?? 0) * 7 +
        (_parse(_daysCtrl.text) ?? 0);
    return total > 0 ? total : null;
  }

  /// The sessions count, or null when it is not a length at all.
  int? get _sessions {
    final n = _parse(_sessionsCtrl.text);
    return n != null && n > 0 ? n : null;
  }

  /// [b]'s weeks-mode length in days, or null when it declares none. Only
  /// meaningful once [_mode] matches the block's own mode — which is exactly
  /// what the mode comparison in [hasUnsavedChanges] establishes.
  int? _storedTotalDays(ProgramBlock? b) {
    final weeks = b?.targetWeeks;
    if (weeks == null) return null;
    final total = weeks * 7 + (b?.targetDays ?? 0);
    return total > 0 ? total : null;
  }

  /// Switching units is a re-decision, so the other field keeps whatever it
  /// held rather than being cleared — the number is not carried across (8 weeks
  /// is not 8 sessions), but nothing the user typed is thrown away either.
  void _setMode(BlockLengthMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
  }

  /// Weeks are anchored to Starts: moving the anchor moves the end with it, and
  /// clearing it takes the end along rather than re-anchoring to today. A block
  /// with no start has no end to project, and inventing one would quietly
  /// re-date the block every time the editor was opened.
  void _clearStart() => setState(() => _startDate = null);

  /// `Ends` = `Starts` + the length — the one projection the block's two date
  /// fields are, and the reason picking an end back-computes the length rather
  /// than being stored beside it. Null whenever there is nothing to project:
  /// no anchor, or no length to anchor.
  ///
  /// The length fields are the stored value and this is what they look like on
  /// a calendar, so the field re-renders the moment either one changes. The two
  /// are exact inverses now that a remainder can be carried, so a picked end
  /// back-fills precisely — no rounding, and nothing to see and adjust.
  DateTime? get _projectedEnd {
    final start = _startDate;
    final total = _totalDays;
    if (start == null || total == null) return null;
    return endDateFor(start, total ~/ 7, total % 7);
  }

  /// Sessions mode has no calendar end at all; weeks mode writes the projection.
  DateTime? get _endDateToSave =>
      _mode == BlockLengthMode.weeks ? _projectedEnd : null;

  Future<bool> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Give the block a name.');
      return false;
    }
    setState(() => _saving = true);
    final notes = _notesCtrl.text.trim();
    final totalDays = _mode == BlockLengthMode.weeks ? _totalDays : null;
    final sessions = _mode == BlockLengthMode.sessions ? _sessions : null;
    // Normalized on the way out: the column holds whole weeks plus a remainder
    // of days, so `6 weeks 9 days` is written as `7 weeks 2 days`. Doing the
    // arithmetic here rather than refusing the value is what lets the user type
    // the sum that is in their head and still get a legal block. A zero
    // remainder is stored as null — the column's null means "no remainder", not
    // "zero days".
    final targetWeeks = totalDays == null ? null : totalDays ~/ 7;
    final targetDays =
        totalDays == null || totalDays % 7 == 0 ? null : totalDays % 7;

    final bool ok;
    if (_isNew) {
      final created = await _vm.createBlock(
        name: name,
        notes: notes.isEmpty ? null : notes,
        targetWeeks: targetWeeks,
        targetDays: targetDays,
        targetSessions: sessions,
        startDate: _startDate,
        endDate: _endDateToSave,
      );
      ok = created != null;
    } else {
      final b = widget.block!;
      ok = await _vm.updateBlock(
        b.blockId,
        name: name,
        clearNotes: notes.isEmpty,
        notes: notes.isEmpty ? null : notes,
        // Every clear flag is always sent: they are how the editor states which
        // unit this block is measured in and how long it is, which a nullable
        // number alone cannot say. The repository enforces the same rule, so
        // this is the caller being explicit rather than the caller being
        // trusted.
        targetWeeks: targetWeeks,
        clearWeeks: targetWeeks == null,
        targetDays: targetDays,
        clearTargetDays: targetDays == null,
        targetSessions: sessions,
        clearSessions: sessions == null,
        startDate: _startDate,
        clearStartDate: _startDate == null,
        endDate: _endDateToSave,
        clearEndDate: _endDateToSave == null,
      );
    }
    if (!mounted) return ok;
    setState(() {
      _saving = false;
      // The fields re-spell what was stored, so a length typed as `6 / 9` comes
      // back as `7 / 2`. Letting the form keep showing a remainder the column
      // cannot hold would leave the screen and the database disagreeing about a
      // number the user is still looking at. Sessions mode is left alone — its
      // fields are the user's memory of another unit, not this save's output.
      if (ok && _mode == BlockLengthMode.weeks) {
        _weeksCtrl.text = _fmt(targetWeeks);
        _daysCtrl.text = _fmt(targetDays);
      }
    });
    if (!ok) {
      _snack(
        _vm.state.value.error ??
            'Could not save. Creating a block needs a network connection.',
      );
    }
    return ok;
  }

  Future<void> _saveAndClose() async {
    if (_saving) return;
    if (!await _save()) return;
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  /// This block's own slice of the program's history — the revisions cut while
  /// it was running and the reviews that checkpointed them.
  ///
  /// Saved first: the history is a read of the program's contents, and leaving
  /// with unsaved edits would show a timeline that disagrees with the screen
  /// the user just left.
  Future<void> _openHistory() async {
    final block = widget.block!;
    if (hasUnsavedChanges) {
      if (!await _save()) return;
      if (!mounted) return;
    }
    if (!mounted) return;
    context.go(
      '/exercises/programs/${block.programId}/history?block=${block.blockId}',
    );
  }

  /// Tab taps run the unsaved-changes guard before leaving — the same contract
  /// the workout editor honours while it covers the tab shell.
  Future<void> _onNavTap(String route) async {
    final router = GoRouter.of(context);
    if (!await confirmBack()) return;
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    router.go(route);
  }

  /// Copies a workout into this block. The copy lands in the source's slot;
  /// assigning it here is what puts it in THIS block, which is the only way to
  /// have the same training in two phases without the two sharing one row.
  Future<void> _duplicateWorkout(PlannedSession workout) async {
    final newId = await _vm.duplicatePlannedSession(workout);
    if (newId == null) return;
    await _vm.assignWorkoutToBlock(newId, widget.block!.blockId);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppFonts.ui(fontSize: AppTextStyles.sm),
        ),
      ),
    );
  }

  /// The anchor date. Bounded generously in both directions: a block is a plan,
  /// so it may have begun well before today or be scheduled years ahead.
  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await showDatePickerSheet(
      context,
      initial: _startDate,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      title: 'STARTS',
    );
    if (picked == null) return;
    setState(() => _startDate = picked);
  }

  /// Picking an end **back-computes the length** rather than storing a second
  /// date. The two fields are one value shown twice, so the only way to keep
  /// them from ever disagreeing is for the end to be a question about the
  /// length — and now that the length can carry a remainder, that question has
  /// an exact answer for any day the user can pick.
  Future<void> _pickEnd() async {
    final start = _startDate;
    if (start == null) return;
    final now = DateTime.now();
    final picked = await showDatePickerSheet(
      context,
      initial: _projectedEnd,
      // The day after the start: an end on the start is not a length, and
      // `lengthBetween` would return null for it — a silent no-op where the
      // honest thing is to not offer the day at all.
      firstDate: DateTime(start.year, start.month, start.day + 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      title: 'ENDS',
    );
    if (picked == null) return;
    final length = lengthBetween(startDate: start, endDate: picked);
    if (length == null) return;
    setState(() {
      _weeksCtrl.text = '${length.weeks}';
      _daysCtrl.text = _fmt(length.days);
    });
  }

  /// The block's workouts, in the program's global order, reorderable within
  /// the block only.
  List<PlannedSession> get _workouts {
    for (final group in _vm.blockGroups) {
      if (group.block?.blockId == widget.block?.blockId) return group.workouts;
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    return buildGuardedScaffold(
      scaffold: Scaffold(
        backgroundColor: AppColors.bg,
        body: ValueListenableBuilder<ProgramDetailState>(
          valueListenable: _vm.state,
          builder: (context, state, _) => Column(
            children: [
              PageHeader(
                title: _isNew ? 'New Block' : widget.block!.name,
                left: IconButton(
                  icon: Icon(Icons.arrow_back, color: AppColors.primary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                right: _isNew
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.history,
                              color: AppColors.accent,
                            ),
                            tooltip: 'This block\'s history',
                            onPressed: _openHistory,
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: AppColors.danger,
                            ),
                            onPressed: _confirmArchive,
                          ),
                        ],
                      ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LambdaInput(
                        controller: _nameCtrl,
                        label: 'Name',
                        placeholder: 'e.g. Accumulation',
                        textCapitalization: TextCapitalization.sentences,
                        required: true,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      LambdaInput(
                        controller: _notesCtrl,
                        label: 'Notes',
                        placeholder: 'What is this phase for?',
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 2,
                        maxLines: 5,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // One length, chosen once. The block is measured in weeks
                      // or in sessions — never both, because two answers to
                      // "is this phase over?" is one answer too many.
                      SegmentedControl<BlockLengthMode>(
                        value: _mode,
                        onChange: _setMode,
                        options: const [
                          SegmentOption(
                            label: 'Weeks',
                            value: BlockLengthMode.weeks,
                          ),
                          SegmentOption(
                            label: 'Sessions',
                            value: BlockLengthMode.sessions,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // Anchor first, then the length. Read in that order and
                      // the third field — the end date — is just the first two
                      // multiplied out, which is exactly what it is.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _DateField(
                              label: 'Starts',
                              date: _startDate,
                              onTap: _pickStart,
                              onClear: _startDate == null ? null : _clearStart,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            flex: 2,
                            child: _mode == BlockLengthMode.weeks
                                // Two narrow boxes, because a calendar length is
                                // weeks *plus* a remainder of days and the pair
                                // has to read as one number. Neither takes a
                                // placeholder: at this width the hint would clip,
                                // and the labels above them already do the
                                // naming. Each rebuilds so Ends re-renders the
                                // new projection as the numbers are typed — this
                                // is what makes the fill live rather than a
                                // surprise on save.
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: LambdaInput(
                                          controller: _weeksCtrl,
                                          label: 'Weeks',
                                          keyboardType:
                                              TextInputType.number,
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                        child: LambdaInput(
                                          controller: _daysCtrl,
                                          label: 'Days',
                                          keyboardType:
                                              TextInputType.number,
                                          onChanged: (_) => setState(() {}),
                                        ),
                                      ),
                                    ],
                                  )
                                : LambdaInput(
                                    controller: _sessionsCtrl,
                                    label: 'Sessions',
                                    placeholder: 'e.g. 24',
                                    keyboardType: TextInputType.number,
                                  ),
                          ),
                        ],
                      ),
                      // Weeks mode only: a sessions block has no calendar end
                      // at all, so the field is absent rather than empty.
                      if (_mode == BlockLengthMode.weeks) ...[
                        const SizedBox(height: AppSpacing.md),
                        _DateField(
                          label: 'Ends',
                          date: _projectedEnd,
                          // Inert without an anchor: it is derived from Starts
                          // and Weeks, so with no Starts there is nothing for a
                          // pick to mean.
                          onTap: _startDate == null ? null : _pickEnd,
                          hint: _startDate == null
                              ? 'Set Starts first'
                              : 'Pick a date…',
                          onClear: null,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _mode == BlockLengthMode.weeks
                            ? 'Ends is Starts plus the weeks and days. Pick an '
                                'end and the length is worked out for you.'
                            : 'The block ends when you have done this many '
                                'sessions. You will be asked to end it.',
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.xs,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      GlassButton(
                        label: _saving ? 'Saving…' : 'Save',
                        icon: Icons.check,
                        onPressed: _saveAndClose,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Workouts',
                              style: AppFonts.ui(
                                fontSize: AppTextStyles.md,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          if (!_isNew)
                            GlassButton(
                              label: '',
                              icon: Icons.add,
                              compact: true,
                              onPressed: _addWorkouts,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_isNew)
                        Text(
                          'Save the block first, then add workouts to it.',
                          style: AppFonts.ui(
                            color: AppColors.muted,
                            fontSize: AppTextStyles.sm,
                          ),
                        )
                      else if (_workouts.isEmpty)
                        Text(
                          'No workouts in this block yet.',
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
                            final updated = List<PlannedSession>.from(_workouts);
                            final item = updated.removeAt(oldIndex);
                            updated.insert(newIndex, item);
                            _vm.reorderBlockWorkouts(
                              widget.block!.blockId,
                              updated.map((w) => w.sessionId).toList(),
                            );
                          },
                          children: [
                            for (var i = 0; i < _workouts.length; i++)
                              ProgramWorkoutRow(
                                key: ValueKey(_workouts[i].sessionId),
                                workout: _workouts[i],
                                dragIndex: i,
                                swipeActions: [
                                  SwipeAction(
                                    icon: Icons.copy_rounded,
                                    label: 'Duplicate',
                                    color: AppColors.accent,
                                    onTap: () => _duplicateWorkout(_workouts[i]),
                                  ),
                                  SwipeAction(
                                    icon: Icons.remove_circle_outline,
                                    label: 'Remove',
                                    color: AppColors.danger,
                                    onTap: () => _vm.assignWorkoutToBlock(
                                      _workouts[i].sessionId,
                                      null,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      const SizedBox(height: AppSpacing.lg),
                      _buildGoalsSection(state),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                  ),
                ),
              ),
              BottomNavBar(
                currentRoute: '/exercises',
                onTap: _onNavTap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// This block's own goals — the targets that are chased while it runs.
  ///
  /// Read from the shared state's full goal list rather than queried again: the
  /// program's goals are already loaded, and a block's are a filter over them,
  /// not a second source that could disagree about what exists.
  ///
  /// Nothing is scoped here — every goal added on this screen is this block's,
  /// because that is what the screen is. A program-level target belongs on the
  /// program, where it can be seen to apply to every phase.
  Widget _buildGoalsSection(ProgramDetailState state) {
    final block = widget.block;
    final goals = block == null
        ? const <Goal>[]
        : [
            for (final g in state.programGoals)
              if (g.blockId == block.blockId) g,
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Goals',
          style: AppFonts.ui(
            fontSize: AppTextStyles.md,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_isNew)
          Text(
            'Save the block first, then set its targets.',
            style: AppFonts.ui(
              color: AppColors.muted,
              fontSize: AppTextStyles.sm,
            ),
          )
        else ...[
          if (goals.isEmpty)
            Text(
              'No targets for this phase yet.',
              style: AppFonts.ui(
                color: AppColors.muted,
                fontSize: AppTextStyles.sm,
              ),
            ),
          for (final g in goals) ...[
            GoalRow(
              label: goalLabelFor(g, state.exerciseDetailMap),
              outcome: state.goalOutcomes[g.goalId],
              onDelete: () => _vm.deleteGoal(g.goalId),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          const SizedBox(height: AppSpacing.sm),
          ExerciseTargetPicker(
            detailMap: state.exerciseDetailMap,
            variations: state.allVariations,
            onAdd: (target) => _vm.addGoal(
              exerciseId: target.exerciseId,
              exerciseName: target.exerciseName,
              variationId: target.variationId,
              targetWeight: target.weight,
              targetReps: target.reps,
              blockId: block!.blockId,
            ),
          ),
        ],
      ],
    );
  }

  /// Offers the program's unassigned workouts, and assigns the chosen one here.
  Future<void> _addWorkouts() async {
    final unassigned = _vm.blockGroups
        .where((g) => g.isUnassigned)
        .expand((g) => g.workouts)
        .toList();
    if (unassigned.isEmpty) {
      _snack('No unassigned workouts to add.');
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
                'Add to ${widget.block!.name}',
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
    await _vm.assignWorkoutToBlock(picked.sessionId, widget.block!.blockId);
  }

  Future<void> _confirmArchive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Remove Block',
          style: AppFonts.ui(
            fontWeight: FontWeight.w800,
            color: AppColors.danger,
          ),
        ),
        content: Text(
          'This block is removed from the program. Its workouts stay in the '
          'program, unassigned — nothing is deleted.',
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
    if (ok != true || !mounted) return;
    await _vm.archiveBlock(widget.block!.blockId);
    if (mounted) Navigator.of(context).pop(true);
  }
}

/// A tappable date field.
///
/// A null [onTap] renders it inert — how `Ends` reads in weeks mode before
/// there is a `Starts` to project it from — and [hint] is where such a field
/// says why, since a greyed control with no explanation is just a dead end.
///
/// Dates render `d MMM yyyy`, the app's spelling everywhere else; this field
/// was the last one still writing `d/m/yyyy`.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
    this.onClear,
    this.hint = 'Pick a date…',
  });

  final String label;
  final DateTime? date;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppFonts.ui(
            fontSize: AppTextStyles.sm,
            fontWeight: FontWeight.w600,
            color: enabled ? AppColors.primary : AppColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onTap,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              decoration: glassBox(AppColors.primary, radius: AppRadius.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      date == null
                          ? hint
                          : DateFormat('d MMM yyyy').format(date!),
                      style: AppFonts.ui(
                        color: date != null && enabled
                            ? AppColors.primary
                            : AppColors.muted,
                      ),
                    ),
                  ),
                  if (onClear != null)
                    GestureDetector(
                      onTap: onClear,
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: AppColors.muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
