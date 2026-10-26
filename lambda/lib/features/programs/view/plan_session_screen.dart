import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../shared/widgets/undo_redo_buttons.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../core/utils/name_limit.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/models/program_content.dart';
import '../../../shared/mixins/unsaved_changes_guard.dart';
import '../../../shared/router/app_router.dart';
import '../../../shared/widgets/add_exercise_modal.dart';
import '../../../shared/widgets/bar_icon_button.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/exercise_selector.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/keyboard_floor_layout.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/session_date_bar.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../../session/view/lessons_modal.dart';
import '../../session/view/pr_history_sheet.dart';
import '../../session/view/session_stats_bar.dart';
import '../viewmodel/workout_editor_viewmodel.dart';
import 'review_container.dart';

/// Asks before opening a workout editor while the program it belongs to is
/// running.
///
/// Informational rather than a guard against loss: an edit applies to every
/// session logged from now on, while the sets already logged are snapshots
/// that will not change. Shared by the two ways in — the program's workout
/// list, and a block's rows — because a second copy of this dialog is a second
/// place for the wording to drift, and the two screens are the same promise.
///
/// Returns true when it is fine to proceed.
Future<bool> confirmEditWhileRunning(BuildContext context) async {
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
        style: AppFonts.ui(color: AppColors.inkSecondary, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'Cancel',
            style: AppFonts.ui(color: AppColors.inkSecondary),
          ),
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
  return ok == true;
}

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
    this.newWorkoutBlockId,
    this.reviewSession,
  });

  final WorkoutEditorViewModel viewModel;
  final PlannedSession? workout; // null = new workout

  /// When true, a new workout is a standalone workout (no program).
  final bool standalone;

  /// When set, opens an existing standalone workout for editing.
  final String? standaloneWorkoutId;

  /// The block a brand-new workout is made inside, when the editor was opened
  /// from one. The link is created with it, so the workout is never briefly
  /// unfiled — which matters because a blocked program has no Workouts tab for
  /// an unfiled row to appear in.
  final String? newWorkoutBlockId;

  /// The review this editor was opened under, when it was — handed in by the
  /// review route rather than left to the ambient scope (2026-10-25).
  ///
  /// The scope is how an in-pass editor finds its review, and it works while
  /// the pass runs: the notifier sits above the navigator. But it is a
  /// GLOBAL, and a bar that reads it falls back to the app's tab bar the
  /// moment it is empty — a record's workout, a route left standing after
  /// the pass moved on, a rebuild after a reload. A workout opened from a
  /// review is inside a ceremony for as long as it is on screen, so the
  /// ceremony travels with the route. Null for every editor opened outside
  /// one.
  final ReviewSession? reviewSession;

  @override
  State<PlanSessionScreen> createState() => _PlanSessionScreenState();
}

class _PlanSessionScreenState extends State<PlanSessionScreen>
    with UnsavedChangesGuard<PlanSessionScreen>, WidgetsBindingObserver {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _notesCtrl;
  final _nameFocus = FocusNode();
  final _notesFocus = FocusNode();

  /// The comparison taken mid-pass, held for as long as it is on screen.
  /// Non-null means the editor is showing the workout as the record has it
  /// rather than as the plan holds it — Compare toggles it, and the plan is
  /// untouched underneath, so leaving is only forgetting the record.
  ReviewComparison? _original;

  /// The open workout as the record holds it — non-null while Compare is up.
  /// The comparison is already narrowed to this workout, so there is exactly
  /// one session to read, when there is one at all.
  ContentSession? get _originalSession {
    final sessions = _original?.before?.sessions;
    return (sessions == null || sessions.isEmpty) ? null : sessions.first;
  }

  /// The pass this editor is inside, or null for a plain editor.
  ///
  /// The route's own review is the base — a workout opened from a review stays
  /// in the ceremony even after the ambient scope has gone — with the live
  /// copy read back by id when the notifier still holds this pass, so a Done
  /// tick or an open workout keeps moving the bar. The scope lookup stays on
  /// this path for the editors that were handed no review: it is both their
  /// source and their rebuild dependency.
  ReviewSession? get _reviewSession {
    final scoped = ReviewScope.maybeOf(context);
    final base = widget.reviewSession ?? scoped;
    if (base == null) return null;
    final live = reviewSessionNotifier.value;
    return (live != null && live.reviewId == base.reviewId) ? live : base;
  }

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
        // A review's editor reads the workout with its removals in it: a
        // group deleted during the pass stays on the card, red, so its note
        // can explain why it went (2026-10-26).
        await widget.viewModel.openEditWorkout(
          widget.workout!,
          includeArchived: _reviewSession != null,
        );
      } else if (widget.standalone) {
        await widget.viewModel.createStandaloneWorkoutAndOpen();
      } else {
        await widget.viewModel.createWorkoutAndOpen(
          blockId: widget.newWorkoutBlockId,
        );
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
  Future<void> onDiscard() {
    // Roll back to the open-time snapshot (or last Save): header fields and
    // sets. A workout created this editing session rolls back to
    // nonexistence; one with no exercises left after a full rollback is
    // removed rather than kept as an empty orphan.
    //
    // Awaited — the guard re-reads `hasUnsavedChanges` the moment this
    // returns (2026-10-26). Un-awaited, the pop was decided mid-rollback,
    // the guard declined, and the editor was left standing on its spinner
    // with no workout under it.
    return widget.viewModel.discardWorkoutChanges();
  }

  /// A nav-bar tab tap: run the unsaved-changes guard, then leave the editor
  /// and jump to the tapped tab.
  ///
  /// Under a review the review route is what covers the shell, and this editor
  /// is one of its pages — the whole ceremony has to come down, or the tab
  /// would land behind it. No review means this editor is itself the pushed
  /// route on top, and it pops alone.
  Future<void> _onNavTap(int index) async {
    final router = GoRouter.of(context);
    if (!await confirmBack()) return;
    if (!mounted) return;
    if (!unwindReview(context)) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    router.go(tabRouteAt(index));
  }

  /// Opens one exercise of the open workout — where the review bar's changes
  /// sheet taps through to. The sheet closes itself first, so the switch lands
  /// on the card the user asked for. A group with no slot left (an exercise
  /// removed since the record) has nowhere to land and nothing happens — its
  /// card offers no tap in the first place.
  void _openExercise(String plannedExerciseId) {
    final slots = widget.viewModel.state.value.workoutExerciseSlots;
    final index = slots.indexWhere(
      (slot) => slot.plannedExerciseId == plannedExerciseId,
    );
    if (index < 0) return;
    widget.viewModel.tapTab(index);
  }

  /// This editor's chrome: the app's floating nav bar, which it draws itself
  /// because it is pushed over the tab shell — or, while a review runs, the
  /// review's own bar in the same container.
  ///
  /// The session furniture that used to ride [aboveBar] — the counts pill,
  /// then the review's undo/redo storey — is the page's own floor now
  /// (2026-10-26): [KeyboardFloorLayout] draws it inside the body, so the
  /// floating bar is all that stands on the chrome. The floor still measures
  /// its bottom inset from inside this wrapper, which is why the page is
  /// built by a `Builder` under it.
  ///
  /// Compare is wired here because the record lives here: the bar loads a
  /// comparison and hands it back, and what this screen does with it is swap
  /// its own sets for it — and hand back null when the bar's button is tapped
  /// again.
  Widget _navBar(Widget child) => editorNavBar(
    context,
    child: child,
    session: _reviewSession,
    onTap: _onNavTap,
    settle: settleForReview,
    settleForCompare: settleForCompare,
    comparing: _original != null,
    onExerciseTap: _openExercise,
    onComparison: (comparison) {
      // Rows re-seed their cells when the flip happens, and deliberately leave
      // a focused cell alone — a commit reload must never eat what is being
      // typed. Comparing is not a commit reload: the keyboard goes with it, so
      // the record can never land under a half-updated, still-focused cell.
      if (comparison != null) FocusScope.of(context).unfocus();
      setState(() => _original = comparison);
    },
  );

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
            // A review can open onto this: the pass keeps its way out even
            // when the editor underneath never arrived. No Finish — nothing
            // has been examined, so there is nothing to record.
            return Scaffold(
              backgroundColor: AppColors.bg,
              body: reviewChrome(
                context,
                settle: null,
                // The route's own pass, like the bar below it (2026-10-25).
                session: _reviewSession,
                child: Center(
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
              ),
            );
          }
          return Scaffold(
            backgroundColor: AppColors.bg,
            body: reviewChrome(
              context,
              settle: null,
              session: _reviewSession,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            ),
          );
        }
        // The record, when Compare is up. Read once here: it decides what the
        // body shows, and the exercise card draws from it.
        final original = _originalSession;
        return _navBar(
          buildGuardedScaffold(
            scaffold: Scaffold(
              backgroundColor: AppColors.bg,
              // The keyboard paints over the floor instead of lifting it
              // (2026-10-25), the same rule the session surfaces follow: the
              // nav or review bar keeps its place and the page's scroll
              // shrinks its viewport to the keyboard's top.
              resizeToAvoidBottomInset: false,
              // The editor is pushed full-screen (root navigator), which covers
              // the tab shell — so it draws the app's floating bar itself. Tab
              // taps run the unsaved-changes guard before leaving; while a
              // review runs, the pass's own bar takes that bar's place.
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
                    // The floor keeps its place under the keyboard, the
                    // session surfaces' rule (2026-10-25): it is laid out
                    // first and the page above it shrinks to the keyboard's
                    // top, so a focused target cell is revealed above the
                    // keyboard rather than behind it.
                    //
                    // The Builder is load-bearing: the floor measures the
                    // floating bar it stands under through
                    // `ScrollShrinkNavBar.contentInset`, which only answers
                    // from a context INSIDE `_navBar`'s wrapper.
                    child: Builder(
                      builder: (context) => KeyboardFloorLayout(
                        page: SingleChildScrollView(
                          // The viewer's own insets — the card opens on the
                          // same 22pt gutter, from the same 16 of air under
                          // the header (2026-10-26).
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.lg,
                            AppSpacing.lg,
                            AppSpacing.lg,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Session Notes is hidden from the frontend for now
                              // (the VM plumbing stays — see initState). Day-of-week
                              // scheduling is retired for now: a workout is a list
                              // of exercises, and nothing assigns it to a weekday.
                              //
                              // Compare does not change the page: the same card
                              // draws the same workout, with the record's rows in
                              // place of the plan's (`original` below). The card's
                              // tabs and buttons hold their places — the flip is
                              // values only — and the note box flips its words
                              // with them: the record's own note, labelled as the
                              // record's, while the record is up. Which is what
                              // the bar's label is there to tell apart.
                              if (state.workoutSetsLoading)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.lg,
                                    ),
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
                                    decoration: lambdaBox(
                                      ContainerTone.surface,
                                      radius: AppRadius.lg,
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
                                            color: AppColors.inkSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                        Text(
                                          'A workout needs at least one exercise',
                                          style: AppFonts.ui(
                                            fontSize: AppTextStyles.xs,
                                            color: AppColors.inkSecondary,
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
                                  original: original,
                                  originalNotes:
                                      _original?.beforeNotes ?? const {},
                                ),
                            ],
                          ),
                        ),
                        floor: _planFloor(context, state, original),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _editableHeader(bool unsaved, bool noExercises) {
    final topPadding = MediaQuery.of(context).padding.top;
    // Inside a review the header keeps no Delete: the trash deletes the
    // planned workout, which is not what a pass is doing — taking a workout
    // OUT of a review is the landing's swipe. The pass's own verbs (the
    // workout's note among them) are on its bar, at the floor.
    final review = _reviewSession;
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
              child: HeaderIconButton(
                icon: Icons.arrow_back_ios_new,
                semanticsLabel: 'Back',
                glyphSize: 18,
                color: AppColors.primary,
                onPressed: () async {
                  // Blur first — set cells commit on focus loss, and the
                  // back guard must see the typed values.
                  FocusManager.instance.primaryFocus?.unfocus();
                  if (await confirmBack() && mounted) {
                    Navigator.of(context, rootNavigator: true).pop();
                  }
                },
              ),
            ),
            Positioned(
              // The symmetric 88-band every header uses (PageHeader's), so
              // the name is centred on the SCREEN — not on the gap left
              // between the back chevron and the chips.
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
                  // A header title has no room for a counter under it — the
                  // field stops at the cap, which is the same hard stop the
                  // workout cards enforce.
                  maxLength: kMaxWorkoutNameLength,
                  style: AppFonts.ui(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Session name',
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  onChanged: widget.viewModel.setWorkoutNameDraft,
                ),
              ),
            ),
            Positioned(
              // Every control in this row is a box now — the bare glyphs wear
              // [HeaderIconButton]'s 44px target — so the row takes the header
              // inset its neighbours use, not the tighter one a bare glyph's
              // own bearing answered for.
              right: 16,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Undo/redo live on the floor in both modes (2026-10-26):
                  // the editor wears the session floor now, and the header
                  // keeps only the verbs that belong to the workout's
                  // identity.
                  if (unsaved && !noExercises) ...[
                    GlassButton(
                      label: '',
                      icon: Icons.check,
                      semanticsLabel: 'Save workout',
                      color: AppColors.success,
                      compact: true,
                      onPressed: () => widget.viewModel.saveWorkout(),
                    ),
                    if (review == null) const SizedBox(width: AppSpacing.xs),
                  ],
                  if (review == null)
                    HeaderIconButton(
                      icon: Icons.delete_outline,
                      semanticsLabel: 'Delete workout',
                      color: AppColors.danger,
                      onPressed: _confirmDelete,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The planner's floor (2026-10-26): the session floors' own furniture, so
  /// planning reads as the same screen as logging — the same date bar, the
  /// same row of 48pt squares, the same tiles.
  ///
  /// What the planner cannot do, it draws spent rather than omitting, the
  /// session floors' own rule for a null callback:
  ///
  /// * the date bar is [SessionDateBar.plan] — a template is planned *for*
  ///   sessions, so its phrase reads `PLAN` and both chevrons are greyed;
  /// * the star is a session's ratings, and a plan has no session: greyed;
  /// * the trash restores deleted sets, and the planner deletes groups
  ///   outright (undo is the way back): greyed.
  ///
  /// The tiles are the one live door. A plan is *informed* by what the
  /// exercise has done — every PR it ever landed, every note it carries — so
  /// the trophy opens the PR History sheet and the note opens the exercise
  /// notes modal, both scoped to the exercise on the card. The counts are
  /// whole shelves, not a session gain, so the tiles draw `gain: false`
  /// (2026-10-26).
  ///
  /// Undo/redo answer as they always have — and stay spent while Compare is
  /// up, because the record on screen is not the plan underneath.
  Widget _planFloor(
    BuildContext context,
    WorkoutEditorState state,
    ContentSession? original,
  ) {
    final vm = widget.viewModel;
    final exerciseId = state.activeSlot?.exerciseId;
    final locked = original != null;
    return Container(
      key: const ValueKey('plan-session-bar'),
      // The session floor's insets — the bottom one included: the page sits
      // under the floating bar, so the row ends where the live page's does.
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        ScrollShrinkNavBar.contentInset(context),
      ),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SessionDateBar.plan(),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              UndoRedoButtons(
                canUndo: vm.canUndo && !locked,
                canRedo: vm.canRedo && !locked,
                onUndo: vm.undo,
                onRedo: vm.redo,
                // The trash keeps its slot and stays spent: a planner's
                // deletion is a group, and undo is its way back.
                deletedExercises: const [],
                onPickDeletedExercise: (_) {},
              ),
              const SizedBox(width: AppSpacing.sm),
              BarIconButton(
                key: const ValueKey('plan-ratings-button'),
                icon: Icons.star_rounded,
                semanticsLabel: 'Session ratings',
                onPressed: () {},
                enabled: false,
                color: AppColors.accent,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SessionStatsTiles(
                  prCount: exerciseId == null ? 0 : vm.prCountFor(exerciseId),
                  lessonCount: exerciseId == null
                      ? 0
                      : vm.lessonCountFor(exerciseId),
                  // A plan gains nothing: the counts are the whole shelves
                  // behind the doors.
                  gain: false,
                  onPrTap: exerciseId == null
                      ? null
                      : () => _openPrHistory(exerciseId),
                  onLessonTap: exerciseId == null
                      ? null
                      : () => _openLessons(exerciseId),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The floor's trophy: the active exercise's PR History, drawn by the same
  /// sheet the session surfaces open. A plan has no session to narrow
  /// against, so the sheet is handed no set ids and no start — every PR is
  /// history — and, when a review stands behind the editor, the pass's own
  /// window so PRs landed since it lead the feed (2026-10-26).
  void _openPrHistory(String exerciseId) {
    showPrHistorySheet(
      context,
      exerciseName: toProperCase(
        widget.viewModel.exerciseDisplayName(exerciseId),
      ),
      prs: widget.viewModel.prHistoryFor(exerciseId),
      sessionSetIds: const <String>{},
      sinceLastReviewAt: _reviewSession?.sinceDate,
    );
  }

  /// The floor's note: the active exercise's exercise notes, through the
  /// session's own modal and the editor's own lesson callbacks — so a note
  /// can be written, pinned and edited while planning, exactly as it can
  /// while logging (2026-10-26). No session id and no start: the shelves are
  /// the exercise's whole story, split by the pass's window when one stands
  /// behind the editor.
  void _openLessons(String exerciseId) {
    final vm = widget.viewModel;
    showLessonsModal(
      context,
      listenable: vm.state,
      lessonsFor: vm.lessonsFor,
      loadLessonsFor: vm.loadLessonsFor,
      addLesson: vm.addLesson,
      toggleLessonPin: vm.toggleLessonPin,
      deleteLesson: vm.deleteLesson,
      updateLesson: vm.updateLessonText,
      exerciseId: exerciseId,
      exerciseName: toProperCase(vm.exerciseDisplayName(exerciseId)),
      sinceLastReviewAt: _reviewSession?.sinceDate,
    );
  }

  void _confirmRemoveExercise(int index) {
    final state = widget.viewModel.state.value;
    if (index < 0 || index >= state.workoutExerciseSlots.length) return;
    final slot = state.workoutExerciseSlots[index];
    // Already removed (a review's read keeps it on the card): there is
    // nothing left to remove, and undo is the way back (2026-10-26).
    if (slot.deleted) return;
    final name = toProperCase(
      state.exerciseDetailMap[slot.exerciseId]?.name ?? 'exercise',
    );
    final setCount = state.plannedSetsFor(slot.plannedExerciseId ?? '').length;

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
          // Inside a review the removal is a change worth explaining, so the
          // card keeps the removed group on screen, red, until the pass
          // finishes — the note beside it is where the reason goes. Outside a
          // review the planner hides it like it always has (2026-10-26).
          _reviewSession == null
              ? 'Remove $name from this workout?\n$setCount set${setCount == 1 ? '' : 's'} will be removed.'
              : 'Remove $name from this workout?\nIt stays on the card, red, so the review note can say why.',
          style: AppFonts.ui(color: AppColors.inkSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Keep',
              style: AppFonts.ui(color: AppColors.inkSecondary),
            ),
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
          style: AppFonts.ui(color: AppColors.inkSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: AppFonts.ui(color: AppColors.inkSecondary),
            ),
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
              lastUsed: lastUsedFromHistory(s.historyByExercise, e.exerciseId),
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

// ── Exercise Card ─────────────────────────────────────────────────────────────

/// The planner's exercise card — an adapter over the shared
/// [SessionExerciseCard] with planned-mode rows (targets, not logged sets).
///
/// It wears the session's flat look (2026-10-26): no card fill, no border, the
/// 6pt inner inset that lands every control on the page's 22pt gutter — so
/// planning and logging read as one screen. The flat card draws no
/// Notes/History/PRs pills at all; the exercise's PRs and notes are the floor
/// tiles' doors now, which is why this card wires none of them.
class _PlanExerciseCard extends StatelessWidget {
  const _PlanExerciseCard({
    required this.viewModel,
    required this.slot,
    required this.onAddExercise,
    this.original,
    this.originalNotes = const {},
  });

  final WorkoutEditorViewModel viewModel;
  final PlanExerciseSlot slot;
  final VoidCallback onAddExercise;

  /// The open workout as the record holds it, while Compare is up — the same
  /// workout drawn through this same card, with the record's rows in place of
  /// the plan's.
  ///
  /// The tabs and `+ ADD SET` do not move — the flip is values only, so the
  /// grid must not change height — but the names do carry the record's
  /// reading while it is up: a tab the record does not hold wears a green
  /// plus ([ExerciseMark.added]), which is a fact about the plan that only
  /// the record can reveal. The note box flips with the values: it
  /// reads the record's own note ([originalNotes]), labelled as the record's,
  /// because the pass's note is about the plan and the plan is not what is on
  /// screen. The rows themselves are read-only and draggable by nobody: the
  /// record is immutable, and the plan underneath is untouched.
  final ContentSession? original;

  /// [original]'s exercise notes, keyed by `planned_exercise_id` — the
  /// record's own words, carried by the comparison that loaded it. Empty for
  /// a record that left none (and for a baseline: the plan as found had no
  /// notes of its own).
  final Map<String, String> originalNotes;

  @override
  Widget build(BuildContext context) {
    // The scope, not the editor's route-carried review: this is the note
    // bar, and its notes live in [reviewNotesNotifier], which only a live
    // pass seeds — a carried review (a record's workout) has no notes to
    // write, so drawing the box for it would offer a field over nothing.
    final review = ReviewScope.maybeOf(context);
    if (review == null) return _card(context, null, const {});
    // The note bar is the pass's record in flight: a save from any card has
    // to land under its exercise without the screen being reloaded.
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: reviewNotesNotifier,
      builder: (context, notes, _) => _card(context, review, notes),
    );
  }

  /// The card itself. [review] is the review this card is being drawn inside,
  /// when there is one; [notes] the exercise notes it carries so far.
  Widget _card(
    BuildContext context,
    ReviewSession? review,
    Map<String, String> notes,
  ) {
    final vm = viewModel;
    final s = vm.state.value;
    final exerciseId = slot.exerciseId;
    final plannedExerciseId = slot.plannedExerciseId ?? '';
    final sets = s.plannedSetsFor(plannedExerciseId);
    final draftIds = s.workoutSetDrafts[plannedExerciseId] ?? const <int>[];
    // The record's own entry for the exercise on screen, when Compare is up.
    // No entry means the record held no sets for it — a fact worth showing
    // plainly, so the grid is drawn empty rather than the plan leaking back.
    final record = original == null
        ? null
        : _recordExercise(original!, plannedExerciseId);
    // A record names its variation by id; names live in the library, and a
    // rename shows through here as it does everywhere else.
    final recordVariationNames = {
      for (final v in s.allVariations) v.variationId: v.name,
    };

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
    if (original != null) {
      // The record's rows, and only its rows: no drafts, no drag handles, no
      // callback that could write. Keyed by the same `planned_set_id` the live
      // row carries, so the flip reuses each element and changes only its
      // values.
      final recordSets = record?.sets ?? const <ContentSet>[];
      for (var i = 0; i < recordSets.length; i++) {
        rows.add(
          recordSetRow(
            set: recordSets[i],
            index: i,
            exerciseId: record?.exerciseId ?? exerciseId,
            variationNames: recordVariationNames,
            variationOptions: variationOptions,
            allVariations: allVariations,
          ),
        );
      }
    } else {
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
            // A removed group stays on screen for its rows: red, inert, and
            // outside the drag list (2026-10-26).
            deleted: slot.deleted,
            dragIndex: slot.deleted ? null : i,
            onRegisterCommit: vm.registerCommitHandle,
            onUnregisterCommit: vm.unregisterCommitHandle,
            onCommit: (isDraft, v, {bool immediate = false}) async {
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
            onDelete: () =>
                vm.deletePlannedSessionExerciseSet(set.plannedSetId),
            onDuplicate: (v) => vm.duplicatePlannedSessionExerciseSet(
              set,
              targetWeight: v.weight,
              targetReps: v.reps,
            ),
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
            // Registered like a real row's: a draft's variation and notes live
            // in the row until it commits, and the commit that saves them is
            // whatever destroys or flushes the row — the exercise switch above
            // all, since only the active card is built.
            onRegisterCommit: vm.registerCommitHandle,
            onUnregisterCommit: vm.unregisterCommitHandle,
            onCommit: (isDraft, v, {bool immediate = false}) async {
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
            onDuplicate: (_) {},
            variationOptions: variationOptions,
            allVariations: allVariations,
            findSimilarVariations: vm.findSimilarVariations,
            submitNewVariation: vm.submitNewVariation,
          ),
        );
      }
    }

    // The record's side of the eye, on the plan's own names: while Compare is
    // up, a tab the record does not hold wears a green plus — it is an
    // exercise this pass added. There is no mirror-image minus, and none is
    // missing: the flip is values only, so the tabs are the plan's slots, and
    // an exercise the record held and the plan dropped has no tab to sit on
    // (2026-10-12 — the completed review's own screen, which lists each side's
    // exercises, is where both marks can be read).
    final exerciseMarks = <ExerciseMark?>[];
    if (original != null) {
      for (final slot in s.workoutExerciseSlots) {
        final id = slot.plannedExerciseId;
        // A slot with no planned row yet — being created right now — cannot
        // be in a frozen record either.
        exerciseMarks.add(
          id != null && _recordExercise(original!, id) != null
              ? null
              : ExerciseMark.added,
        );
      }
    }

    return SessionExerciseCard(
      // The session's own look (2026-10-26): no fill, no border, no pills —
      // the same card the Training page and the viewer draw.
      flat: true,
      exerciseNames: [
        for (final slot in s.workoutExerciseSlots)
          toProperCase(vm.exerciseDisplayName(slot.exerciseId)),
      ],
      exerciseMarks: exerciseMarks,
      // The card names each slot's state for the selector: a group removed
      // during this review reads red, exactly as a deleted exercise does on
      // the session surfaces (2026-10-26).
      deletedExercises: [
        for (final slot in s.workoutExerciseSlots) slot.deleted,
      ],
      activeIndex: s.activeSlotIndex,
      // Switching tabs is looking, and stays: the record is read one exercise
      // at a time. Reordering and adding are writing, and grey out — the plan
      // underneath is not what is on screen. A removed group is a record of
      // its own: it stays readable, and nothing writes to it.
      onSelect: (i) => vm.tapTab(i),
      onMove: original == null && !slot.deleted
          ? (i, dir) => vm.reorderExercises(i, i + dir)
          : null,
      onAdd: original == null ? onAddExercise : null,
      rows: rows,
      // While the record is up there is nothing to add a set to, and nothing
      // to drag: the row is drawn dead to hold the card's height, and the
      // grid stops being reorderable — both are the card's own height and
      // order staying put across the flip.
      onAddSet: original == null && !slot.deleted
          ? () => vm.addDraftPlannedSessionExerciseSet(plannedExerciseId)
          : null,
      reserveAddSet: original != null,
      onReorderSets: original == null && !slot.deleted
          ? (oldIndex, newIndex) =>
                vm.reorderPlannedSets(plannedExerciseId, oldIndex, newIndex)
          : null,
      // Inside a review the card also carries that review's note for this
      // exercise — the box is shown even with none yet, because an empty box
      // is the way in. Outside one the note never existed and the box is not
      // drawn; a slot with no planned row has nothing to key a note to.
      //
      // While the record is up the box reads the RECORD's note instead —
      // read-only (no change callback is wired, so the box is display and
      // nothing else) and labelled as the record's, because the pass's note
      // is about the plan and the plan is not what is on screen. An exercise
      // the record left nothing about keeps the box anyway, reading
      // [kNoPreviousNoteText]: the flip changes values, never furniture, and
      // the absence of a note is itself an answer.
      reviewNote: original != null
          ? originalNotes[plannedExerciseId]
          : review == null
          ? null
          : notes[plannedExerciseId],
      reviewNoteLabel: original == null
          ? kReviewNoteLabel
          : kPreviousReviewNoteLabel,
      reviewNoteEmptyText: original == null ? null : kNoPreviousNoteText,
      onReviewNoteChanged:
          original != null || review == null || plannedExerciseId.isEmpty
          ? null
          : (note) =>
                _writeReviewNote(context, review, plannedExerciseId, note),
    );
  }

  /// The record's own entry for one exercise. Null when the record holds no
  /// such exercise — the workout had no sets for it then, which the empty grid
  /// then says plainly.
  ContentExercise? _recordExercise(
    ContentSession session,
    String plannedExerciseId,
  ) {
    for (final exercise in session.exercises) {
      if (exercise.plannedExerciseId == plannedExerciseId) return exercise;
    }
    return null;
  }

  /// Writes the note this exercise's box now holds, one keystroke at a time.
  ///
  /// There is no Save to press and no sheet to close: the box is the whole of
  /// the note's life, and the house rule for typed values applies — write as
  /// it is typed, so leaving the screen can never lose a word. The write goes
  /// row-first through [saveReviewExerciseNote]; a failure says so, and the
  /// box keeps what was typed (the next keystroke carries it again).
  Future<void> _writeReviewNote(
    BuildContext context,
    ReviewSession review,
    String plannedExerciseId,
    String note,
  ) async {
    try {
      await saveReviewExerciseNote(
        reviewId: review.reviewId,
        plannedExerciseId: plannedExerciseId,
        note: note,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Could not save the note: $e')));
    }
  }
}
