import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/styles/app_colors.dart';
import '../../../core/styles/app_fonts.dart';
import '../../../core/styles/app_radius.dart';
import '../../../core/styles/app_spacing.dart';
import '../../../core/styles/app_text_styles.dart';
import '../../../core/utils/session_format.dart';
import '../../../data/models/program_block.dart';
import '../../../data/models/program_review.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/scroll_shrink_nav_bar.dart';
import '../model/program_content_diff.dart';
import '../viewmodel/program_history_viewmodel.dart';
import 'content_diff_sheet.dart';
import 'review_container.dart';
import 'review_detail_sheet.dart';
import 'review_snapshot_screen.dart';

/// A program's history: the reviews that checkpoint it, newest first, each one
/// able to show the program as it stood when it was taken.
///
/// Checkpoints are the whole record now — a review is the only thing that
/// writes one, whether the user scheduled it or a run ended. The row answers
/// "what did we say about it, and what was true then", and opening it reads
/// back the snapshot it froze.
///
/// It loads itself. The program screen's Reviews tab and the pushed History
/// screen — how a block editor links to its own phase — are the same read at
/// two sizes, and neither host has a reason to own the state.
class ProgramHistoryPanel extends StatefulWidget {
  const ProgramHistoryPanel({
    super.key,
    required this.programId,
    this.initialBlockId,
  });

  final String programId;

  /// Opens with the timeline already scoped to this block. Set when a block
  /// is what the user came from — "what happened during this phase" is a
  /// different question from "what has this program been", and arriving with
  /// the filter already applied is the whole point of the entry point.
  final String? initialBlockId;

  @override
  State<ProgramHistoryPanel> createState() => _ProgramHistoryPanelState();
}

class _ProgramHistoryPanelState extends State<ProgramHistoryPanel>
    with AutomaticKeepAliveClientMixin {
  final _vm = ProgramHistoryViewModel();

  // The tab view disposes pages that scroll out of it, and this panel's load
  // decodes every snapshot's contents — not something to redo on a swipe back.
  // It reloads when it is meant to: on entry, and when the program screen
  // bumps the key it is built under.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Deferred: `load` writes the notifier synchronously, and mutating state
    // during the first build is not allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _vm.load(widget.programId);
      final blockId = widget.initialBlockId;
      // Applied after the load rather than before: `load` drops a filter that
      // names a block it did not find, and setting it first would race that.
      if (blockId != null && mounted) _vm.setBlockFilter(blockId);
    });
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  /// Reopens [review] — it was already open, and the card is how it is entered.
  ///
  /// Nothing is written: the row exists, and that is the whole difference from
  /// [_start]. A card tap that inserted a second row would fork one pass into
  /// two reviews, each asking its own question and cutting its own snapshot.
  Future<void> _resume(ProgramReview review) async {
    final resumed = await _vm.resumeReview(widget.programId, review);
    if (!mounted) return;
    if (resumed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the review.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await _openCeremony(resumed);
  }

  /// Puts the ceremony up on [started] and reloads the timeline once it ends.
  Future<void> _openCeremony(StartedReview started) async {
    if (!mounted) return;
    final finished = await startReview(
      context,
      ReviewSession(
        reviewId: started.review.reviewId,
        programId: widget.programId,
        // The resolution's own set, never the row's raw columns — those are
        // null on legacy rows and stale on none.
        sessionIds: started.sessionIds,
        // The ticks already made in this pass: the run prompt and a resume
        // both land here, and both must show what is already done.
        reviewed: started.review.reviewedSessions,
        title: started.review.title,
        sinceDate: started.sinceDate,
        achievements: started.achievements,
      ),
    );
    // Only a finish cut a snapshot; backing out left the review open, and the
    // timeline already shows it from the viewmodel's own reload.
    if (finished == true && mounted) await _vm.load(widget.programId);
  }

  /// Opens one checkpoint. A completed one is a record and reads back its own
  /// snapshot; an open one is a pass still to be taken.
  Future<void> _open(ProgramHistoryState state, ProgramReview review) async {
    if (review.isOpen) {
      await _resume(review);
      return;
    }
    if (!review.hasSnapshot) return;

    final previous = _previousCheckpoint(state, review);
    final before = previous == null ? null : scopedSnapshot(previous);
    final content = scopedSnapshot(review);
    final change = before != null && content != null
        ? diffContent(
            before,
            content,
            exerciseNames: state.exerciseNames,
            variationNames: state.variationNames,
          )
        : null;

    await showReviewDetailSheet(
      context,
      review: review,
      usesBlocks: state.usesBlocks,
      change: change,
      exerciseNames: state.exerciseNames,
      onViewChanges: change == null
          ? null
          : () => _showChanges(state, review, previous!),
      onViewWorkouts: () => _openSnapshot(state, review),
    );
  }

  /// The whole diff, at the size it deserves.
  void _showChanges(
    ProgramHistoryState state,
    ProgramReview review,
    ProgramReview previous,
  ) {
    final before = scopedSnapshot(previous);
    final after = scopedSnapshot(review);
    if (before == null || after == null) return;
    showContentDiffSheet(
      context,
      title: review.title?.trim().isNotEmpty == true
          ? review.title!.trim()
          : kReviewChangesTitle,
      subtitle:
          '${DateFormat('MMM d').format(previous.effectiveDate)}'
          '  ·  '
          '${DateFormat('MMM d, yyyy').format(review.effectiveDate)}',
      before: before,
      after: after,
      exerciseNames: state.exerciseNames,
      variationNames: state.variationNames,
    );
  }

  /// Opens one checkpoint's snapshot. Pushed on the ROOT navigator, matching
  /// the workout editor (`PlanSessionScreen`) — a snapshot is a full-screen
  /// read of one record, not another level of the tab it was reached from.
  void _openSnapshot(ProgramHistoryState state, ProgramReview review) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ReviewSnapshotScreen(
          review: review,
          previous: _previousCheckpoint(state, review),
          exerciseNames: state.exerciseNames,
          variationNames: state.variationNames,
        ),
      ),
    );
  }

  /// The completed same-scope checkpoint before [review] that carries a
  /// snapshot — the one its "Changes" sheet diffs against.
  ///
  /// Same pairing rule as the viewmodel's digests: two checkpoints compare only
  /// when they cover the same workouts ([reviewScopeKey] — a legacy row's old
  /// one-thing scope keys the same way it always did). A scope that has changed
  /// in between is skipped, never bridged.
  static ProgramReview? _previousCheckpoint(
    ProgramHistoryState state,
    ProgramReview review,
  ) {
    final i = state.reviews.indexWhere((r) => r.reviewId == review.reviewId);
    if (i < 0) return null;
    final key = reviewScopeKey(review);
    for (var j = i + 1; j < state.reviews.length; j++) {
      final r = state.reviews[j];
      if (r.hasSnapshot && reviewScopeKey(r) == key) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    // One review at a time. This panel is itself reachable from inside a
    // program-scope review — the program screen's Reviews tab is part of what
    // is being reviewed — and the ceremony is a single global session, so a
    // second review would fight the first for the bar. The container refuses
    // as the backstop; here the controls go inert.
    final reviewing = ReviewScope.maybeOf(context) != null;
    return ValueListenableBuilder<ProgramHistoryState>(
      valueListenable: _vm.state,
      builder: (context, state, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'HISTORY',
                      style: AppFonts.mono(
                        fontSize: AppTextStyles.xs,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  // No Review button here: starting a pass is the Reviews
                  // tab's job now — reviews are workouts and goals, not a
                  // program, so this timeline resumes passes (the cards below)
                  // and no longer creates them.
                ],
              ),
            ),
            // Only a program that uses blocks has anything to scope by — a
            // blockless program's history is the same panel it always was.
            if (state.blocks.isNotEmpty)
              _BlockFilterRow(
                blocks: state.blocks,
                value: state.blockFilter,
                onChange: _vm.setBlockFilter,
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
              child: state.isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    )
                  : _ReviewList(
                      state: state,
                      reviewing: reviewing,
                      onOpen: (r) => _open(state, r),
                      onDismiss: (r) => _vm.dismissReview(
                        widget.programId,
                        r.reviewId,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ReviewList extends StatelessWidget {
  const _ReviewList({
    required this.state,
    required this.reviewing,
    required this.onOpen,
    required this.onDismiss,
  });

  final ProgramHistoryState state;

  /// Whether a review is already running — see the panel's build.
  final bool reviewing;

  final ValueChanged<ProgramReview> onOpen;
  final ValueChanged<ProgramReview> onDismiss;

  @override
  Widget build(BuildContext context) {
    final reviews = state.visibleReviews;
    if (reviews.isEmpty) {
      return const _EmptyTab(
        'No reviews yet',
        detail:
            'A review is a pass over the plan with a record of what it looked '
            'like attached. Start one when you want to look through a workout, '
            'a block, or the whole program.',
      );
    }
    return ListView.separated(
      // Zero on the review route, which sits over the shell — the history
      // panel is read inside the shell's Reviews tab and inside a review.
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + ScrollShrinkNavBar.contentInset(context),
      ),
      itemCount: reviews.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final review = reviews[i];
        return _ReviewCard(
          review: review,
          // Only the open one gets the achievements treatment — a closed
          // review reads back its frozen record instead.
          isDue: review.isDue(DateTime.now()),
          // What it changed, already derived from consecutive same-scope
          // snapshots — the Versions timeline's question, on the row.
          changeSummary: state.digestFor(review.reviewId).vsPrevious?.summary,
          // An open review opens the ceremony, which is occupied. A completed
          // one only reads back, so it stays reachable.
          onTap: review.isOpen && reviewing ? null : () => onOpen(review),
          onDismiss: review.isOpen ? () => onDismiss(review) : null,
        );
      },
    );
  }
}

/// One review in the timeline. Open, due, done and dismissed are four states of
/// one row, not four widgets.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.review,
    required this.isDue,
    required this.changeSummary,
    required this.onTap,
    this.onDismiss,
  });

  final ProgramReview review;
  final bool isDue;
  final String? changeSummary;

  /// Null when the row is inert — nothing to read back, or an open review whose
  /// ceremony is already occupied.
  final VoidCallback? onTap;

  /// "Not now" — only an open review can be dismissed, because only an open
  /// one is asking anything.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final open = review.isOpen;
    final accent = isDue && open;

    // A completed checkpoint opens read-only; an open one opens the plan.
    // One completed without a snapshot (a dismissal, or a record written
    // before the snapshot column existed) has nothing to open.
    return AppCard(
      onTap: (open || review.hasSnapshot) ? onTap : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (review.title?.trim().isNotEmpty == true
                          ? review.title!.trim()
                          : reviewKindLabel(review.kind))
                      .toUpperCase(),
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: accent ? AppColors.accent : AppColors.primary,
                  ),
                ),
              ),
              _StatusChip(review: review, accent: accent),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  _when(review),
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    color: accent ? AppColors.accent : AppColors.muted,
                  ),
                ),
              ),
              // The timeline's answer to "what did this one change?" — the
              // same line the checkpoint's own sheet leads with.
              if (changeSummary != null && !open)
                Text(
                  changeSummary!,
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    color: AppColors.muted,
                  ),
                ),
              if (onDismiss != null)
                GestureDetector(
                  onTap: onDismiss,
                  child: Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: Text(
                      'Dismiss',
                      style: AppFonts.ui(
                        fontSize: AppTextStyles.xs,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (review.notes?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              review.notes!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A closed review reports when it was completed. An open one has no end
  /// date yet: it reports when it came due where a date was ever set — rows
  /// from the scheduling era — and otherwise when it was started, which since
  /// reviews begin the moment they are set up is every review taken now.
  static String _when(ProgramReview r) {
    if (r.completedDate != null) {
      return 'completed ${DateFormat('MMM d, yyyy').format(r.completedDate!)}';
    }
    final due = r.scheduledFor;
    if (due != null) {
      return 'due ${DateFormat('EEE, d MMM yyyy').format(due)}';
    }
    return 'started ${DateFormat('MMM d, yyyy').format(r.createdDate)}';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.review, required this.accent});

  final ProgramReview review;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final label = review.isOpen
        ? (accent ? 'DUE' : 'OPEN')
        : reviewOutcomeLabel(review.outcome).toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      // The same chrome as the outcome chip on a snapshot's header, so the
      // two chips read as the same kind of thing.
      decoration: accent
          ? lambdaBox(ContainerTone.accent)
          : lambdaBox(ContainerTone.ghost),
      child: Text(
        label,
        style: AppFonts.mono(
          fontSize: AppTextStyles.xs,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: accent ? AppColors.accent : AppColors.muted,
        ),
      ),
    );
  }
}

/// Scopes the timeline to one block. A review's `block_id` IS its scope, so
/// this narrows to the checkpoints taken of that block — it never re-reads a
/// program checkpoint as if it were one.
///
/// A scrolling chip row rather than a segmented control: a program can have
/// more blocks than fit, and the segmented control's equal-width cells would
/// squeeze the names to nothing.
class _BlockFilterRow extends StatelessWidget {
  const _BlockFilterRow({
    required this.blocks,
    required this.value,
    required this.onChange,
  });

  final List<ProgramBlock> blocks;
  final String? value;
  final ValueChanged<String?> onChange;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          _chip(
            label: 'All',
            selected: value == null,
            onTap: () => onChange(null),
          ),
          for (final b in blocks) ...[
            const SizedBox(width: AppSpacing.sm),
            _chip(
              label: b.name,
              selected: value == b.blockId,
              onTap: () => onChange(b.blockId),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      alignment: Alignment.center,
      decoration: selected
          ? lambdaBox(ContainerTone.accent, radius: AppRadius.md)
          : lambdaBox(ContainerTone.ghost, radius: AppRadius.md),
      child: Text(
        toProperCase(label),
        style: AppFonts.ui(
          fontSize: AppTextStyles.sm,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: AppColors.primary,
        ),
      ),
    ),
  );
}

/// The empty state points at the action row above rather than duplicating the
/// button.
class _EmptyTab extends StatelessWidget {
  const _EmptyTab(this.title, {this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: AppFonts.ui(
              fontSize: AppTextStyles.md,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: AppFonts.ui(
                fontSize: AppTextStyles.sm,
                color: AppColors.muted,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
