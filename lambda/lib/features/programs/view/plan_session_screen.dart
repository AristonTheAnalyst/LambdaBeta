import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/planned_session.dart';
import '../../../shared/mixins/unsaved_changes_guard.dart';
import '../../../shared/widgets/add_exercise_modal.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../../../shared/widgets/stats_row.dart';
import '../viewmodel/workout_editor_viewmodel.dart';

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

  final WorkoutEditorViewModel viewModel;
  final PlannedSession? workout; // null = new workout

  /// When true, a new workout is a standalone workout (no program).
  final bool standalone;

  /// When set, opens an existing standalone workout for editing.
  final String? standaloneWorkoutId;

  @override
  State<PlanSessionScreen> createState() => _PlanSessionScreenState();
}

class _PlanSessionScreenState extends State<PlanSessionScreen>
    with UnsavedChangesGuard<PlanSessionScreen>, WidgetsBindingObserver {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _notesCtrl;
  final _nameFocus = FocusNode();
  final _notesFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final sid = widget.standaloneWorkoutId;
      if (sid != null) {
        // Awaited: the standalone open loads its name asynchronously and the
        // sync below must see the loaded draft — otherwise the header keeps
        // the 'New Session' seed forever.
        await widget.viewModel.openStandaloneWorkout(sid);
      } else if (widget.workout != null) {
        await widget.viewModel.openEditWorkout(widget.workout!);
      } else if (widget.standalone) {
        await widget.viewModel.createStandaloneWorkoutAndOpen();
      } else {
        await widget.viewModel.createWorkoutAndOpen();
      }
      // The VM may generate a bumped name ("New Session 2") after open —
      // sync the header controller so the editor shows the real name.
      if (!mounted) return;
      final draft = widget.viewModel.state.value.workoutNameDraft;
      if (draft.isNotEmpty && _nameCtrl.text != draft) {
        _nameCtrl.text = draft;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The live session's rule, which the planner was missing: a draft row
    // commits on blur alone, so backgrounding the app — or a kill right after
    // — would drop the variation and note the row is holding for it.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      widget.viewModel.flushPendingCommits();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    // Roll back to the open-time snapshot (or last Save): header fields and
    // sets. A workout created this editing session rolls back to
    // nonexistence; one with no exercises left after a full rollback is
    // removed rather than kept as an empty orphan.
    widget.viewModel.discardWorkoutChanges();
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
    return ValueListenableBuilder<WorkoutEditorState>(
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
                        // (the VM plumbing stays — see initState). Day-of-week
                        // scheduling is retired for now: a workout is a list
                        // of exercises, and nothing assigns it to a weekday.
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
                              decoration: lambdaBox(ContainerTone.surface, radius: 
                                  AppRadius.lg,
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
                    setCount: state.workoutPlannedSessionExerciseSets.length,
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
                        // The glass recipe in success — the pressable chrome.
                        decoration: glassBox(AppColors.success),
                        child: Text(
                          'Save',
                          style: AppFonts.ui(
                            fontSize: 14,
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
    final setCount = state
        .plannedSetsFor(slot.plannedExerciseId ?? '')
        .length;

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
    final vm = widget.viewModel;
    showAddExerciseModal(
      context,
      listenable: vm.state,
      entries: () {
        final s = vm.state.value;
        return [
          for (final e in s.exerciseDetailMap.values)
            AddExerciseEntry(
              exerciseId: e.exerciseId,
              name: toProperCase(e.name),
              lastUsed: lastUsedFromHistory(
                s.historyByExercise,
                e.exerciseId,
              ),
            ),
        ];
      },
      isAdded: (id) => vm.state.value.workoutExerciseSlots.any(
        (slot) => slot.exerciseId == id,
      ),
      onAdd: vm.addPlannedExerciseGroup,
      onRemoveRequest: (id) async {
        final i = vm.state.value.workoutExerciseSlots.indexWhere(
          (slot) => slot.exerciseId == id,
        );
        if (i >= 0) _confirmRemoveExercise(i);
      },
      onCreate: vm.submitNewExercise,
      isCreating: () => vm.state.value.newExCreating,
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
  });

  final WorkoutEditorViewModel viewModel;
  final PlanExerciseSlot slot;
  final VoidCallback onAddExercise;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final s = vm.state.value;
    final exerciseId = slot.exerciseId;
    final plannedExerciseId = slot.plannedExerciseId ?? '';
    final sets = s.plannedSetsFor(plannedExerciseId);
    final draftIds = s.workoutSetDrafts[plannedExerciseId] ?? const <int>[];

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
          key: ValueKey(set.plannedSetId),
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
          onRegisterCommit: vm.registerCommitHandle,
          onUnregisterCommit: vm.unregisterCommitHandle,
          onCommit: (isDraft, v) async {
            if (!isDraft) {
              await vm.quickUpdatePlannedSessionExerciseSet(
                set,
                weight: v.weight,
                clearWeight: v.weight == null,
                reps: v.reps,
                clearReps: v.reps == null,
              );
            }
          },
          onVariationChanged: (id) => vm.quickUpdatePlannedSessionExerciseSet(
            set,
            variationId: id,
            clearVariation: id == null,
          ),
          onNotesSave: (v) => vm.quickUpdatePlannedSessionExerciseSet(
            set,
            notes: v.trim().isEmpty ? null : v.trim(),
            clearNotes: v.trim().isEmpty,
          ),
          onDelete: () => vm.deletePlannedSessionExerciseSet(set.plannedSetId),
          onDuplicate: () => vm.duplicatePlannedSessionExerciseSet(set),
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
          // Registered like a real row's: a draft's variation and notes live in
          // the row until it commits, and the commit that saves them is
          // whatever destroys or flushes the row — the exercise switch above
          // all, since only the active card is built.
          onRegisterCommit: vm.registerCommitHandle,
          onUnregisterCommit: vm.unregisterCommitHandle,
          onCommit: (isDraft, v) async {
            if (isDraft) {
              await vm.quickCreatePlannedSessionExerciseSet(
                exerciseId: exerciseId,
                plannedExerciseId: plannedExerciseId,
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
          onDelete: () async => vm.removeDraftPlannedSessionExerciseSet(
            plannedExerciseId,
            draftId,
          ),
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
          toProperCase(vm.exerciseDisplayName(slot.exerciseId)),
      ],
      activeIndex: s.activeSlotIndex,
      onSelect: (i) => vm.tapTab(i),
      onMove: (i, dir) => vm.reorderExercises(i, i + dir),
      onAdd: onAddExercise,
      lessonsCount: 0,
      onLessonsTap: null,
      prCount: 0,
      onPrTap: null,
      rows: rows,
      onAddSet: () => vm.addDraftPlannedSessionExerciseSet(plannedExerciseId),
      history: null,
    );
  }
}
