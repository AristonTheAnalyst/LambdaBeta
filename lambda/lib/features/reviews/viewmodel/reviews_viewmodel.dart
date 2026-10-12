import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/session_format.dart';
import '../../../data/models/program_review.dart';
import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/planned_session_repository.dart';
import '../../../data/repositories/program_history_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../shared/widgets/exercise_target_picker.dart'
    show goalTargetValue;
import '../../goals/view/goal_row.dart' show goalExerciseNameFor;
import '../../programs/viewmodel/program_history_viewmodel.dart'
    show StartedReview;

/// One workout the review picker offers, display-ready.
///
/// The picker's rows are workouts by name, wherever they live: a review
/// covers workouts, not a program, so where one sits is not part of the row.
/// Each row carries two lines, and they are all it needs beside the name:
/// how long it has been since the last completed review ([sinceReviewLabel]
/// — one window shared by every row, because a review covers the user, not a
/// workout) and how much of this workout happened inside it ([finishedLabel]).
class ReviewableWorkout {
  const ReviewableWorkout({
    required this.sessionId,
    required this.label,
    this.finished = 0,
    this.lastLogged,
    this.lastReview,
  });

  final String sessionId;

  /// The workout's own name.
  final String label;

  /// Finished sessions since the user's last completed review — or, when
  /// there is none to count from, every finished session. Which one the
  /// number means is what [sinceReview] says, and the row says it back.
  final int finished;

  /// When this workout was last logged, or null when it never has been.
  ///
  /// The recency the list is ordered by — the agreed rule, "last logged, then
  /// newest created" — applied by the loader; the row itself no longer states
  /// it (2026-10-10).
  final DateTime? lastLogged;

  /// When the user last completed a review — the same moment on every row,
  /// because a review covers the user, not a workout. Null until the first
  /// one is finished, and what the window line counts from.
  final DateTime? lastReview;

  bool get sinceReview => lastReview != null;

  /// The window line: how long it has been since the last completed review.
  /// The count under it is measured over this stretch; with no review ever
  /// completed the line says so, and the count is a lifetime one.
  String get sinceReviewLabel {
    final at = lastReview;
    if (at == null) return 'No reviews yet';
    final days = DateTime.now().difference(at).inDays;
    if (days <= 0) return 'Last review today';
    return '$days day${days == 1 ? '' : 's'} since last review';
  }

  /// The count line, in the one wording the picker and the scope sheet share.
  String get finishedLabel =>
      '$finished workout${finished == 1 ? '' : 's'} finished'
      '${sinceReview ? ' since last review' : ''}';
}

/// One goal the review picker offers, display-ready.
///
/// A goal has no recency in the picker's sense — nothing logs against a goal
/// directly — so the list stays in the repository's own creation order, which
/// is the order the library already reads in.
class ReviewableGoal {
  const ReviewableGoal({
    required this.goalId,
    required this.exerciseName,
    this.target = '',
    this.targetWeight,
    this.targetReps,
  });

  final String goalId;

  /// Built with `goalExerciseNameFor` — the exercise's live name, falling
  /// back to the text captured when the goal was written.
  final String exerciseName;

  /// The target alone ("100 kg × 5"), or empty when the goal recorded neither
  /// number. The row draws it as its own element rather than gluing it to the
  /// name with a dash (2026-10-10).
  final String target;

  /// The numbers behind [target], kept as numbers so a caller can order by
  /// how heavy the goal is — [target] is display text, not a sort key
  /// (2026-10-10). Null when the goal recorded no weight.
  final num? targetWeight;
  final int? targetReps;
}

/// Every goal the user could review — the whole library, because a review is
/// *about* goals. Goals carry no scope while they are unattached (2026-10-08),
/// so there is nothing to narrow by; the read still returns legacy scoped rows
/// if any exist, chipless like the rest.
Future<List<ReviewableGoal>> fetchReviewableGoals({
  required String userId,
  ProgramRepository? programRepository,
  ExerciseRepository? exerciseRepository,
}) async {
  final programs = programRepository ?? ProgramRepository();
  final exercises = exerciseRepository ?? ExerciseRepository();

  final options = await programs.fetchGoalOptions(userId);
  // Names read once, after the early-out: an empty library costs nothing, and
  // a full one costs one read rather than one per goal.
  if (options.isEmpty) return const [];
  final details = await exercises.fetchExerciseDetailMap(userId);

  return [
    for (final option in options)
      ReviewableGoal(
        goalId: option.goal.goalId,
        exerciseName: goalExerciseNameFor(option.goal, details),
        target: goalTargetValue(
          option.goal.targetWeight,
          option.goal.targetReps,
        ),
        targetWeight: option.goal.targetWeight,
        targetReps: option.goal.targetReps,
      ),
  ];
}

/// Everything the standalone review picker can offer: every active workout of
/// the user's — any program or none — with how much is finished since the last
/// review and when it was last logged, in the agreed recency order.
///
/// A free function rather than a view-model method alone, so the ordering rule
/// has exactly one implementation and a host test can drive it through the
/// fakes. The order, and the count each row states, are decided by
/// [PlannedSessionRepository.fetchReviewableRows]; this only dresses the rows.
Future<List<ReviewableWorkout>> fetchReviewableWorkouts({
  required String userId,
  PlannedSessionRepository? plannedRepository,
}) async {
  final planned = plannedRepository ?? PlannedSessionRepository();

  final rows = await planned.fetchReviewableRows(userId);
  return [
    for (final row in rows)
      ReviewableWorkout(
        sessionId: row.session.sessionId,
        label: toProperCase(row.session.name),
        finished: row.finished,
        lastLogged: row.lastLogged,
        lastReview: row.lastReview,
      ),
  ];
}

/// One review the user has, with the set it covers resolved for display.
class ReviewListEntry {
  const ReviewListEntry({
    required this.review,
    this.sessionIds = const [],
    this.workoutNames = const [],
  });

  final ProgramReview review;

  /// The workouts the pass covers, resolved — a standalone pass reads its own
  /// stored set, a program pass resolves against its program's links.
  final List<String> sessionIds;

  /// Their names, in set order — shorter than [sessionIds] when a workout has
  /// been deleted since (its name is gone; the id still is not).
  final List<String> workoutNames;

  bool get isOpen => review.isOpen;

  /// What the row shows as the pass's name: the given title, else the workouts
  /// it covers, else the bare noun.
  String get label {
    final title = review.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    if (workoutNames.isEmpty) return 'Review';
    return workoutNames.join(' · ');
  }

  /// How many of the set have been ticked — the open row's progress.
  int get reviewedCount => [
    for (final id in sessionIds)
      if (review.reviewedSessions.containsKey(id)) id,
  ].length;

  int get total => sessionIds.length;
}

class ReviewsState {
  const ReviewsState({
    this.isLoading = false,
    this.isStarting = false,
    this.error,
    this.entries = const [],
  });

  final bool isLoading;

  /// A review is being started — the row is being written.
  final bool isStarting;
  final String? error;

  /// Every review the user has, open pinned first — newest first inside each
  /// half, the order the repository sorted them in.
  final List<ReviewListEntry> entries;

  List<ReviewListEntry> get open => [for (final e in entries) if (e.isOpen) e];

  List<ReviewListEntry> get completed => [
    for (final e in entries)
      if (e.review.isCompleted) e,
  ];

  ReviewsState copyWith({
    bool? isLoading,
    bool? isStarting,
    String? error,
    bool clearError = false,
    List<ReviewListEntry>? entries,
  }) => ReviewsState(
    isLoading: isLoading ?? this.isLoading,
    isStarting: isStarting ?? this.isStarting,
    error: clearError ? null : error ?? this.error,
    entries: entries ?? this.entries,
  );
}

/// The Reviews tab's view model: the user's reviews, and the two ways into one
/// — start a pass, or go back into an open one.
///
/// A review is standalone here: workouts and goals picked directly, no program
/// in the picture. The program surfaces keep their own entry points and their
/// own view model; this one owns the list and the ceremony's opening facts.
class ReviewsViewModel {
  ReviewsViewModel({
    ProgramHistoryRepository? historyRepository,
    PlannedSessionRepository? plannedRepository,
    ProgramRepository? programRepository,
    ExerciseRepository? exerciseRepository,
    String? userId,
  }) : _historyRepo = historyRepository ?? ProgramHistoryRepository(),
       _plannedRepo = plannedRepository ?? PlannedSessionRepository(),
       _programRepo = programRepository ?? ProgramRepository(),
       _exerciseRepo = exerciseRepository ?? ExerciseRepository(),
       _userIdOverride = userId;

  final ProgramHistoryRepository _historyRepo;
  final PlannedSessionRepository _plannedRepo;
  final ProgramRepository _programRepo;
  final ExerciseRepository _exerciseRepo;
  final String? _userIdOverride;

  final state = ValueNotifier(const ReviewsState());
  bool _disposed = false;

  /// The signed-in user. Overridable because host tests cannot construct
  /// `Supabase.instance` at all.
  String get _userId =>
      _userIdOverride ?? Supabase.instance.client.auth.currentUser!.id;

  Future<void> load() async {
    state.value = state.value.copyWith(isLoading: true, clearError: true);
    try {
      final reviews = await _historyRepo.fetchReviewsForUser(_userId);
      // Names for whatever the sets resolve to, read from the same list the
      // picker offers (every active workout, any membership): one source for
      // both, so the picker and the list can never name a workout differently.
      final rows = await _plannedRepo.fetchReviewableRows(_userId);
      final namesByName = {
        for (final row in rows)
          row.session.sessionId: toProperCase(row.session.name),
      };
      if (_disposed) return;

      // A program's links, fetched once per program and not once per review:
      // a legacy row resolves through them, and a list of ten reviews of one
      // program must not cost ten reads.
      final linksByProgram =
          <String, List<({String sessionId, String? blockId})>>{};
      final entries = <ReviewListEntry>[];
      for (final review in reviews) {
        final programId = review.programId;
        List<String> ids;
        if (programId == null) {
          ids = review.storedSessionIds ?? const [];
        } else {
          var links = linksByProgram[programId];
          if (links == null) {
            links = [
              for (final link in await _plannedRepo.fetchProgramLinks(programId))
                (sessionId: link.plannedSessionId, blockId: link.blockId),
            ];
            linksByProgram[programId] = links;
          }
          ids = review.sessionsIn(links);
        }
        entries.add(
          ReviewListEntry(
            review: review,
            sessionIds: ids,
            workoutNames: [for (final id in ids) ?namesByName[id]],
          ),
        );
      }
      if (_disposed) return;

      // Open pinned first — a pass being taken right now is what the list is
      // for getting back into. Two comprehensions rather than a sort because
      // Dart's sort is not stable, and each half is already newest-first from
      // the repository.
      state.value = ReviewsState(
        entries: [
          for (final e in entries)
            if (e.isOpen) e,
          for (final e in entries)
            if (!e.isOpen) e,
        ],
      );
    } catch (_) {
      if (_disposed) return;
      state.value = state.value.copyWith(
        isLoading: false,
        error: 'Could not load your reviews.',
      );
    }
  }

  /// Everything the picker can offer, in its recency order.
  Future<List<ReviewableWorkout>> reviewableWorkouts() =>
      fetchReviewableWorkouts(
        userId: _userId,
        plannedRepository: _plannedRepo,
      );

  /// The goals half of the picker, in library order.
  Future<List<ReviewableGoal>> reviewableGoals() => fetchReviewableGoals(
    userId: _userId,
    programRepository: _programRepo,
    exerciseRepository: _exerciseRepo,
  );

  /// Starts a standalone review **now**: writes the row, records "as found",
  /// and returns what the ceremony needs to open on it.
  ///
  /// The row is written before the ceremony opens, because the pass's whole job
  /// is to end in a snapshot on it: a review that existed only in the UI until
  /// Finish would lose everything the user did if the app died mid-pass.
  /// [goalIds] travels with the set — a review contains workouts **and** goals,
  /// and both are stored at the start so a resume opens the same pass.
  ///
  /// Null when the write failed; the state carries the error.
  Future<StartedReview?> startReview({
    required List<String> sessionIds,
    List<String> goalIds = const [],
    String? title,
  }) async {
    state.value = state.value.copyWith(isStarting: true, clearError: true);
    try {
      final review = await _historyRepo.beginReview(
        userId: _userId,
        // Standalone: the program surfaces are retired from the UI, and this
        // tab was born without one.
        programId: null,
        sessionIds: sessionIds,
        goalIds: goalIds,
        title: title,
      );
      // Where the pass's window opens: the newest completed pass over any of
      // these workouts, whoever started it. Null — a first look — and the
      // landing says nothing about a window.
      final since = await _historyRepo.checkpointForSet(
        _userId,
        sessionIds: sessionIds,
      );
      await load();
      return StartedReview(
        review: review,
        sessionIds: sessionIds,
        sinceDate: since,
        // A standalone pass has no program to derive achievements against;
        // the null the notifier already renders.
        achievements: null,
      );
    } catch (_) {
      if (!_disposed) {
        state.value = state.value.copyWith(
          isLoading: false,
          isStarting: false,
          error: 'Could not start the review.',
        );
      }
      return null;
    }
  }

  /// Cancels [reviewId] — the open row is deleted outright, then the list is
  /// re-read so the row leaves the way every other write's effect does.
  ///
  /// False when the write failed, the same contract [startReview] has with its
  /// caller; the state carries the sentence. The repository's own guard decides
  /// races: a row completed elsewhere simply survives the delete, and the
  /// reload shows it under COMPLETED.
  Future<bool> cancelReview(String reviewId) async {
    try {
      await _historyRepo.deleteReview(reviewId);
      await load();
      return true;
    } catch (_) {
      if (!_disposed) {
        state.value = state.value.copyWith(
          error: 'Could not cancel the review.',
        );
      }
      return false;
    }
  }

  /// Reopens [review], which is already open: the same facts [startReview]
  /// gathers, without writing a review row.
  ///
  /// The baseline is (re)captured on the way — idempotent by construction, so
  /// a pass that already has one is untouched and only one that began before
  /// baselines were recorded heals here.
  Future<StartedReview?> resumeReview(ProgramReview review) async {
    try {
      final ids = await _resolveSet(review);
      final current =
          await _historyRepo.captureBaseline(
            review.reviewId,
            userId: _userId,
          ) ??
          review;
      final since = await _historyRepo.checkpointForSet(
        _userId,
        sessionIds: ids,
      );
      return StartedReview(
        review: current,
        sessionIds: ids,
        sinceDate: since,
      );
    } catch (_) {
      return null;
    }
  }

  /// The workouts [review] covers, resolved — a standalone pass reads its own
  /// stored set, a program pass resolves against its program's live links
  /// (the rule [ProgramReview.sessionsIn] applies; the links are fetched here).
  Future<List<String>> _resolveSet(ProgramReview review) async {
    final programId = review.programId;
    if (programId == null) return review.storedSessionIds ?? const [];
    final links = await _plannedRepo.fetchProgramLinks(programId);
    return review.sessionsIn([
      for (final link in links)
        (sessionId: link.plannedSessionId, blockId: link.blockId),
    ]);
  }

  void dispose() {
    _disposed = true;
    state.dispose();
  }
}
