import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/coach_feedback.dart';
import '../../../data/models/exercise_note.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../shared/mixins/unsaved_changes_guard.dart';
import '../../../shared/router/app_router.dart';
import '../../../shared/widgets/add_exercise_modal.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/bar_icon_button.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/exercise_selector.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/keyboard_floor_layout.dart';
import '../../../shared/widgets/lambda_input.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/session_date_bar.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../../../shared/widgets/slide_up_modal.dart';
import '../../../shared/widgets/undo_redo_buttons.dart';
import '../../../shared/widgets/user_name_text.dart';
import '../../goals/view/exercise_goals_sheet.dart';
import '../../goals/view/goal_sheet.dart';
import '../../session/model/session_local_state.dart';
import '../../session/view/exercise_notes_modal.dart';
import '../../session/view/pr_history_sheet.dart';
import '../../session/view/ratings_sheet.dart';
import '../../session/view/session_stats_bar.dart';
import '../viewmodel/session_detail_viewmodel.dart';

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.sessionId,
    this.initialTab,
    this.initialExerciseId,
    this.fromLive = false,
    this.userId,
    this.readOnly = false,
    this.canCoach = false,
    this.navRoute = '/session',
    this.navItems,
    this.navIndex,
    this.onNavTap,
    this.aboveBar,
    this.navLeading,
    this.navTrailing,
  });

  final String sessionId;

  /// Accepted for route compatibility (`?tab=`); the viewer no longer has
  /// surfaces to switch between (2026-10-22). The goal sheet's completion
  /// row still lands right, because `?exercise=` is what selects the
  /// exercise and it is honoured.
  final String? initialTab;

  /// The exercise the reader came to see, selected on open — the goal's own
  /// (2026-10-20). Null leaves the first slot active.
  final String? initialExerciseId;

  /// The route was pushed by the live Training page (`AppRouter.fromLiveExtra`,
  /// 2026-10-22): stepping forward onto "today" pops back onto the live page
  /// still mounted underneath rather than rebuilding the shell.
  final bool fromLive;

  /// Whose record this is; null reads the signed-in user's own. The friend
  /// viewer passes the friend's id, and every read — the record, its walk
  /// stamps, the catalog, PRs, notes and goals — follows it (2026-10-23).
  final String? userId;

  /// A friend's record: no edit path, no Restore, no write affordance
  /// anywhere. The header's edit button and the notes modal's composer are
  /// the two doors this closes; everything else was already read-only in
  /// view mode.
  final bool readOnly;

  /// The coach's own route (`/coach/:athleteId/sessions/:sessionId`,
  /// 2026-10-26, #24): the record stays read-only — a coach never edits an
  /// athlete's sets — but the page gains the feedback card's write door. The
  /// viewer is the signed-in coach; [userId] is the athlete whose session it
  /// is, exactly as on the friend route.
  final bool canCoach;

  /// Which tab the page's own bar lights — '/session' for the Training
  /// viewer, '/friends' for a friend's.
  final String navRoute;

  /// The bar's items, when the host is not the app's five-tab shell. Coach
  /// mode passes its two (Session · Library, 2026-10-28); null keeps
  /// [appTabItems].
  final List<ScrollShrinkNavItem>? navItems;

  /// The bar's lit index; null falls back to [navRoute]'s tab.
  final int? navIndex;

  /// What a bar tap does. Coach mode pops back to its shell and picks the
  /// tab; null keeps the default `go(tabRouteAt(index))`.
  final ValueChanged<int>? onNavTap;

  /// A storey above the bar — coach mode's banner. Null draws none.
  final Widget? aboveBar;

  /// A control before the bar's items — coach mode's exit chevron
  /// (2026-10-28). Null keeps the items alone.
  final Widget? navLeading;

  /// The bar's right half, when the host splits it — coach mode's athlete
  /// identity (2026-10-28). Null keeps the items alone.
  final Widget? navTrailing;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen>
    with UnsavedChangesGuard<SessionDetailScreen> {
  late final SessionDetailViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = SessionDetailViewModel(
      userId: widget.userId,
      readOnly: widget.readOnly,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _vm.load(widget.sessionId, initialExerciseId: widget.initialExerciseId);
    });
  }

  @override
  void didUpdateWidget(covariant SessionDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A rebuild that carries a different route id under the same State: the
    // page reads the new record. The date bar's own walk never comes through
    // here — it steps the view model in place, without a navigation
    // (2026-10-22).
    if (oldWidget.sessionId != widget.sessionId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _vm.load(widget.sessionId, initialExerciseId: widget.initialExerciseId);
      });
    }
  }

  // ── The date bar's walk (2026-10-22) ───────────────────────────────────

  /// The live Training page's guard, one step at a time: stepping away from
  /// a record being edited asks exactly what leaving it does. A settle in
  /// progress is flushed either way — a keystroke must not be dropped by a
  /// step.
  Future<bool> _settleBeforeWalk() async {
    if (_vm.state.value.isEditing) {
      final didProceed = await confirmBack();
      return didProceed && mounted;
    }
    await _vm.flushPendingCommits();
    return mounted;
  }

  Future<void> _walkOlder() async {
    final id = _vm.state.value.walk?.olderId;
    if (id == null || !await _settleBeforeWalk() || !mounted) return;
    // In place: the same page, the same view model, the neighbouring record
    // swapped under it — the PR Lab's pager, not a navigation (2026-10-22).
    await _vm.walkTo(id);
  }

  Future<void> _walkNewer() async {
    final walk = _vm.state.value.walk;
    if (walk == null || !await _settleBeforeWalk() || !mounted) return;
    final newerId = walk.newerId;
    if (newerId != null) {
      await _vm.walkTo(newerId);
      return;
    }
    if (!walk.hasLiveSession) return;
    // A friend's record never walks onto "today": the live page on this
    // device is the viewer's own session, not the friend's (2026-10-23).
    if (widget.readOnly) return;
    // The top of the stack steps onto "today" — a different surface, so this
    // one is a real move: a viewer pushed from Training pops back onto the
    // live page still mounted underneath; one opened from the library enters
    // the session tab.
    if (widget.fromLive && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      GoRouter.of(context).go('/session');
    }
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  // ── UnsavedChangesGuard ─────────────────────────────────────────────────

  @override
  bool get hasUnsavedChanges =>
      (_vm.state.value.isEditing ||
      _vm.state.value.workoutSetDrafts.values.any((l) => l.isNotEmpty));

  @override
  Future<void> onSave() async {
    await _vm.saveNotes();
  }

  @override
  Future<void> onDiscard() async {
    _vm.cancelEditing();
  }

  /// The floating bar the Training page wears (2026-10-22). The viewer is a
  /// pushed page on the root navigator, so the shell's bar is behind it —
  /// the viewer draws the shell's own bar for itself, the tab the route came
  /// from lit ([widget.navRoute]), and a tab tap leaves the record through
  /// the same unsaved-changes guard the back arrow uses.
  Future<void> _onNavTap(int index) async {
    if (widget.onNavTap != null) {
      if (_vm.state.value.isEditing) {
        final didProceed = await confirmBack();
        if (!didProceed || !mounted) return;
      }
      widget.onNavTap!(index);
      return;
    }
    final router = GoRouter.of(context);
    if (_vm.state.value.isEditing) {
      final didProceed = await confirmBack();
      if (!didProceed || !mounted) return;
    }
    router.go(tabRouteAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      // The keyboard paints over the page instead of shoving it up
      // (2026-10-25), exactly as on the live Training page: the floor bar
      // keeps the date bar where it is, and the card's scroll shrinks its
      // viewport to the keyboard's top.
      resizeToAvoidBottomInset: false,
      body: ValueListenableBuilder<SessionDetailState>(
        valueListenable: _vm.state,
        builder: (context, state, _) {
          if (state.isLoading) {
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
              // The outer Scaffold's opt-out is repeated here: with only one
              // of the two opted out, the other would resize the body and
              // strip the bottom viewInsets from the inner MediaQuery, and
              // the scroll below would have nothing to shrink by (2026-10-25).
              resizeToAvoidBottomInset: false,
              // The shell's floating bar, drawn here because this page is a
              // push over the shell — the Training page's bar, element for
              // element (Session tab lit; logs live in its branch).
              body: ScrollShrinkNavBar(
                // '/session' for the Training viewer, '/friends' for a
                // friend's record — the bar always lights the tab the page
                // was opened from (2026-10-23). Coach mode overrides all
                // three with its two-tab bar (2026-10-28).
                currentIndex: widget.navIndex ?? tabIndexFor(widget.navRoute),
                onTap: _onNavTap,
                items: widget.navItems ?? appTabItems,
                aboveBar: widget.aboveBar,
                leading: widget.navLeading,
                trailing: widget.navTrailing,
                child: Column(
                  children: [
                    PageHeader(
                      // The header is the Training page's header (2026-10-22):
                      // the session's own name — the plan it followed, or
                      // Freestyle — so the two surfaces are the same page. The
                      // date bar on the floor says it is a record being read;
                      // the header never restates the mode in words. One title
                      // owner for both surfaces: [sessionTitle] (2026-10-23).
                      title: state.sessionTitle ?? 'Freestyle Session',
                      left: HeaderIconButton(
                        icon: Icons.arrow_back_ios_new,
                        semanticsLabel: 'Back',
                        glyphSize: 18,
                        color: AppColors.primary,
                        onPressed: () async {
                          if (state.isEditing) {
                            final didProceed = await confirmBack();
                            if (didProceed && mounted) {
                              Navigator.of(this.context).pop();
                            }
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                      right: widget.readOnly
                          // A friend's record has no edit path at all — no
                          // pencil, no Done (2026-10-23).
                          ? null
                          : state.isEditing
                          // The Training header's one-word verbs are glyphs
                          // (golden rule 5): Done saves and leaves the mode,
                          // exactly like the live page's check.
                          ? HeaderIconButton(
                              icon: Icons.check,
                              semanticsLabel: 'Done editing',
                              glyphSize: 22,
                              color: AppColors.success,
                              onPressed: state.isSaving
                                  ? null
                                  : () => _vm.saveNotes(),
                            )
                          : HeaderIconButton(
                              icon: Icons.edit_outlined,
                              semanticsLabel: 'Edit session',
                              glyphSize: 20,
                              color: AppColors.primary,
                              onPressed: _vm.startEditing,
                            ),
                    ),
                    Expanded(
                      child: SessionDetailView(
                        viewModel: _vm,
                        state: state,
                        initialTab: widget.initialTab,
                        readOnly: widget.readOnly,
                        canEdit: !widget.readOnly,
                        canCoach: widget.canCoach,
                        onWalkOlder: _walkOlder,
                        onWalkNewer: _walkNewer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

/// The past-session viewer — the Training view, read-only (2026-10-22).
///
/// Same shape as the live session, element for element: the name in the
/// header, the exercise card on the page's gutter, and the floor bar the
/// live page wears — the date bar (`PREVIOUSLY - 20 Oct 2026`), then
/// undo/redo with the historic trash, the ratings pencil and the two count
/// tiles. The old PRs | Details | Reflection toggle is gone; its three
/// surfaces live behind the floor now — PRs behind the trophy, pre/post
/// answers behind the pencil, notes behind the book — and the sets were
/// always the page itself.
///
/// Shared between the /logs route (with its Edit header glyph) and read-only
/// embeds (the another-device preview).
class SessionDetailView extends StatelessWidget {
  const SessionDetailView({
    super.key,
    required this.viewModel,
    required this.state,
    this.initialTab,
    this.readOnly = false,
    this.canEdit = false,
    this.canCoach = false,
    this.onWalkOlder,
    this.onWalkNewer,
    this.floorBottomInset,
  });

  final SessionDetailViewModel viewModel;
  final SessionDetailState state;

  /// A friend's record (2026-10-23): the Restore button is not drawn and the
  /// notes modal opens without its composer — no write affordance exists on
  /// the page.
  final bool readOnly;

  /// The page carries a read/edit MODE to switch (2026-10-27): only the
  /// /logs route does, because only it draws the header's Edit/Done glyph.
  /// The live page's history peek and the another-device preview are
  /// read-only by construction (they never enter edit mode), so their
  /// ratings sheet carries no pencil and no draft callbacks — the frame,
  /// not [readOnly], is what says whether a mode exists.
  final bool canEdit;

  /// The coach reading their athlete's record (2026-10-26, #24): the
  /// feedback card gains its write door. A coach still never edits the sets,
  /// so this rides beside [readOnly] — it does not replace it.
  final bool canCoach;

  /// The date bar's steps (2026-10-22). The route supplies them so a step
  /// takes the same unsaved-changes guard as the back arrow; read-only
  /// embeds (the another-device preview) omit them, and the arrows stay
  /// spent.
  final VoidCallback? onWalkOlder;

  /// The floor's own bottom padding — what it leaves for whatever floats
  /// under it. Null reads [ScrollShrinkNavBar.contentInset], the shell's bar
  /// the page sits over. The another-device preview passes [AppSpacing.sm]
  /// (2026-10-27): its Switch band stands directly under the floor and is
  /// what clears the bar, so the floor keeps only the row's own air and the
  /// bar's clearance is spent once, by the band.
  final double? floorBottomInset;
  final VoidCallback? onWalkNewer;

  /// No surface is named any more — the viewer draws them all at once.
  /// Accepted so `?tab=` links and existing callers keep compiling; the
  /// value is ignored (2026-10-22).
  final String? initialTab;

  @override
  Widget build(BuildContext context) {
    return KeyboardFloorLayout(
      // The card above the floor: the keyboard shrinks this viewport to its
      // top, so an edited set cell is revealed above it while the date bar
      // below keeps its place under it (2026-10-25).
      page: state.exerciseSlots.isEmpty
          ? Center(
              child: Text(
                'No sets recorded.',
                style: AppFonts.ui(
                  fontSize: AppTextStyles.body,
                  color: AppColors.inkSecondary,
                ),
              ),
            )
          : SingleChildScrollView(
              // The live Training page's own insets — the card opens on
              // the same 22pt gutter, from the same place, with the same
              // 16 of air under the header (2026-10-22).
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The coach's feedback on this record (2026-10-26, #24):
                  // drawn for whoever can read it — the athlete on their own
                  // record, the coach, the friend path never passes
                  // `canCoach` — and above the sets, because it is a comment
                  // ABOUT the session that follows.
                  if (state.feedback.isNotEmpty || canCoach) ...[
                    _CoachFeedbackCard(
                      viewModel: viewModel,
                      state: state,
                      canCoach: canCoach,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  if (state.activeSlot != null)
                    _DetailCardBuilder(
                      viewModel: viewModel,
                      state: state,
                      slot: state.activeSlot!,
                      readOnly: readOnly,
                      onAddExercise: () => _showAddExercise(context),
                    ),
                ],
              ),
            ),
      floor: _floorBar(context),
    );
  }

  /// The Training view's floor (2026-10-22): the date bar the live session
  /// wears, then its action row — undo/redo with the historic trash, the
  /// ratings star, and the PR / goals / notes doors (2026-10-27). View mode
  /// greys what edit mode lights: undo/redo answer nothing until there are
  /// edits to walk, and the trash reads in both modes (a tap shows the
  /// deleted exercise).
  ///
  /// The row is the live page's row, control for control, at the same sizes
  /// — the two floors are one recipe.
  Widget _floorBar(BuildContext context) {
    // The tiles speak for the exercise on screen — its own gains, its own
    // doors — the live bar's recipe, so a count always names the feed behind
    // it (2026-10-22).
    final exerciseId = state.activeSlot?.exerciseId;
    final prCount = exerciseId == null ? 0 : viewModel.prCountFor(exerciseId);
    final exerciseNoteCount = exerciseId == null
        ? 0
        : viewModel.sessionExerciseNotesCount(exerciseId);
    final goalCount = exerciseId == null
        ? 0
        : viewModel.openGoalsFor(exerciseId);
    final session = state.session;
    final exerciseMode = state.dateBarMode == SessionDateMode.exercise;
    final viewed = state.viewedHistorySession;
    return Container(
      key: const ValueKey('session-detail-bar'),
      // The live floor's own insets, the bottom one included: the page sits
      // under the floating bar, so the action row ends where the live one
      // does. A caller whose own band clears the bar passes
      // [floorBottomInset] and reserves nothing here (2026-10-27) — the
      // another-device preview's Switch band stands below this floor.
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        floorBottomInset ?? ScrollShrinkNavBar.contentInset(context),
      ),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // PREVIOUSLY, not TODAY: this is a record being read, whatever
          // the clock says. The same bar the live page draws, with the one
          // word that marks the mode — and the same walk: the arrows step
          // through completed sessions, and the newest record's right arrow
          // is the way back onto today's live session when one exists
          // (2026-10-22).
          //
          // EXERCISE is the default on this surface too (2026-10-23): the
          // arrows walk the active exercise's own performances strictly
          // before the record, the card's sets swapping while the record
          // (header, floor, tiles) stays the page. SESSION restores the
          // record walk above. The radios under the date switch the two.
          if (session != null) ...[
            SessionDateBar(
              isToday: false,
              date: viewed?.date ?? session.createdDatetime,
              mode: state.dateBarMode,
              onToggleMode: viewModel.toggleDateBarMode,
              onOlder: exerciseMode
                  ? (state.effectiveExerciseHistoryIndex <
                            state.exerciseHistoryStack.length
                        ? () => unawaited(viewModel.stepExerciseHistory(1))
                        : null)
                  : (state.walk?.olderId != null && onWalkOlder != null
                        ? onWalkOlder
                        : null),
              onNewer: exerciseMode
                  ? (state.effectiveExerciseHistoryIndex > 0
                        ? () => unawaited(viewModel.stepExerciseHistory(-1))
                        : null)
                  : ((state.walk?.newerId != null ||
                                (state.walk?.hasLiveSession ?? false)) &&
                            onWalkNewer != null
                        ? onWalkNewer
                        : null),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              // The live floor's pair, at the live floor's size. View mode
              // draws them spent — nothing has been edited yet — and edit
              // mode lights them as the undo stack fills. The trash rides
              // in its slot in both modes: a row opens the deleted exercise
              // for reading, and the Restore button under the card is the
              // write (2026-10-14).
              UndoRedoButtons(
                canUndo: state.isEditing && viewModel.canUndo,
                canRedo: state.isEditing && viewModel.canRedo,
                onUndo: viewModel.undo,
                onRedo: viewModel.redo,
                deletedExercises: [
                  for (final e in viewModel.deletedExerciseEntries) e.name,
                ],
                onPickDeletedExercise: viewModel.viewDeletedExerciseAt,
              ),
              const SizedBox(width: AppSpacing.sm),
              BarIconButton(
                key: const ValueKey('session-detail-ratings-button'),
                // The star, matching the live floor and the sheet's five
                // feeling stars (2026-10-23). Neutral glass — the star stays
                // white while the three score doors take the accent
                // (2026-10-27).
                icon: Icons.star_rounded,
                semanticsLabel: 'Session ratings',
                onPressed: () => _openRatings(context),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SessionStatsTiles(
                  prCount: prCount,
                  exerciseNoteCount: exerciseNoteCount,
                  goalCount: goalCount,
                  // Doors at any count — the PR Lab's bar recipe. A past
                  // record with no session PRs still opens onto the
                  // exercise's whole history, split around this session
                  // (2026-10-23).
                  onPrTap: exerciseId == null
                      ? null
                      : () => _openPrHistory(context, exerciseId),
                  onNoteTap: exerciseId == null
                      ? null
                      : () => _openNotes(context, exerciseId),
                  // The goals door (2026-10-26) — the owner's record only: a
                  // friend's or athlete's page draws no bullseye, because
                  // the New goal behind it would file under their id.
                  onGoalTap: exerciseId == null || readOnly
                      ? null
                      : () => _openGoals(context, exerciseId),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The floor's trophy door: the active exercise's PR History, scoped to
  /// the record on screen — the PR Lab's sheet, the live bar's door
  /// (2026-10-22). The record's start places every other PR before it or
  /// after it, so reading an old record never flies future PRs under
  /// `PREVIOUSLY` (2026-10-23).
  void _openPrHistory(BuildContext context, String exerciseId) {
    showPrHistorySheet(
      context,
      exerciseName: toProperCase(viewModel.exerciseDisplayName(exerciseId)),
      prs: viewModel.prHistoryFor(exerciseId),
      sessionSetIds: viewModel.sessionPrSetIdsFor(exerciseId),
      sessionStartedAt: state.session?.createdDatetime,
      // The record's own review boundary, when a pass has covered it
      // (2026-10-26): PRs landed since that pass lead the feed.
      sinceLastReviewAt: state.reviewCheckpoint,
      // A PR that also met a goal draws green (2026-10-26).
      goalSetIds: state.goalSetIds,
    );
  }

  /// The floor's bullseye (2026-10-26): the exercise's goals on the PR
  /// History sheet's furniture, open ones first by default. The New goal door
  /// inside it seeds the goals screen's form with just this exercise.
  void _openGoals(BuildContext context, String exerciseId) {
    final name = toProperCase(viewModel.exerciseDisplayName(exerciseId));
    showExerciseGoalsSheet(
      context,
      exerciseName: name,
      listenable: viewModel.state,
      goalsFor: () => viewModel.goalsForExercise(exerciseId),
      setsFor: () => viewModel.goalTimeline,
      variationNames: {
        for (final v in state.allVariations) v.variationId: v.name,
      },
      onNewGoal: () => showAddGoalSheet(
        context,
        detailMap: state.exerciseDetailMap,
        variations: state.allVariations,
        lastUsed: viewModel.lastUsedByExercise,
        pastSets: viewModel.pastSets,
        seed: ExerciseTarget(exerciseId: exerciseId, exerciseName: name),
        onAdd: viewModel.createGoalFromTarget,
      ),
    );
  }

  /// The floor's book door: the active exercise's notes, grouped around
  /// the record on screen — its own, the ones before it, and the ones added
  /// since. The record's id is the scope, not "whatever session happens to
  /// be live".
  void _openNotes(BuildContext context, String exerciseId) {
    showExerciseNotesModal(
      context,
      listenable: viewModel.state,
      notesFor: viewModel.notesFor,
      loadNotesFor: viewModel.loadNotesFor,
      addNote: viewModel.addNote,
      toggleNotePin: viewModel.toggleNotePin,
      deleteNote: viewModel.deleteNote,
      updateNote: viewModel.updateNoteText,
      exerciseId: exerciseId,
      exerciseName: toProperCase(viewModel.exerciseDisplayName(exerciseId)),
      sessionId: state.session?.sessionId,
      sessionStartedAt: state.session?.createdDatetime,
      readOnly: readOnly,
      sinceLastReviewAt: state.reviewCheckpoint,
    );
  }

  /// The same four answers the live pencil sheet edits. View mode reads the
  /// stored session; edit mode reads (and writes) the drafts, which the
  /// header's Done persists in one `updateSessionNotes` write.
  ///
  /// The sheet carries its own mode pencil since 2026-10-27, just left of its
  /// X, so the drafts are handed in for BOTH modes (the sheet gates them on
  /// the mode it shows) and the pencil drives the page's one mode — the same
  /// `startEditing`/`cancelEditing` the header glyph does. Only a surface
  /// with a mode ([canEdit], the /logs route) gets either; the peek and the
  /// preview read, and a friend's record has no mode at all.
  void _openRatings(BuildContext context) {
    final session = state.session;
    if (session == null) return;
    final editing = state.isEditing;
    showSessionRatingsSheet(
      context,
      editing: editing,
      preFeeling: editing ? state.preFeelingDraft : session.preFeeling,
      preNotes: editing ? state.preNotesDraft : (session.preNotes ?? ''),
      postFeeling: editing ? state.postFeelingDraft : session.feeling,
      postNotes: editing ? state.postNotesDraft : (session.postNotes ?? ''),
      onPreFeelingChanged: canEdit ? viewModel.setPreFeelingDraft : null,
      onPreNotesChanged: canEdit ? viewModel.setPreNotesDraft : null,
      onPostFeelingChanged: canEdit ? viewModel.setPostFeelingDraft : null,
      onPostNotesChanged: canEdit ? viewModel.setPostNotesDraft : null,
      onEditingChanged: canEdit
          ? (on) => on ? viewModel.startEditing() : viewModel.cancelEditing()
          : null,
    );
  }

  void _showAddExercise(BuildContext context) {
    final vm = viewModel;
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
      isAdded: (id) =>
          vm.state.value.exerciseSlots.any((slot) => slot.exerciseId == id),
      onAdd: vm.addExerciseGroup,
      onRemoveRequest: (id) async {
        final i = vm.state.value.exerciseSlots.indexWhere(
          (slot) => slot.exerciseId == id,
        );
        // A deleted exercise's tick is historic — there is nothing left to
        // remove; its way back is the Restore button (2026-10-14).
        if (i >= 0 && !vm.state.value.exerciseSlots[i].deleted) {
          _confirmRemoveExercise(context, i);
        }
      },
      onCreate: vm.submitNewExercise,
      isCreating: () => vm.state.value.newExCreating,
    );
  }

  /// Remove-exercise confirmation, addressed by slot index. Lives on the body
  /// rather than on the card because the exercise picker identifies an
  /// exercise by id, not by the tab the card happens to be showing.
  void _confirmRemoveExercise(BuildContext context, int index) {
    final state = viewModel.state.value;
    final slot = state.exerciseSlots[index];
    final name = toProperCase(viewModel.exerciseDisplayName(slot.exerciseId));
    final setCount = state.setsFor(slot.groupOrder).length;

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
              viewModel.removeExerciseGroup(index);
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
}

// ── Exercise card ────────────────────────────────────────────────────────────

/// The past-session viewer's exercise card — an adapter over the shared
/// [SessionExerciseCard]. View mode greys edit-only affordances (reorder,
/// add, ADD SET, swipe, editable cells); edit mode enables them. The selector
/// switch works in both modes (browsing).
class _DetailCardBuilder extends StatelessWidget {
  const _DetailCardBuilder({
    required this.viewModel,
    required this.state,
    required this.slot,
    required this.onAddExercise,
    required this.readOnly,
  });

  final SessionDetailViewModel viewModel;
  final SessionDetailState state;
  final SessionDetailExerciseSlot slot;
  final VoidCallback onAddExercise;

  /// A friend's record: no Restore button, no notes composer — the card
  /// shows what is there and offers no way to change it (2026-10-23).
  final bool readOnly;

  /// The goal door (2026-10-26): the New goal form the goals screen composes,
  static String _fmtNum(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  static double? _parseWeight(String? t) =>
      t == null || t.isEmpty ? null : double.tryParse(t);

  static List<num>? _parseReps(String? t) {
    final r = t == null || t.isEmpty ? null : num.tryParse(t);
    return r == null ? null : [r];
  }

  /// Delete with the PR-count warning — cascade so PRs recompute.
  Future<void> _confirmDeleteSet(
    SessionExerciseSet set,
    BuildContext context,
  ) async {
    // In-memory PR count from the already-computed workout PR events.
    final prCount = state.prEvents
        .where((r) => r.sessionExerciseSetId == set.sessionExerciseSetId)
        .length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Delete Set',
          style: AppFonts.ui(
            fontWeight: FontWeight.w800,
            color: AppColors.danger,
          ),
        ),
        content: Text(
          prCount > 0
              ? 'This set holds $prCount PR record${prCount == 1 ? '' : 's'}, which will be deleted too. Remove this set?'
              : 'Remove this set from the workout?',
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
    if (ok == true) {
      await viewModel.deleteSetCascade(
        set.sessionExerciseSetId,
        set.exerciseId ?? '',
      );
      if (context.mounted) _showDeleteErrorIfAny(context);
    }
  }

  void _showDeleteErrorIfAny(BuildContext context) {
    final err = viewModel.state.value.error;
    if (err == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) {
    final exerciseId = slot.exerciseId;
    final order = slot.groupOrder;
    final name = toProperCase(viewModel.exerciseDisplayName(exerciseId));
    final history = viewModel.historyFor(exerciseId);
    final sets = state.setsFor(order);
    final draftIds = state.workoutSetDrafts[order] ?? const <int>[];
    // The orange PR accent = this session's PR events — the same sets the
    // stats tile, pills, and modal count.
    final prSetIds = {
      for (final r in state.prEvents)
        if (r.sessionExerciseSetId != null) r.sessionExerciseSetId!,
    };

    // The pinned note shows right under the exercise — pinning is what
    // decides whether a note appears there.
    ExerciseNote? pinnedNote;
    for (final l in viewModel.notesFor(exerciseId)) {
      if (l.pinned) {
        pinnedNote = l;
        break;
      }
    }

    void openExerciseNotesModal() => showExerciseNotesModal(
      context,
      listenable: viewModel.state,
      notesFor: viewModel.notesFor,
      loadNotesFor: viewModel.loadNotesFor,
      addNote: viewModel.addNote,
      toggleNotePin: viewModel.toggleNotePin,
      deleteNote: viewModel.deleteNote,
      updateNote: viewModel.updateNoteText,
      exerciseId: exerciseId,
      exerciseName: name,
      // The record being read, not "whatever is live" — this session's
      // notes form the sheet's first group, and its start splits the rest
      // into before and after (2026-10-23).
      sessionId: state.session?.sessionId,
      sessionStartedAt: state.session?.createdDatetime,
      readOnly: readOnly,
      sinceLastReviewAt: state.reviewCheckpoint,
    );

    final variationOptions = [
      const DropdownOption<String?>(label: 'No Variation', value: null),
      ...viewModel.variationsByRecency.map(
        (v) => DropdownOption<String?>(label: v.name, value: v.variationId),
      ),
    ];
    final allVariations = [
      for (final v in state.allVariations) (id: v.variationId, name: v.name),
    ];

    List<Widget> rows = [];
    for (var i = 0; i < sets.length; i++) {
      final set = sets[i];
      rows.add(
        SessionSetRow(
          key: ValueKey(set.sessionExerciseSetId),
          mode: SetRowMode.history,
          exerciseId: exerciseId,
          displayIndex: i + 1,
          isDraft: false,
          // Only edit mode moves rows — view mode is a record. A deleted
          // row never moves: it is a fact being shown (2026-10-14).
          dragIndex: state.isEditing && !set.isDeleted ? i : null,
          initialWeightText: set.weight != null ? _fmtNum(set.weight!) : '',
          initialRepsText: set.reps.isNotEmpty ? _fmtNum(set.reps.first) : '',
          initialVariationId: set.variationId,
          initialVariationName: set.variationName,
          initialNotes: set.notes,
          hasNotes: set.notes?.isNotEmpty ?? false,
          isPr: prSetIds.contains(set.sessionExerciseSetId),
          isGoal: state.goalSetIds.contains(set.sessionExerciseSetId),
          // A soft-deleted row reads red and inert in either mode — the
          // exercise-level Restore button is its way back.
          deleted: set.isDeleted,
          readOnly: !state.isEditing,
          onCommit: (isDraft, v, {bool immediate = false}) async {
            if (!isDraft) {
              await viewModel.quickUpdateSet(
                set,
                weight: _parseWeight(v.weight),
                clearWeight: v.weight == null,
                reps: _parseReps(v.reps),
                clearReps: v.reps == null,
                immediate: immediate,
              );
            }
          },
          onVariationChanged: (id) => viewModel.quickUpdateSet(
            set,
            variationId: id,
            clearVariation: id == null,
            immediate: true,
          ),
          onNotesSave: (v) => viewModel.quickUpdateSet(
            set,
            notes: v.trim().isEmpty ? null : v.trim(),
            clearNotes: v.trim().isEmpty,
            immediate: true,
          ),
          onDelete: () => _confirmDeleteSet(set, context),
          onDuplicate: (v) => viewModel.duplicateSet(
            set,
            weight: _parseWeight(v.weight),
            reps: _parseReps(v.reps),
          ),
          variationOptions: variationOptions,
          allVariations: allVariations,
          findSimilarVariations: viewModel.findSimilarVariations,
          submitNewVariation: viewModel.submitNewVariation,
        ),
      );
    }
    for (var i = 0; i < draftIds.length; i++) {
      final draftId = draftIds[i];
      rows.add(
        SessionSetRow(
          key: ValueKey('draft-$draftId'),
          mode: SetRowMode.history,
          exerciseId: exerciseId,
          displayIndex: sets.length + i + 1,
          isDraft: true,
          initialWeightText: '',
          initialRepsText: '',
          initialVariationId: null,
          hasNotes: false,
          onCommit: (isDraft, v, {bool immediate = false}) async {
            if (isDraft) {
              // The row guarantees reps text for history drafts — the
              // numeric formatter makes this parse safe.
              final reps = num.tryParse(v.reps!) ?? 0;
              await viewModel.commitDraftSet(
                exerciseId,
                order,
                draftId,
                variationId: v.variationId,
                weight: _parseWeight(v.weight),
                reps: [reps],
                notes: v.notes,
              );
            }
          },
          onVariationChanged: (_) {},
          onNotesSave: (_) {},
          onDelete: () async => viewModel.removeDraftSet(order, draftId),
          onDuplicate: (_) {},
          variationOptions: variationOptions,
          allVariations: allVariations,
          findSimilarVariations: viewModel.findSimilarVariations,
          submitNewVariation: viewModel.submitNewVariation,
        ),
      );
    }

    final card = SessionExerciseCard(
      exerciseNames: [
        for (final sl in state.exerciseSlots)
          toProperCase(viewModel.exerciseDisplayName(sl.exerciseId)),
      ],
      // A deleted exercise is red with the minus — the historic trash
      // reading, drawn in the field and every popover row (2026-10-14).
      deletedExercises: [for (final sl in state.exerciseSlots) sl.deleted],
      exerciseMarks: [
        for (final sl in state.exerciseSlots)
          sl.deleted ? ExerciseMark.removed : null,
      ],
      activeIndex: state.activeSlotIndex,
      onSelect: (i) => viewModel.tapTab(i),
      // Edit-only affordances: null greys the reorder arrows and the Add
      // Exercise row.
      onMove: state.isEditing
          ? (i, dir) => viewModel.reorderExercises(i, i + dir)
          : null,
      onAdd: state.isEditing ? onAddExercise : null,
      pinnedNote: pinnedNote != null
          ? PinnedNoteData(
              text: pinnedNote.text,
              date: pinnedNote.createdDate,
            )
          : null,
      onPinnedNoteTap: openExerciseNotesModal,
      // Session-scoped, so the pill, the floor tile and the live card's
      // count agree — a past session's notes don't inflate this one.
      exerciseNotesCount: viewModel.sessionExerciseNotesCount(exerciseId),
      onExerciseNotesTap: openExerciseNotesModal,
      prCount: viewModel.prCountFor(exerciseId),
      // Always a door, like the floor's trophy: the sheet holds the
      // exercise's whole history, not only this record's gains (2026-10-23).
      onPrTap: () => showPrHistorySheet(
        context,
        exerciseName: name,
        prs: viewModel.prHistoryFor(exerciseId),
        sessionSetIds: viewModel.sessionPrSetIdsFor(exerciseId),
        sessionStartedAt: state.session?.createdDatetime,
        sinceLastReviewAt: state.reviewCheckpoint,
        goalSetIds: state.goalSetIds,
      ),
      // The plan-linked blue is the selector field and the set rows,
      // matching live (2026-10-23) — the session's plan is a fact about the
      // values, not about the caption. A deleted exercise reads off its red
      // selector name and rows, not a card rim.
      planned: slot.planned,
      // The viewer is the Training view read-only (2026-10-22): the same
      // flat card, every row on the 22pt gutter.
      flat: true,
      rows: rows,
      onAddSet: state.isEditing ? () => viewModel.addDraftSet(order) : null,
      // View mode draws no ADD SET at all (2026-10-26): a past session read as
      // a record carries no dead affordance. The card's shape may therefore
      // change when editing starts — the button appearing is the honest
      // signal that the page just became a form.
      reserveAddSet: false,
      onReorderSets: state.isEditing
          ? (oldIndex, newIndex) =>
                viewModel.reorderSets(order, oldIndex, newIndex)
          : null,
      history: history,
      // The date bar's EXERCISE walk selects a performance (2026-10-23):
      // the flat card has no pills row, so the stage hands the card the one
      // it is showing. Home (the record's own sets) is null.
      historySelection: state.viewedHistorySession,
      // The history viewer is the regular sets grid — read-only here (the
      // screen's own edit mode is the logs' editing surface), so the rows
      // are inert shared SessionSetRows with no edit gate.
      historyRowBuilder: (s) => SessionSetRow(
        key: ValueKey('history-${s.sessionExerciseSetId}'),
        mode: SetRowMode.history,
        exerciseId: s.exerciseId ?? '',
        displayIndex: s.setNumber,
        isDraft: false,
        initialWeightText: s.weight != null ? _fmtNum(s.weight!) : '',
        initialRepsText: s.reps.isNotEmpty ? _fmtNum(s.reps.first) : '',
        initialVariationId: s.variationId,
        initialVariationName: s.variationName,
        initialNotes: s.notes,
        hasNotes: s.notes?.isNotEmpty ?? false,
        // Past PR sets badge like the grid — events are keyed by set id — and
        // a past set that achieved a goal reads green with the G.
        isPr: state.prEventSetIds.contains(s.sessionExerciseSetId),
        isGoal: state.goalSetIds.contains(s.sessionExerciseSetId),
        readOnly: true,
        onCommit: (_, _, {bool immediate = false}) async {},
        onVariationChanged: (_) {},
        onNotesSave: (_) {},
        onDelete: () async {},
        onDuplicate: (_) {},
        variationOptions: variationOptions,
        allVariations: allVariations,
        findSimilarVariations: viewModel.findSimilarVariations,
        submitNewVariation: viewModel.submitNewVariation,
      ),
      // The picker tiles show each past session's PR count.
      isPrSet: (setId) => state.prEventSetIds.contains(setId),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        // The way back for deleted sets: a button under the card, so the
        // reader sees exactly what comes back — everything under the
        // exercise, whether it folded away entirely or kept active rows
        // (2026-10-14). Edit mode restores directly; view mode confirms and
        // enters edit mode FIRST — every restore lands in the edit session
        // and is undoable. A friend's record draws no button: it is not
        // theirs to restore (2026-10-23).
        if (!readOnly && sets.any((s) => s.isDeleted)) ...[
          const SizedBox(height: AppSpacing.md),
          GlassButton(
            label: 'Restore',
            onPressed: () => _restoreDeleted(context),
          ),
        ],
      ],
    );
  }

  Future<void> _restoreDeleted(BuildContext context) async {
    if (!state.isEditing) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Restore Exercise',
            style: AppFonts.ui(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          content: Text(
            'This exercise was deleted from the workout. Restoring it changes '
            'this session, so the workout enters edit mode.',
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
                'Enter Edit Mode',
                style: AppFonts.ui(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
      viewModel.startEditing();
    }
    await viewModel.restoreDeletedExercise(
      state.exerciseSlots.indexWhere((sl) => sl.groupOrder == slot.groupOrder),
    );
  }
}

// ── Coach feedback (2026-10-26, #24) ────────────────────────────────────────

/// The coach's note on the record on screen, above the sets: who wrote it,
/// when, and the prose. The athlete reads it on their own record; the coach
/// reads it — and writes it — on the route that opened the athlete's record
/// ([SessionDetailScreen.canCoach]).
///
/// It is drawn only when there is something to draw or someone can write:
/// a friend's record passes neither, and a record no coach has touched shows
/// the athlete nothing.
class _CoachFeedbackCard extends StatelessWidget {
  const _CoachFeedbackCard({
    required this.viewModel,
    required this.state,
    required this.canCoach,
  });

  final SessionDetailViewModel viewModel;
  final SessionDetailState state;

  /// The coach's route: the card gains its write/edit door.
  final bool canCoach;

  /// The caller's own row, on the coach's route — the one their pencil edits
  /// and their trash deletes. Another coach's row is read-only here.
  CoachFeedback? get _mine => canCoach
      ? state.feedback
            .where((f) => f.coachUserId == viewModel.viewerId)
            .firstOrNull
      : null;

  Future<void> _openSheet(BuildContext context) async {
    final mine = _mine;
    await showCoachFeedbackSheet(
      context,
      eyebrow: state.sessionTitle,
      feedback: mine,
      onSave: viewModel.saveCoachFeedback,
      onDelete: mine == null ? null : () => viewModel.deleteCoachFeedback(mine),
      // The ViewModel records its refusal as a sentence for the user; the
      // sheet that caused it draws it under the field.
      errorText: () => viewModel.state.value.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const ValueKey('session-coach-feedback'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'COACH FEEDBACK',
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: AppColors.primary,
                  ),
                ),
              ),
              if (canCoach)
                // A word, not a glyph: writing the note is this card's whole
                // point for a coach (frontend-design §5, one-off actions).
                GlassButton(
                  key: const ValueKey('session-coach-feedback-write'),
                  label: _mine == null ? 'Leave feedback' : 'Edit feedback',
                  compact: true,
                  onPressed: () => _openSheet(context),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (state.feedback.isEmpty)
            Text(
              'No feedback yet.',
              key: const ValueKey('session-coach-feedback-empty'),
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.inkSecondary,
                height: 1.4,
              ),
            )
          else
            for (final (index, feedback) in state.feedback.indexed) ...[
              if (index > 0) const SizedBox(height: AppSpacing.lg),
              _feedbackRow(feedback),
            ],
        ],
      ),
    );
  }

  Widget _feedbackRow(CoachFeedback feedback) {
    final name = state.coachNames[feedback.coachUserId] ?? 'Coach';
    final date = feedback.displayDate;
    return Column(
      key: ValueKey('session-coach-feedback-row-${feedback.feedbackId}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: UserNameText(
                name,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.sm,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            if (date != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${DateFormat('d MMM yyyy').format(date.toLocal())}'
                        '${feedback.isEdited ? ' · EDITED' : ''}'
                    .toUpperCase(),
                style: AppFonts.mono(
                  fontSize: AppTextStyles.xs,
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          feedback.body,
          style: AppFonts.ui(
            fontSize: AppTextStyles.body,
            color: AppColors.primary,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// The feedback composer — one coach's note on one session (2026-10-26, #24).
///
/// [feedback] null means nothing is written yet (the sheet starts empty);
/// a row means the coach is rewriting it, so the field opens on the old text
/// and Save stays spent until something differs. Delete is offered only when
/// there is a row to remove, behind the house two-verb confirm.
Future<void> showCoachFeedbackSheet(
  BuildContext context, {
  required String? eyebrow,
  required CoachFeedback? feedback,
  required Future<bool> Function(String body) onSave,
  Future<bool> Function()? onDelete,
  String? Function()? errorText,
}) {
  return showLambdaModal(
    context,
    fitContent: true,
    keyboardAware: true,
    child: _CoachFeedbackSheet(
      eyebrow: eyebrow,
      feedback: feedback,
      onSave: onSave,
      onDelete: onDelete,
      errorText: errorText,
    ),
  );
}

class _CoachFeedbackSheet extends StatefulWidget {
  const _CoachFeedbackSheet({
    required this.eyebrow,
    required this.feedback,
    required this.onSave,
    required this.onDelete,
    required this.errorText,
  });

  final String? eyebrow;
  final CoachFeedback? feedback;
  final Future<bool> Function(String body) onSave;
  final Future<bool> Function()? onDelete;

  /// The caller's refusal sentence — read after a failed write so the sheet
  /// shows the real reason instead of a generic one.
  final String? Function()? errorText;

  @override
  State<_CoachFeedbackSheet> createState() => _CoachFeedbackSheetState();
}

class _CoachFeedbackSheetState extends State<_CoachFeedbackSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.feedback?.body ?? '',
  );
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  /// Notes are prose: no cap, only the empty-and-unchanged refusal — a Save
  /// that would write nothing stays spent (the modal gating rule).
  bool get _canSave {
    final text = _controller.text.trim();
    return text.isNotEmpty && text != (widget.feedback?.body ?? '').trim();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final didSave = await widget.onSave(_controller.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!didSave) {
        _error = widget.errorText?.call() ?? 'Could not save that feedback.';
      }
    });
    if (didSave) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Delete feedback?',
          style: AppFonts.ui(
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
        content: Text(
          'The athlete will no longer see this note.',
          style: AppFonts.ui(color: AppColors.inkSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Keep it',
              style: AppFonts.ui(color: AppColors.inkSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete feedback',
              style: AppFonts.ui(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    final didDelete = await widget.onDelete!();
    if (!mounted) return;
    setState(() {
      _deleting = false;
      if (!didDelete) {
        _error = widget.errorText?.call() ?? 'Could not delete that feedback.';
      }
    });
    if (didDelete) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      key: const ValueKey('session-coach-feedback-sheet'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.eyebrow?.isNotEmpty == true)
                        Text(
                          widget.eyebrow!.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.mono(
                            fontSize: AppTextStyles.caption,
                            fontWeight: FontWeight.w500,
                            color: AppColors.inkSecondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      Text(
                        'Coach Feedback',
                        style: AppFonts.ui(
                          fontSize: AppTextStyles.lg,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                GlassButton(
                  key: const ValueKey('session-coach-feedback-close'),
                  label: '',
                  icon: Icons.close,
                  semanticsLabel: 'Close feedback',
                  compact: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            LambdaInput(
              key: const ValueKey('session-coach-feedback-input'),
              controller: _controller,
              label: 'Note',
              placeholder:
                  'How did the session go?\nWhat to keep, what to fix?',
              // The sheet's ground is `surface`: a step up for the field
              // (frontend-design §6, the ground rule).
              elevated: true,
              minLines: 4,
              maxLines: 8,
              autofocus: widget.feedback == null,
              error: _error,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                if (widget.onDelete != null)
                  TextButton(
                    key: const ValueKey('session-coach-feedback-delete'),
                    onPressed: _saving || _deleting ? null : _delete,
                    child: Text(
                      'Delete',
                      style: AppFonts.ui(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const Spacer(),
                GlassButton(
                  key: const ValueKey('session-coach-feedback-save'),
                  label: 'Save feedback',
                  color: AppColors.success,
                  solid: true,
                  loading: _saving,
                  disabled: !_canSave || _deleting,
                  onPressed: _save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
