import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/lesson.dart';
import '../../../data/models/session_exercise_set.dart';
import '../../../shared/mixins/unsaved_changes_guard.dart';
import '../../../shared/router/app_router.dart';
import '../../../shared/widgets/add_exercise_modal.dart';
import '../../../shared/widgets/bar_icon_button.dart';
import '../../../shared/widgets/dropdown_select.dart';
import '../../../shared/widgets/exercise_selector.dart';
import '../../../shared/widgets/exercise_target_picker.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/header_icon_button.dart';
import '../../../shared/widgets/keyboard_floor_layout.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/session_date_bar.dart';
import '../../../shared/widgets/session_exercise_card.dart';
import '../../../shared/widgets/session_set_row.dart';
import '../../../shared/widgets/undo_redo_buttons.dart';
import '../../goals/view/goal_sheet.dart';
import '../../session/model/session_local_state.dart';
import '../../session/view/lessons_modal.dart';
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
    this.navRoute = '/session',
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
  /// stamps, the catalog, PRs, lessons and goals — follows it (2026-10-23).
  final String? userId;

  /// A friend's record: no edit path, no Restore, no write affordance
  /// anywhere. The header's edit button and the lessons modal's composer are
  /// the two doors this closes; everything else was already read-only in
  /// view mode.
  final bool readOnly;

  /// Which tab the page's own bar lights — '/session' for the Training
  /// viewer, '/friends' for a friend's.
  final String navRoute;

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
                // was opened from (2026-10-23).
                currentIndex: tabIndexFor(widget.navRoute),
                onTap: _onNavTap,
                items: appTabItems,
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
/// answers behind the pencil, lessons behind the book — and the sets were
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
    this.onWalkOlder,
    this.onWalkNewer,
  });

  final SessionDetailViewModel viewModel;
  final SessionDetailState state;

  /// A friend's record (2026-10-23): the Restore button is not drawn and the
  /// lessons modal opens without its composer — no write affordance exists on
  /// the page.
  final bool readOnly;

  /// The date bar's steps (2026-10-22). The route supplies them so a step
  /// takes the same unsaved-changes guard as the back arrow; read-only
  /// embeds (the another-device preview) omit them, and the arrows stay
  /// spent.
  final VoidCallback? onWalkOlder;
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
  /// ratings pencil, the PR and lesson tiles. View mode greys what edit mode
  /// lights: undo/redo answer nothing until there are edits to walk, and the
  /// trash reads in both modes (a tap shows the deleted exercise).
  ///
  /// The row is the live page's row, control for control, at the same sizes
  /// — the two floors are one recipe.
  Widget _floorBar(BuildContext context) {
    // The tiles speak for the exercise on screen — its own gains, its own
    // doors — the live bar's recipe, so a count always names the feed behind
    // it (2026-10-22).
    final exerciseId = state.activeSlot?.exerciseId;
    final prCount = exerciseId == null ? 0 : viewModel.prCountFor(exerciseId);
    final lessonCount = exerciseId == null
        ? 0
        : viewModel.sessionLessonsCount(exerciseId);
    final session = state.session;
    final exerciseMode = state.dateBarMode == SessionDateMode.exercise;
    final viewed = state.viewedHistorySession;
    return Container(
      key: const ValueKey('session-detail-bar'),
      // The live floor's own insets, the bottom one included: the page sits
      // under the floating bar, so the action row ends where the live one
      // does. `contentInset` answers zero where no bar floats (the
      // another-device preview holds its own action bar instead).
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
                // feeling stars (2026-10-23).
                icon: Icons.star_rounded,
                semanticsLabel: 'Session ratings',
                onPressed: () => _openRatings(context),
                // The tiles' accent glass — a door to session content, the
                // live floor's reading (2026-10-22).
                color: AppColors.accent,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SessionStatsTiles(
                  prCount: prCount,
                  lessonCount: lessonCount,
                  // Doors at any count — the PR Lab's bar recipe. A past
                  // record with no session PRs still opens onto the
                  // exercise's whole history, split around this session
                  // (2026-10-23).
                  onPrTap: exerciseId == null
                      ? null
                      : () => _openPrHistory(context, exerciseId),
                  onLessonTap: exerciseId == null
                      ? null
                      : () => _openLessons(context, exerciseId),
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
    );
  }

  /// The floor's book door: the active exercise's lessons, grouped around
  /// the record on screen — its own, the ones before it, and the ones added
  /// since. The record's id is the scope, not "whatever session happens to
  /// be live".
  void _openLessons(BuildContext context, String exerciseId) {
    showLessonsModal(
      context,
      listenable: viewModel.state,
      lessonsFor: viewModel.lessonsFor,
      loadLessonsFor: viewModel.loadLessonsFor,
      addLesson: viewModel.addLesson,
      toggleLessonPin: viewModel.toggleLessonPin,
      deleteLesson: viewModel.deleteLesson,
      updateLesson: viewModel.updateLessonText,
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
  void _openRatings(BuildContext context) {
    final session = state.session;
    if (session == null) return;
    final editing = state.isEditing;
    showSessionRatingsSheet(
      context,
      preFeeling: editing ? state.preFeelingDraft : session.preFeeling,
      preNotes: editing ? state.preNotesDraft : (session.preNotes ?? ''),
      postFeeling: editing ? state.postFeelingDraft : session.feeling,
      postNotes: editing ? state.postNotesDraft : (session.postNotes ?? ''),
      onPreFeelingChanged: editing ? viewModel.setPreFeelingDraft : null,
      onPreNotesChanged: editing ? viewModel.setPreNotesDraft : null,
      onPostFeelingChanged: editing ? viewModel.setPostFeelingDraft : null,
      onPostNotesChanged: editing ? viewModel.setPostNotesDraft : null,
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

  /// A friend's record: no Restore button, no lessons composer — the card
  /// shows what is there and offers no way to change it (2026-10-23).
  final bool readOnly;

  /// The goal door (2026-10-26): the New goal form the goals screen composes,
  /// opened on the row the user swiped — the record's own set, variation,
  /// weight and reps already in it. A past record is exactly where a target
  /// comes from: the session is over, and what it showed is what to chase.
  ///
  /// The row is re-read AFTER the pending commits are flushed (the form must
  /// open on what the row SHOWS), and the write behind ADD folds the new goal
  /// into the G badges in place — the set that meets it turns green with the
  /// record still on the desk.
  ///
  /// The form opens on a one-shot draft, and it wires no "open that workout"
  /// door: this page walks records in place rather than pushing another
  /// viewer over itself.
  Future<void> _openGoalForSet(BuildContext context, String setId) async {
    await viewModel.flushPendingCommits();
    if (!context.mounted) return;
    final fresh = viewModel.state.value;
    SessionExerciseSet? set;
    for (final sets in fresh.setsByOrder.values) {
      for (final s in sets) {
        if (s.sessionExerciseSetId == setId) {
          set = s;
          break;
        }
      }
      if (set != null) break;
    }
    final exerciseId = set?.exerciseId;
    if (set == null || exerciseId == null) return;
    await showAddGoalSheet(
      context,
      detailMap: fresh.exerciseDetailMap,
      variations: fresh.allVariations,
      lastUsed: viewModel.lastUsedByExercise,
      pastSets: viewModel.pastSets,
      seed: ExerciseTarget(
        exerciseId: exerciseId,
        exerciseName: toProperCase(viewModel.exerciseDisplayName(exerciseId)),
        variationId: set.variationId,
        weight: set.weight,
        reps: set.reps.isEmpty ? null : set.reps.first.toInt(),
      ),
      onAdd: viewModel.createGoalFromTarget,
    );
  }

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

    // The pinned lesson shows right under the exercise — pinning is what
    // decides whether a note appears there.
    Lesson? pinnedLesson;
    for (final l in viewModel.lessonsFor(exerciseId)) {
      if (l.pinned) {
        pinnedLesson = l;
        break;
      }
    }

    void openLessonsModal() => showLessonsModal(
      context,
      listenable: viewModel.state,
      lessonsFor: viewModel.lessonsFor,
      loadLessonsFor: viewModel.loadLessonsFor,
      addLesson: viewModel.addLesson,
      toggleLessonPin: viewModel.toggleLessonPin,
      deleteLesson: viewModel.deleteLesson,
      updateLesson: viewModel.updateLessonText,
      exerciseId: exerciseId,
      exerciseName: name,
      // The record being read, not "whatever is live" — this session's
      // lessons form the sheet's first group, and its start splits the rest
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
          // The goal door (2026-10-26) — the owner's record in either mode.
          // A friend's passes none: the write would file under their id.
          onCreateGoal: readOnly
              ? null
              : () => _openGoalForSet(context, set.sessionExerciseSetId),
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
      pinnedLesson: pinnedLesson != null
          ? PinnedLessonData(
              text: pinnedLesson.text,
              date: pinnedLesson.createdDate,
            )
          : null,
      onPinnedLessonTap: openLessonsModal,
      // Session-scoped, so the pill, the floor tile and the live card's
      // count agree — a past session's lessons don't inflate this one.
      lessonsCount: viewModel.sessionLessonsCount(exerciseId),
      onLessonsTap: openLessonsModal,
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
