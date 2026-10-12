import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/swipe_actions.dart';
import '../../programs/view/review_container.dart';
import '../../programs/viewmodel/program_history_viewmodel.dart'
    show StartedReview;
import '../viewmodel/reviews_viewmodel.dart';
import 'review_cancel_dialog.dart';
import 'review_name_sheet.dart';
import 'review_selection_screen.dart';

/// The reviews library: every pass the user has, open ones pinned first, and
/// the + that starts a new one.
///
/// This is the standalone home reviews were given — a review contains workouts
/// and goals, not a program, so it does not begin by picking one. It is also
/// the only start surface *for now*, deliberately: the program and run entry
/// points are retired while the concept is ironed out, and their plumbing is
/// kept for the day it is not.
///
/// [showHeader] false is the embedded form — the Library's Reviews tab and the
/// dev lab — the same idiom as the workout library: the host owns the header,
/// and the compact + sits on a caption row instead.
class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key, this.showHeader = true, this.viewModel});

  final bool showHeader;

  /// The view model a host test injects. The seam exists for host tests —
  /// the real constructor reads Supabase — and a real caller never passes
  /// one.
  final ReviewsViewModel? viewModel;

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  late final ReviewsViewModel _vm;
  var _ownsVm = false;

  /// True while the + is assembling its two questions — the option lists are
  /// read between the name sheet and the picker, and the button must say so
  /// rather than sit there looking untouched.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final injected = widget.viewModel;
    _vm = injected ?? ReviewsViewModel();
    _ownsVm = injected == null;
    _vm.state.addListener(_onState);
    // A host test drives the load itself — it owns the VM's fakes. The screen
    // loads only when it owns the view model.
    if (_ownsVm) {
      _vm.load();
    } else {
      // Still reflect whatever the injected VM already holds.
      _onState();
    }
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.state.removeListener(_onState);
    if (_ownsVm) {
      _vm.dispose();
    }
    super.dispose();
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );

  /// + → name it → pick what to review → start, and open the ceremony on it.
  ///
  /// The row is written before the ceremony opens — the pass's whole job is to
  /// end in a snapshot on it — and the ceremony is opened by route, so
  /// finishing or backing out lands back on this list, reloaded either way.
  Future<void> _start() async {
    if (_busy) return;
    final name = await showReviewNameSheet(context);
    if (name == null || !mounted) return;

    setState(() => _busy = true);
    final List<ReviewableWorkout> workouts;
    final List<ReviewableGoal> goals;
    try {
      workouts = await _vm.reviewableWorkouts();
      goals = await _vm.reviewableGoals();
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('Could not load your workouts.');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final selection =
        await Navigator.of(context, rootNavigator: true).push<ReviewSelection>(
          MaterialPageRoute(
            builder: (_) => ReviewSelectionScreen(
              name: name,
              workouts: workouts,
              goals: goals,
            ),
          ),
        );
    if (selection == null || !mounted) return;

    final started = await _vm.startReview(
      sessionIds: selection.sessionIds,
      goalIds: selection.goalIds,
      title: name,
    );
    if (!mounted) return;
    if (started == null) {
      _snack('Could not start the review.');
      return;
    }
    await _openCeremony(
      started,
      // The stored ids, read back off the written row — with the picker's own
      // answer as the fallback, so a read that came back thin cannot drop the
      // goals half of the pass.
      goalIds: started.review.storedGoalIds ?? selection.goalIds,
    );
  }

  /// Reopens an open review — nothing is written. The row exists; that is the
  /// whole difference from [_start], and a tap that wrote a second row would
  /// fork one pass into two.
  Future<void> _resume(ReviewListEntry entry) async {
    final resumed = await _vm.resumeReview(entry.review);
    if (!mounted) return;
    if (resumed == null) {
      _snack('Could not open the review.');
      return;
    }
    await _openCeremony(
      resumed,
      goalIds: resumed.review.storedGoalIds ?? const [],
    );
  }

  /// Puts the ceremony up on [started] and reloads the list once it ends —
  /// ticks and a finish both live on the list.
  Future<void> _openCeremony(
    StartedReview started, {
    required List<String> goalIds,
  }) async {
    if (!mounted) return;
    await startReview(
      context,
      ReviewSession(
        reviewId: started.review.reviewId,
        programId: started.review.programId,
        // The resolution's own set, never the row's raw columns — those are
        // null on legacy rows and only the raw store of what was resolved.
        sessionIds: started.sessionIds,
        goalIds: goalIds,
        // The ticks already made in this pass: a resume must show what is
        // already done.
        reviewed: started.review.reviewedSessions,
        title: started.review.title,
        sinceDate: started.sinceDate,
        achievements: started.achievements,
      ),
    );
    if (mounted) await _vm.load();
  }

  /// A completed review opens on the landing it was walked on — read-only:
  /// the same workouts and goals, the ticks as they were recorded, and no way
  /// to write a thing. The ceremony's notifier is deliberately untouched: a
  /// record is not a pass being taken.
  Future<void> _openCompleted(ReviewListEntry entry) async {
    await openCompletedReview(
      context,
      completedReviewSession(
        review: entry.review,
        sessionIds: entry.sessionIds,
      ),
    );
  }

  /// Cancels an open pass: a confirm first — the row is deleted outright, and
  /// the ticks and notes go with it — then the write, then the list.
  Future<void> _cancel(ReviewListEntry entry) async {
    if (!await confirmCancelReview(context, label: entry.label)) return;
    if (!mounted) return;
    final cancelled = await _vm.cancelReview(entry.review.reviewId);
    if (!mounted || cancelled) return;
    _snack('Could not cancel the review.');
  }

  @override
  Widget build(BuildContext context) {
    final state = _vm.state.value;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          if (widget.showHeader)
            PageHeader(
              title: 'Reviews',
              right: GlassButton(
                label: '',
                icon: Icons.add,
                compact: true,
                loading: _busy,
                onPressed: _start,
              ),
            ),
          if (!widget.showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Passes over the workouts and goals you pick.',
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.xs,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GlassButton(
                    label: '',
                    icon: Icons.add,
                    compact: true,
                    loading: _busy,
                    onPressed: _start,
                  ),
                ],
              ),
            ),
          Expanded(child: _body(state)),
        ],
      ),
    );
  }

  Widget _body(ReviewsState state) {
    // The list stays up through a refresh — only a cold open has nothing to
    // show while the read is in flight.
    if (state.isLoading && state.entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: AppFonts.ui(
                  fontSize: AppTextStyles.md,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              GlassButton(label: 'Retry', onPressed: _vm.load),
            ],
          ),
        ),
      );
    }
    if (state.entries.isEmpty) return const _EmptyState();

    final open = state.open;
    final completed = state.completed;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        // Zero unless the shell's bar is floating over this list, which is
        // where the Library's Reviews tab lives.
        AppSpacing.lg + ScrollShrinkNavBar.contentInset(context),
      ),
      children: [
        if (open.isNotEmpty) ...[
          const _SectionLabel('IN PROGRESS'),
          const SizedBox(height: AppSpacing.sm),
          for (final entry in open) ...[
            SwipeActions(
              // Keyed by review, so a cancel never hands an open drawer's
              // state to the card that slides up into its place.
              key: ValueKey(entry.review.reviewId),
              actions: [
                SwipeAction(
                  icon: Icons.delete_outline,
                  label: 'Cancel',
                  color: AppColors.danger,
                  onTap: () => _cancel(entry),
                ),
              ],
              child: _OpenReviewCard(entry: entry, onTap: () => _resume(entry)),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
        if (completed.isNotEmpty) ...[
          const _SectionLabel('COMPLETED'),
          const SizedBox(height: AppSpacing.sm),
          for (final entry in completed) ...[
            _CompletedReviewCard(
              entry: entry,
              onTap: () => _openCompleted(entry),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ],
    );
  }
}

/// Nothing yet: the one place the screen can say what a review *is*, to
/// somebody who has never started one.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No reviews yet',
            style: AppFonts.ui(
              fontSize: AppTextStyles.md,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'A review is a pass over workouts you pick: open each one, change '
            'what needs changing, note what you think — then finish it and it '
            'is kept here.',
            textAlign: TextAlign.center,
            style: AppFonts.ui(
              fontSize: AppTextStyles.xs,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

/// An open review: what it is, how far through, and the way back in.
///
/// The accent border is the state, not decoration — the list is mostly record,
/// and this is the one kind of row that is still asking something of the user.
class _OpenReviewCard extends StatelessWidget {
  const _OpenReviewCard({required this.entry, required this.onTap});

  final ReviewListEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      borderColor: AppColors.accent,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.md,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.reviewedCount} of ${entry.total} reviewed',
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GlassButton(
            label: 'Resume',
            compact: true,
            color: AppColors.accent,
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}

/// A completed review: what it was, and when it was taken.
class _CompletedReviewCard extends StatelessWidget {
  const _CompletedReviewCard({required this.entry, required this.onTap});

  final ReviewListEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final review = entry.review;
    final goals = review.storedGoalIds?.length ?? 0;
    final caption = [
      entry.total == 1 ? '1 workout' : '${entry.total} workouts',
      if (goals > 0) goals == 1 ? '1 goal' : '$goals goals',
      DateFormat('d MMM yyyy').format(review.effectiveDate),
    ].join(' · ');

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.ui(
                    fontSize: AppTextStyles.md,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 16, color: AppColors.muted),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppFonts.mono(
      fontSize: AppTextStyles.xs,
      color: AppColors.muted,
      letterSpacing: 0.8,
    ),
  );
}
