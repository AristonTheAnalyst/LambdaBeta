import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/planned_session.dart';
import '../../../shared/mixins/unsaved_changes_guard.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/segmented_control.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/stats_row.dart';
import '../viewmodel/program_detail_viewmodel.dart';

const _dayOfWeekOptions = [
  SegmentOption<int?>(label: 'Mon', value: 1),
  SegmentOption<int?>(label: 'Tue', value: 2),
  SegmentOption<int?>(label: 'Wed', value: 3),
  SegmentOption<int?>(label: 'Thu', value: 4),
  SegmentOption<int?>(label: 'Fri', value: 5),
  SegmentOption<int?>(label: 'Sat', value: 6),
  SegmentOption<int?>(label: 'Sun', value: 7),
];

/// Full-screen planned-workout editor that mirrors the active-session UX:
/// tabbed by exercise, inline editable set grid (PlanSetRow), auto-commit on
/// blur, Lessons/History per exercise, swipe-to-reveal delete/duplicate.
/// Pushed via [program_detail_screen.dart] on create or edit.
class PlanSessionScreen extends StatefulWidget {
  const PlanSessionScreen({
    super.key,
    required this.viewModel,
    this.workout,
    this.standalone = false,
    this.standaloneWorkoutId,
  });

  final ProgramDetailViewModel viewModel;
  final PlannedSession? workout; // null = new workout

  /// When true, a new workout is a standalone workout (no program).
  final bool standalone;

  /// When set, opens an existing standalone workout for editing.
  final String? standaloneWorkoutId;

  @override
  State<PlanSessionScreen> createState() => _PlanSessionScreenState();
}

class _PlanSessionScreenState extends State<PlanSessionScreen>
    with UnsavedChangesGuard<PlanSessionScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _notesCtrl;
  final _nameFocus = FocusNode();
  final _notesFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Initialize controllers from the workout param directly, NOT from the
    // viewmodel state (which may be stale from a previous closeWorkoutEditor).
    // This ensures the TextField shows the correct text from the start.
    _nameCtrl = TextEditingController(
      text: widget.workout?.name ?? 'New Session',
    );
    // Session Notes is hidden from the UI for now — the controller and
    // commit plumbing stay so re-enabling is a one-line addition.
    _notesCtrl = TextEditingController(text: widget.workout?.notes ?? '');
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) widget.viewModel.commitWorkoutName();
    });
    _notesFocus.addListener(() {
      if (!_notesFocus.hasFocus) widget.viewModel.commitWorkoutNotes();
    });
    widget.viewModel.loadHistoryIfNeeded();
    // Defer viewmodel state mutations past the first frame so the
    // ValueListenableBuilder doesn't try to rebuild during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sid = widget.standaloneWorkoutId;
      if (sid != null) {
        widget.viewModel.openStandaloneWorkout(sid);
      } else if (widget.workout != null) {
        widget.viewModel.openEditWorkout(widget.workout!);
      } else if (widget.standalone) {
        widget.viewModel.createStandaloneWorkoutAndOpen();
      } else {
        widget.viewModel.createWorkoutAndOpen();
      }
      // The VM may generate a bumped name ("New Session 2") after open —
      // sync the header controller so the editor shows the real name.
      final draft = widget.viewModel.state.value.workoutNameDraft;
      if (draft.isNotEmpty && _nameCtrl.text != draft) {
        _nameCtrl.text = draft;
      }
    });
  }

  @override
  void dispose() {
    // Final commit on dispose in case the user navigates back without blurring.
    // Must happen before controller disposal — commit methods can trigger state
    // updates that rebuild widgets referencing these controllers.
    widget.viewModel.commitWorkoutName();
    widget.viewModel.commitWorkoutNotes();
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    _nameFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  // ── UnsavedChangesGuard ─────────────────────────────────────────────────

  @override
  bool get hasUnsavedChanges =>
      widget.viewModel.state.value.workoutUnsavedChanges;

  @override
  Future<void> onSave() async {
    // Blur first — set cells commit on focus loss; Save must persist the
    // typed values.
    FocusManager.instance.primaryFocus?.unfocus();
    await widget.viewModel.saveWorkout();
  }

  @override
  void onDiscard() {
    // If the workout has no exercises, treat it as abandoned — delete it from
    // the DB rather than leaving an empty orphan row.
    if (widget.viewModel.state.value.workoutExerciseSlots.isEmpty) {
      widget.viewModel.deletePlannedSession();
    } else {
      widget.viewModel.closeWorkoutEditor();
    }
  }

  /// A nav-bar tab tap: run the unsaved-changes guard, then leave the
  /// editor and jump to the tapped tab.
  Future<void> _onNavTap(String route) async {
    final router = GoRouter.of(context);
    if (!await confirmBack()) return;
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    router.go(route);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProgramDetailState>(
      valueListenable: widget.viewModel.state,
      builder: (context, state, _) {
        final workout = state.editingWorkout;
        if (workout == null) {
          final err = state.error;
          if (err != null) {
            // A failed open must never hang on the loading spinner — show the
            // reason and a way out instead.
            return Scaffold(
              backgroundColor: AppColors.bg,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Could not open workout',
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.lg,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        err,
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.sm,
                          color: AppColors.danger,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(context, rootNavigator: true).pop(),
                        child: Text(
                          'Close',
                          style: AppFonts.ui(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return Scaffold(
            backgroundColor: AppColors.bg,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          );
        }
        return buildGuardedScaffold(
          scaffold: Scaffold(
            backgroundColor: AppColors.bg,
            // The editor is pushed full-screen (root navigator), which covers
            // the tab shell — re-render the shared nav bar so tab navigation
            // stays available while editing. Tab taps run the unsaved-changes
            // guard before leaving.
            bottomNavigationBar: BottomNavBar(
              currentRoute: '/exercises',
              onTap: _onNavTap,
            ),
            body: Column(
              children: [
                _editableHeader(
                  state.workoutUnsavedChanges,
                  state.workoutExerciseSlots.isEmpty,
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
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.xxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Session Notes is hidden from the frontend for now
                        // (the VM plumbing stays — see initState).
                        if (state.isCalendarMode) ...[
                          Text(
                            'Day of week',
                            style: AppFonts.ui(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SegmentedControl<int?>(
                            options: _dayOfWeekOptions,
                            value: state.workoutDayOfWeekDraft,
                            onChange: (v) =>
                                widget.viewModel.commitWorkoutDayOfWeek(v),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        if (state.workoutSetsLoading)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: CircularProgressIndicator(
                                color: AppColors.accent,
                              ),
                            ),
                          )
                        else if (state.workoutExerciseSlots.isEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          GestureDetector(
                            onTap: _showAddExercise,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.xxl,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.fitness_center_outlined,
                                    size: 32,
                                    color: AppColors.muted,
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    'Tap to add an exercise',
                                    style: AppFonts.ui(
                                      fontSize: AppTextStyles.md,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    'A workout needs at least one exercise',
                                    style: AppFonts.ui(
                                      fontSize: AppTextStyles.xs,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else if (state.activeSlot != null)
                          _PlanExerciseCard(
                            viewModel: widget.viewModel,
                            slot: state.activeSlot!,
                            onAddExercise: _showAddExercise,
                            onRemoveExercise: () =>
                                _confirmRemoveExercise(state.activeSlotIndex),
                          ),
                      ],
                    ),
                  ),
                ),
                // Sticky bottom: SETS/EXERCISES, greyed — mirrors the live
                // session's bottom stats bar; greyed because planning has no
                // live data to summarize.
                Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    border: Border(
                      top: BorderSide(color: AppColors.border, width: 0.5),
                    ),
                  ),
                  child: _PlanStatsBar(
                    setCount: state.workoutPlannedSessionSets.length,
                    exerciseCount: state.workoutExerciseSlots.length,
                    greyed: true,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _editableHeader(bool unsaved, bool noExercises) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: topPadding),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SizedBox(
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 16,
              child: GestureDetector(
                onTap: () async {
                  // Blur first — set cells commit on focus loss, and the
                  // back guard must see the typed values.
                  FocusManager.instance.primaryFocus?.unfocus();
                  if (await confirmBack() && mounted) {
                    Navigator.of(context, rootNavigator: true).pop();
                  }
                },
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
            ),
            Positioned(
              left: 88,
              right: 88,
              top: 0,
              bottom: 0,
              child: Center(
                child: TextField(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.words,
                  style: AppFonts.ui(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Session name',
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  onChanged: widget.viewModel.setWorkoutNameDraft,
                ),
              ),
            ),
            Positioned(
              right: 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (unsaved && !noExercises)
                    GestureDetector(
                      onTap: () => widget.viewModel.saveWorkout(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.successBg,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.success),
                        ),
                        child: Text(
                          'Save',
                          style: AppFonts.ui(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _confirmDelete,
                    child: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppColors.danger,
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

  void _confirmRemoveExercise(int index) {
    final state = widget.viewModel.state.value;
    if (index < 0 || index >= state.workoutExerciseSlots.length) return;
    final slot = state.workoutExerciseSlots[index];
    final name = toProperCase(
      state.exerciseDetailMap[slot.exerciseId]?.name ?? 'exercise',
    );
    final setCount = state.plannedSetsFor(slot.exerciseSequenceOrder).length;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Remove Exercise',
          style: AppFonts.ui(
            fontWeight: FontWeight.w800,
            color: AppColors.danger,
          ),
        ),
        content: Text(
          'Remove $name from this workout?\n$setCount set${setCount == 1 ? '' : 's'} will be removed.',
          style: AppFonts.ui(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Keep', style: AppFonts.ui(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.viewModel.removePlannedExerciseGroup(index);
            },
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
  }

  void _confirmDelete() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Delete Session',
          style: AppFonts.ui(
            fontWeight: FontWeight.w800,
            color: AppColors.danger,
          ),
        ),
        content: Text(
          'Remove this planned workout and its sets?',
          style: AppFonts.ui(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: AppFonts.ui(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              // Await the delete BEFORE popping the editor — the library
              // reloads on return, and an un-awaited delete races that
              // reload (the deleted workout would still be listed).
              await widget.viewModel.deletePlannedSession();
              if (mounted) {
                Navigator.of(context, rootNavigator: true).pop();
              }
            },
            child: Text(
              'Delete',
              style: AppFonts.ui(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddExercise() {
    showLambdaModal(
      context,
      fitContent: true,
      keyboardAware: true,
      child: _AddExerciseContent(viewModel: widget.viewModel),
    );
  }
}

// ── Stats Bar ────────────────────────────────────────────────────────────────

class _PlanStatsBar extends StatelessWidget {
  const _PlanStatsBar({
    required this.setCount,
    required this.exerciseCount,
    this.greyed = false,
  });

  final int setCount;
  final int exerciseCount;
  final bool greyed;

  @override
  Widget build(BuildContext context) {
    return StatsRow(
      tiles: [
        StatsTile(label: 'SETS', value: '$setCount', greyed: greyed),
        StatsTile(label: 'EXERCISES', value: '$exerciseCount', greyed: greyed),
      ],
    );
  }
}

// ── Exercise Card ─────────────────────────────────────────────────────────────

/// The planner's exercise card — an adapter over the shared
/// [SessionExerciseCard] with planned-mode rows (targets, not logged sets).
/// Lessons/History/PRs stay greyed by decision even though the VM holds
/// lesson/history data: planning is about targets, and those surfaces stay
/// disabled until they get planner wiring.
class _PlanExerciseCard extends StatelessWidget {
  const _PlanExerciseCard({
    required this.viewModel,
    required this.slot,
    required this.onAddExercise,
    required this.onRemoveExercise,
  });

  final ProgramDetailViewModel viewModel;
  final PlanExerciseSlot slot;
  final VoidCallback onAddExercise;
  final VoidCallback onRemoveExercise;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final s = vm.state.value;
    final exerciseId = slot.exerciseId;
    final order = slot.exerciseSequenceOrder;
    final sets = s.plannedSetsFor(order);
    final draftIds = s.workoutSetDrafts[order] ?? const <int>[];

    final variationOptions = [
      const DropdownOption<String?>(label: 'No Variation', value: null),
      ...vm.variationsByRecency.map(
        (v) => DropdownOption<String?>(label: v.name, value: v.variationId),
      ),
    ];
    final allVariations = [
      for (final v in s.allVariations) (id: v.variationId, name: v.name),
    ];

    List<Widget> rows = [];
    for (var i = 0; i < sets.length; i++) {
      final set = sets[i];
      rows.add(
        SessionSetRow(
          key: ValueKey(set.setId),
          mode: SetRowMode.planned,
          exerciseId: exerciseId,
          displayIndex: i + 1,
          isDraft: false,
          initialWeightText: set.targetWeight ?? '',
          initialRepsText: set.targetReps ?? '',
          initialVariationId: set.variationId,
          initialVariationName: set.variationName,
          initialNotes: set.targetNotes,
          hasNotes: set.targetNotes?.isNotEmpty ?? false,
          onCommit: (isDraft, v) async {
            if (!isDraft) {
              await vm.quickUpdatePlannedSessionSet(
                set,
                weight: v.weight,
                clearWeight: v.weight == null,
                reps: v.reps,
                clearReps: v.reps == null,
              );
            }
          },
          onVariationChanged: (id) => vm.quickUpdatePlannedSessionSet(
            set,
            variationId: id,
            clearVariation: id == null,
          ),
          onNotesSave: (v) => vm.quickUpdatePlannedSessionSet(
            set,
            notes: v.trim().isEmpty ? null : v.trim(),
            clearNotes: v.trim().isEmpty,
          ),
          onDelete: () => vm.deletePlannedSessionSet(set.setId),
          onDuplicate: () => vm.duplicatePlannedSessionSet(set),
          variationOptions: variationOptions,
          allVariations: allVariations,
          findSimilarVariations: vm.findSimilarVariations,
          submitNewVariation: vm.submitNewVariation,
        ),
      );
    }
    for (var i = 0; i < draftIds.length; i++) {
      final draftId = draftIds[i];
      rows.add(
        SessionSetRow(
          key: ValueKey('draft-$draftId'),
          mode: SetRowMode.planned,
          exerciseId: exerciseId,
          displayIndex: sets.length + i + 1,
          isDraft: true,
          initialWeightText: '',
          initialRepsText: '',
          initialVariationId: null,
          hasNotes: false,
          onCommit: (isDraft, v) async {
            if (isDraft) {
              await vm.quickCreatePlannedSessionSet(
                exerciseId: exerciseId,
                exerciseSequenceOrder: order,
                draftId: draftId,
                variationId: v.variationId,
                weight: v.weight,
                reps: v.reps,
                notes: v.notes,
              );
            }
          },
          onVariationChanged: (_) {},
          onNotesSave: (_) {},
          onDelete: () async => vm.removeDraftPlannedSessionSet(order, draftId),
          onDuplicate: () {},
          variationOptions: variationOptions,
          allVariations: allVariations,
          findSimilarVariations: vm.findSimilarVariations,
          submitNewVariation: vm.submitNewVariation,
        ),
      );
    }

    return SessionExerciseCard(
      exerciseNames: [
        for (final slot in s.workoutExerciseSlots)
          toProperCase(s.exerciseDetailMap[slot.exerciseId]?.name ?? ''),
      ],
      activeIndex: s.activeSlotIndex,
      onSelect: (i) => vm.tapTab(i),
      onMove: (i, dir) => vm.reorderExercises(i, i + dir),
      onAdd: onAddExercise,
      onDeleteRequest: onRemoveExercise,
      lessonsCount: 0,
      onLessonsTap: null,
      prCount: 0,
      onPrTap: null,
      rows: rows,
      onAddSet: () => vm.addDraftPlannedSessionSet(order),
      history: null,
    );
  }
}

class _AddExerciseContent extends StatefulWidget {
  const _AddExerciseContent({required this.viewModel});

  final ProgramDetailViewModel viewModel;

  @override
  State<_AddExerciseContent> createState() => _AddExerciseContentState();
}

class _AddExerciseContentState extends State<_AddExerciseContent> {
  String _query = '';

  List<MapEntry<String, String>> get _filtered {
    final s = widget.viewModel.state.value;
    final entries = s.exerciseDetailMap.entries
        .where(
          (e) => toProperCase(
            e.value.name,
          ).toLowerCase().contains(_query.toLowerCase()),
        )
        .map((e) => MapEntry(e.key, toProperCase(e.value.name)))
        .toList();
    // Most recently used first (newest history session per exercise, nulls
    // last), then name.
    final lastUsed = <String, DateTime>{};
    for (final sessions in s.historyByExercise.values) {
      if (sessions.isNotEmpty) {
        lastUsed[sessions.first.sets.first.exerciseId] = sessions.first.date;
      }
    }
    entries.sort((a, b) {
      final da = lastUsed[a.key];
      final db = lastUsed[b.key];
      if (da != null && db != null) return db.compareTo(da);
      if (da != null) return -1;
      if (db != null) return 1;
      return a.value.toLowerCase().compareTo(b.value.toLowerCase());
    });
    return entries;
  }

  bool get _canCreate =>
      _query.trim().length > 1 &&
      !widget.viewModel.state.value.exerciseDetailMap.values.any(
        (e) => e.name.toLowerCase() == _query.trim().toLowerCase(),
      );

  void _pick(String exerciseId) {
    widget.viewModel.addPlannedExerciseGroup(exerciseId);
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _createNew() async {
    final id = await widget.viewModel.submitNewExercise(_query);
    if (id == null || !mounted) return;
    _pick(id);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Add exercise',
                    style: AppFonts.ui(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: Icon(Icons.close, size: 20, color: AppColors.muted),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              autofocus: true,
              style: AppFonts.ui(fontSize: 14, color: AppColors.primary),
              decoration: InputDecoration(
                hintText: 'Search exercises…',
                hintStyle: AppFonts.ui(color: AppColors.muted),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: AppColors.muted,
                ),
                filled: true,
                fillColor: AppColors.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ValueListenableBuilder<ProgramDetailState>(
                valueListenable: widget.viewModel.state,
                builder: (context, state, _) => ListView(
                  shrinkWrap: true,
                  children: [
                    ..._filtered.map(
                      (e) => _resultRow(e.value, () => _pick(e.key)),
                    ),
                    if (_canCreate)
                      _resultRow(
                        '+ Create "${_query.trim()}"',
                        state.newExCreating ? null : _createNew,
                        accent: true,
                      ),
                    if (_filtered.isEmpty &&
                        !_canCreate &&
                        _query.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ),
                        child: Center(
                          child: Text(
                            'No exercises found',
                            style: AppFonts.ui(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultRow(String label, VoidCallback? onTap, {bool accent = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: accent
                  ? AppColors.accent.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppFonts.ui(
              fontSize: 14,
              fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
              color: accent ? AppColors.accent : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
