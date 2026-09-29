import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/program_block.dart';
import '../../../data/models/program_review.dart';
import '../../../data/models/program_revision.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../model/achievements_derivation.dart';
import '../model/program_achievements.dart';
import '../model/program_revision_diff.dart';

/// Which half of the history the screen is showing.
enum HistoryTab { versions, reviews }

class ProgramHistoryState {
  const ProgramHistoryState({
    this.isLoading = false,
    this.isSaving = false,
    this.isReviewing = false,
    this.error,
    this.tab = HistoryTab.versions,
    this.revisions = const [],
    this.diffs = const {},
    this.reviews = const [],
    this.exerciseNames = const {},
    this.variationNames = const {},
    this.achievements,
    this.blocks = const [],
    this.blockFilter,
  });

  final bool isLoading;

  /// A capture is in flight — drives the header button's spinner. Distinct from
  /// [isLoading] because capturing also reloads, and the timeline should not
  /// blank out to a spinner while the version the user just cut is being
  /// numbered and fetched back.
  final bool isSaving;

  /// A review action (schedule, complete, dismiss) is in flight.
  final bool isReviewing;
  final String? error;

  final HistoryTab tab;

  /// Newest first — the order the timeline renders.
  final List<ProgramRevision> revisions;

  /// `revisionId → what changed in it since the version before it`, computed
  /// once at load. A timeline row showing "no content changes" or "+2 −1" needs
  /// both documents decoded, so deriving it per build would re-parse every
  /// revision in the list on every frame. The first version has no entry —
  /// there is nothing before it to compare against.
  final Map<String, RevisionDiff> diffs;

  /// Newest first.
  final List<ProgramReview> reviews;

  /// Resolved live from the dims (names are never stored in a revision), and
  /// including archived rows so a version can still name an exercise that has
  /// since been retired.
  final Map<String, String> exerciseNames;
  final Map<String, String> variationNames;

  /// What the program has produced since the last checkpoint, derived at load
  /// and shown by the review sheet. Null when there is no open review — there
  /// is nothing to present, and deriving it anyway would read the whole
  /// training history every time the timeline is opened.
  final ProgramAchievements? achievements;

  /// The program's active blocks, for the scope filter.
  ///
  /// Revisions and reviews store `block_id` as **context** — which block was
  /// active when they were cut — never as scope: a revision is always a
  /// whole-program snapshot. So filtering is a display concern, which is why
  /// the lists below are the *loaded* ones and these getters do the narrowing.
  final List<ProgramBlock> blocks;

  /// The block whose history is being shown, or null for all of it.
  final String? blockFilter;

  /// [revisions] narrowed to [blockFilter]. Diffs are computed over the whole
  /// list regardless, so "Version 7 · +2 −1" counts the same changes in both
  /// views — and the oldest visible row keeps the diff it has in the full list
  /// rather than losing its predecessor to the filter.
  List<ProgramRevision> get visibleRevisions {
    final id = blockFilter;
    if (id == null) return revisions;
    return [for (final r in revisions) if (r.blockId == id) r];
  }

  List<ProgramReview> get visibleReviews {
    final id = blockFilter;
    if (id == null) return reviews;
    return [for (final r in reviews) if (r.blockId == id) r];
  }

  /// The block behind [blockFilter], or null when unfiltered (or when the
  /// block has since been archived — the filter still applies, it just cannot
  /// be named).
  ProgramBlock? get filteredBlock {
    final id = blockFilter;
    if (id == null) return null;
    for (final b in blocks) {
      if (b.blockId == id) return b;
    }
    return null;
  }

  bool get isEmpty => revisions.isEmpty && reviews.isEmpty;

  bool get hasOpenReview => openReview != null;

  /// The open checkpoint, or null. At most one in practice.
  ProgramReview? get openReview {
    for (final r in reviews) {
      if (r.isOpen) return r;
    }
    return null;
  }

  /// What changed in [revisionId] since the version before it, or null when it
  /// is the first version (or either document can't be decoded).
  RevisionDiff? diffFor(String revisionId) => diffs[revisionId];

  /// The revision immediately before [revision] in the timeline, or null when
  /// [revision] is the first version. Comparing a version to its predecessor is
  /// the question the history exists to answer ("what changed?"), so this is
  /// derived here rather than re-queried per screen.
  ProgramRevision? previousOf(ProgramRevision revision) {
    final i = revisions.indexWhere((r) => r.revisionId == revision.revisionId);
    if (i < 0) return null;
    // Newest first, so the predecessor is the NEXT entry.
    final next = i + 1;
    return next < revisions.length ? revisions[next] : null;
  }

  ProgramHistoryState copyWith({
    bool? isLoading,
    bool? isSaving,
    bool? isReviewing,
    String? error,
    bool clearError = false,
    HistoryTab? tab,
    List<ProgramRevision>? revisions,
    Map<String, RevisionDiff>? diffs,
    List<ProgramReview>? reviews,
    Map<String, String>? exerciseNames,
    Map<String, String>? variationNames,
    ProgramAchievements? achievements,
    bool clearAchievements = false,
    List<ProgramBlock>? blocks,
    String? blockFilter,
    bool clearBlockFilter = false,
  }) =>
      ProgramHistoryState(
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        isReviewing: isReviewing ?? this.isReviewing,
        error: clearError ? null : error ?? this.error,
        tab: tab ?? this.tab,
        revisions: revisions ?? this.revisions,
        diffs: diffs ?? this.diffs,
        reviews: reviews ?? this.reviews,
        exerciseNames: exerciseNames ?? this.exerciseNames,
        variationNames: variationNames ?? this.variationNames,
        achievements:
            clearAchievements ? null : achievements ?? this.achievements,
        blocks: blocks ?? this.blocks,
        blockFilter: clearBlockFilter ? null : blockFilter ?? this.blockFilter,
      );
}

/// The program's history: the revision timeline, the reviews that checkpoint
/// it, the name maps that let a version render, and the actions that cut one.
class ProgramHistoryViewModel {
  ProgramHistoryViewModel({
    ProgramHistoryRepository? historyRepository,
    ExerciseRepository? exerciseRepository,
    ProgramRepository? programRepository,
    AchievementsDerivation? achievementsDerivation,
  })  : _historyRepo = historyRepository ?? ProgramHistoryRepository(),
        _exerciseRepo = exerciseRepository ?? ExerciseRepository(),
        _programRepo = programRepository ?? ProgramRepository(),
        _derivation = achievementsDerivation ?? AchievementsDerivation();

  final ProgramHistoryRepository _historyRepo;
  final ExerciseRepository _exerciseRepo;
  final ProgramRepository _programRepo;
  final AchievementsDerivation _derivation;

  final state = ValueNotifier(const ProgramHistoryState());
  bool _disposed = false;

  String get _userId => Supabase.instance.client.auth.currentUser!.id;

  void setTab(HistoryTab tab) {
    state.value = state.value.copyWith(tab: tab);
  }

  /// Narrows the timeline to one block's checkpoints, or to all of them.
  ///
  /// No reload: both lists are already loaded, and a filter that refetched
  /// would make a toggle feel like a navigation. It also keeps the diffs
  /// identical across scopes, which they would not be if the query narrowed —
  /// a revision's diff is against its predecessor in the whole program, and
  /// recomputing it inside a filtered list would compare across gaps.
  void setBlockFilter(String? blockId) {
    state.value = blockId == null
        ? state.value.copyWith(clearBlockFilter: true)
        : state.value.copyWith(blockFilter: blockId);
  }

  Future<void> load(String programId) async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final revisions = await _historyRepo.fetchRevisions(programId);
      final reviews = await _historyRepo.fetchReviews(programId);
      final blocks = await _programRepo.fetchBlocks(programId);
      if (_disposed) return;

      // A filter naming a block that no longer exists would show an empty
      // timeline with no way to tell why — drop back to the full history.
      final filter = state.value.blockFilter;
      final filterHolds =
          filter == null || blocks.any((b) => b.blockId == filter);

      // Names are fetched only once there is something to name — an empty
      // history is the common case on a fresh program.
      if (revisions.isEmpty && reviews.isEmpty) {
        state.value = state.value.copyWith(
          isLoading: false,
          revisions: const [],
          reviews: const [],
          blocks: blocks,
          clearAchievements: true,
          clearBlockFilter: !filterHolds,
        );
        return;
      }

      final exerciseNames = await _exerciseRepo.fetchExerciseNameMap(_userId);
      final variationNames = await _exerciseRepo.fetchVariationNameMap(_userId);
      if (_disposed) return;

      final achievements = await _achievementsFor(programId, reviews);
      if (_disposed) return;

      state.value = ProgramHistoryState(
        tab: state.value.tab,
        revisions: revisions,
        diffs: _diffAll(revisions, exerciseNames),
        reviews: reviews,
        exerciseNames: exerciseNames,
        variationNames: variationNames,
        achievements: achievements,
        blocks: blocks,
        blockFilter: filterHolds ? filter : null,
      );
    } catch (_) {
      if (_disposed) return;
      state.value = state.value.copyWith(
        isLoading: false,
        error: 'Could not load version history.',
      );
    }
  }

  /// What the program has produced since its last checkpoint — derived only
  /// when a review is actually open to show it in.
  ///
  /// The window opens at [ProgramHistoryRepository.checkpointFor], which skips
  /// dismissed reviews: a dismissal means "not now", so it must not swallow
  /// everything achieved since the last real review.
  Future<ProgramAchievements?> _achievementsFor(
    String programId,
    List<ProgramReview> reviews,
  ) async {
    ProgramReview? open;
    for (final r in reviews) {
      if (r.isOpen) {
        open = r;
        break;
      }
    }
    if (open == null) return null;

    final from = await _historyRepo.checkpointFor(programId);
    return _derivation.derive(
      userId: _userId,
      from: from,
      programId: programId,
      // The review names the block it belongs to, so a review scheduled while
      // a phase was running reports that phase's goals.
      blockId: open.blockId,
      runId: open.programRunId,
    );
  }

  /// Each version's changes against the one before it.
  ///
  /// [revisions] is newest first, so a version's predecessor is the NEXT entry,
  /// and the oldest version gets no entry — there is nothing to compare it to.
  /// A document this build can't decode is skipped rather than treated as
  /// empty, which would report the whole program as removed.
  static Map<String, RevisionDiff> _diffAll(
    List<ProgramRevision> revisions,
    Map<String, String> exerciseNames,
  ) {
    final diffs = <String, RevisionDiff>{};
    for (var i = 0; i + 1 < revisions.length; i++) {
      final before = revisions[i + 1].content;
      final after = revisions[i].content;
      if (before == null || after == null) continue;
      diffs[revisions[i].revisionId] =
          diffRevisions(before, after, exerciseNames: exerciseNames);
    }
    return diffs;
  }

  /// Cuts a version of the program's current contents and reloads the timeline.
  ///
  /// The very first capture is recorded as [kRevisionCreated] rather than a
  /// manual save — the first version of a program IS its creation, and later
  /// phases (reviews, run ends, first-save) key their labels off `reason`.
  ///
  /// Returns the captured revision, or null if it failed.
  Future<ProgramRevision?> capture(String programId) async {
    final existing = state.value.revisions;
    state.value = state.value.copyWith(isSaving: true, clearError: true);
    try {
      final revision = await _historyRepo.captureRevision(
        userId: _userId,
        programId: programId,
        reason: existing.isEmpty ? kRevisionCreated : kRevisionManual,
      );
      // Reloads rather than appending: the number is claimed in the database,
      // and the timeline's diffs are derived from the list as a whole.
      await load(programId);
      return revision;
    } catch (_) {
      if (!_disposed) {
        state.value = state.value.copyWith(
          isLoading: false,
          isSaving: false,
          error: 'Could not save a version.',
        );
      }
      return null;
    }
  }

  // ── Reviews ──────────────────────────────────────────────────────────────

  /// Schedules the program's next checkpoint.
  ///
  /// [withProposal] schedules a **change** rather than a plain review: the
  /// program's contents are captured alongside the schedule, so the prompt can
  /// name what it is asking about and show how the program has drifted since
  /// the change was proposed. [title] and [notes] carry the intent — the
  /// proposal document is only what the program looked like at the time, and a
  /// proposal with no rationale is a diff with no story.
  ///
  /// Returns the new review, or null if it failed.
  Future<ProgramReview?> scheduleReview(
    String programId, {
    String? blockId,
    String? programRunId,
    String? title,
    String? notes,
    DateTime? scheduledFor,
    bool withProposal = false,
  }) async {
    state.value = state.value.copyWith(isReviewing: true, clearError: true);
    try {
      final proposal = withProposal
          ? await _historyRepo.buildContent(
              userId: _userId,
              programId: programId,
            )
          : null;
      final review = await _historyRepo.scheduleReview(
        userId: _userId,
        programId: programId,
        blockId: blockId,
        programRunId: programRunId,
        title: title,
        notes: notes,
        scheduledFor: scheduledFor,
        proposedContent: proposal,
      );
      await load(programId);
      return review;
    } catch (_) {
      if (!_disposed) {
        state.value = state.value.copyWith(
          isLoading: false,
          isReviewing: false,
          error: 'Could not schedule the review.',
        );
      }
      return null;
    }
  }

  /// Completes [reviewId], cutting the revision it is a checkpoint of.
  ///
  /// The revision snapshots the **live** program, never the proposal: applying
  /// a change means the user edited the program through the normal editor, and
  /// this records what that produced. Nothing copies `proposed_content` into
  /// live rows.
  ///
  /// Returns the revision, or null when nothing was cut — a
  /// [kOutcomeDismissed] review is "not now", not a checkpoint, and records no
  /// outcome either way.
  Future<ProgramRevision?> completeReview(
    String programId,
    String reviewId, {
    required String outcome,
    String? notes,
  }) async {
    state.value = state.value.copyWith(isReviewing: true, clearError: true);
    try {
      final revision = await _historyRepo.completeReview(
        reviewId,
        userId: _userId,
        outcome: outcome,
        notes: notes,
      );
      await load(programId);
      return revision;
    } catch (_) {
      if (!_disposed) {
        state.value = state.value.copyWith(
          isLoading: false,
          isReviewing: false,
          error: 'Could not complete the review.',
        );
      }
      return null;
    }
  }

  /// Dismisses the open review without cutting anything.
  ///
  /// Deliberately does not schedule a replacement: "not now" is an answer, and
  /// silently pushing the prompt a week out would make a dismissal
  /// indistinguishable from a snooze.
  Future<void> dismissReview(String programId, String reviewId,
      {String? notes}) async {
    await completeReview(
      programId,
      reviewId,
      outcome: kOutcomeDismissed,
      notes: notes,
    );
  }

  /// The program's contents right now — the other half of a proposal diff.
  ///
  /// Built on demand rather than held in state: only the "what would this
  /// change do?" sheet reads it, and putting it in [ProgramHistoryState] would
  /// make every timeline open build a document nobody looks at. Null when it
  /// can't be read, which the diff sheet renders as "unavailable" rather than
  /// as an empty program.
  Future<ProgramRevisionContent?> liveContent(String programId) async {
    try {
      return await _historyRepo.buildContent(
        userId: _userId,
        programId: programId,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _disposed = true;
    state.dispose();
  }
}
