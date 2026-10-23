import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/date_range.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/date_range_selector.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/lambda_search_field.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../../../shared/widgets/swipe_actions.dart';
import '../../programs/view/review_container.dart';
import '../../programs/viewmodel/program_history_viewmodel.dart'
    show StartedReview;
import '../viewmodel/reviews_viewmodel.dart';
import 'review_dialogs.dart';
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
/// The tab wears the library's toolbar (2026-10-19): search narrows both
/// halves by name, and the date button opens the shared range sheet for the
/// records. A date filter never hides an open pass — that is current work,
/// not history — so it only narrows the COMPLETED half.
///
/// [showHeader] false is the embedded form — the Library's Reviews tab and the
/// dev lab — the same idiom as the workout library: the host owns the header,
/// and the compact + stands in the toolbar instead.
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

  final _searchController = TextEditingController();
  String _query = '';

  /// All time until the date button says otherwise. The same shared selection
  /// the Logs and exercise-insights filters use, so the sheet and the list
  /// cannot disagree about what a range means.
  static const _allTime = DateRangeSelection.preset(DateRangePreset.all);
  DateRangeSelection _dateSelection = _allTime;

  bool get _dateActive => _dateSelection != _allTime;

  @override
  void initState() {
    super.initState();
    final injected = widget.viewModel;
    _vm = injected ?? ReviewsViewModel();
    _ownsVm = injected == null;
    _vm.state.addListener(_onState);
    _searchController.addListener(() {
      if (mounted) setState(() => _query = _searchController.text);
    });
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
    _searchController.dispose();
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

    final selection = await Navigator.of(context, rootNavigator: true)
        .push<ReviewSelection>(
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

  /// Deletes a completed record: a confirm first — a record is the finished
  /// thing the pass existed to make — then the write, then the list.
  Future<void> _deleteCompleted(ReviewListEntry entry) async {
    if (!await confirmDeleteCompletedReview(context, label: entry.label)) {
      return;
    }
    if (!mounted) return;
    final deleted = await _vm.deleteCompletedReview(entry.review.reviewId);
    if (!mounted || deleted) return;
    _snack('Could not delete the review.');
  }

  /// The shared range sheet, seeded with the range in force. Picking a preset
  /// is one tap; a custom range is the calendar's.
  Future<void> _pickDate() async {
    final selection = await showDateRangeSelector(
      context,
      initial: _dateSelection,
    );
    if (selection != null && mounted) {
      setState(() => _dateSelection = selection);
    }
  }

  /// Search reads the whole row: the pass's label, its stored title, and the
  /// workouts it covered — typing "bench" finds a pass by what was in it, not
  /// only by what it was called.
  bool _matchesSearch(ReviewListEntry entry) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    final haystack = [
      entry.label,
      entry.review.title ?? '',
      ...entry.workoutNames,
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  /// A date filter narrows the RECORDS only. An open pass is current work, not
  /// history — hiding it because it sits outside the chosen range would take
  /// the one thing still asking something of the user off the screen.
  bool _matchesDate(ReviewListEntry entry) {
    if (!_dateActive) return true;
    final completed = entry.review.completedDate;
    if (completed == null) return true;
    final window = _dateSelection.window(DateTime.now());
    return !completed.isBefore(window.from) && completed.isBefore(window.to);
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
                semanticsLabel: 'Start review',
                compact: true,
                loading: _busy,
                onPressed: _start,
              ),
            ),
          _toolbar(showAdd: !widget.showHeader),
          Expanded(child: _body(state)),
        ],
      ),
    );
  }

  /// The toolbar every library tab wears (2026-10-19): search, then the date
  /// button, then the tab's own + where the host header has none.
  ///
  /// The date button is icon-only to keep the search box wide on a phone —
  /// its state reads off the accent, and the sheet it opens names the range
  /// in words.
  Widget _toolbar({required bool showAdd}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: LambdaSearchField(
              controller: _searchController,
              hint: 'Search reviews…',
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Semantics(
            button: true,
            label: 'Date filter',
            child: GlassButton(
              label: '',
              icon: Icons.date_range_outlined,
              compact: true,
              color: _dateActive ? AppColors.accent : null,
              onPressed: _pickDate,
            ),
          ),
          if (showAdd) ...[
            const SizedBox(width: AppSpacing.sm),
            GlassButton(
              label: '',
              icon: Icons.add,
              semanticsLabel: 'Start review',
              compact: true,
              loading: _busy,
              onPressed: _start,
            ),
          ],
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

    final open = state.open.where(_matchesSearch).toList();
    final completed = state.completed
        .where(_matchesSearch)
        .where(_matchesDate)
        .toList();
    if (open.isEmpty && completed.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            _query.trim().isNotEmpty
                ? 'No reviews match "${_query.trim()}".'
                : 'No reviews in this range.',
            textAlign: TextAlign.center,
            style: AppFonts.ui(
              fontSize: AppTextStyles.md,
              color: AppColors.inkSecondary,
            ),
          ),
        ),
      );
    }
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

                  color: AppColors.danger,
                  foreground: AppColors.dangerText,
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
            SwipeActions(
              // Keyed by review, like the open drawer: a delete must not hand
              // one record's drawer state to the card that slides up into its
              // place.
              key: ValueKey(entry.review.reviewId),
              actions: [
                SwipeAction(
                  icon: Icons.delete_outline,
                  color: AppColors.danger,
                  foreground: AppColors.dangerText,
                  onTap: () => _deleteCompleted(entry),
                ),
              ],
              child: _CompletedReviewCard(
                entry: entry,
                onTap: () => _openCompleted(entry),
              ),
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
              color: AppColors.inkSecondary,
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
              color: AppColors.inkSecondary,
              height: 1.4,
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
                    color: AppColors.inkSecondary,
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
      fontWeight: FontWeight.w600,
      color: AppColors.primary,
      letterSpacing: 0.8,
    ),
  );
}
