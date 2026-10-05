import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../data/models/planned_session.dart';
import '../../../data/models/program_block.dart';
import '../../../data/models/program_review.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../shared/widgets/glass_button.dart';
import '../model/program_achievements.dart';
import '../viewmodel/program_detail_viewmodel.dart';
import 'plan_session_screen.dart';
import 'program_block_editor_screen.dart';
import 'program_detail_screen.dart';
import 'review_notes_sheet.dart';

/// The review currently being taken, or null.
///
/// A review is not a screen. It is a *ceremony* around the editors that already
/// exist: you pick a scope, the normal editor opens for it, you look through
/// the plan and change what needs changing, and when you finish the plan is
/// snapshotted onto the review row. That is why this is above the navigator
/// rather than a route — the bar has to survive drilling into a workout, and
/// the editor has to be the real one, not a copy.
///
/// Deliberately a plain top-level notifier, matching `themeNotifier`: the
/// session outlives every route in the stack, which is exactly the lifetime no
/// widget owns.
final reviewSessionNotifier = ValueNotifier<ReviewSession?>(null);

/// What the review ceremony is currently examining. Everything the bar and the
/// notes sheet need, captured at start and never re-read.
class ReviewSession {
  const ReviewSession({
    required this.reviewId,
    required this.programId,
    required this.scopeKind,
    required this.scopeLabel,
    this.blockId,
    this.sessionId,
    this.title,
    this.sinceDate,
    this.achievements,
  });

  final String reviewId;
  final String programId;
  final ReviewScopeKind scopeKind;

  /// What to call the scope on the bar — "Whole program", or the block's or
  /// workout's name. Captured rather than derived: the editor below can rename
  /// a block mid-review, and a label that silently rewrote itself under the
  /// user's eyes would read as a bug, not a feature.
  final String scopeLabel;

  final String? blockId;
  final String? sessionId;
  final String? title;

  /// Where the "since" window opens — the completion of the previous review at
  /// this same scope, or the run's start. Null hides the line.
  final DateTime? sinceDate;

  /// What the program produced inside that window, carried to the finish sheet
  /// rather than shown on the review itself.
  ///
  /// The editor is where the plan is examined; this is the context for the
  /// notes written at the end, and the notes are the record of *why* the plan
  /// now says what it says. Captured at start because the derivation belongs to
  /// the history screen that already ran it — re-deriving here would read the
  /// whole training history a second time for a sheet the user may never open.
  final ProgramAchievements? achievements;
}

/// Publishes the ambient [ReviewSession] to the whole tree, above the
/// navigator so every pushed route and `useRootNavigator` sheet is a
/// descendant. That is what lets the editor's own bottom bar carry the review
/// bar without either knowing about the other.
class ReviewScope extends InheritedNotifier<ValueNotifier<ReviewSession?>> {
  ReviewScope({super.key, required super.child})
    : super(notifier: reviewSessionNotifier);

  static ReviewSession? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ReviewScope>()
      ?.notifier
      ?.value;
}

/// Opens the ceremony for [session] — pushes the editor route and puts the bar
/// up.
Future<bool?> startReview(BuildContext context, ReviewSession session) {
  reviewSessionNotifier.value = session;
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      settings: const RouteSettings(name: kReviewRouteName),
      builder: (_) => ReviewRoute(session: session),
    ),
  );
}

/// The name [startReview]'s route carries, so the bar can unwind back to it
/// after a finish without knowing how deep the user drilled.
const kReviewRouteName = 'lambda-review';

/// The editor for the review's scope, rendered inline.
///
/// It owns its [ProgramDetailViewModel] rather than borrowing one, because the
/// review is reachable from places that have no program screen open — and it
/// passes that view model down, so drilling into a workout shares one piece of
/// state instead of accumulating copies that can disagree.
class ReviewRoute extends StatefulWidget {
  const ReviewRoute({super.key, required this.session});

  final ReviewSession session;

  @override
  State<ReviewRoute> createState() => _ReviewRouteState();
}

class _ReviewRouteState extends State<ReviewRoute> {
  late final ProgramDetailViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = ProgramDetailViewModel();
    _vm.load(widget.session.programId);
  }

  @override
  void dispose() {
    // Only clear what is still ours. A second review started from within the
    // first (or a sign-out redirect, or a hot restart) disposes this route
    // with a different session already live, and blanking that one would tear
    // the bar out from under the review the user is actually in.
    //
    // Deferred past the frame, because the write notifies `ReviewScope`,
    // which marks itself needing to build — and the cases this guard exists
    // for (a hot restart, a router redirect) unmount the tree *during* a
    // build. Writing here directly tripped "setState() or markNeedsBuild()
    // called when widget tree was locked" on every hot restart.
    final session = widget.session;
    if (identical(reviewSessionNotifier.value, session)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (identical(reviewSessionNotifier.value, session)) {
          reviewSessionNotifier.value = null;
        }
      });
    }
    // Safe despite children holding `_vm`: they are pushed routes, and a route
    // can only be disposed after everything above it has gone.
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProgramDetailState>(
      valueListenable: _vm.state,
      builder: (context, state, _) {
        if (state.isLoading && state.program == null) {
          return Scaffold(
            backgroundColor: AppColors.bg,
            body: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _editorFor(state) ?? _missing();
      },
    );
  }

  Widget? _editorFor(ProgramDetailState state) {
    switch (widget.session.scopeKind) {
      case ReviewScopeKind.program:
        return ProgramDetailScreen(
          programId: widget.session.programId,
          viewModel: _vm,
        );

      case ReviewScopeKind.block:
        final block = _blockOf(state, widget.session.blockId);
        if (block == null) return null;
        return ProgramBlockEditorScreen(viewModel: _vm, block: block);

      case ReviewScopeKind.session:
        final workout = _workoutOf(state, widget.session.sessionId);
        if (workout == null) return null;
        return PlanSessionScreen(viewModel: _vm.editor, workout: workout);
    }
  }

  ProgramBlock? _blockOf(ProgramDetailState state, String? blockId) {
    if (blockId == null) return null;
    for (final b in state.blocks) {
      if (b.blockId == blockId) return b;
    }
    return null;
  }

  PlannedSession? _workoutOf(ProgramDetailState state, String? sessionId) {
    if (sessionId == null) return null;
    for (final w in state.plannedWorkouts) {
      if (w.sessionId == sessionId) return w;
    }
    return null;
  }

  /// The scope named a row the program no longer has — it was deleted between
  /// the review being scheduled and being opened. Says so rather than opening
  /// the wrong editor or a blank screen.
  Widget _missing() => Scaffold(
    backgroundColor: AppColors.bg,
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          'This review\'s ${widget.session.scopeKind == ReviewScopeKind.block ? 'block' : 'workout'} '
          'is no longer in the program.',
          textAlign: TextAlign.center,
          style: AppFonts.ui(color: AppColors.muted),
        ),
      ),
    ),
  );
}

/// What an editor should put in its `bottomNavigationBar` slot: the review bar
/// stacked above [child], or [child] untouched when no review is running.
///
/// A function rather than a widget for one reason that matters: with no review
/// running and no child it returns **null**, which is what leaves a `Scaffold`
/// with no bottom navigation bar at all. Handing it a zero-height placeholder
/// instead would flip the `Scaffold`'s internal `removeBottomPadding`, and the
/// editor's content would start scrolling under the home indicator with
/// nothing drawn there. `program_detail_screen` and
/// `program_block_editor_screen` have no bottom bar today, so for them that
/// null is the difference between "unchanged" and "subtly broken".
///
/// A slot rather than wrapping the whole `Scaffold` in a `Column`, because the
/// editors already own their `SafeArea` and keyboard insets in this slot and a
/// wrapper would sit below the bar's own chrome.
///
/// [settle] resolves the enclosing editor's unsaved changes, and is called
/// before the notes sheet opens — a review snapshots the plan as it actually
/// stands, so an unsettled editor would capture the stored state rather than
/// the edits the user just made.
Widget? reviewBottomSlot(
  BuildContext context, {
  required Future<bool> Function() settle,
  Widget? child,
}) {
  final session = ReviewScope.maybeOf(context);
  if (session == null) return child;
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ReviewBar(
        session: session,
        settle: settle,
        // Alone in the slot it is the bottom-most thing on the screen, so it
        // has to carry the home-indicator inset; stacked above [child] that
        // child is, and owns it.
        ownsBottomInset: child == null,
      ),
      ?child,
    ],
  );
}

/// The bar itself: what is being reviewed, a way to finish, and a way out.
class ReviewBar extends StatefulWidget {
  const ReviewBar({
    super.key,
    required this.session,
    required this.settle,
    this.ownsBottomInset = false,
  });

  final ReviewSession session;
  final Future<bool> Function() settle;

  /// Whether the bar has to keep its controls clear of the home indicator
  /// itself. The inset is folded into the bar's own padding — the way
  /// `BottomNavBar` does it — so the accent still reaches the screen edge
  /// while the buttons stay out of the gesture zone.
  ///
  /// False when an editor bar is stacked under it: that bar already absorbs
  /// the inset, and padding here as well would open a strip of accent
  /// between the two.
  final bool ownsBottomInset;

  @override
  State<ReviewBar> createState() => _ReviewBarState();
}

class _ReviewBarState extends State<ReviewBar> {
  bool _finishing = false;

  /// The bar's bottom padding: the home-indicator inset **in place of** the
  /// base padding, never in addition to it.
  ///
  /// Stacking the two leaves the content sitting high with a dead band under
  /// it. And when there is no inset — an older device, or a raised keyboard,
  /// where it drops to zero — the content would instead sit flush against the
  /// bottom edge, so the base padding is the floor.
  double _bottomPadding(BuildContext context) {
    if (!widget.ownsBottomInset) return AppSpacing.lg;
    final inset = MediaQuery.of(context).padding.bottom;
    return inset > AppSpacing.lg ? inset : AppSpacing.lg;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        border: Border(top: BorderSide(color: AppColors.accent.withValues(alpha: 0.30))),
      ),
      // The sides take `xl` — a step wider than the editors' own content —
      // so the label and the Finish button are not crowding the screen
      // edges. Top stays `lg`, matching the bar's other chrome.
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        _bottomPadding(context),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Reviewing',
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.accentText,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  widget.session.scopeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.sm,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentText,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _finishing ? null : _leave,
            icon: const Icon(Icons.close, size: 20),
            color: AppColors.accentText,
            tooltip: 'Leave without finishing',
            visualDensity: VisualDensity.compact,
          ),
          GlassButton(
            label: 'Finish',
            compact: true,
            loading: _finishing,
            color: AppColors.accentText,
            onPressed: _finish,
          ),
        ],
      ),
    );
  }

  /// Walks out of the ceremony without completing the review. The review stays
  /// open and untouched — reviewing is optional, and someone who opened one to
  /// look around must be able to back out without a snapshot being cut.
  void _leave() {
    reviewSessionNotifier.value = null;
    _unwind(finished: false);
  }

  Future<void> _finish() async {
    // Settle first: the snapshot must record the plan the user just edited,
    // and a save that fails leaves the dialog's answer as "no".
    if (!await widget.settle()) return;
    if (!mounted) return;

    final notes = await showReviewNotesSheet(context, session: widget.session);
    // Dismissed the sheet — back to the editor, still reviewing.
    if (notes == null || !mounted) return;

    setState(() => _finishing = true);
    try {
      final userId = _currentUserId();
      await ProgramHistoryRepository().completeReview(
        widget.session.reviewId,
        userId: userId,
        outcome: kOutcomeReviewed,
        notes: notes.isEmpty ? null : notes,
      );
      if (!mounted) return;
      reviewSessionNotifier.value = null;
      _unwind(finished: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _finishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not finish the review: $e')),
      );
    }
  }

  /// Pops everything the user drilled into, then the review route itself, so
  /// Finish lands back where the review started rather than one screen up.
  void _unwind({required bool finished}) {
    final nav = Navigator.of(context, rootNavigator: true);
    var atReview = false;
    nav.popUntil((route) {
      if (route.settings.name == kReviewRouteName) atReview = true;
      return atReview;
    });
    if (atReview) nav.pop(finished);
  }
}

String _currentUserId() {
  final id = Supabase.instance.client.auth.currentUser?.id;
  if (id == null) {
    throw StateError('Cannot finish a review while signed out.');
  }
  return id;
}
