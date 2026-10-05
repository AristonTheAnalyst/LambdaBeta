import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/session_format.dart';
import '../../../data/models/program_block.dart';
import '../../../data/models/program_content.dart';
import '../../../data/models/program_review.dart';
import '../../../data/models/program_run.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/planned_session_repository.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/program_run_repository.dart';
import '../model/achievements_derivation.dart';
import '../model/program_achievements.dart';
import '../model/program_content_diff.dart';

/// What one checkpoint contains, and what it changed.
///
/// The counts are flat projections kept for the timeline card; [vsPrevious] is
/// the diff against the review before it **at the same scope** — null when
/// there is no same-scope predecessor, or when either snapshot is missing or
/// unreadable.
class ReviewDigest {
  const ReviewDigest({
    this.sessionCount = 0,
    this.exerciseCount = 0,
    this.setCount = 0,
    this.vsPrevious,
  });

  final int sessionCount;
  final int exerciseCount;
  final int setCount;
  final ContentDiff? vsPrevious;
}

/// One thing a review can be taken **of** — the whole program, one of its
/// blocks, or one of its workouts.
///
/// Display-ready on purpose: the three labels come from three different places
/// (a constant, a block row, a workout row) and the picker, the filter and the
/// review bar all have to say the same words about the same thing.
class ScopeOption {
  const ScopeOption({
    required this.kind,
    required this.label,
    this.blockId,
    this.sessionId,
  });

  final ReviewScopeKind kind;
  final String label;

  /// The block a block scope examines — also the block a workout scope's
  /// workout is filed under, which is what the timeline filter uses to keep a
  /// session review visible under its own phase.
  final String? blockId;

  final String? sessionId;
}

/// A review that has just been started: the row that was written, plus the two
/// facts its ceremony needs to open — where its window begins, and what the
/// program produced inside it.
///
/// A plain data result rather than a screen object: this layer does not know
/// what a review bar looks like, and the caller already holds the scope's own
/// label.
class StartedReview {
  const StartedReview({
    required this.review,
    this.sinceDate,
    this.achievements,
  });

  final ProgramReview review;
  final DateTime? sinceDate;
  final ProgramAchievements? achievements;
}

class ProgramHistoryState {
  const ProgramHistoryState({
    this.isLoading = false,
    this.isReviewing = false,
    this.error,
    this.reviews = const [],
    this.digests = const {},
    this.exerciseNames = const {},
    this.variationNames = const {},
    this.achievements,
    this.blocks = const [],
    this.blockFilter,
    this.usesBlocks = false,
    this.scopes = const [],
  });

  final bool isLoading;

  /// A review action (schedule, complete, dismiss) is in flight.
  final bool isReviewing;
  final String? error;

  /// Newest first by effective date — the order the timeline renders.
  final List<ProgramReview> reviews;

  /// `reviewId → what the checkpoint contains and changed`, computed once at
  /// load. A timeline row showing "no content changes" or "+2 −1" needs both
  /// documents decoded, so deriving it per build would re-parse every snapshot
  /// in the list on every frame. Predecessors are per scope: a session
  /// review's "what changed" is answered by the session review before it, not
  /// by a block or program checkpoint that happened in between.
  final Map<String, ReviewDigest> digests;

  /// Resolved live from the dims (names are never stored in a snapshot), and
  /// including archived rows so a checkpoint can still name an exercise that
  /// has since been retired.
  final Map<String, String> exerciseNames;
  final Map<String, String> variationNames;

  /// What the program has produced since the last checkpoint, derived at load
  /// and shown by the review sheet. Null when there is no open review — there
  /// is nothing to present, and deriving it anyway would read the whole
  /// training history every time the timeline is opened.
  final ProgramAchievements? achievements;

  /// The program's active blocks, for the scope filter.
  final List<ProgramBlock> blocks;

  /// The block whose history is being shown, or null for all of it.
  final String? blockFilter;

  /// Whether this program is built from blocks.
  ///
  /// Read from `dim_program.uses_blocks` and never from [blocks] being empty:
  /// a blocked program with no blocks yet is a real state, and the review
  /// sheet renders one's contents as "no blocks yet" rather than as a flat
  /// workout list it does not have.
  final bool usesBlocks;

  /// Everything a review can be scoped to here: the program itself, then one
  /// entry per active block, then one per workout. Program first because it is
  /// the default, and workouts after blocks because a workout is the narrower
  /// thing to say.
  ///
  /// A workout in a block carries that block's id, so choosing it can also
  /// narrow the timeline — the phase and the workout are not two different
  /// answers to "where does this review sit".
  final List<ScopeOption> scopes;

  /// [reviews] narrowed to [blockFilter]. Digests are computed over the whole
  /// list regardless, so "what changed" counts the same changes in both
  /// views — and the oldest visible row keeps the predecessor it has in the
  /// full list rather than losing it to the filter.
  List<ProgramReview> get visibleReviews {
    final id = blockFilter;
    if (id == null) return reviews;
    return [
      for (final r in reviews)
        if (r.blockId == id) r,
    ];
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

  bool get isEmpty => reviews.isEmpty;

  bool get hasOpenReview => openReview != null;

  /// The open checkpoint, or null. At most one in practice.
  ProgramReview? get openReview {
    for (final r in reviews) {
      if (r.isOpen) return r;
    }
    return null;
  }

  /// What [reviewId]'s checkpoint contains and changed, or an empty digest
  /// when the review never carried a snapshot (an open one, or a dismissal).
  ReviewDigest digestFor(String reviewId) =>
      digests[reviewId] ?? const ReviewDigest();

  ProgramHistoryState copyWith({
    bool? isLoading,
    bool? isReviewing,
    String? error,
    bool clearError = false,
    List<ProgramReview>? reviews,
    Map<String, ReviewDigest>? digests,
    Map<String, String>? exerciseNames,
    Map<String, String>? variationNames,
    ProgramAchievements? achievements,
    bool clearAchievements = false,
    List<ProgramBlock>? blocks,
    String? blockFilter,
    bool clearBlockFilter = false,
    bool? usesBlocks,
    List<ScopeOption>? scopes,
  }) => ProgramHistoryState(
    isLoading: isLoading ?? this.isLoading,
    isReviewing: isReviewing ?? this.isReviewing,
    error: clearError ? null : error ?? this.error,
    reviews: reviews ?? this.reviews,
    digests: digests ?? this.digests,
    exerciseNames: exerciseNames ?? this.exerciseNames,
    variationNames: variationNames ?? this.variationNames,
    achievements: clearAchievements ? null : achievements ?? this.achievements,
    blocks: blocks ?? this.blocks,
    blockFilter: clearBlockFilter ? null : blockFilter ?? this.blockFilter,
    usesBlocks: usesBlocks ?? this.usesBlocks,
    scopes: scopes ?? this.scopes,
  );
}

/// The program's history: the checkpoints that record it, the name maps that
/// let a snapshot render, and the actions that schedule and complete one.
class ProgramHistoryViewModel {
  ProgramHistoryViewModel({
    ProgramHistoryRepository? historyRepository,
    ExerciseRepository? exerciseRepository,
    ProgramRepository? programRepository,
    ProgramRunRepository? runRepository,
    PlannedSessionRepository? plannedSessionRepository,
    AchievementsDerivation? achievementsDerivation,
    String? userId,
  }) : _historyRepo = historyRepository ?? ProgramHistoryRepository(),
       _exerciseRepo = exerciseRepository ?? ExerciseRepository(),
       _programRepo = programRepository ?? ProgramRepository(),
       _runRepo = runRepository ?? ProgramRunRepository(),
       _plannedRepo = plannedSessionRepository ?? PlannedSessionRepository(),
       _derivation = achievementsDerivation ?? AchievementsDerivation(),
       _userIdOverride = userId;

  final ProgramHistoryRepository _historyRepo;
  final ExerciseRepository _exerciseRepo;
  final ProgramRepository _programRepo;
  final ProgramRunRepository _runRepo;
  final PlannedSessionRepository _plannedRepo;
  final AchievementsDerivation _derivation;
  final String? _userIdOverride;

  final state = ValueNotifier(const ProgramHistoryState());
  bool _disposed = false;

  /// The signed-in user. Overridable because host tests cannot construct
  /// `Supabase.instance` at all.
  String get _userId =>
      _userIdOverride ?? Supabase.instance.client.auth.currentUser!.id;

  /// Narrows the timeline to one block's checkpoints, or to all of them.
  ///
  /// No reload: the list is already loaded, and a filter that refetched would
  /// make a toggle feel like a navigation. It also keeps the digests identical
  /// across scopes, which they would not be if the query narrowed — a
  /// checkpoint's diff is against its predecessor at the same scope, and
  /// recomputing it inside a filtered list would compare across gaps.
  void setBlockFilter(String? blockId) {
    state.value = blockId == null
        ? state.value.copyWith(clearBlockFilter: true)
        : state.value.copyWith(blockFilter: blockId);
  }

  Future<void> load(String programId) async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final reviews = await _historyRepo.fetchReviews(programId);
      final blocks = await _programRepo.fetchBlocks(programId);
      // One row, and the panel renders two different things from it — the
      // review sheet's contents view has to know a program with no blocks yet
      // from one that will never have any.
      final program = await _programRepo.fetchProgram(programId);
      // Loaded even when there is nothing to show yet: a program with no
      // reviews is exactly when someone starts one, and the picker would
      // otherwise open empty on the only screen that offers it.
      final scopes = await _scopesFor(programId, blocks);
      if (_disposed) return;

      // A filter naming a block that no longer exists would show an empty
      // timeline with no way to tell why — drop back to the full history.
      final filter = state.value.blockFilter;
      final filterHolds =
          filter == null || blocks.any((b) => b.blockId == filter);

      // Names are fetched only once there is something to name — an empty
      // history is the common case on a fresh program.
      if (reviews.isEmpty) {
        state.value = state.value.copyWith(
          isLoading: false,
          reviews: const [],
          digests: const {},
          blocks: blocks,
          usesBlocks: program?.usesBlocks ?? false,
          scopes: scopes,
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
        reviews: reviews,
        digests: _digestAll(reviews, exerciseNames),
        exerciseNames: exerciseNames,
        variationNames: variationNames,
        achievements: achievements,
        blocks: blocks,
        blockFilter: filterHolds ? filter : null,
        usesBlocks: program?.usesBlocks ?? false,
        scopes: scopes,
      );
    } catch (_) {
      if (_disposed) return;
      state.value = state.value.copyWith(
        isLoading: false,
        error: 'Could not load the history.',
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

    // A first-ever run has no previous checkpoint, so the window has to open
    // where the run did — `checkpointFor`'s bare `now` fallback made a first
    // run's window empty and its panel show nothing however much was lifted.
    // The run behind the review answers first; failing that, the current run
    // when it is this program's AND at this scope — another block's run would
    // date the window from a phase the review is not about. A review with no
    // run behind it (scheduled by hand, nothing running) keeps the old empty
    // window.
    DateTime? runStart;
    try {
      if (open.programRunId != null) {
        runStart = (await _runRepo.fetchRunById(
          open.programRunId!,
        ))?.startedDate;
      }
      runStart ??= (await _currentRunFor(programId, blockId: open.blockId))
          ?.startedDate;
    } catch (_) {
      // Unreadable runs fall back to "now" — a diagnostic read must not stop
      // the panel rendering.
    }

    final from = await _historyRepo.checkpointFor(
      programId,
      blockId: open.blockId,
      sessionId: open.sessionId,
      fallback: runStart,
    );
    return _derivation.derive(
      userId: _userId,
      from: from,
      programId: programId,
      // The review's scope, threaded through everything it reports: a block's
      // review shows that block's sessions, PRs and goals plus the program's
      // goals in force in it, a session's review shows that planned session's
      // logged sessions, and a program-level one shows every run of the
      // program in its window.
      blockId: open.blockId,
      sessionId: open.sessionId,
    );
  }

  /// The run in progress, but only when it belongs to **this** program AND
  /// **this** scope.
  ///
  /// A run is the only thing that can date a first review's window, and a run
  /// of another program — or of another block — would date it from a phase the
  /// review is not about. Null rather than a guess: a review with no run behind
  /// it (started by hand, nothing running) opens its window where
  /// `checkpointFor` decides.
  Future<ProgramRun?> _currentRunFor(
    String programId, {
    String? blockId,
  }) async {
    final current = await _runRepo.getCurrentRun(_userId);
    if (current == null) return null;
    if (current.programId != programId) return null;
    if (current.blockId != blockId) return null;
    return current;
  }

  /// Everything this program can be reviewed as, in the order the picker
  /// offers them.
  ///
  /// Read from the program's **links**, not from its workouts: a workout's
  /// membership — which block holds it, and where it sits in the order — lives
  /// on the join row, and a workout the program does not contain is not a scope
  /// a review of it can have.
  Future<List<ScopeOption>> _scopesFor(
    String programId,
    List<ProgramBlock> blocks,
  ) async {
    final blockNames = {for (final b in blocks) b.blockId: b.name};
    final links = await _plannedRepo.fetchProgramLinks(programId);
    final workouts = await _plannedRepo.fetchPlannedSessions(
      _userId,
      programId: programId,
    );
    final names = {for (final w in workouts) w.sessionId: w.name};

    return [
      const ScopeOption(
        kind: ReviewScopeKind.program,
        label: 'Whole program',
      ),
      for (final b in blocks)
        ScopeOption(
          kind: ReviewScopeKind.block,
          label: toProperCase(b.name),
          blockId: b.blockId,
        ),
      for (final link in links)
        if (names[link.plannedSessionId] case final name?)
          ScopeOption(
            kind: ReviewScopeKind.session,
            // A workout is named with the phase it sits in when it has one:
            // "Day 1" in two blocks is two different workouts, and a picker
            // that showed the same words twice would be asking the user to
            // guess.
            label: [
              toProperCase(name),
              if (blockNames[link.blockId] case final blockName?)
                toProperCase(blockName),
            ].join(' · '),
            blockId: link.blockId,
            sessionId: link.plannedSessionId,
          ),
    ];
  }

  /// Starts a review **now** — the ad-hoc path, as opposed to scheduling one
  /// for a later date.
  ///
  /// Writes the review row immediately and returns what the ceremony needs to
  /// open on it. The row is written first because the ceremony's whole job is
  /// to end in a snapshot on it: a review that existed only in the UI until
  /// Finish would lose everything the user did if the app died mid-pass.
  ///
  /// [title] is optional — a review with no name is still a review, and asking
  /// for one before the pass would be asking the user to name it before they
  /// know what they found.
  Future<StartedReview?> startReview(
    String programId, {
    ReviewScopeKind kind = ReviewScopeKind.program,
    String? blockId,
    String? sessionId,
    String? title,
  }) async {
    try {
      final run = await _currentRunFor(programId, blockId: blockId);
      final review = await scheduleReview(
        programId,
        // Only the scope's own column is set — the two are mutually exclusive
        // by both this call and the database's CHECK.
        blockId: kind == ReviewScopeKind.block ? blockId : null,
        sessionId: kind == ReviewScopeKind.session ? sessionId : null,
        programRunId: run?.programRunId,
        title: title,
      );
      if (review == null) return null;

      final since = await _historyRepo.checkpointFor(
        programId,
        blockId: review.blockId,
        sessionId: review.sessionId,
        // The same window `load` just derived achievements over, so the sheet's
        // "since <date>" and the achievements under it cannot disagree.
        fallback: run?.startedDate,
      );

      return StartedReview(
        review: review,
        sinceDate: since,
        // Read back from state rather than derived again: `scheduleReview`
        // reloads, and the load is what derives this — over the very review
        // just written.
        achievements: state.value.achievements,
      );
    } catch (_) {
      if (!_disposed) {
        state.value = state.value.copyWith(
          isLoading: false,
          isReviewing: false,
          error: 'Could not start the review.',
        );
      }
      return null;
    }
  }

  /// Each checkpoint's contents, and its changes against the one before it
  /// **at the same scope**.
  ///
  /// [reviews] is newest first, so a review's same-scope predecessor is the
  /// next entry at that scope — walking from the end keeps the last completed
  /// review seen per scope, which is exactly that predecessor. Open and
  /// dismissed reviews carry no snapshot: they can never be a predecessor, and
  /// they get a digest with no diff. A document this build can't decode is
  /// skipped the same way rather than treated as empty, which would report the
  /// whole program as removed.
  static Map<String, ReviewDigest> _digestAll(
    List<ProgramReview> reviews,
    Map<String, String> exerciseNames,
  ) {
    final digests = <String, ReviewDigest>{};
    final lastByScope = <String, ProgramReview>{};

    for (final review in reviews.reversed) {
      final content = review.snapshot;
      final scope = _scopeKey(review);
      final previous = lastByScope[scope];
      if (content != null) lastByScope[scope] = review;

      final before = previous?.snapshot;
      digests[review.reviewId] = ReviewDigest(
        sessionCount: content?.sessionCount ?? 0,
        exerciseCount: content?.exerciseCount ?? 0,
        setCount: content?.setCount ?? 0,
        vsPrevious: before != null && content != null
            ? diffContent(before, content, exerciseNames: exerciseNames)
            : null,
      );
    }
    return digests;
  }

  /// Which checkpoint stream a review answers for. Two snapshots compare only
  /// when they answer the same question.
  static String _scopeKey(ProgramReview r) => switch (r.scopeKind) {
    ReviewScopeKind.program => 'program',
    ReviewScopeKind.block => 'block:${r.blockId}',
    ReviewScopeKind.session => 'session:${r.sessionId}',
  };

  // ── Reviews ──────────────────────────────────────────────────────────────

  /// Schedules the program's next checkpoint.
  ///
  /// [blockId] and [sessionId] are the review's **scope** (mutually exclusive;
  /// both null reviews the program), passed through unchanged.
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
    String? sessionId,
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
        sessionId: sessionId,
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

  /// Completes [reviewId], writing the snapshot it is a checkpoint of.
  ///
  /// The snapshot records the **live** program, never the proposal: applying a
  /// change means the user edited the program through the normal editor, and
  /// this records what that produced. Nothing copies `proposed_content` into
  /// live rows.
  ///
  /// Returns the completed review, or null when the write failed. A
  /// [kOutcomeDismissed] review is "not now", not a checkpoint: it is closed
  /// without a snapshot, and the returned row says so.
  Future<ProgramReview?> completeReview(
    String programId,
    String reviewId, {
    required String outcome,
    String? notes,
  }) async {
    state.value = state.value.copyWith(isReviewing: true, clearError: true);
    try {
      final review = await _historyRepo.completeReview(
        reviewId,
        userId: _userId,
        outcome: outcome,
        notes: notes,
      );
      await load(programId);
      return review;
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
  Future<void> dismissReview(
    String programId,
    String reviewId, {
    String? notes,
  }) async {
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
  Future<ProgramContent?> liveContent(String programId) async {
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
