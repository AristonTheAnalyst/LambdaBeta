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
import '../../../data/models/program_revision.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/container_styles.dart';
import '../../../shared/widgets/glass_button.dart';
import '../../../shared/widgets/segmented_control.dart';
import '../model/program_revision_diff.dart';
import '../viewmodel/program_history_viewmodel.dart';
import 'program_revision_screen.dart';
import 'review_sheet.dart';
import 'revision_diff_sheet.dart';
import 'schedule_review_sheet.dart';

/// A program's history — the versions its contents have passed through, and
/// the reviews that checkpointed them — as one panel.
///
/// Two segments rather than one merged list because they answer different
/// questions. Versions answer "what changed?" and are the complete record;
/// reviews answer "what did we say about it?" and are the small subset someone
/// actually wrote. Merging them would bury the second in the first.
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
  // decodes every revision's contents — not something to redo on a swipe back.
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

  Future<void> _capture() async {
    final revision = await _vm.capture(widget.programId);
    if (!mounted) return;
    // Only on success — a failure is already reported by the error bar, and
    // saying it twice would be noise.
    if (revision != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Version ${revision.revisionNumber} saved.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _schedule() async {
    final request = await showScheduleReviewSheet(context);
    if (request == null || !mounted) return;
    final review = await _vm.scheduleReview(
      widget.programId,
      // Scheduled while scoped to a block, this is that block's checkpoint —
      // the block id is recorded as context so the timeline can group by it.
      blockId: _vm.state.value.blockFilter,
      title: request.title,
      notes: request.notes,
      scheduledFor: request.scheduledFor,
      withProposal: request.isChange,
    );
    if (!mounted || review == null) return;
    _vm.setTab(HistoryTab.reviews);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${reviewKindLabel(review.kind)} scheduled for '
          '${DateFormat('d MMM').format(request.scheduledFor)}.',
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Opens the checkpoint and acts on what the user decides.
  Future<void> _review(ProgramHistoryState state, ProgramReview review) async {
    final decision = await showReviewSheet(
      context,
      review: review,
      achievements: state.achievements,
      proposedSummary: _proposalSummary(review),
      onViewProposal: () => _showProposal(state, review),
    );
    if (decision == null || !mounted) return;

    // "Make changes" is the one answer that does not close the review: the
    // user is going to edit the program, and completing the checkpoint before
    // they have would record a revision of the state they rejected.
    if (decision.outcome == null) {
      if (decision.wantsEditor) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Edit the program, then come back and complete this review.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final revision = await _vm.completeReview(
      widget.programId,
      review.reviewId,
      outcome: decision.outcome!,
    );
    if (!mounted || revision == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Version ${revision.revisionNumber} saved.'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// What a proposal says, in the terms the timeline uses — it is one more
  /// document of the same shape, diffed against the program as it stands now.
  Future<void> _showProposal(
    ProgramHistoryState state,
    ProgramReview review,
  ) async {
    final proposal = review.proposal;
    if (proposal == null) return;
    final live = await _vm.liveContent(widget.programId);
    if (!mounted) return;
    showRevisionDiffSheet(
      context,
      title: review.title?.trim().isNotEmpty == true
          ? review.title!.trim()
          : 'Proposed change',
      subtitle: 'proposed  ·  against the program today',
      before: live,
      after: proposal,
      exerciseNames: state.exerciseNames,
    );
  }

  String? _proposalSummary(ProgramReview review) {
    final proposal = review.proposal;
    if (proposal == null) return null;
    final sessions = proposal.sessions.length;
    final sets = proposal.sessions.fold<int>(
      0,
      (n, s) => n + s.exercises.fold<int>(0, (m, e) => m + e.sets.length),
    );
    return 'Proposes $sessions workouts · $sets sets.';
  }

  /// Opens one version. Pushed on the ROOT navigator, matching the workout
  /// editor (`PlanSessionScreen`) — a version is a full-screen read of one
  /// record, not another level of the tab it was reached from.
  void _open(ProgramHistoryState state, ProgramRevision revision) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ProgramRevisionScreen(
          revision: revision,
          previous: state.previousOf(revision),
          exerciseNames: state.exerciseNames,
          variationNames: state.variationNames,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    return ValueListenableBuilder<ProgramHistoryState>(
      valueListenable: _vm.state,
      builder: (context, state, _) {
        final onVersions = state.tab == HistoryTab.versions;
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
                    child: SegmentedControl<HistoryTab>(
                      subtle: true,
                      value: state.tab,
                      onChange: _vm.setTab,
                      options: [
                        SegmentOption(
                          label:
                              'Versions (${state.visibleRevisions.length})',
                          value: HistoryTab.versions,
                        ),
                        SegmentOption(
                          label: 'Reviews (${state.visibleReviews.length})',
                          value: HistoryTab.reviews,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // One action per segment, always in the same place: the
                  // thing you want to do most is the thing you are looking at.
                  GlassButton(
                    label: onVersions ? 'Save version' : 'Schedule',
                    compact: true,
                    loading: onVersions ? state.isSaving : state.isReviewing,
                    disabled: onVersions ? state.isSaving : state.isReviewing,
                    onPressed: onVersions ? _capture : _schedule,
                  ),
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
                      child: CircularProgressIndicator(
                        color: AppColors.accent,
                      ),
                    )
                  : state.tab == HistoryTab.versions
                      ? _VersionsTab(
                          state: state,
                          onOpen: (r) => _open(state, r),
                        )
                      : _ReviewsTab(
                          state: state,
                          onOpen: (r) => _review(state, r),
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _VersionsTab extends StatelessWidget {
  const _VersionsTab({required this.state, required this.onOpen});

  final ProgramHistoryState state;
  final ValueChanged<ProgramRevision> onOpen;

  @override
  Widget build(BuildContext context) {
    final revisions = state.visibleRevisions;
    if (revisions.isEmpty) return const _EmptyTab('No versions yet');
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: revisions.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final revision = revisions[i];
        return _VersionCard(
          revision: revision,
          // No predecessor at all, versus one that can't be compared — the
          // card says different things.
          isFirst: state.previousOf(revision) == null,
          diff: state.diffFor(revision.revisionId),
          onTap: () => onOpen(revision),
        );
      },
    );
  }
}

class _ReviewsTab extends StatelessWidget {
  const _ReviewsTab({required this.state, required this.onOpen});

  final ProgramHistoryState state;
  final ValueChanged<ProgramReview> onOpen;

  @override
  Widget build(BuildContext context) {
    final reviews = state.visibleReviews;
    if (reviews.isEmpty) {
      return const _EmptyTab(
        'No reviews yet',
        detail: 'A review is a checkpoint with a note attached. Schedule one '
            'to look at what this program has produced since the last time.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: reviews.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final review = reviews[i];
        return _ReviewCard(
          review: review,
          // Only the open one gets the achievements treatment — a closed
          // review reads back its frozen record instead.
          isDue: review.isDue(DateTime.now()),
          onTap: () => onOpen(review),
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
    required this.onTap,
  });

  final ProgramReview review;
  final bool isDue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final open = review.isOpen;
    final accent = isDue && open;

    return AppCard(
      onTap: open ? onTap : null,
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
          Text(
            _when(review),
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              color: accent ? AppColors.accent : AppColors.muted,
            ),
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
          if (review.hasProposal) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'PROPOSED EDIT ATTACHED',
              style: AppFonts.mono(
                fontSize: AppTextStyles.xs,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A closed review reports when it was completed; an open one reports when
  /// it is due, which is the date the user chose rather than the date the row
  /// happened to be created.
  static String _when(ProgramReview r) {
    if (r.completedDate != null) {
      return 'completed ${DateFormat('MMM d, yyyy').format(r.completedDate!)}';
    }
    final due = r.scheduledFor;
    if (due == null) {
      return 'not scheduled';
    }
    return 'due ${DateFormat('EEE, d MMM yyyy').format(due)}';
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
      // The same chrome as the version card's reason chip, so the two chips
      // read as the same kind of thing.
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

/// One version in the timeline: when it was cut, why, what it contained, and
/// what it changed.
class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.revision,
    required this.diff,
    required this.isFirst,
    required this.onTap,
  });

  final ProgramRevision revision;

  /// Changes since the version before this one. Null when either document
  /// can't be decoded by this build.
  final RevisionDiff? diff;

  /// The oldest version on record — there is nothing before it.
  final bool isFirst;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'VERSION ${revision.revisionNumber}',
                  style: AppFonts.mono(
                    fontSize: AppTextStyles.xs,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: AppColors.accent,
                  ),
                ),
              ),
              _ReasonChip(reason: revision.reason),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${DateFormat('MMM d, yyyy').format(revision.createdDate)}'
            '  ·  #${revision.contentHash.isEmpty ? '--------' : revision.contentHash.substring(0, 8)}',
            style: AppFonts.mono(
              fontSize: AppTextStyles.xs,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${revision.sessionCount} workouts · '
            '${revision.exerciseCount} exercises · '
            '${revision.setCount} sets',
            style: AppFonts.ui(
              fontSize: AppTextStyles.sm,
              color: AppColors.muted,
            ),
          ),
          if (isFirst || diff != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ChangeLine(summary: isFirst ? 'first version' : diff!.summary,
                isMuted: isFirst || diff!.isEmpty),
          ],
        ],
      ),
    );
  }
}

/// `+2 −1 ~3` — what this version changed, in one line.
class _ChangeLine extends StatelessWidget {
  const _ChangeLine({required this.summary, required this.isMuted});

  final String summary;
  final bool isMuted;

  @override
  Widget build(BuildContext context) => Text(
        summary,
        style: AppFonts.mono(
          fontSize: AppTextStyles.xs,
          fontWeight: FontWeight.w700,
          color: isMuted ? AppColors.muted : AppColors.accent,
        ),
      );
}

/// Scopes the timeline to one block. Context, not scope, is how `block_id` is
/// stored — a revision is always a whole-program snapshot — so this narrows
/// what is shown, never what a checkpoint means.
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
          _chip(label: 'All', selected: value == null, onTap: () => onChange(null)),
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
  }) =>
      GestureDetector(
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

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        // Ghost rather than the accent a single version uses: in a list of
        // them the version number is the accent element, and two competing
        // accents per row would read as noise.
        decoration: lambdaBox(ContainerTone.ghost),
        child: Text(
          revisionReasonLabel(reason).toUpperCase(),
          style: AppFonts.mono(
            fontSize: AppTextStyles.xs,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.muted,
          ),
        ),
      );
}

/// Both segments start empty the same way, and both actions sit in the row
/// above — so the empty state points at that row rather than duplicating the
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
