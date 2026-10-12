import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/session_format.dart';
import '../../../data/models/program_block.dart';
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

/// One workout a review can cover, display-ready for the picker.
///
/// A review's unit is the workout, and the picker has to offer them by name —
/// so this carries what a picker row shows: the workout's name, the block it
/// sits in (grouping, and the line under the name), and how much is in it.
class WorkoutOption {
  const WorkoutOption({
    required this.sessionId,
    required this.label,
    this.blockId,
    this.blockName,
    this.exerciseCount = 0,
  });

  final String sessionId;

  /// The workout's own name, proper-cased.
  final String label;

  /// The block it sits in, when the program has blocks — also what the
  /// timeline filter compares a review's set against.
  final String? blockId;
  final String? blockName;

  final int exerciseCount;
}

/// Everything a review of [programId] can cover, in the order the picker
/// offers them: one entry per workout the program contains.
///
/// Read from the program's **links**, not from its workouts: a workout's
/// membership — which block holds it, and where it sits in the order — lives
/// on the join row, and a workout the program does not contain cannot be
/// covered by a review of it. Fetched when the picker opens rather than at
/// load: the exercise counts cost one read per workout, and the timeline that
/// precedes the picker has no use for them.
///
/// A free function rather than a view-model method alone because two screens
/// open the picker: the Reviews tab through [ProgramHistoryViewModel], and the
/// run's length-reached prompt, which owns no history view model but asks the
/// same question. One implementation, so the two lists cannot disagree.
Future<List<WorkoutOption>> fetchWorkoutOptions({
  required String userId,
  required String programId,
  PlannedSessionRepository? plannedRepository,
  ProgramRepository? programRepository,
}) async {
  final planned = plannedRepository ?? PlannedSessionRepository();
  final programs = programRepository ?? ProgramRepository();
  final links = await planned.fetchProgramLinks(programId);
  final workouts = await planned.fetchPlannedSessions(
    userId,
    programId: programId,
  );
  final blocks = await programs.fetchBlocks(programId);
  final blockNames = {for (final b in blocks) b.blockId: toProperCase(b.name)};
  final byId = {for (final w in workouts) w.sessionId: w};

  return [
    for (final link in links)
      if (byId[link.plannedSessionId] case final workout?)
        WorkoutOption(
          sessionId: workout.sessionId,
          label: toProperCase(workout.name),
          blockId: link.blockId,
          blockName: blockNames[link.blockId],
          exerciseCount:
              (await planned.fetchPlannedExercises(workout.sessionId)).length,
        ),
  ];
}

/// A review that has just been started: the row that was written, the workouts
/// it covers, and the two facts its ceremony needs to open — where its window
/// begins, and what the program produced inside it.
///
/// A plain data result rather than a screen object: this layer does not know
/// what a review bar looks like. The set travels here because the caller must
/// never read it back off the row's own columns — those are null on legacy
/// rows and are only the raw store of what [sessionsIn] resolves.
class StartedReview {
  const StartedReview({
    required this.review,
    this.sessionIds = const [],
    this.sinceDate,
    this.achievements,
  });

  final ProgramReview review;

  /// The workouts the pass covers, resolved.
  final List<String> sessionIds;

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
    this.reviewSessions = const {},
    this.sessionBlocks = const {},
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

  /// `reviewId → the workouts it covers`, every loaded row resolved once at
  /// load. Resolution reads the program's live links, so what a pass covers is
  /// one answer shared by the timeline filter, the digests and the next pass's
  /// window — and a legacy row's old scope resolves in the same place, so
  /// nothing downstream ever consults its columns.
  final Map<String, List<String>> reviewSessions;

  /// `workoutId → blockId` for the program's links. The timeline filter asks
  /// "does this review touch the block being shown"; a review's set of workout
  /// ids does not say which block that is on its own.
  final Map<String, String> sessionBlocks;

  /// [reviews] narrowed to [blockFilter]. A review sits under a block when its
  /// set touches that block's workouts — a block is no longer a scope, so
  /// "this block's history" means the passes that walked any of its workouts.
  /// Digests are computed over the whole list regardless, so "what changed"
  /// counts the same changes in both views — and the oldest visible row keeps
  /// the predecessor it has in the full list rather than losing it to the
  /// filter.
  List<ProgramReview> get visibleReviews {
    final id = blockFilter;
    if (id == null) return reviews;
    return [
      for (final r in reviews)
        if ((reviewSessions[r.reviewId] ?? const []).any(
          (s) => sessionBlocks[s] == id,
        ))
          r,
    ];
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
    Map<String, List<String>>? reviewSessions,
    Map<String, String>? sessionBlocks,
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
    reviewSessions: reviewSessions ?? this.reviewSessions,
    sessionBlocks: sessionBlocks ?? this.sessionBlocks,
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
      // Every review answers for a set of workouts, and the set is resolved
      // against the program's links — read here because the timeline filter,
      // the digests and the next pass's window all consume the same resolution,
      // and one read is what keeps them from disagreeing.
      final links = await _plannedRepo.fetchProgramLinks(programId);
      final sessionBlocks = {
        for (final link in links)
          if (link.blockId != null) link.plannedSessionId: link.blockId!,
      };
      final sessionLinks = [
        for (final link in links)
          (sessionId: link.plannedSessionId, blockId: link.blockId),
      ];
      final reviewSessions = {
        for (final r in reviews) r.reviewId: r.sessionsIn(sessionLinks),
      };
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
          reviewSessions: const {},
          sessionBlocks: sessionBlocks,
          clearAchievements: true,
          clearBlockFilter: !filterHolds,
        );
        return;
      }

      final exerciseNames = await _exerciseRepo.fetchExerciseNameMap(_userId);
      final variationNames = await _exerciseRepo.fetchVariationNameMap(_userId);
      if (_disposed) return;

      final achievements = await _achievementsFor(
        programId,
        reviews,
        reviewSessions,
        sessionBlocks,
      );
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
        reviewSessions: reviewSessions,
        sessionBlocks: sessionBlocks,
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
    Map<String, List<String>> reviewSessions,
    Map<String, String> sessionBlocks,
  ) async {
    ProgramReview? open;
    for (final r in reviews) {
      if (r.isOpen) {
        open = r;
        break;
      }
    }
    if (open == null) return null;

    // The open pass's own workouts are what both the window question and the
    // derivation are about — resolved once at load and read here, so the
    // sheet's numbers and the timeline's cannot disagree about what it covers.
    final set = reviewSessions[open.reviewId] ?? const <String>[];

    // A first-ever run has no previous checkpoint, so the window has to open
    // where the run did — `checkpointFor`'s bare `now` fallback made a first
    // run's window empty and its panel show nothing however much was lifted.
    // The run behind the review answers first; failing that, the current run
    // when it is this program's AND is running one of these workouts' blocks —
    // a run of another program, or of a block none of them sit in, would date
    // the window from a phase the review is not about. A review with no run
    // behind it (scheduled by hand, nothing running) keeps the old empty
    // window.
    DateTime? runStart;
    try {
      if (open.programRunId != null) {
        runStart = (await _runRepo.fetchRunById(
          open.programRunId!,
        ))?.startedDate;
      }
      runStart ??= (await _currentRunFor(
        programId,
        sessionIds: set,
        sessionBlocks: sessionBlocks,
      ))?.startedDate;
    } catch (_) {
      // Unreadable runs fall back to "now" — a diagnostic read must not stop
      // the panel rendering.
    }

    final from = await _historyRepo.checkpointFor(
      programId,
      sessionIds: set,
      fallback: runStart,
    );
    return _derivation.derive(
      userId: _userId,
      from: from,
      programId: programId,
      // The review's workouts, threaded through everything it reports: the
      // sessions are those of the named plans, and the goals in force are the
      // program's own plus the goals of every block any of them sits in.
      sessionIds: set,
    );
  }

  /// The run in progress, but only when it belongs to **this** program AND is
  /// running one of the **named** workouts' blocks.
  ///
  /// A run is the only thing that can date a first review's window, and a run
  /// of another program — or of a block none of the reviewed workouts sit in —
  /// would date it from a phase the review is not about. Null rather than a
  /// guess: a review with no run behind it (started by hand, nothing running)
  /// opens its window where `checkpointFor` decides.
  Future<ProgramRun?> _currentRunFor(
    String programId, {
    required Iterable<String> sessionIds,
    required Map<String, String> sessionBlocks,
  }) async {
    final current = await _runRepo.getCurrentRun(_userId);
    if (current == null) return null;
    if (current.programId != programId) return null;
    final blocks = {for (final id in sessionIds) sessionBlocks[id]};
    return blocks.contains(current.blockId) ? current : null;
  }

  /// Everything a review of this program can cover, in the order the picker
  /// offers them.
  ///
  /// [fetchWorkoutOptions] does the reading; this is the tab's way in, through
  /// the same repositories the rest of this view model uses.
  Future<List<WorkoutOption>> workoutOptions(String programId) =>
      fetchWorkoutOptions(
        userId: _userId,
        programId: programId,
        plannedRepository: _plannedRepo,
        programRepository: _programRepo,
      );

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
    required List<String> sessionIds,
    String? title,
  }) async {
    try {
      final run = await _currentRunFor(
        programId,
        sessionIds: sessionIds,
        sessionBlocks: state.value.sessionBlocks,
      );
      state.value = state.value.copyWith(isReviewing: true, clearError: true);
      // The row and its "as found" baseline are written together: a pass that
      // began without one would have nothing to compare its first edits
      // against. [ProgramHistoryRepository.beginReview] is that pair; the
      // reload after it is this view model's own (the load derives the
      // achievements read back below).
      final review = await _historyRepo.beginReview(
        userId: _userId,
        programId: programId,
        sessionIds: sessionIds,
        programRunId: run?.programRunId,
        title: title,
      );
      await load(programId);

      final since = await _historyRepo.checkpointFor(
        programId,
        sessionIds: sessionIds,
        // The same window `load` just derived achievements over, so the sheet's
        // "since <date>" and the achievements under it cannot disagree.
        fallback: run?.startedDate,
      );

      return StartedReview(
        review: review,
        sessionIds: sessionIds,
        sinceDate: since,
        // Read back from state rather than derived again: the reload above is
        // what derives this — over the very review just written.
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
  /// **covering the same workouts**.
  ///
  /// [reviews] is newest first, so a review's predecessor is the next entry
  /// with the same [reviewScopeKey] — walking from the end keeps the last
  /// completed review seen per key, which is exactly that predecessor. Open and
  /// dismissed reviews carry no snapshot: they can never be a predecessor, and
  /// they get a digest with no diff. A document this build can't decode is
  /// skipped the same way rather than treated as empty, which would report the
  /// whole program as removed.
  ///
  /// Both sides read through [scopedSnapshot], so a set review's "what changed"
  /// counts its own workouts — and a predecessor covering the same ids compares
  /// on the same ground, which is what lets one of them show as removed.
  static Map<String, ReviewDigest> _digestAll(
    List<ProgramReview> reviews,
    Map<String, String> exerciseNames,
  ) {
    final digests = <String, ReviewDigest>{};
    final lastByScope = <String, ProgramReview>{};

    for (final review in reviews.reversed) {
      final content = scopedSnapshot(review);
      final scope = reviewScopeKey(review);
      final previous = lastByScope[scope];
      if (content != null) lastByScope[scope] = review;

      final before = previous == null ? null : scopedSnapshot(previous);
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

  // ── Reviews ──────────────────────────────────────────────────────────────

  /// Schedules the program's next checkpoint.
  ///
  /// [sessionIds] is the review's **scope**: the workouts it will cover, passed
  /// through unchanged.
  ///
  /// Returns the new review, or null if it failed.
  Future<ProgramReview?> scheduleReview(
    String programId, {
    required List<String> sessionIds,
    String? programRunId,
    String? title,
    String? notes,
    DateTime? scheduledFor,
  }) async {
    state.value = state.value.copyWith(isReviewing: true, clearError: true);
    try {
      final review = await _historyRepo.scheduleReview(
        userId: _userId,
        programId: programId,
        sessionIds: sessionIds,
        programRunId: programRunId,
        title: title,
        notes: notes,
        scheduledFor: scheduledFor,
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

  /// Reopens [review], which is already open: the same facts [startReview]
  /// gathers, without writing anything.
  ///
  /// A card tap lands in the review that exists rather than in a second row.
  /// Two rows for one pass would ask the same question twice and cut two
  /// snapshots, and the timeline could not tell which was the real one.
  Future<StartedReview?> resumeReview(
    String programId,
    ProgramReview review,
  ) async {
    try {
      // The pass's workouts, from the resolution `load` already made — one
      // answer for the window question, the run match and the ceremony ahead.
      final set =
          state.value.reviewSessions[review.reviewId] ?? const <String>[];
      final run = await _currentRunFor(
        programId,
        sessionIds: set,
        sessionBlocks: state.value.sessionBlocks,
      );
      // A review that began before baselines were recorded has none to
      // compare against, and the moment it is next looked at is the best "as
      // found" available for it. Idempotent by construction: a review that
      // has one keeps it, so a resume can never move a live baseline.
      final current =
          await _historyRepo.captureBaseline(review.reviewId, userId: _userId) ??
          review;
      final since = await _historyRepo.checkpointFor(
        programId,
        sessionIds: set,
        fallback: run?.startedDate,
      );
      return StartedReview(
        review: current,
        sessionIds: set,
        sinceDate: since,
        achievements: state.value.achievements,
      );
    } catch (_) {
      return null;
    }
  }

  /// Completes [reviewId], writing the snapshot it is a checkpoint of.
  ///
  /// The snapshot records the **live** program: reviewing IS editing, and
  /// finishing records what that produced.
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

  void dispose() {
    _disposed = true;
    state.dispose();
  }
}
